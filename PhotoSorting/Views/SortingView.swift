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
    @State private var pinchScale: CGFloat = 1.0
    @State private var pinchAnchor: UnitPoint = .center
    @State private var panOffset: CGSize = .zero
    @State private var isZooming: Bool = false
    @State private var sessionFinished = false
    
    // массив кейсов для кнопки "назад"
    @State private var swipeHistory: [SwipeDirection] = []
    enum SwipeDirection { case left, right }
    
    // Сколько фото за сегодня осталось несвайпнутых
    // Считается при показе финального экрана
    @State private var remainingPhotos: Int = 0
    
    // Освобождаемое место (оценка) для финального экрана.
    // Считается заранее, пока pendingDeleteIDs ещё указывают на существующие
    // ассеты — после удаления PHAsset исчезает и размер не получить.
    @State private var estimatedFreedBytes: Int64 = 0
    
    @State private var preloadTasks: [Task<Void, Never>] = []
    
    // MARK: - Constants
    
    private let swipeThreshold: CGFloat = 120   // минимальный сдвиг для засчитывания свайпа
    private let cardFlyOutDistance: CGFloat = 600 // расстояние улёта карточки за экран
    private let labelOpacityDivisor: Double = 80  // делитель для прозрачности надписей УДАЛИТЬ/ОСТАВИТЬ
    private let labelOpacityOffset: Double = 20   // сдвиг начала появления надписи
    private let swipeAnimationDuration: Double = 0.25  // длительность анимации улёта карточки
    private let nextCardDelay: Double = 0.3            // задержка перед показом следующей карточки
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
        // Without this, the first .medium haptic call has a noticeable delay
        // because iOS has to power up the Taptic Engine.
        let medium = UIImpactFeedbackGenerator(style: .medium)
        medium.prepare()
        
        let light = UIImpactFeedbackGenerator(style: .light)
        light.prepare()
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
                    // Кнопка "Назад" (отмена последнего свайпа)
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
                    
                    // Кнопка "X" — выход из сортировки с сохранением прогресса
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
            GeometryReader { geometry in
                ZStack {
                    behindCardLabels
                    PhotoCardView(
                        item: photos[currentIndex],
                        offset: dragOffset,
                        onSkip: {
                            performSwipe(direction: .right)
                        },
                        pinchScale: $pinchScale,
                        pinchAnchor: $pinchAnchor,
                        panOffset: $panOffset
                    )
                    .id(currentIndex)
                    .animation(.interactiveSpring(), value: dragOffset)
                    
                    // Show zoom overlay only for photos, not videos
                    // Videos have their own controls (play, slider) that need touch access
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
        
        // STEP 1: Start the visual animation IMMEDIATELY.
        // Nothing here can block the main thread for long — no disk writes,
        // no JSON encoding. The user sees the card fly away instantly.
        HapticsService.shared.play(.medium)
        
        swipeHistory.append(direction)
        
        withAnimation(.easeOut(duration: swipeAnimationDuration)) {
            dragOffset = direction == .left ? -cardFlyOutDistance : cardFlyOutDistance
        }
        
        // STEP 2: Do the heavy work asynchronously.
        // Storage writes (UserDefaults JSON encoding) run on a background task
        // so they don't block the animation.
        Task {
            // Mutate the local copy of the session
            if direction == .left {
                session.pendingDeleteIDs.append(photo.id)
                session.currentDeletedIDs.append(photo.id)
            } else {
                session.currentKeptIDs.append(photo.id)
            }
            session.processedIDs.insert(photo.id)
            
            // Записываем свайп в журнал. swipeLog — это упорядоченная история
            // свайпов за сессию; используется при переоткрытии SortingView для
            // восстановления currentIndex и swipeHistory (см. reconstructStateFromLog).
            let entryDirection: DailySessionState.SwipeEntry.Direction =
                direction == .left ? .left : .right
            session.swipeLog.append(
                DailySessionState.SwipeEntry(photoID: photo.id, direction: entryDirection)
            )
            
            // Storage writes (these trigger UserDefaults I/O)
            storage.currentSession = session
            
            var sorted = storage.sortedPhotoIDs
            sorted.insert(photo.id)
            storage.sortedPhotoIDs = sorted
            
            // STEP 3: Wait for the fly-out animation to mostly finish,
            // then show the next card.
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
        
        // Снимаем последнюю запись из журнала свайпов — он должен идти
        // в ногу с swipeHistory и currentDeletedIDs/currentKeptIDs.
        if !session.swipeLog.isEmpty {
            session.swipeLog.removeLast()
        }
        
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
    
    // MARK: - Восстановление состояния из swipeLog

    // Вызывается при появлении SortingView. Смотрит на journal свайпов
    // в session.swipeLog и приводит локальное состояние (currentIndex,
    // swipeHistory) в соответствие.
    //
    // Зачем: после закрытия SortingView и повторного открытия @State
    // сбрасывается — currentIndex становится 0, swipeHistory пустеет.
    // Но в session.swipeLog хранится полная история свайпов за сессию.
    // Этот метод "догоняет" локальное состояние до содержимого журнала.
    private func reconstructStateFromLog() {
        let log = session.swipeLog
        guard !log.isEmpty else {
            // Журнал пуст — новая или ни разу не свайпавшаяся сессия.
            // Оставляем currentIndex = 0, swipeHistory = [].
            return
        }
        
        // На случай если какие-то фото из журнала больше не существуют
        // (пользователь удалил через iOS Photos между сессиями), считаем
        // только те записи, чьи photoID есть в текущем списке photos.
        let existingIDs = Set(photos.map(\.id))
        let validEntries = log.filter { existingIDs.contains($0.photoID) }
        
        // currentIndex — количество валидных свайпов. Следующий несвайпнутый
        // фото находится в photos[validEntries.count] (если он существует).
        currentIndex = validEntries.count
        
        // Восстанавливаем swipeHistory в том же порядке, что и в журнале —
        // последний элемент = последний свайп = первый кандидат на undo.
        swipeHistory = validEntries.map { entry in
            entry.direction == .left ? .left : .right
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
        
        // Считаем размер и тип ДО удаления — после удаления PHAsset исчезает
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
        session.swipeLog = []
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
    
    // Оценивает освобождаемое место по pendingDeleteIDs (до фактического удаления).
    // Показывается на финальном экране.
    private func estimatePendingFreedBytes() -> Int64 {
        let assets = pendingAssets()
        return assets.reduce(Int64(0)) { sum, asset in
            sum + PhotoLibraryService.estimateSize(for: asset)
        }
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
            // Спокойный заголовок с галочкой вместо 🎉
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            
            Text("Сессия завершена")
                .font(.system(size: 24, weight: .bold))
            
            // Главный мотиватор: освобождаемое место.
            // Показываем только когда есть что удалять.
            if hasDeletions {
                freedSpaceBlock
            }
            
            // Счётчики карточками
            countCards
            
            Spacer().frame(height: 4)
            
            // Кнопки действий
            actionButtons
        }
        .padding(32)
        .alert("Начать сортировку заново?", isPresented: $showStartOverConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Да, начать заново", role: .destructive) { onStartOver() }
        } message: {
            Text("Все ваши решения за эту сессию будут отменены. Файлы вернутся в общий пул и нужно будет начать сортировку с самого начала.")
        }
        .alert("Удалить \(deletedCount) \(deletedCount.fileWordFinal())?", isPresented: $showContinueConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить и продолжить", role: .destructive) { onContinueWithRemaining() }
        } message: {
            Text("Перед продолжением сортировки нужно удалить \(deletedCount) \(deletedCount.fileWordFinal()) в корзину. Это действие нельзя отменить.")
        }
    }
    
    // MARK: - Блок освобождаемого места
    
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
    
    // MARK: - Счётчики карточками
    
    private var countCards: some View {
        HStack(spacing: 12) {
            // Карточка «к удалению» — показываем если что-то удаляем
            if hasDeletions {
                countCard(value: deletedCount, label: "к удалению", color: .red)
            }
            // Карточка «оставлено» — показываем если что-то оставлено
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
    
    // MARK: - Кнопки действий
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Основное действие — всегда верхней кнопкой.
            // Удаление всегда красное с корзиной; на его месте никогда
            // не стоит безопасная кнопка.
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
                
                // Вторичное: продолжить сортировку оставшихся
                if hasKept {
                    Button("Удалить и продолжить") { showContinueConfirm = true }
                        .secondaryButtonStyle()
                }
            } else {
                // Удалять нечего → нейтральное завершение на месте основного действия
                Button("Готово") { onExitWithoutDeleting() }
                    .primaryButtonStyle()
            }
            
            // «Начать заново» — всегда последней тихой строкой
            Button("Начать сортировку заново") {
                showStartOverConfirm = true
            }
            .plainDestructiveButtonStyle()
        }
    }
    
    // MARK: - Форматирование места
    
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
