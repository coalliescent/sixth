#if !TESTING
import AVFoundation
import AppKit

@MainActor
class AudioPlayer {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var trackQueue: [PlaylistItem] = []
    private(set) var currentTrack: PlaylistItem?
    private(set) var isPlaying = false
    private var stationToken: String?
    private let api: PandoraAPI
    private var consecutiveFailures = 0

    // Callbacks
    var onTrackChanged: ((PlaylistItem) -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?
    var onProgress: ((Double, Double) -> Void)? // current, duration
    var onError: ((String) -> Void)?
    var onNeedMoreTracks: (() -> Void)?
    var onQueueStale: (() -> Void)?

    init(api: PandoraAPI) {
        self.api = api
    }

    // MARK: - Station

    func setStation(_ token: String) {
        print("[AudioPlayer] setStation: \(token)")
        stationToken = token
        trackQueue.removeAll()
        consecutiveFailures = 0
        stop()
    }

    // MARK: - Queue Management

    func enqueue(_ tracks: [PlaylistItem]) {
        print("[AudioPlayer] enqueue: \(tracks.count) tracks (queue was \(trackQueue.count))")
        trackQueue.append(contentsOf: tracks)
        consecutiveFailures = 0
        if currentTrack == nil && !trackQueue.isEmpty {
            playNext()
        }
    }

    func clearQueue() {
        print("[AudioPlayer] clearQueue (had \(trackQueue.count) tracks)")
        trackQueue.removeAll()
        consecutiveFailures = 0
    }

    // MARK: - Playback Controls

    func playNext() {
        guard !trackQueue.isEmpty else {
            print("[AudioPlayer] playNext: queue empty, requesting more tracks")
            onNeedMoreTracks?()
            return
        }

        let track = trackQueue.removeFirst()
        print("[AudioPlayer] playNext: \(track.songName ?? "?") (\(trackQueue.count) remaining)")
        play(track: track)

        // Prefetch when queue is low
        if trackQueue.count <= 2 {
            onNeedMoreTracks?()
        }
    }

    func play(track: PlaylistItem) {
        guard let urlStr = track.bestAudioUrl, let url = URL(string: urlStr) else {
            print("[AudioPlayer] play: no audio URL for \(track.songName ?? "?")")
            onError?("No audio URL for track")
            playNext()
            return
        }

        // Clean up previous
        cleanupObservers()
        NotificationCenter.default.removeObserver(self)

        print("[AudioPlayer] play: \(track.songName ?? "?") by \(track.artistName ?? "?")")
        currentTrack = track
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 10
        playerItem = item

        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }

        // KVO: observe item status for load failures (e.g. expired URLs)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch observedItem.status {
                case .failed:
                    let errMsg = observedItem.error?.localizedDescription ?? "unknown"
                    print("[AudioPlayer] item FAILED to load: \(errMsg)")

                    // Classify the error to choose recovery strategy
                    if let nsError = observedItem.error as NSError? {
                        let code = nsError.code
                        if code == NSURLErrorNotConnectedToInternet ||
                           code == NSURLErrorNetworkConnectionLost {
                            // Network gone — don't burn through queue
                            print("[AudioPlayer] network unavailable, waiting")
                            self.onError?("Network unavailable")
                            return
                        }
                        if code == NSURLErrorResourceUnavailable ||
                           code == NSURLErrorFileDoesNotExist ||
                           code == NSURLErrorNoPermissionsToReadFile {
                            // URL expired or forbidden — queue is stale
                            print("[AudioPlayer] resource unavailable — queue stale")
                            self.onQueueStale?()
                            return
                        }
                    }

                    // Other errors: skip track, but track consecutive failures
                    self.consecutiveFailures += 1
                    if self.consecutiveFailures >= 3 {
                        print("[AudioPlayer] \(self.consecutiveFailures) consecutive failures — queue stale")
                        self.onQueueStale?()
                    } else {
                        self.playNext()
                    }
                case .readyToPlay:
                    print("[AudioPlayer] item ready to play")
                    self.consecutiveFailures = 0
                default:
                    break
                }
            }
        }

        // Observe end of track
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.playNext()
            }
        }

        // Observe mid-playback errors
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in
                print("[AudioPlayer] mid-playback error: \(error?.localizedDescription ?? "unknown")")
                self?.onError?(error?.localizedDescription ?? "Playback failed")
                self?.playNext()
            }
        }

        // Time observer for progress
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self,
                      let duration = self.player?.currentItem?.duration,
                      duration.isNumeric else { return }
                let current = time.seconds
                let total = duration.seconds
                self.onProgress?(current, total)
            }
        }

        player?.play()
        isPlaying = true
        print("[AudioPlayer] play: started, player.rate=\(player?.rate ?? -1), item.status=\(playerItem?.status.rawValue ?? -1)")
        onTrackChanged?(track)
        onPlaybackStateChanged?(true)
    }

    func togglePlayPause() {
        guard player != nil else { return }
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            isPlaying = true
        }
        onPlaybackStateChanged?(isPlaying)
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        currentTrack = nil
        cleanupObservers()
        NotificationCenter.default.removeObserver(self)
        onPlaybackStateChanged?(false)
    }

    // MARK: - Volume

    var volume: Float {
        get { player?.volume ?? 1.0 }
        set { player?.volume = newValue }
    }

    // MARK: - Cleanup

    private func cleanupObservers() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        statusObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
#else
// Minimal stub for testing
class AudioPlayer {
    var currentTrack: PlaylistItem?
    var isPlaying = false
    var onTrackChanged: ((PlaylistItem) -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?
    var onProgress: ((Double, Double) -> Void)?
    var onError: ((String) -> Void)?
    var onNeedMoreTracks: (() -> Void)?
    var onQueueStale: (() -> Void)?

    init(api: PandoraAPI) {}
    func setStation(_ token: String) {}
    func enqueue(_ tracks: [PlaylistItem]) {}
    func clearQueue() {}
    func playNext() {}
    func togglePlayPause() {}
    func stop() {}
}
#endif
