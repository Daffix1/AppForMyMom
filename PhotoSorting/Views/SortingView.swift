import SwiftUI
import Photos

@MainActor
struct SortingView: View {
    let photos: [PhotoItem]
    
    private let photoService = PhotoLibraryService.shared
    private let storage = StorageService.shared
    
    // Колбэки
    let onFinish: () -> Void              // выйти на главный
    let onContinueRequested: () -> Void   // продолжить с оставшимися (закрыть и переоткрыть)
    
    // Копия сессии чтобы не нагружать память
    @State private var session: DailySessionState = StorageService.shared.currentSession
    
    // Счетчик фото, сколько отсортировали
    @State private var currentIndex = 0
    
    // Анимационные переменные
    @State private var dragOffset: CGFloat = 0
    @State private var sessionFinished = false
    @State private var showStreakAchieved = false
    
    // массив кейсов для кнопки "назад"
    @State private var swipeHistory: [SwipeDirection] = []
    enum SwipeDirection { case left, right }
    
    // Сколько фото за сегодня осталось несвайпнутых
    // Считается при показе финального экрана
    @State private var remainingPhotos: Int = 0
    
    @State private var preloadTasks: [Task<Void, Never>] = []
    
    // MARK: - Constants
    
    private let swipeThreshold: CGFloat = 120   // минимальный сдвиг для засчитывания свайпа
    private let cardFlyOutDistance: CGFloat = 600 // расстояние улёта карточки за экран
    private let labelOpacityDivisor: Double = 80  // делитель для прозрачности надписей УДАЛИТЬ/ОСТАВИТЬ
    private let labelOpacityOffset: Double = 20   // сдвиг начала появления надписи
    private let swipeAnimationDuration: Double = 0.25  // длительность анимации улёта карточки
    private let nextCardDelay: Double = 0.3            // задержка перед показом следующей карточки
    private let streakOverlayDuration: Double = 2.0    // сколько секунд показывается оверлей стрика
    private let streakOverlayFadeOut: Double = 0.3     // длительность исчезновения оверлея
    private let preloadAheadCount: Int = 2             // сколько карточек предзагружать вперёд
    private let cardTargetWidth: CGFloat = 360         // ширина карточки для загрузки изображения
    private let cardTargetHeight: CGFloat = 540        // высота карточки для загрузки изображения
    
    var body: some View {
        ZStack {
            mainContent
            if showStreakAchieved {
                streakAchievedOverlay
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            // Загружаем свежую копию сессии
            session = storage.currentSession
            if session.phase == .idle {
                session.phase = .sorting
                storage.currentSession = session
            }
            preloadNextPhotos()
        }
        .task(id: sessionFinished) {
            if sessionFinished {
                remainingPhotos = await calculateRemaining()
            }
        }
    }
    
    // MARK: - Основной контент
    
    @ViewBuilder
    private var mainContent: some View {
        // финальные экраны. Либо юзер сам попадает на финальный экран сортировки, либо его перекидывает приложение
        // если во время финального экрана он вышел из приложения
        if sessionFinished || session.phase == .awaitingDecision {
            sessionFinishedView
        } else if currentIndex < photos.count {
            sortingContent
            // показываем финальный экран, если досвайпали фото до конца
        } else {
            sessionFinishedView
        }
    }
    
    // MARK: - Экран сортировки
    
    private var sortingContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    // кнопка "Назад"
                    Button {
                        undoLastSwipe()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(swipeHistory.isEmpty ? .gray.opacity(0.4) : .blue)
                            .frame(width: 36, height: 36)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(Circle())
                    }
                    .disabled(swipeHistory.isEmpty)
                    
                    progressBar
                }
                
                // Подсказка про стрик
                if !storage.todayStreakReached {
                    let remaining = storage.photosRemainingForStreak
                    if remaining > 0 {
                        HStack {
                            Text("🔥 Ещё \(remaining) до серии")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.orange)
                            Spacer()
                        }
                    }
                }
                
                // Кнопка "Завершить сортировку" после набора минимума
                if session.totalProcessedToday >= StorageService.dailyMinimum {
                    Button {
                        finishSessionEarly()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Завершить сортировку")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .clipShape(Capsule())
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .animation(.spring(response: 0.4), value: session.totalProcessedToday)
            
            Spacer()
            
            // Фото + жесты + надписи
            ZStack {
                behindCardLabels
                PhotoCardView(
                    item: photos[currentIndex],
                    offset: dragOffset,
                    onSkip: {
                        performSwipe(direction: .right)
                    }
                )
                .id(currentIndex)
                .animation(.interactiveSpring(), value: dragOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle()) // чтобы свайп работал не только на фото, но и на пустое пространство над и под ним
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        handleSwipeEnd(translation: value.translation.width)
                    }
            )
            .padding(.horizontal, 20)
            
            Text(photos[currentIndex].creationDate.formatted(date: .long, time: .omitted))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .padding(.top, 14)
            
            Spacer()
        }
    }
    
    // MARK: - Прогресс-бар
    
    private var progressBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(currentIndex) из \(photos.count)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
                Text("🗑 \(session.deletedCount)  ✓ \(session.keptCount)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(
                            width: geometry.size.width * CGFloat(currentIndex) / CGFloat(max(photos.count, 1)),
                            height: 6
                        )
                        .animation(.easeInOut, value: currentIndex)
                }
            }
            .frame(height: 6)
        }
    }
    
    // MARK: - Надписи за карточкой
    
    private var behindCardLabels: some View {
        ZStack {
            HStack {
                Text("ОСТАВИТЬ")
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(.green)
                    .opacity(Double(max(dragOffset - labelOpacityOffset, 0)) / labelOpacityDivisor)
                Spacer()
            }
            .padding(.leading, 24)
            
            HStack {
                Spacer()
                Text("УДАЛИТЬ")
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(.red)
                    .opacity(Double(max(-dragOffset - labelOpacityOffset, 0)) / labelOpacityDivisor)
            }
            .padding(.trailing, 24)
        }
    }
    
    // MARK: - Оверлей "Серия засчитана"
    
    private var streakAchievedOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            
            VStack(spacing: 16) {
                Text("🔥").font(.system(size: 80))
                Text("Серия дней засчитана!")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Text("\(storage.currentStreak) дней подряд")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.orange.opacity(0.95))
                    .shadow(color: .black.opacity(0.3), radius: 20)
            )
            .padding(40)
        }
    }
    
    // MARK: - Финальный экран сортировки
        
    private var sessionFinishedView: some View {
        SessionFinishedView(
            deletedCount: session.deletedCount,
            keptCount: session.keptCount,
            remainingCount: remainingPhotos,
            onDeleteAndExit: {
                Task { await deleteAndExit() }
            },
            onContinueWithRemaining: {
                Task { await deleteAndContinue() }
            },
            onStartOver: {
                startOver()
            },
            onExitWithoutDeleting: {
                exitWithoutDeleting()
            }
        )
    }

    // MARK: - Обработка свайпа, что делать с карточкой. Удалить, оставить или вернуть на центр
    
    private func handleSwipeEnd(translation: CGFloat) {
        if translation < -swipeThreshold {
            performSwipe(direction: .left)
        } else if translation > swipeThreshold {
            performSwipe(direction: .right)
        } else {
            dragOffset = 0
        }
    }
    
    // MARK: - Сам свайп
    
    private func performSwipe(direction: SwipeDirection) {
        let photo = photos[currentIndex]
        HapticsService.shared.play(.medium)
        
        // добавляем в массив свайпов сделанный свайп для кнопки "назад"
        swipeHistory.append(direction)
        
        if direction == .left {
            session.pendingDeleteIDs.append(photo.id) // массив фоток, которые потом удалим до конца
            session.currentDeletedIDs.append(photo.id) // массив фоток для счетчика наверху
        } else {
            session.currentKeptIDs.append(photo.id)
        }
        
        session.processedIDs.insert(photo.id) // множество для минимума стрика и фильтрации
        
        // Сохраняем в storage если приложение крашнется или юзер выйдет из него
        storage.currentSession = session
        
        // Глобальный список тоже обновляем
        var sorted = storage.sortedPhotoIDs
        sorted.insert(photo.id)
        storage.sortedPhotoIDs = sorted
        
        // Проверка стрика
        let reachedMinimum = session.totalProcessedToday >= StorageService.dailyMinimum
        let isLastPhoto = currentIndex + 1 >= photos.count
        
        if (reachedMinimum || isLastPhoto) && !storage.todayStreakReached {
            storage.updateStreak()
            HapticsService.shared.play(.success)
            
            withAnimation(.spring(response: 0.4)) {
                showStreakAchieved = true
            }
            // скрытие поздравшки с закрытием стрика
            Task {
                try? await Task.sleep(for: .seconds(streakOverlayDuration))
                withAnimation(.easeOut(duration: streakOverlayFadeOut)) {
                    showStreakAchieved = false
                }
            }
        }
        
        // Анимация улёта карточки
        withAnimation(.easeOut(duration: swipeAnimationDuration)) {
            dragOffset = direction == .left ? -cardFlyOutDistance : cardFlyOutDistance
        }

        Task {
            try? await Task.sleep(for: .seconds(nextCardDelay))
            currentIndex += 1
            dragOffset = 0
            
            if currentIndex >= photos.count {
                session.phase = .awaitingDecision
                storage.currentSession = session
                sessionFinished = true
            } else {
                preloadNextPhotos()
            }
        }
    }
    // MARK: - Досрочное завершение (нажатие на кнопку "завершить сортировку")
    
    private func finishSessionEarly() {
        HapticsService.shared.play(.medium)
        session.phase = .awaitingDecision
        storage.currentSession = session
        sessionFinished = true
    }
    
    // MARK: - Откат свайпа
    
    private func undoLastSwipe() {
        guard !swipeHistory.isEmpty, currentIndex > 0 else { return }
        HapticsService.shared.play(.light)
        currentIndex -= 1
        
        let lastDirection = swipeHistory.removeLast()
        let photo = photos[currentIndex]
        
        // Откатываем изменения в session
        if lastDirection == .left {
            if !session.currentDeletedIDs.isEmpty {
                session.currentDeletedIDs.removeLast()
            }
            if let idx = session.pendingDeleteIDs.lastIndex(of: photo.id) {
                session.pendingDeleteIDs.remove(at: idx)
            }
        } else {
            if !session.currentKeptIDs.isEmpty {
                session.currentKeptIDs.removeLast()
            }
        }
        
        session.processedIDs.remove(photo.id)
        storage.currentSession = session
        
        // Откат в глобальном списке
        var sorted = storage.sortedPhotoIDs
        sorted.remove(photo.id)
        storage.sortedPhotoIDs = sorted
        
        dragOffset = 0
    }
    
    // MARK: - Предзагрузка следующих фото
 
    private func preloadNextPhotos() {
        // Отменяем предыдущие задачи предзагрузки — они уже не нужны
        preloadTasks.forEach { $0.cancel() }
        preloadTasks = []
        
        let nextIndex = currentIndex + 1
        let endIndex = min(nextIndex + preloadAheadCount, photos.count)
        guard nextIndex < photos.count else { return }
        
        let scale = UIScreen.main.scale
        let size = CGSize(width: cardTargetWidth * scale, height: cardTargetHeight * scale)
        
        for i in nextIndex..<endIndex {
            let asset = photos[i].asset
            let task = Task {
                _ = await photoService.loadImage(
                    for: asset,
                    targetSize: size,
                    deliveryMode: .highQualityFormat
                )
            }
            preloadTasks.append(task)
        }
    }
    
   
    
    // MARK: - Действия с финального экрана
        
    // "Удалить N в корзину" → выход на главный
    private func deleteAndExit() async {
        guard await deleteFromGalleryIfNeeded() else { return }
        returnKeptToPool()
        clearSessionBuffers()
        saveSessionPhase(.completed)
        onFinish()
    }
        
    // "Удалить и продолжить" — удаляем, оставшиеся возвращаем в пул, переоткрываем
    private func deleteAndContinue() async {
        guard await deleteFromGalleryIfNeeded() else { return }
        returnKeptToPool()
        clearSessionBuffers()
        saveSessionPhase(.sorting)
        onContinueRequested()
    }
        
    // "Завершить" (когда удалять нечего) — возвращаем оставленные в пул и выходим
    private func exitWithoutDeleting() {
        returnKeptToPool()
        clearSessionBuffers()
        saveSessionPhase(.completed)
        onFinish()
    }
        
    // "Начать заново" — откат всего, возвращаем все обработанные в пул, переоткрываем
    private func startOver() {
        returnAllProcessedToPool()
        session.processedIDs = []
        clearSessionBuffers()
        saveSessionPhase(.sorting)
        onContinueRequested()
    }
        
    // MARK: - Helper-методы для финала
    
    // Удаляет фото в системную корзину и обновляет статистику.
    // Возвращает true если удалять было нечего ИЛИ удаление прошло успешно.
    // Возвращает false при ошибке (например, пользователь отменил системный диалог).
    private func deleteFromGalleryIfNeeded() async -> Bool {
        let assetsToDelete = pendingAssets()
        guard !assetsToDelete.isEmpty else { return true }
        
        // Считаем размер ДО удаления — после удаления PHAsset исчезает
        let freedBytes = assetsToDelete.reduce(Int64(0)) { sum, asset in
            sum + PhotoLibraryService.estimateSize(for: asset)
        }
        
        let success = await photoService.deletePhotos(assetsToDelete)
        guard success else { return false }
        
        storage.totalDeleted += session.deletedCount
        storage.totalFreedBytes += freedBytes
        
        return true
    }
        
    // Возвращает оставленные ID в общий пул — снова появятся в следующих сессиях
    private func returnKeptToPool() {
        var sorted = storage.sortedPhotoIDs
        for id in session.currentKeptIDs {
            sorted.remove(id)
        }
        storage.sortedPhotoIDs = sorted
    }
        
    // Возвращает ВСЕ обработанные ID в пул (для startOver)
    // Включая помеченные к удалению — они не были физически удалены, только помечены
    private func returnAllProcessedToPool() {
        var sorted = storage.sortedPhotoIDs
        for id in session.processedIDs {
            sorted.remove(id)
        }
        storage.sortedPhotoIDs = sorted
    }
    
    // Сбрасывает буферы текущей под-сессии (processedIDs не трогаем — он копится за день)
    private func clearSessionBuffers() {
        session.pendingDeleteIDs = []
        session.currentDeletedIDs = []
        session.currentKeptIDs = []
    }
    
    // Меняет фазу сессии и сохраняет в storage
    private func saveSessionPhase(_ phase: DailySessionState.Phase) {
        session.phase = phase
        storage.currentSession = session
    }
    
    // MARK: - Вспомогательные функции
    
    // Получает PHAsset-ы по ID из pendingDeleteIDs
    private func pendingAssets() -> [PHAsset] {
        guard !session.pendingDeleteIDs.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: session.pendingDeleteIDs, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
        
    // Сколько фото за сегодня ещё несвайпнуты
    private func calculateRemaining() async -> Int {
        let remaining = await photoService.fetchPhotosForToday()
        return remaining.count
    }
}

// MARK: - Финальный экран

struct SessionFinishedView: View {
    let deletedCount: Int
    let keptCount: Int
    let remainingCount: Int
    
    let onDeleteAndExit: () -> Void
    let onContinueWithRemaining: () -> Void
    let onStartOver: () -> Void
    let onExitWithoutDeleting: () -> Void

    @State private var showStartOverConfirm = false
    @State private var showContinueConfirm = false
    
    private var hasDeletions: Bool { deletedCount > 0 }
    private var hasKept: Bool { keptCount > 0 }
    
    var body: some View {
        VStack(spacing: 24) {
            Text("🎉").font(.system(size: 80))
            
            Text("Сессия завершена!")
                .font(.system(size: 28, weight: .bold))
            
            VStack(spacing: 12) {
                Text("Удалено: \(deletedCount) фото")
                    .font(.system(size: 18))
                    .foregroundColor(.red)
                Text("Оставлено: \(keptCount) фото")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
            }
            .padding(20)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            Spacer().frame(height: 8)
            
            VStack(spacing: 12) {
                if hasDeletions && hasKept {
                    Button("Удалить \(deletedCount) фото в корзину") { onDeleteAndExit() }
                        .destructiveButtonStyle()
                    Button("Отсортировать остальное") { showContinueConfirm = true }
                        .secondaryButtonStyle()
                }
                if hasDeletions && !hasKept {
                    Button("Удалить \(deletedCount) фото в корзину") { onDeleteAndExit() }
                        .destructiveButtonStyle()
                }
                if !hasDeletions && hasKept {
                    Button("Завершить") { onExitWithoutDeleting() }
                        .primaryButtonStyle()
                }
                
                Button("Начать сортировку заново") {
                    showStartOverConfirm = true
                }
                .plainDestructiveButtonStyle()
            }
        }
        .padding(40)
        .alert("Начать сортировку заново?", isPresented: $showStartOverConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Да, начать заново", role: .destructive) { onStartOver() }
        } message: {
            Text("Все ваши решения за эту сессию будут отменены. Фото вернутся в общий пул и нужно будет начать сортировку с самого начала.")
        }
        .alert("Удалить \(deletedCount) фото?", isPresented: $showContinueConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить и продолжить", role: .destructive) { onContinueWithRemaining() }
        } message: {
            Text("Перед продолжением сортировки нужно удалить \(deletedCount) фото в корзину. Это действие нельзя отменить.")
        }
    }
}
