import SwiftUI
import Photos

// MARK: - TrashReviewView
//
// Ревизия «корзины» на финальном экране: мини-иконки всех PHAsset-ов,
// помеченных на удаление, с возможностью восстановить (крестик на иконке
// или кнопка в просмотре) и открыть каждый крупно с листанием свайпом.
//
// Источник истины — session.pendingDeleteIDs в SortingView. Сюда приходит
// готовый массив [PHAsset] (из pendingAssets()) и колбэк onRestore.
struct TrashReviewView: View {
    let assets: [PHAsset]
    let onRestore: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var previewIndex: Int?

    private let cellSide: CGFloat = 108
    private let cellSpacing: CGFloat = 8

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cellSide), spacing: cellSpacing)]
    }

    var body: some View {
        NavigationStack {
            Group {
                if assets.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Помечены на удаление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !assets.isEmpty {
                        Button("Восстановить всё") { restoreAll() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: previewBinding) { box in
            TrashPagerView(
                assets: assets,
                startIndex: box.value,
                onRestore: onRestore,
                onClose: { previewIndex = nil }
            )
        }
    }

    private var previewBinding: Binding<IndexBox?> {
        Binding(
            get: { previewIndex.map(IndexBox.init) },
            set: { previewIndex = $0?.value }
        )
    }

    private struct IndexBox: Identifiable {
        let value: Int
        var id: Int { value }
        init(_ value: Int) { self.value = value }
    }

    // MARK: - Сетка мини-иконок

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: cellSpacing) {
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    TrashThumbnail(
                        asset: asset,
                        side: cellSide,
                        onOpen: { previewIndex = index },
                        onRestore: { onRestore(asset.localIdentifier) }
                    )
                }
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.slash")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Корзина пуста")
                .font(.system(size: 17, weight: .semibold))
            Text("Здесь появляются файлы, помеченные на удаление.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func restoreAll() {
        let ids = assets.map(\.localIdentifier)
        for id in ids { onRestore(id) }
    }
}

// MARK: - TrashThumbnail

private struct TrashThumbnail: View {
    let asset: PHAsset
    let side: CGFloat
    let onOpen: () -> Void
    let onRestore: () -> Void

    @State private var image: UIImage?

    private var targetSize: CGSize {
        let px = side * UIScreen.main.scale
        return CGSize(width: px, height: px)
    }

    var body: some View {
        ZStack {
            Color.gray.opacity(0.15)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
            } else {
                ProgressView()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onOpen() }
        .overlay(alignment: .topTrailing) { restoreButton }
        .overlay(alignment: .topLeading) { videoBadge }
        .task {
            image = await PhotoLibraryService.shared.loadImage(
                for: asset,
                targetSize: targetSize,
                deliveryMode: .opportunistic
            )
        }
    }

    private var restoreButton: some View {
        Button {
            onRestore()
        } label: {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white, Color.blue)
                .shadow(color: .black.opacity(0.35), radius: 2)
                .padding(5)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var videoBadge: some View {
        if asset.mediaType == .video {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 3)
                .padding(6)
        }
    }
}

// MARK: - TrashPagerView
//
// Крупный просмотр с листанием. Свайп — обычный SwiftUI DragGesture на
// контейнере, ТОЧНО как в SortingView (где видео листается по всей
// площади и «плей» работает). НЕ UISwipeGestureRecognizer поверх плеера:
// тот перехватывал тап по «плей». fullScreenCover не имеет системного
// swipe-to-dismiss, поэтому DragGesture тут безопасен.
//
// Разведение осей (приоритет горизонтали): в .onEnded сначала проверяем
// горизонталь; свайп вниз срабатывает только при ЯВНО вертикальном жесте
// (height заметно больше |width|).
//
// Плеер видео ограничен по высоте (playerMaxHeight), чтобы его нижние
// controls не налезали на кнопку «Восстановить». VideoPlayerView НЕ
// меняется — ограничиваем снаружи, только здесь.
private struct TrashPagerView: View {
    let assets: [PHAsset]
    let startIndex: Int
    let onRestore: (String) -> Void
    let onClose: () -> Void

    @State private var currentIndex: Int

    // Смещение текущей страницы для двухфазной анимации листания.
    @State private var pageOffset: CGFloat = 0
    // Идёт ли сейчас анимация листания — блокирует новый свайп, пока
    // предыдущий переход не закончился (иначе фазы наложатся).
    @State private var isAnimating = false

    // Пороги свайпа
    private let horizontalThreshold: CGFloat = 60
    private let verticalCloseThreshold: CGFloat = 80
    // Во сколько раз вертикаль должна превышать горизонталь, чтобы это
    // считалось «явным» свайпом вниз (а не диагональю при листании).
    private let verticalDominance: CGFloat = 1.5

    // Длительность одной фазы (улёт или въезд). Две фазы встык = 2×.
    private let phaseDuration: Double = 0.16
    // На сколько уводим страницу за край экрана.
    private var offscreenDistance: CGFloat { UIScreen.main.bounds.width }

    init(
        assets: [PHAsset],
        startIndex: Int,
        onRestore: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.assets = assets
        self.startIndex = startIndex
        self.onRestore = onRestore
        self.onClose = onClose
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Верхняя панель
                HStack {
                    positionCounter
                    Spacer()
                    closeButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer(minLength: 8)

                // Контент с ограниченной высотой — оставляет место снизу
                // под кнопку «Восстановить», чтобы controls видео не налезали.
                //
                // Анимация листания сделана через pageOffset (смещение), а НЕ
                // через .transition. Причина: .transition анимирует уход
                // старого и приход нового ОДНОВРЕМЕННО — они накладывались.
                // Здесь на экране всегда ОДНА вьюха, у которой меняется offset:
                // фаза 1 — уезжает за край, фаза 2 — новый въезжает с другого
                // края. Наложения нет, т.к. второго элемента в дереве нет.
                Group {
                    if assets.indices.contains(currentIndex) {
                        TrashPageContent(asset: assets[currentIndex])
                            .id(assets[currentIndex].localIdentifier)
                            .offset(x: pageOffset)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)

                Spacer(minLength: 8)

                // Кнопка «Восстановить» — под плеером, в своей полосе.
                restoreButton
                    .padding(.bottom, 24)
            }
        }
        // Свайп по всей площади — как в SortingView.
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onEnded { value in
                    handleDragEnd(value.translation)
                }
        )
    }

    // MARK: - Разбор свайпа

    private func handleDragEnd(_ translation: CGSize) {
        let dx = translation.width
        let dy = translation.height

        // Приоритет горизонтали: сначала пытаемся листать.
        if abs(dx) > horizontalThreshold && abs(dx) >= abs(dy) {
            if dx < 0 {
                goNext()   // палец справа налево → следующий
            } else {
                goPrev()   // палец слева направо → предыдущий
            }
            return
        }

        // Вниз — только если жест ЯВНО вертикальный.
        if dy > verticalCloseThreshold && dy > abs(dx) * verticalDominance {
            onClose()
        }
    }

    // MARK: - Верхняя панель

    private var positionCounter: some View {
        Text("\(min(currentIndex + 1, assets.count)) из \(assets.count)")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())
    }

    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }

    private var restoreButton: some View {
        Button {
            restoreCurrent()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward")
                Text("Восстановить")
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Color.blue)
            .clipShape(Capsule())
        }
    }

    // MARK: - Навигация (двухфазная анимация: улёт → въезд)
    //
    // Вперёд (свайп влево): текущий уезжает ВЛЕВО за экран, новый въезжает
    // СПРАВА. Назад — зеркально. Фазы идут встык, без паузы и без наложения:
    // на экране всегда одна вьюха, просто её offset проходит путь
    // 0 → -край (улёт), затем мгновенно +край → 0 (въезд нового).

    private func goNext() {
        guard !isAnimating, currentIndex + 1 < assets.count else { return }
        animatePage(forward: true) { currentIndex += 1 }
    }

    private func goPrev() {
        guard !isAnimating, currentIndex > 0 else { return }
        animatePage(forward: false) { currentIndex -= 1 }
    }

    // Общая механика для обоих направлений.
    // forward == true  → улёт влево (-), въезд справа (+)
    // forward == false → улёт вправо (+), въезд слева (-)
    private func animatePage(forward: Bool, changeIndex: @escaping () -> Void) {
        isAnimating = true
        HapticsService.shared.play(.light)

        let exitOffset: CGFloat = forward ? -offscreenDistance : offscreenDistance
        let enterFrom: CGFloat = forward ? offscreenDistance : -offscreenDistance

        // Фаза 1 — улёт текущего за край.
        withAnimation(.easeIn(duration: phaseDuration)) {
            pageOffset = exitOffset
        }

        // По завершении фазы 1: сменить контент и поставить новый за
        // противоположным краем БЕЗ анимации, затем запустить фазу 2.
        DispatchQueue.main.asyncAfter(deadline: .now() + phaseDuration) {
            changeIndex()
            pageOffset = enterFrom          // мгновенно, вне withAnimation

            // Фаза 2 — въезд нового к центру.
            withAnimation(.easeOut(duration: phaseDuration)) {
                pageOffset = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + phaseDuration) {
                isAnimating = false
            }
        }
    }

    // MARK: - Восстановление текущего (вариант В)

    private func restoreCurrent() {
        guard assets.indices.contains(currentIndex) else {
            onClose()
            return
        }
        HapticsService.shared.play(.medium)
        let id = assets[currentIndex].localIdentifier
        let countAfter = assets.count - 1
        onRestore(id)
        if countAfter <= 0 {
            onClose()
        } else if currentIndex >= countAfter {
            currentIndex = countAfter - 1
        }
    }
}

// MARK: - TrashPageContent
//
// Одна страница: фото (картинка) или видео (VideoPlayerView).
// Видео ограничено по высоте, чтобы его нижние controls не доставали до
// кнопки «Восстановить». Фото такого ограничения не требует (у него нет
// нижних контролов), но для единообразия компоновки держим его в тех же
// границах через scaledToFit.
private struct TrashPageContent: View {
    let asset: PHAsset

    @State private var image: UIImage?

    // Ограничение высоты плеера. Оставляет снизу полосу под кнопку.
    // Значение эмпирическое — подобрать на устройстве, если понадобится.
    private var playerMaxHeight: CGFloat {
        UIScreen.main.bounds.height * 0.72
    }

    private var targetSize: CGSize {
        let scale = UIScreen.main.scale
        return CGSize(width: 360 * scale, height: 540 * scale)
    }

    var body: some View {
        Group {
            if asset.mediaType == .video {
                VideoPlayerView(asset: asset, onSkip: {})
                    .frame(maxHeight: playerMaxHeight)
            } else {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: playerMaxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    ProgressView()
                        .tint(.white)
                        .task {
                            image = await PhotoLibraryService.shared.loadImage(
                                for: asset,
                                targetSize: targetSize,
                                deliveryMode: .opportunistic
                            )
                        }
                }
            }
        }
    }
}
