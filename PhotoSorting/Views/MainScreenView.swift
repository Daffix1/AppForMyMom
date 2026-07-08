import SwiftUI
import Photos

@MainActor
struct MainScreenView: View {
    private var photoService = PhotoLibraryService.shared
    
    @State private var state: ScreenState = .loading
    @State private var photos: [PhotoItem] = []
    @State private var sortingPayload: SortingSessionPayload?
    
    @State private var showStats = false
    @State private var showSettings = false
    @State private var showCalendar = false
    
    @State private var autoStartAfterDismiss = false
    
    // Wrapper for the data fullScreenCover(item:) hands off to SortingView.
    // Using item: instead of isPresented: guarantees SwiftUI has the full
    // payload in place before it constructs the SortingView body.
    //
    // Теперь payload несёт не только фото, но и sessionStore. Причина:
    // стор бывает разный (TodaySessionStore для сегодня, EphemeralSessionStore
    // для дня из календаря), и его нужно создать РОВНО ОДИН РАЗ и передать в
    // SortingView. Если бы стор создавался в замыкании fullScreenCover, при
    // каждой перерисовке возникал бы новый пустой стор и прогресс эфемерного
    // дня терялся бы. Кладя стор в payload, фиксируем один экземпляр на сессию.
    
    private struct SortingSessionPayload: Identifiable {
        let id = UUID()
        let photos: [PhotoItem]
        let sessionStore: SessionStore
    }
    
    // Прямой доступ к реактивному singleton'у
    private let storage = StorageService.shared
    
    var body: some View {
        Group {
            if !storage.onboardingCompleted {
                OnboardingView {
                    Task { await loadPhotos() }
                }
            } else {
                mainContent
            }
        }
    }
    
    private var mainContent: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            
            VStack {
                switch state {
                case .loading:        loadingView
                case .needsAccess:    needsAccessView
                case .accessDenied:   accessDeniedView
                case .ready:          readyView
                case .completedToday: completedTodayView
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Button { showStats = true } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(width: 40, height: 40)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(Circle())
                }
                Spacer()
                Button { showCalendar = true } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(width: 40, height: 40)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(Circle())
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 40, height: 40)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .task {
            await loadPhotos()
        }
        .fullScreenCover(item: $sortingPayload, onDismiss: {
            Task {
                await loadPhotos()
                if autoStartAfterDismiss {
                    autoStartAfterDismiss = false
                    if state == .ready {
                        await startSorting()
                    }
                }
            }
        }) { payload in
            SortingView(
                photos: payload.photos,
                sessionStore: payload.sessionStore,
                onFinish: { sortingPayload = nil },
                onContinueRequested: {
                    autoStartAfterDismiss = true
                    sortingPayload = nil
                }
            )
        }
        .sheet(isPresented: $showStats) {
            StatsView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView {
                Task { await loadPhotos() }
            }
        }
        .sheet(isPresented: $showCalendar) {
            CalendarView(onDateSelected: { date in
                // Подключено: выбор даты запускает сортировку за этот день.
                // launchSorting сам выберет нужный стор по дате.
                Task { await launchSorting(for: date) }
            })
        }
    }
    
    // MARK: - Состояния
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.4)
            Text("Ищем фото...")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
    }
    
    private var needsAccessView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            VStack(spacing: 8) {
                Text("Photo Sorting")
                    .font(.system(size: 28, weight: .bold))
                Text("Чистим галерею вместе по\u{00a0}одному дню за\u{00a0}раз")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer().frame(height: 8)
            
            Button("Разрешить доступ к фото") {
                Task { await loadPhotos() }
            }
            .primaryButtonStyle()
        }
    }
    
    private var accessDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundColor(.orange)
            
            Text("Доступ к фото запрещён")
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
            
            Text("Откройте Настройки → Photo Sorting → Фото и выберите «Все фото».")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Открыть настройки") {
                openSettings()
            }
            .primaryButtonStyle()
        }
    }
    
    private var readyView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 8) {
                Text(todayDateString())
                    .font(.system(size: 32, weight: .bold))
                Text("Этот день в прошлые годы")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            
            Spacer().frame(height: 60)
            
            VStack(spacing: 6) {
                Text("\(photos.count)")
                    .font(.system(size: 80, weight: .bold))
                    .foregroundColor(.blue)
                Text("\(photos.count.photoWord()) за этот день")
                    .font(.system(size: 17))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(buttonTitleForReady) {
                Task { await startSorting() }
            }
            .primaryButtonStyle()
        }
    }
    
    private var buttonTitleForReady: String {
        let phase = storage.currentSession.phase
        if phase == .awaitingDecision {
            return "Вернуться к результатам"
        } else if phase == .sorting {
            return "Продолжить сортировку"
        } else {
            return "Начать сортировку"
        }
    }
    
    private var completedTodayView: some View {
        VStack(spacing: 24) {
            Text("🎉").font(.system(size: 80))
            
            Text("На сегодня всё!")
                .font(.system(size: 26, weight: .bold))
            
            Text("Возвращайтесь завтра в 00:00 за новой порцией фото")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            if !photos.isEmpty {
                Button("Отсортировать оставшееся") {
                    Task { await startSorting() }
                }
                .primaryButtonStyle()
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Загрузка фото
    
    private func loadPhotos() async {
        state = .loading
        
        // Проверяем актуальность сессии — если день сменился и сессия "тихая",
        // создаётся новая. Активные сессии (sorting/awaitingDecision) не трогаются.
        storage.ensureFreshSession()
        
        let granted = await photoService.requestAuthorization()
        
        if !granted {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if status == .denied || status == .restricted {
                state = .accessDenied
            } else {
                state = .needsAccess
            }
            return
        }
        
        let foundPhotos = await photoService.fetchPhotosForToday()
        
        photos = foundPhotos
        let session = storage.currentSession
        
        if session.phase == .completed {
            state = .completedToday
        } else if session.phase == .awaitingDecision {
            state = .ready
        } else if foundPhotos.isEmpty {
            // Фото за сегодня нет — помечаем день завершённым
            var updated = storage.currentSession
            updated.phase = .completed
            storage.currentSession = updated
            state = .completedToday
        } else {
            state = .ready
        }
    }
    
    // MARK: - Запуск сортировки
    
    // Единая точка входа в сортировку за ЛЮБОЙ день.
    //
    //   - Выбирает стор по дате: сегодня → TodaySessionStore (персист + resume),
    //     прошлый день → EphemeralSessionStore (в памяти, разовая сессия).
    //   - Грузит фото за этот день через fetchAllPhotos(for:).
    //   - Кладёт фото И стор в payload (стор создаётся здесь ровно один раз).
    //
    // И кнопка с главного экрана, и колбэк из календаря идут через этот метод —
    // логика выбора стора живёт в одном месте.
    private func launchSorting(for date: Date) async {
        let store: SessionStore
        if Calendar.current.isDateInToday(date) {
            // Сегодня — всегда через TodaySessionStore, независимо от того,
            // откуда зашли (главный экран или календарь). Это гарантирует
            // ЕДИНУЮ сегодняшнюю сессию с одним прогрессом.
            store = TodaySessionStore()
        } else {
            // Прошлый день — эфемерная сессия в памяти.
            store = EphemeralSessionStore(date: date)
        }
        
        let dayPhotos = await photoService.fetchAllPhotos(for: date)
        
        // Setting this single piece of state both triggers the cover AND
        // hands SwiftUI the photos array + store atomically.
        sortingPayload = SortingSessionPayload(photos: dayPhotos, sessionStore: store)
    }
    
    // Запуск сегодняшней сортировки — тонкая обёртка над launchSorting.
    // Берём дату из текущей сессии (она сегодняшняя), чтобы поведение
    // совпадало с прежним startSorting.
    private func startSorting() async {
        await launchSorting(for: storage.currentSession.date)
    }
    
    // MARK: - Прочее
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func todayDateString() -> String {
        Date().formatted(.dateTime.day().month(.wide))
    }
}

enum ScreenState {
    case loading
    case needsAccess
    case accessDenied
    case ready
    case completedToday
}
