import SwiftUI
import Photos

struct PhotoCardView: View {
    let item: PhotoItem
    let offset: CGFloat
    let onSkip: () -> Void
    
    @Binding var pinchScale: CGFloat
    @Binding var pinchAnchor: UnitPoint  // NEW
    @Binding var panOffset: CGSize

    var body: some View {
        Group {
            if item.asset.mediaType == .video {
                VideoPlayerView(asset: item.asset, onSkip: onSkip)
            } else {
                PhotoImageView(asset: item.asset, onSkip: onSkip)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    // Scale around the anchor point captured at pinch start
                    .scaleEffect(pinchScale, anchor: pinchAnchor)
                    // Then translate based on pan
                    .offset(panOffset)
            }
        }
        .rotationEffect(.degrees(Double(offset) / 20))
        .offset(x: offset)
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
