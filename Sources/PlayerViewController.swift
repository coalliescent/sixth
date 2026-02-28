#if !TESTING
import AppKit

// Shared image cache for album art and station icons
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: URLSessionDataTask] = [:]

    private init() {
        cache.countLimit = 100
    }

    func cachedImage(for urlString: String) -> NSImage? {
        return cache.object(forKey: urlString as NSString)
    }

    func prefetch(_ urlString: String) {
        guard cache.object(forKey: urlString as NSString) == nil else { return }
        image(for: urlString) { _ in }
    }

    func image(for urlString: String, completion: @escaping (NSImage?) -> Void) {
        if let cached = cache.object(forKey: urlString as NSString) {
            completion(cached)
            return
        }

        // Cancel any existing request for this URL
        inFlight[urlString]?.cancel()

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = NSImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self?.cache.setObject(image, forKey: urlString as NSString)
            self?.inFlight.removeValue(forKey: urlString)
            DispatchQueue.main.async { completion(image) }
        }
        inFlight[urlString] = task
        task.resume()
    }
}

class PlayerViewController: NSViewController {
    // UI Elements
    private let albumArt = NSImageView()
    private let songLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let playPauseButton = NSButton()
    private let nextButton = NSButton()
    private let thumbsUpButton = NSButton()
    private let thumbsDownButton = NSButton()
    private let stationsButton = NSButton()
    private let settingsButton = NSButton()

    private let loadingSpinner = NSProgressIndicator()
    private let offlineOverlay = NSView()
    private let offlineLabel = NSTextField(labelWithString: "")

    private var errorTimer: Timer?
    private var currentSong = ""
    private var currentArtist = ""
    private var currentArtUrl: String?

    // Callbacks
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onThumbsUp: (() -> Void)?
    var onThumbsDown: (() -> Void)?
    var onStations: (() -> Void)?
    var onSettings: (() -> Void)?
    var onAbout: (() -> Void)?
    var onQuit: (() -> Void)?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 130))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor
        self.view = container
        self.preferredContentSize = NSSize(width: 360, height: 130)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        // Top row: settings gear (right-aligned)
        settingsButton.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")
        settingsButton.isBordered = false
        settingsButton.contentTintColor = .lightGray
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.sendAction(on: .leftMouseDown)
        settingsButton.target = self
        settingsButton.action = #selector(settingsTapped)

        let settingsMenu = NSMenu()
        settingsMenu.addItem(withTitle: "About Sixth", action: #selector(aboutTapped), keyEquivalent: "")
            .target = self
        settingsMenu.addItem(.separator())
        settingsMenu.addItem(withTitle: "Settings...", action: #selector(settingsMenuTapped), keyEquivalent: "")
            .target = self
        settingsMenu.addItem(.separator())
        settingsMenu.addItem(withTitle: "Quit", action: #selector(quitTapped), keyEquivalent: "")
            .target = self
        settingsButton.menu = settingsMenu

        view.addSubview(settingsButton)

        // Album art
        albumArt.wantsLayer = true
        albumArt.layer?.cornerRadius = 4
        albumArt.layer?.masksToBounds = true
        albumArt.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        albumArt.imageScaling = .scaleProportionallyUpOrDown
        albumArt.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(albumArt)

        // Song title
        songLabel.font = .systemFont(ofSize: 14, weight: .bold)
        songLabel.textColor = .white
        songLabel.lineBreakMode = .byTruncatingTail
        songLabel.maximumNumberOfLines = 1
        songLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(songLabel)

        // Artist
        artistLabel.font = .systemFont(ofSize: 12)
        artistLabel.textColor = .lightGray
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.maximumNumberOfLines = 1
        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(artistLabel)

        // Elapsed time label (left of progress bar)
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        elapsedLabel.textColor = .lightGray
        elapsedLabel.alignment = .left
        elapsedLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(elapsedLabel)

        // Progress bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.controlSize = .small
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressBar)

        // Time label (remaining, right of progress bar)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .lightGray
        timeLabel.alignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timeLabel)

        // Bottom row: thumbs | play/pause, next | stations
        thumbsDownButton.image = NSImage(systemSymbolName: "hand.thumbsdown.fill", accessibilityDescription: "Thumbs Down")
        thumbsDownButton.isBordered = false
        thumbsDownButton.contentTintColor = .lightGray
        thumbsDownButton.translatesAutoresizingMaskIntoConstraints = false
        thumbsDownButton.target = self
        thumbsDownButton.action = #selector(thumbsDownTapped)
        view.addSubview(thumbsDownButton)

        thumbsUpButton.image = NSImage(systemSymbolName: "hand.thumbsup.fill", accessibilityDescription: "Thumbs Up")
        thumbsUpButton.isBordered = false
        thumbsUpButton.contentTintColor = .lightGray
        thumbsUpButton.translatesAutoresizingMaskIntoConstraints = false
        thumbsUpButton.target = self
        thumbsUpButton.action = #selector(thumbsUpTapped)
        view.addSubview(thumbsUpButton)

        playPauseButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play/Pause")
        playPauseButton.isBordered = false
        playPauseButton.contentTintColor = .white
        let playConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        playPauseButton.symbolConfiguration = playConfig
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.target = self
        playPauseButton.action = #selector(playPauseTapped)
        view.addSubview(playPauseButton)

        nextButton.image = NSImage(systemSymbolName: "forward.end.fill", accessibilityDescription: "Next")
        nextButton.isBordered = false
        nextButton.contentTintColor = .white
        let nextConfig = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        nextButton.symbolConfiguration = nextConfig
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.target = self
        nextButton.action = #selector(nextTapped)
        view.addSubview(nextButton)

        stationsButton.title = "Stations"
        stationsButton.bezelStyle = .rounded
        stationsButton.controlSize = .small
        stationsButton.translatesAutoresizingMaskIntoConstraints = false
        stationsButton.target = self
        stationsButton.action = #selector(stationsTapped)
        view.addSubview(stationsButton)

        songLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        artistLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            // Top row
            settingsButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            settingsButton.widthAnchor.constraint(equalToConstant: 24),
            settingsButton.heightAnchor.constraint(equalToConstant: 24),

            // Album art
            albumArt.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            albumArt.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            albumArt.widthAnchor.constraint(equalToConstant: 80),
            albumArt.heightAnchor.constraint(equalToConstant: 80),

            // Song + artist
            songLabel.topAnchor.constraint(equalTo: albumArt.topAnchor, constant: 4),
            songLabel.leadingAnchor.constraint(equalTo: albumArt.trailingAnchor, constant: 12),
            songLabel.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -8),

            artistLabel.topAnchor.constraint(equalTo: songLabel.bottomAnchor, constant: 2),
            artistLabel.leadingAnchor.constraint(equalTo: songLabel.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: songLabel.trailingAnchor),

            // Elapsed label + Progress bar + time label
            elapsedLabel.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor),
            elapsedLabel.leadingAnchor.constraint(equalTo: songLabel.leadingAnchor),
            elapsedLabel.widthAnchor.constraint(equalToConstant: 34),

            progressBar.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 6),
            progressBar.leadingAnchor.constraint(equalTo: elapsedLabel.trailingAnchor, constant: 6),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -56),

            timeLabel.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: progressBar.trailingAnchor, constant: 6),
            timeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            // Bottom row
            thumbsDownButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            thumbsDownButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            thumbsDownButton.widthAnchor.constraint(equalToConstant: 24),
            thumbsDownButton.heightAnchor.constraint(equalToConstant: 24),

            thumbsUpButton.centerYAnchor.constraint(equalTo: thumbsDownButton.centerYAnchor),
            thumbsUpButton.leadingAnchor.constraint(equalTo: thumbsDownButton.trailingAnchor, constant: 12),
            thumbsUpButton.widthAnchor.constraint(equalToConstant: 24),
            thumbsUpButton.heightAnchor.constraint(equalToConstant: 24),

            playPauseButton.centerYAnchor.constraint(equalTo: thumbsDownButton.centerYAnchor),
            playPauseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 10),
            playPauseButton.widthAnchor.constraint(equalToConstant: 32),
            playPauseButton.heightAnchor.constraint(equalToConstant: 32),

            nextButton.centerYAnchor.constraint(equalTo: thumbsDownButton.centerYAnchor),
            nextButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 12),
            nextButton.widthAnchor.constraint(equalToConstant: 28),
            nextButton.heightAnchor.constraint(equalToConstant: 28),

            stationsButton.centerYAnchor.constraint(equalTo: thumbsDownButton.centerYAnchor),
            stationsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        // Loading spinner (shown during track fetches)
        loadingSpinner.style = .spinning
        loadingSpinner.controlSize = .small
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        loadingSpinner.isHidden = true
        view.addSubview(loadingSpinner)
        NSLayoutConstraint.activate([
            loadingSpinner.centerYAnchor.constraint(equalTo: artistLabel.centerYAnchor),
            loadingSpinner.leadingAnchor.constraint(equalTo: songLabel.leadingAnchor),
        ])

        // Offline overlay (initially hidden)
        offlineOverlay.wantsLayer = true
        offlineOverlay.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        offlineOverlay.translatesAutoresizingMaskIntoConstraints = false
        offlineOverlay.isHidden = true
        view.addSubview(offlineOverlay)

        // Keep settings button above the overlay
        view.addSubview(settingsButton, positioned: .above, relativeTo: offlineOverlay)

        // Offline label with wifi.slash icon
        let attachment = NSTextAttachment()
        attachment.image = NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: "No WiFi")
        attachment.image?.isTemplate = true
        let attrStr = NSMutableAttributedString(attachment: attachment)
        attrStr.append(NSAttributedString(string: "  No Network Connection"))
        attrStr.addAttributes([
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
        ], range: NSRange(location: 0, length: attrStr.length))
        offlineLabel.attributedStringValue = attrStr
        offlineLabel.alignment = .center
        offlineLabel.translatesAutoresizingMaskIntoConstraints = false
        offlineOverlay.addSubview(offlineLabel)

        NSLayoutConstraint.activate([
            offlineOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            offlineOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            offlineOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            offlineOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            offlineLabel.centerXAnchor.constraint(equalTo: offlineOverlay.centerXAnchor),
            offlineLabel.centerYAnchor.constraint(equalTo: offlineOverlay.centerYAnchor),
        ])
    }

    // MARK: - Update Methods

    func updateTrack(song: String, artist: String) {
        currentSong = song
        currentArtist = artist
        errorTimer?.invalidate()
        errorTimer = nil
        loadingSpinner.stopAnimation(nil)
        loadingSpinner.isHidden = true
        songLabel.stringValue = song
        songLabel.textColor = .white
        songLabel.toolTip = song
        artistLabel.stringValue = artist
        artistLabel.toolTip = artist
    }

    func updateAlbumArt(url: String?) {
        currentArtUrl = url
        guard let urlStr = url else {
            albumArt.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "No Art")
            return
        }

        // Use cached image immediately if available, otherwise show placeholder
        if let cached = ImageCache.shared.cachedImage(for: urlStr) {
            albumArt.image = cached
            return
        }

        albumArt.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "No Art")

        ImageCache.shared.image(for: urlStr) { [weak self] image in
            guard self?.currentArtUrl == urlStr else { return }
            if let image = image {
                self?.albumArt.image = image
            }
        }
    }

    func updateProgress(current: Double, duration: Double) {
        guard duration > 0 else { return }
        progressBar.doubleValue = current / duration

        let elapsedSec = Int(current)
        let elapsedMin = elapsedSec / 60
        let elapsedS = elapsedSec % 60
        elapsedLabel.stringValue = String(format: "%d:%02d", elapsedMin, elapsedS)

        let remaining = Int(duration - current)
        let minutes = remaining / 60
        let seconds = remaining % 60
        timeLabel.stringValue = String(format: "-%d:%02d", minutes, seconds)
    }

    func updatePlayState(isPlaying: Bool) {
        let name = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "Play/Pause")
    }

    func highlightThumbsUp(_ highlighted: Bool) {
        thumbsUpButton.contentTintColor = highlighted ? .systemGreen : .lightGray
    }

    func showError(_ message: String) {
        // Don't overwrite the now-playing display with background errors
        if !currentSong.isEmpty {
            print("[Player] suppressing error overlay (track playing): \(message)")
            return
        }
        errorTimer?.invalidate()
        songLabel.stringValue = message
        songLabel.textColor = .systemRed
        artistLabel.stringValue = ""
        errorTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.songLabel.stringValue = ""
            self?.songLabel.textColor = .white
        }
    }

    func showLoading() {
        currentSong = ""
        currentArtist = ""
        songLabel.stringValue = "Loading..."
        songLabel.textColor = .lightGray
        artistLabel.stringValue = ""
        loadingSpinner.startAnimation(nil)
        loadingSpinner.isHidden = false
    }

    func setControlsEnabled(_ enabled: Bool) {
        let tint: NSColor = enabled ? .white : .gray
        let feedbackTint: NSColor = enabled ? .lightGray : .gray
        playPauseButton.isEnabled = enabled
        playPauseButton.contentTintColor = tint
        nextButton.isEnabled = enabled
        nextButton.contentTintColor = tint
        thumbsUpButton.isEnabled = enabled
        thumbsUpButton.contentTintColor = feedbackTint
        thumbsDownButton.isEnabled = enabled
        thumbsDownButton.contentTintColor = feedbackTint
    }

    // MARK: - Offline State

    func showOffline() {
        clearTrackDisplay()
        errorTimer?.invalidate()
        errorTimer = nil
        offlineOverlay.isHidden = false
    }

    func hideOffline() {
        offlineOverlay.isHidden = true
    }

    func clearTrackDisplay() {
        currentSong = ""
        currentArtist = ""
        songLabel.stringValue = ""
        songLabel.textColor = .white
        songLabel.toolTip = nil
        artistLabel.stringValue = ""
        artistLabel.toolTip = nil
        albumArt.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "No Art")
        progressBar.doubleValue = 0
        elapsedLabel.stringValue = "0:00"
        timeLabel.stringValue = "0:00"
    }

    // MARK: - Actions

    @objc private func playPauseTapped() { onPlayPause?() }
    @objc private func nextTapped() { onNext?() }
    @objc private func thumbsUpTapped() { onThumbsUp?() }
    @objc private func thumbsDownTapped() { onThumbsDown?() }
    @objc private func stationsTapped() { onStations?() }

    @objc private func settingsTapped() {
        settingsButton.menu?.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: settingsButton.bounds.height + 2),
            in: settingsButton
        )
    }

    @objc private func aboutTapped() { onAbout?() }
    @objc private func settingsMenuTapped() { onSettings?() }
    @objc private func quitTapped() { onQuit?() }
}
#endif
