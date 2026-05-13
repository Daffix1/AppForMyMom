import SwiftUI
import AVKit
import Photos

struct VideoPlayerView: View {
    let asset: PHAsset
    let onSkip: () -> Void
    
    // MARK: - State
    
    @State private var posterImage: UIImage?
    @State private var playbackState: PlaybackState = .poster
    
    // Player-related state, only used after .playing
    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    @State private var isScrubbing = false
    @State private var timeObserver: Any?
    
    // Cancellation token for the load task
    @State private var loadTask: Task<Void, Never>?
    
    private enum PlaybackState {
        case poster
        case loading
        case playing
        case timedOut
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)
            
            // Always show the poster image underneath if we have one
            if let posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            
            // Layer on top: depends on state
            switch playbackState {
            case .poster:
                playButton
                
            case .loading:
                loadingOverlay
                
            case .playing:
                if let player {
                    CustomVideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    VStack {
                        Spacer()
                        controls.padding(.horizontal, 16).padding(.bottom, 16)
                    }
                    
                    // Center play/pause overlay when paused
                    if !isPlaying {
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
                    }
                }
                
            case .timedOut:
                timedOutOverlay
            }
        }
        .task {
            await loadPosterImage()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    // MARK: - Subviews
    
    private var playButton: some View {
        Button {
            startLoading()
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 32))
                .foregroundColor(.white)
                .frame(width: 70, height: 70)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Загружаем видео...")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    private var timedOutOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 12) {
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
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    private var controls: some View {
        HStack(spacing: 12) {
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
            
            Text(formatTime(currentTime))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 38, alignment: .leading)
            
            CustomSlider(
                value: $currentTime,
                range: 0...max(duration, 0.1),
                onEditingChanged: { editing in
                    if editing {
                        isScrubbing = true
                    } else {
                        seek(to: currentTime)
                    }
                }
            )
            .frame(maxWidth: .infinity)
            
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
    
    // MARK: - Poster image loading
    
    private func loadPosterImage() async {
        let scale = await UIScreen.main.scale
        let size = CGSize(width: 360 * scale, height: 540 * scale)
        
        posterImage = await PhotoLibraryService.shared.loadImage(
            for: asset,
            targetSize: size,
            deliveryMode: .opportunistic
        )
    }
    
    // MARK: - Start loading the video (after user taps play)
    
    private func startLoading() {
        playbackState = .loading
        
        loadTask = Task {
            await loadVideo()
        }
    }
    
    private func loadVideo() async {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .mediumQualityFormat
        options.isNetworkAccessAllowed = true
        
        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            nonisolated(unsafe) var didResume = false
            
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
        
        // Check if the task was cancelled (user swiped away)
        if Task.isCancelled {
            return
        }
        
        guard let avAsset else {
            playbackState = .timedOut
            return
        }
        
        let assetDuration = try? await avAsset.load(.duration)
        let totalSeconds = assetDuration.map { CMTimeGetSeconds($0) } ?? 0
        
        // Check again before creating the player
        if Task.isCancelled {
            return
        }
        
        let item = AVPlayerItem(asset: avAsset)
        let newPlayer = AVPlayer(playerItem: item)
        
        await MainActor.run {
            self.player = newPlayer
            self.duration = totalSeconds
            self.playbackState = .playing
            self.startObservingTime()
            // Auto-start playback since user already tapped play
            newPlayer.play()
            self.isPlaying = true
        }
    }
    
    // MARK: - Time observation
    
    private func startObservingTime() {
        guard let player else { return }
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
    
    // MARK: - Playback control
    
    private func togglePlayPause() {
        guard let player else { return }
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
    
    private func seek(to seconds: Double) {
        guard let player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(
            to: time,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { _ in
            Task { @MainActor in
                isScrubbing = false
            }
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        // Cancel any in-flight load
        loadTask?.cancel()
        loadTask = nil
        
        // Tear down the player
        player?.pause()
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Keep CustomVideoPlayer the same

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
