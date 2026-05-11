import SwiftUI
import AVKit
import Photos

struct VideoPlayerView: View {
    let asset: PHAsset
    let onSkip: () -> Void
    
    // Сам плеер — создаётся когда видео загрузится
    @State private var player: AVPlayer?

    // Текущая позиция в видео (в секундах)
    @State private var currentTime: Double = 0

    // Длина видео (в секундах)
    @State private var duration: Double = 0

    // Играет ли видео сейчас
    @State private var isPlaying = false

    // Перетаскивает ли пользователь ползунок прямо сейчас
    @State private var isScrubbing = false

    // Хранит "наблюдателя" за прогрессом видео
    @State private var timeObserver: Any?
    
    // Состояние загрузки видео — для показа подсказки пользователю
    @State private var loadingState: LoadingState = .silent

    private enum LoadingState {
        case silent
        case generic
        case fromICloud
        case timedOut
    }

    var body: some View {
        ZStack {
            // Фон карточки — пока видео грузится
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)

            if let player = player {
                // VideoPlayer без системных контролов
                CustomVideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(spacing: 12) {
                    if loadingState == .timedOut {
                        Image(systemName: "icloud.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.7))

                        Text("Не удалось загрузить")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))

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
                            .tint(.white)
                        if let text = loadingText {
                            Text(text)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.9))
                                .transition(.opacity)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: loadingState)
            }

            // Контролы поверх видео — снизу
            VStack {
                Spacer()
                if player != nil {
                    controls
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }

            // Большая кнопка play по центру когда видео на паузе
            if player != nil && !isPlaying {
                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                        .frame(width: 70, height: 70)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in }
                        .onEnded { _ in }
                )
            }
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            cleanup()
        }
    }

    // MARK: - Контролы внизу видео

    private var controls: some View {
        HStack(spacing: 12) {
            // Кнопка play/pause
            Button {
                togglePlayPause()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            // Текущее время
            Text(formatTime(currentTime))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 38, alignment: .leading)

            // Наш кастомный ползунок с полным контролем над жестами
            CustomSlider(
                value: $currentTime,
                range: 0...max(duration, 0.1),
                onEditingChanged: { editing in
                    if editing {
                        // Начали тянуть — блокируем автообновление ползунка
                        isScrubbing = true
                    } else {
                        // Отпустили — НЕ снимаем флаг сразу
                        // Сначала перематываем, флаг снимется внутри seek
                        seek(to: currentTime)
                    }
                }
            )
            .frame(maxWidth: .infinity)

            // Общая длительность
            Text(formatTime(duration))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var loadingText: String? {
        switch loadingState {
        case .silent:     return nil
        case .generic:    return "Загружаем видео..."
        case .fromICloud: return "Загружаем из iCloud..."
        case .timedOut:   return nil
        }
    }

    // MARK: - Загрузка видео из галереи

    private func loadVideo() async {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .mediumQualityFormat
        options.isNetworkAccessAllowed = true

        options.progressHandler = { _, _, _, _ in
            Task { @MainActor in
                loadingState = .fromICloud
            }
        }

        // 2-секундный таймер для generic-текста
        let textTimerTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled, player == nil, loadingState == .silent {
                loadingState = .generic
            }
        }

        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            nonisolated(unsafe) var didResume = false

            // Таймаут — через 15 секунд форсируем resume с nil
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(15))
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: nil)
            }

            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, _ in
                guard !didResume else { return }
                didResume = true
                timeoutTask.cancel()
                continuation.resume(returning: avAsset)
            }
        }

        textTimerTask.cancel()

        // avAsset == nil означает таймаут или ошибку
        guard let avAsset else {
            loadingState = .timedOut
            return
        }

        let assetDuration = try? await avAsset.load(.duration)
        let totalSeconds = assetDuration.map { CMTimeGetSeconds($0) } ?? 0

        let item = AVPlayerItem(asset: avAsset)
        let newPlayer = AVPlayer(playerItem: item)

        await MainActor.run {
            self.player = newPlayer
            self.duration = totalSeconds
            startObservingTime()
        }
    }

    // MARK: - Слежение за временем воспроизведения

    private func startObservingTime() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { time in
            if !isScrubbing {
                currentTime = CMTimeGetSeconds(time)
            }
        }
    }

    // MARK: - Управление воспроизведением

    private func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            if currentTime >= duration - 0.1 {
                seek(to: 0)
            }
            player.play()
        }
        isPlaying.toggle()
    }
    // MARK: - Перемотка
    
    private func seek(to seconds: Double) {
        guard let player = player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        
        // seek с completion — плеер сообщит когда перемотка реально завершилась
        player.seek(
            to: time,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { _ in
            // Только после успешной перемотки разрешаем
            // наблюдателю обновлять ползунок снова
            Task { @MainActor in
                isScrubbing = false
            }
        }
    }

    // MARK: - Очистка ресурсов

    private func cleanup() {
        // Сначала остановить воспроизведение
        player?.pause()
        
        // Убрать наблюдатель за временем
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Заменить player item на nil чтобы освободить декодер
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    // MARK: - Форматирование времени

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Кастомный плеер без системных контролов

struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
