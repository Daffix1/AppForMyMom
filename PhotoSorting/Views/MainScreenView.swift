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

    // Обёртка для данных, которые fullScreenCover(item:) передаёт в SortingView.
    // item: (а не isPresented:) гарантирует, что SwiftUI получил полный payload
    // до конструирования тела SortingView.
    //
    // Стор из payload убран: сессия снова одна (storage.currentSession),
    // SortingView читает её напрямую. Достаточно передать фото.
    private struct SortingSessionPayload: Identifiable {
        let id = UUID()
        let photos: [PhotoItem]
    }

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
            CalendarView(
                selectedMonth: storage.currentSession.selectedMonth,
                selectedDay: storage.currentSession.selectedDay,
                onDaySelected: { date in
                    Task {
                        storage.selectSortingDay(date)
                        await loadPhotos()
                    }
                }
            )
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
                            Button {
                                HapticsService.shared.play(.light)
                                showCalendar = true
                            } label: {
                                HStack(spacing: 8) {
                                    Text(selectedDayString())
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(.primary)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.blue.opacity(0.25), lineWidth: 1)
                                )
                            }
                            Text("Этот день во все прошлые годы")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
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

                Text(completedTitle)
                    .font(.system(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(completedSubtitle)
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

        // Сегодняшний ли день сортируется сейчас — по selectedMonth/Day сессии.
    private var isSortingToday: Bool {
        let today = Calendar.current.dateComponents([.month, .day], from: Date())
        let s = storage.currentSession
        return s.selectedMonth == today.month && s.selectedDay == today.day
    }
    private var completedTitle: String {
        isSortingToday ? "На сегодня всё!" : "День отсортирован"
    }
    private var completedSubtitle: String {
        if isSortingToday {
            return "Возвращайтесь завтра в 00:00 за новой порцией фото"
        } else {
            return "Вы разобрали фото за \(selectedDayString()). Можно выбрать другой день в календаре."
        }
    }

    // MARK: - Загрузка фото

    private func loadPhotos() async {
        state = .loading

        // Полуночный сброс: сессия не сегодняшняя → пересоздаём на сегодня.
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

        // Выборка по сортируемому дню текущей сессии (пока это всегда сегодня).
        let session = storage.currentSession
        let foundPhotos = await photoService.fetchPhotos(
            month: session.selectedMonth,
            day: session.selectedDay
        )

        photos = foundPhotos

        if session.phase == .completed {
            state = .completedToday
        } else if session.phase == .awaitingDecision {
            state = .ready
        } else if foundPhotos.isEmpty {
            var updated = storage.currentSession
            updated.phase = .completed
            storage.currentSession = updated
            state = .completedToday
        } else {
            state = .ready
        }
    }

    // MARK: - Запуск сортировки

    // Запуск сортировки за текущий день сессии. Фото грузятся по
    // selectedMonth/selectedDay. Стор больше не создаём — SortingView
    // работает напрямую со storage.currentSession.
    private func startSorting() async {
        let session = storage.currentSession
        let dayPhotos = await photoService.fetchPhotos(
            month: session.selectedMonth,
            day: session.selectedDay
        )
        sortingPayload = SortingSessionPayload(photos: dayPhotos)
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
    
    private func selectedDayString() -> String {
        let session = storage.currentSession
        let month = session.selectedMonth
        let day = session.selectedDay

        // Родительный падеж месяца ("июля", "февраля") — форма для "7 июля".
        // monthSymbols в русской локали даёт именно склоняемую форму для
        // конструкции "<число> <месяца>".
        let symbols = DateFormatter().monthSymbols ?? []
        guard month >= 1, month <= symbols.count else {
            return todayDateString()
        }
        let monthName = symbols[month - 1]
        return "\(day) \(monthName)"
    }
}

enum ScreenState {
    case loading
    case needsAccess
    case accessDenied
    case ready
    case completedToday
}
