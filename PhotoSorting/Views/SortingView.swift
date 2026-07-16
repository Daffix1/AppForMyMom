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

    // Рабочая копия сессии. Инициализируется из storage в onAppear.
    // Все изменения гоним по этой копии, затем пишем обратно в
    // storage.currentSession (что уходит в UserDefaults через didSet).
    @State private var session: DailySessionState = StorageService.shared.currentSession

    // Счетчик фото, сколько отсортировали
    @State private var currentIndex = 0

    // Анимационные переменные
    @State private var dragOffset: CGFloat = 0
    @State private var pinchScale: CGFloat = 1.0
    @State private var pinchAnchor: UnitPoint = .center
    @State private var panOffset: CGSize = .zero
    @State private var isZooming: Bool = false
    @State private var sessionFinished = false

    // массив кейсов для кнопки "назад"
    @State private var swipeHistory: [SwipeDirection] = []
    enum SwipeDirection { case left, right }

    // Сколько фото за выбранный день осталось несвайпнутых.
    // Считается при показе финального экрана.
    @State private var remainingPhotos: Int = 0

    // Освобождаемое место (оценка) для финального экрана.
    // Считается заранее, пока pendingDeleteIDs ещё указывают на существующие
    // ассеты — после удаления PHAsset исчезает и размер не получить.
    @State private var estimatedFreedBytes: Int64 = 0

    @State private var preloadTasks: [Task<Void, Never>] = []

    // MARK: - Constants

    private let swipeThreshold: CGFloat = 120   // минимальный сдвиг для засчитывания свайпа
    private let cardFlyOutDistance: CGFloat = 600 // расстояние улёта карточки за экран
    private let swipeAnimationDuration: Double = 0.18  // длительность анимации улёта карточки
    private let nextCardDelay: Double = 0.18           // задержка перед показом следующей карточки
    private let preloadAheadCount: Int = 2             // сколько карточек предзагружать вперёд
    private let cardTargetWidth: CGFloat = 360         // ширина карточки для загрузки изображения
    private let cardTargetHeight: CGFloat = 540        // высота карточки для загрузки изображения

    var body: some View {
        ZStack {
            mainContent
        }
        .onAppear {
            session = storage.currentSession
            if session.phase == .idle {
                session.phase = .sorting
                storage.currentSession = session
            }
            reconstructStateFromLog()
            preloadNextPhotos()
            prepareHaptics()
        }
        .task(id: sessionFinished) {
            if sessionFinished {
                remainingPhotos = await calculateRemaining()
                estimatedFreedBytes = estimatePendingFreedBytes()
            }
        }
    }

    private func prepareHaptics() {
        // Warm up the haptic engines so the first swipe feels instant.
        let medium = UIImpactFeedbackGenerator(style: .medium)
        medium.prepare()

        let light = UIImpactFeedbackGenerator(style: .light)
        light.prepare()
    }

    // MARK: - Основной контент

    @ViewBuilder
    private var mainContent: some View {
        if sessionFinished || session.phase == .awaitingDecision {
            sessionFinishedView
        } else if currentIndex < photos.count {
            sortingContent
        } else {
            sessionFinishedView
        }
    }

    // MARK: - Экран сортировки

    private var sortingContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
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

                    Button {
                        HapticsService.shared.play(.light)
                        onFinish()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                            .frame(width: 36, height: 36)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(Circle())
                    }
                }

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
            GeometryReader { geometry in
                ZStack {
                    PhotoCardView(
                        item: photos[currentIndex],
                        offset: dragOffset,
                        onSkip: {
                            performSwipe(direction: .right)
                        },
                        dragOffset: dragOffset,
                        pinchScale: $pinchScale,
                        pinchAnchor: $pinchAnchor,
                        panOffset: $panOffset
                    )
                    .id(currentIndex)
                    .animation(.interactiveSpring(), value: dragOffset)

                    if photos[currentIndex].asset.mediaType != .video {
                        ZoomGestureOverlay(
                            scale: $pinchScale,
                            offset: $panOffset,
                            anchor: $pinchAnchor,
                            isZooming: $isZooming,
                            onZoomEnd: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    pinchScale = 1.0
                                    panOffset = .zero
                                }
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard pinchScale == 1.0 else { return }
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            guard pinchScale == 1.0 else { return }
                            handleSwipeEnd(translation: value.translation.width)
                        }
                )
                .padding(.horizontal, 20)
            }

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

    // MARK: - Финальный экран сортировки

    private var sessionFinishedView: some View {
        SessionFinishedView(
            deletedCount: session.deletedCount,
            keptCount: session.keptCount,
            remainingCount: remainingPhotos,
            estimatedFreedBytes: estimatedFreedBytes,
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

    // MARK: - Обработка свайпа

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

        // STEP 1: визуальная анимация СРАЗУ — ничего тяжёлого на главном потоке.
        HapticsService.shared.play(.medium)

        swipeHistory.append(direction)

        withAnimation(.easeOut(duration: swipeAnimationDuration)) {
            dragOffset = direction == .left ? -cardFlyOutDistance : cardFlyOutDistance
        }

        // STEP 2: тяжёлая работа асинхронно (UserDefaults I/O не блокирует анимацию).
        Task {
            if direction == .left {
                session.pendingDeleteIDs.append(photo.id)
                session.currentDeletedIDs.append(photo.id)
            } else {
                session.currentKeptIDs.append(photo.id)
            }
            session.processedIDs.insert(photo.id)

            let entryDirection: DailySessionState.SwipeEntry.Direction =
                direction == .left ? .left : .right
            session.swipeLog.append(
                DailySessionState.SwipeEntry(photoID: photo.id, direction: entryDirection)
            )

            // Пишем сессию в storage (UserDefaults). Глобального пула больше нет —
            // единственный «фильтр показа» это swipeLog внутри самой сессии.
            storage.currentSession = session

            // STEP 3: ждём завершения улёта, показываем следующую карточку.
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

    // MARK: - Досрочное завершение

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

        if !session.swipeLog.isEmpty {
            session.swipeLog.removeLast()
        }

        storage.currentSession = session

        dragOffset = 0
    }

    // MARK: - Предзагрузка следующих фото

    private func preloadNextPhotos() {
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

    // MARK: - Восстановление состояния из swipeLog

    private func reconstructStateFromLog() {
        let log = session.swipeLog
        guard !log.isEmpty else {
            return
        }

        let existingIDs = Set(photos.map(\.id))
        let validEntries = log.filter { existingIDs.contains($0.photoID) }

        currentIndex = validEntries.count

        swipeHistory = validEntries.map { entry in
            entry.direction == .left ? .left : .right
        }
    }

    // MARK: - Действия с финального экрана

    // "Удалить N в корзину" → выход на главный
    private func deleteAndExit() async {
        guard await deleteFromGalleryIfNeeded() else { return }
        clearSessionBuffers()
        saveSessionPhase(.completed)
        onFinish()
    }

    // "Удалить и продолжить" — удаляем, переоткрываем
    private func deleteAndContinue() async {
        guard await deleteFromGalleryIfNeeded() else { return }
        clearSessionBuffers()
        saveSessionPhase(.sorting)
        onContinueRequested()
    }

    // "Завершить" (когда удалять нечего) — просто выходим
    private func exitWithoutDeleting() {
        clearSessionBuffers()
        saveSessionPhase(.completed)
        onFinish()
    }

    // "Начать заново" — сбрасываем прогресс сессии, переоткрываем
    private func startOver() {
        session.processedIDs = []
        clearSessionBuffers()
        saveSessionPhase(.sorting)
        onContinueRequested()
    }

    // MARK: - Helper-методы для финала

    private func deleteFromGalleryIfNeeded() async -> Bool {
        let assetsToDelete = pendingAssets()
        guard !assetsToDelete.isEmpty else { return true }

        var freedBytes: Int64 = 0
        var deletedPhotos = 0
        var deletedVideos = 0
        for asset in assetsToDelete {
            freedBytes += PhotoLibraryService.estimateSize(for: asset)
            if asset.mediaType == .video {
                deletedVideos += 1
            } else {
                deletedPhotos += 1
            }
        }

        let success = await photoService.deletePhotos(assetsToDelete)
        guard success else { return false }

        storage.totalDeletedPhotos += deletedPhotos
        storage.totalDeletedVideos += deletedVideos
        storage.totalFreedBytes += freedBytes

        return true
    }

    // Сбрасывает буферы текущей под-сессии (processedIDs не трогаем — копится за день)
    private func clearSessionBuffers() {
        session.pendingDeleteIDs = []
        session.currentDeletedIDs = []
        session.currentKeptIDs = []
        session.swipeLog = []
    }

    private func saveSessionPhase(_ phase: DailySessionState.Phase) {
        session.phase = phase
        storage.currentSession = session
    }

    // MARK: - Вспомогательные функции

    private func pendingAssets() -> [PHAsset] {
        guard !session.pendingDeleteIDs.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: session.pendingDeleteIDs, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    private func estimatePendingFreedBytes() -> Int64 {
        let assets = pendingAssets()
        return assets.reduce(Int64(0)) { sum, asset in
            sum + PhotoLibraryService.estimateSize(for: asset)
        }
    }

    // Сколько фото за выбранный день ещё несвайпнуты.
    //
    // Считаем по selectedMonth/selectedDay текущей сессии, вычитая уже
    // обработанные в этой сессии (processedIDs). Раньше здесь была развилка
    // «сегодня/прошлый день» под эфемерный стор — теперь стор один, сессия
    // персистентная для любого дня, поэтому логика единая.
    private func calculateRemaining() async -> Int {
        let all = await photoService.fetchPhotos(
            month: session.selectedMonth,
            day: session.selectedDay
        )
        let processed = session.processedIDs
        return all.filter { !processed.contains($0.id) }.count
    }
}

// MARK: - Финальный экран

struct SessionFinishedView: View {
    let deletedCount: Int
    let keptCount: Int
    let remainingCount: Int
    let estimatedFreedBytes: Int64

    let onDeleteAndExit: () -> Void
    let onContinueWithRemaining: () -> Void
    let onStartOver: () -> Void
    let onExitWithoutDeleting: () -> Void

    @State private var showStartOverConfirm = false
    @State private var showContinueConfirm = false

    private var hasDeletions: Bool { deletedCount > 0 }
    private var hasKept: Bool { keptCount > 0 }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("Сессия завершена")
                .font(.system(size: 24, weight: .bold))

            if hasDeletions {
                freedSpaceBlock
            }

            countCards

            Spacer().frame(height: 4)

            actionButtons
        }
        .padding(32)
        .alert("Начать сортировку заново?", isPresented: $showStartOverConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Да, начать заново", role: .destructive) { onStartOver() }
        } message: {
            Text("Все ваши решения за эту сессию будут отменены. Нужно будет начать сортировку с самого начала.")
        }
        .alert("Удалить \(deletedCount) \(deletedCount.fileWordFinal())?", isPresented: $showContinueConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить и продолжить", role: .destructive) { onContinueWithRemaining() }
        } message: {
            Text("Перед продолжением сортировки нужно удалить \(deletedCount) \(deletedCount.fileWordFinal()) в корзину. Это действие нельзя отменить.")
        }
    }

    private var freedSpaceBlock: some View {
        VStack(spacing: 2) {
            Text("ОСВОБОДИТСЯ")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.green)
            Text("~\(formattedFreedSpace)")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.green)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.green.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var countCards: some View {
        HStack(spacing: 12) {
            if hasDeletions {
                countCard(value: deletedCount, label: "к удалению", color: .red)
            }
            if hasKept {
                countCard(value: keptCount, label: "оставлено", color: .green)
            }
        }
    }

    private func countCard(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if hasDeletions {
                Button {
                    onDeleteAndExit()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                        Text("Удалить \(deletedCount) \(deletedCount.fileWordFinal()) и выйти")
                    }
                }
                .destructiveButtonStyle()

                if hasKept {
                    Button("Удалить и продолжить") { showContinueConfirm = true }
                        .secondaryButtonStyle()
                }
            } else {
                Button("Готово") { onExitWithoutDeleting() }
                    .primaryButtonStyle()
            }

            Button("Начать сортировку заново") {
                showStartOverConfirm = true
            }
            .plainDestructiveButtonStyle()
        }
    }

    private var formattedFreedSpace: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: estimatedFreedBytes)
    }
}

// MARK: - Склонение слова «файл» для финального экрана

private extension Int {
    func fileWordFinal() -> String {
        let lastDigit = self % 10
        let lastTwo = self % 100

        if lastTwo >= 11 && lastTwo <= 14 {
            return "файлов"
        }
        switch lastDigit {
        case 1: return "файл"
        case 2, 3, 4: return "файла"
        default: return "файлов"
        }
    }
}
