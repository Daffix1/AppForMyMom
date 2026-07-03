import SwiftUI
import Photos

struct PhotoCardView: View {
    let item: PhotoItem
    let offset: CGFloat
    let onSkip: () -> Void
    
    // NEW: насколько утащили карточку (приходит из SortingView).
    // Нужно для расчёта интенсивности и направления оверлея свайпа.
    // Отрицательное = влево (удалить), положительное = вправо (оставить).
    let dragOffset: CGFloat
    
    @Binding var pinchScale: CGFloat
    @Binding var pinchAnchor: UnitPoint
    @Binding var panOffset: CGSize

    // MARK: - Константы оверлея свайпа
    
    // Дистанция, на которой оверлей достигает максимума.
    // Берём равной swipeThreshold (120) из SortingView — к моменту
    // засчитывания свайпа оверлей уже на полную силу.
    private let overlayFullDistance: CGFloat = 120
    
    // «Мёртвая зона» в начале драга: первые N точек оверлея ещё нет.
    // Защищает от мигания при микродрожании пальца.
    private let overlayActivation: CGFloat = 12
    
    // Потолок непрозрачности цветной ЗАЛИВКИ. Не 1.0 — иначе фото
    // полностью скроется, а пользователь хочет видеть, что удаляет/оставляет.
    private let overlayFillMaxOpacity: Double = 0.45
    
    // Радиус скругления карточки — должен совпадать с фото и видео-плеером.
    private let cardCornerRadius: CGFloat = 20

    var body: some View {
        Group {
            if item.asset.mediaType == .video {
                VideoPlayerView(asset: item.asset, onSkip: onSkip)
            } else {
                PhotoImageView(asset: item.asset, onSkip: onSkip)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
                    // Scale around the anchor point captured at pinch start
                    .scaleEffect(pinchScale, anchor: pinchAnchor)
                    // Then translate based on pan
                    .offset(panOffset)
            }
        }
        // Оверлей свайпа — поверх всего содержимого карточки.
        // Лежит ВНУТРИ PhotoCardView, поэтому наследует rotationEffect и
        // offset ниже — улетает и поворачивается вместе с карточкой.
        .overlay {
            swipeOverlay
        }
        .rotationEffect(.degrees(Double(offset) / 20))
        .offset(x: offset)
    }
    
    // MARK: - Оверлей свайпа
    
    @ViewBuilder
    private var swipeOverlay: some View {
        // intensity: 0...1, насколько ярко показывать оверлей.
        // Вычитаем мёртвую зону, делим на рабочую дистанцию, ограничиваем 0...1.
        let distance = abs(dragOffset)
        let rawIntensity = (distance - overlayActivation) / (overlayFullDistance - overlayActivation)
        let intensity = max(0, min(1, rawIntensity))
        
        // Направление: влево (<0) удалить — красный/корзина;
        // вправо (>0) оставить — зелёный/галочка.
        let isDelete = dragOffset < 0
        let color: Color = isDelete ? .red : .green
        let iconName = isDelete ? "trash.fill" : "checkmark.circle.fill"
        
        // Рисуем только когда есть что показывать (intensity > 0).
        // При intensity == 0 (карточка по центру) оверлей полностью прозрачен.
        if intensity > 0 {
            ZStack {
                // Цветная заливка по форме карточки.
                // Непрозрачность = intensity * потолок (0.45).
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .fill(color.opacity(intensity * overlayFillMaxOpacity))
                
                // Иконка по центру. Непрозрачность доходит до 1.0.
                Image(systemName: iconName)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(intensity)
                    // Лёгкая тень, чтобы иконка читалась на светлом фото.
                    .shadow(color: .black.opacity(0.25), radius: 8)
                    // Небольшой «прирост» размера с интенсивностью —
                    // иконка как будто наливается силой к порогу свайпа.
                    .scaleEffect(0.8 + 0.2 * intensity)
            }
            // Оверлей не должен перехватывать касания — жесты идут сквозь него
            // к нижележащему DragGesture/ZoomGestureOverlay в SortingView.
            .allowsHitTesting(false)
        }
    }
}

struct PhotoImageView: View {
    let asset: PHAsset
    let onSkip: () -> Void
    @State private var image: UIImage?
    @State private var loadingState: LoadingState = .silent

    private enum LoadingState {
        case silent
        case generic
        case fromICloud
        case timedOut
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                loadingPlaceholder
            }
        }
        .task {
            await loadImage()
        }
    }

    // MARK: - Заглушка во время загрузки

    private var loadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.gray.opacity(0.2))
            .overlay {
                VStack(spacing: 12) {
                    if loadingState == .timedOut {
                        // Иконка ошибки
                        Image(systemName: "icloud.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)

                        Text("Не удалось загрузить")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)

                        Button("Что-то пошло не так, отсортировать позже") {
                            onSkip()
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.gray)
                        .clipShape(Capsule())
                    } else {
                        ProgressView()
                        if let text = loadingText {
                            Text(text)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .transition(.opacity)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: loadingState)
            }
    }

    private var loadingText: String? {
        switch loadingState {
        case .silent:     return nil
        case .generic:    return "Загружаем фото..."
        case .fromICloud: return "Загружаем из iCloud..."
        case .timedOut:   return nil  // в timedOut показываем кнопку, не текст
        }
    }

    // MARK: - Загрузка

    private func loadImage() async {
            let scale = await UIScreen.main.scale
            let size = CGSize(width: 360 * scale, height: 540 * scale)

            let textTimerTask = Task {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled, image == nil, loadingState == .silent {
                    loadingState = .generic
                }
            }

            // Pass an onPreview callback so we show the low-quality version
            // immediately while the high-quality version is still loading
            let finalImage = await PhotoLibraryService.shared.loadImage(
                for: asset,
                targetSize: size,
                deliveryMode: .opportunistic,
                onICloudProgress: { _ in
                    loadingState = .fromICloud
                },
                onPreview: { preview in
                    // Only set if we don't have anything yet
                    // (avoids replacing a higher quality image with a preview)
                    if image == nil {
                        image = preview
                    }
                }
            )

            textTimerTask.cancel()

            if let finalImage {
                // High-quality version replaces the preview
                image = finalImage
            } else if image == nil {
                // Nothing loaded at all — timeout state
                loadingState = .timedOut
            }
        }
    }
