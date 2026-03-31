#if !TESTING
import AppKit
import os

private let logger = Logger(subsystem: "com.sixth.app", category: "Player")

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

class PlayerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    // UI Elements
    private let albumArt = NSImageView()
    private let songLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let replayButton = NSButton()
    private let playPauseButton = NSButton()
    private let nextButton = NSButton()
    private let thumbsUpButton = NSButton()
    private let thumbsDownButton = NSButton()
    private let stationsButton = NSButton()
    private let settingsButton = NSButton()
    private let quitButton = NSButton()
    private let aboutButton = NSButton()

    // History UI
    private let historyToggleButton = NSButton()
    private let historyChevron = NSButton()
    private let historySeparator = NSView()
    private let historyScrollView = NSScrollView()
    private let historyTableView = NSTableView()
    private var historyHeightConstraint: NSLayoutConstraint!
    private(set) var isHistoryOpen = false

    private let loadingSpinner = NSProgressIndicator()
    private let offlineOverlay = NSView()
    private let offlineLabel = NSTextField(labelWithString: "")

    private var errorTimer: Timer?
    private var currentSong = ""
    private var currentArtist = ""
    private var currentArtUrl: String?

    // Callbacks
    var onReplay: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onThumbsUp: (() -> Void)?
    var onThumbsDown: (() -> Void)?
    var onStations: (() -> Void)?
    var onSettings: (() -> Void)?
    var onAbout: (() -> Void)?
    var onQuit: (() -> Void)?
    var onHistoryToggled: ((Bool) -> Void)?
    var onHistoryThumbsUp: ((String) -> Void)?
    var onHistoryThumbsDown: ((String) -> Void)?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 134))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor
        container.autoresizingMask = [.width, .height]
        self.view = container
        self.preferredContentSize = NSSize(width: 360, height: 134)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        // Button column (right side): quit, settings, about
        quitButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Quit")
        quitButton.isBordered = false
        quitButton.contentTintColor = .lightGray
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        quitButton.target = self
        quitButton.action = #selector(quitTapped)
        view.addSubview(quitButton)

        settingsButton.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")
        settingsButton.isBordered = false
        settingsButton.contentTintColor = .lightGray
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.target = self
        settingsButton.action = #selector(settingsMenuTapped)
        view.addSubview(settingsButton)

        aboutButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
        aboutButton.isBordered = false
        aboutButton.contentTintColor = .lightGray
        aboutButton.translatesAutoresizingMaskIntoConstraints = false
        aboutButton.target = self
        aboutButton.action = #selector(aboutTapped)
        view.addSubview(aboutButton)

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

        // Bottom row: [historyToggle + chevron] ... [thumbsDown replay play next thumbsUp] ... [stations]

        // History toggle button (left side, chrome style like settings gear)
        historyToggleButton.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "History")
        historyToggleButton.isBordered = false
        historyToggleButton.contentTintColor = .lightGray
        let historyConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        historyToggleButton.symbolConfiguration = historyConfig
        historyToggleButton.translatesAutoresizingMaskIntoConstraints = false
        historyToggleButton.target = self
        historyToggleButton.action = #selector(historyToggleTapped)
        view.addSubview(historyToggleButton)

        // Disclosure chevron
        historyChevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        historyChevron.isBordered = false
        historyChevron.contentTintColor = .lightGray
        let chevronConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        historyChevron.symbolConfiguration = chevronConfig
        historyChevron.translatesAutoresizingMaskIntoConstraints = false
        historyChevron.target = self
        historyChevron.action = #selector(historyToggleTapped)
        view.addSubview(historyChevron)

        // Thumbs down (left of replay, white tint)
        thumbsDownButton.image = NSImage(systemSymbolName: "hand.thumbsdown.fill", accessibilityDescription: "Thumbs Down")
        thumbsDownButton.isBordered = false
        thumbsDownButton.contentTintColor = .white
        let thumbsConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        thumbsDownButton.symbolConfiguration = thumbsConfig
        thumbsDownButton.translatesAutoresizingMaskIntoConstraints = false
        thumbsDownButton.target = self
        thumbsDownButton.action = #selector(thumbsDownTapped)
        view.addSubview(thumbsDownButton)

        // Thumbs up (right of next, white tint)
        thumbsUpButton.image = NSImage(systemSymbolName: "hand.thumbsup.fill", accessibilityDescription: "Thumbs Up")
        thumbsUpButton.isBordered = false
        thumbsUpButton.contentTintColor = .white
        thumbsUpButton.symbolConfiguration = thumbsConfig
        thumbsUpButton.translatesAutoresizingMaskIntoConstraints = false
        thumbsUpButton.target = self
        thumbsUpButton.action = #selector(thumbsUpTapped)
        view.addSubview(thumbsUpButton)

        replayButton.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Replay")
        replayButton.isBordered = false
        replayButton.contentTintColor = .white
        let replayConfig = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        replayButton.symbolConfiguration = replayConfig
        replayButton.translatesAutoresizingMaskIntoConstraints = false
        replayButton.target = self
        replayButton.action = #selector(replayTapped)
        view.addSubview(replayButton)

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

        stationsButton.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "Stations")
        stationsButton.isBordered = false
        stationsButton.contentTintColor = .lightGray
        stationsButton.translatesAutoresizingMaskIntoConstraints = false
        stationsButton.target = self
        stationsButton.action = #selector(stationsTapped)
        view.addSubview(stationsButton)

        songLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        artistLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Bottom row is pinned to top (y=100) instead of bottom, so tray can grow below
        let bottomRowY = view.topAnchor

        NSLayoutConstraint.activate([
            // Button column (right side, top-aligned)
            quitButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            quitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            quitButton.widthAnchor.constraint(equalToConstant: 20),
            quitButton.heightAnchor.constraint(equalToConstant: 20),

            settingsButton.topAnchor.constraint(equalTo: quitButton.bottomAnchor, constant: 8),
            settingsButton.trailingAnchor.constraint(equalTo: quitButton.trailingAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 20),
            settingsButton.heightAnchor.constraint(equalToConstant: 20),

            aboutButton.topAnchor.constraint(equalTo: settingsButton.bottomAnchor, constant: 8),
            aboutButton.trailingAnchor.constraint(equalTo: quitButton.trailingAnchor),
            aboutButton.widthAnchor.constraint(equalToConstant: 20),
            aboutButton.heightAnchor.constraint(equalToConstant: 20),

            stationsButton.topAnchor.constraint(equalTo: aboutButton.bottomAnchor, constant: 8),
            stationsButton.trailingAnchor.constraint(equalTo: quitButton.trailingAnchor),
            stationsButton.widthAnchor.constraint(equalToConstant: 20),
            stationsButton.heightAnchor.constraint(equalToConstant: 20),

            // Album art
            albumArt.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            albumArt.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            albumArt.widthAnchor.constraint(equalToConstant: 80),
            albumArt.heightAnchor.constraint(equalToConstant: 80),

            // Song + artist
            songLabel.topAnchor.constraint(equalTo: albumArt.topAnchor, constant: 4),
            songLabel.leadingAnchor.constraint(equalTo: albumArt.trailingAnchor, constant: 12),
            songLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),

            artistLabel.topAnchor.constraint(equalTo: songLabel.bottomAnchor, constant: 2),
            artistLabel.leadingAnchor.constraint(equalTo: songLabel.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: songLabel.trailingAnchor),

            // Progress bar (full content width)
            progressBar.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 6),
            progressBar.leadingAnchor.constraint(equalTo: songLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),

            // Time labels (below progress bar)
            elapsedLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 2),
            elapsedLabel.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor),

            timeLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 2),
            timeLabel.trailingAnchor.constraint(equalTo: progressBar.trailingAnchor),

            // Bottom row — vertically centered between album art bottom (90) and pane bottom (134)
            historyToggleButton.topAnchor.constraint(equalTo: bottomRowY, constant: 99),
            historyToggleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            historyToggleButton.widthAnchor.constraint(equalToConstant: 24),
            historyToggleButton.heightAnchor.constraint(equalToConstant: 24),

            historyChevron.centerYAnchor.constraint(equalTo: historyToggleButton.centerYAnchor),
            historyChevron.leadingAnchor.constraint(equalTo: historyToggleButton.trailingAnchor, constant: -2),
            historyChevron.widthAnchor.constraint(equalToConstant: 12),
            historyChevron.heightAnchor.constraint(equalToConstant: 12),

            // Centered transport cluster: thumbsDown, replay, play, next, thumbsUp
            playPauseButton.centerYAnchor.constraint(equalTo: historyToggleButton.centerYAnchor),
            playPauseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 32),
            playPauseButton.heightAnchor.constraint(equalToConstant: 32),

            replayButton.centerYAnchor.constraint(equalTo: historyToggleButton.centerYAnchor),
            replayButton.trailingAnchor.constraint(equalTo: playPauseButton.leadingAnchor, constant: -12),
            replayButton.widthAnchor.constraint(equalToConstant: 28),
            replayButton.heightAnchor.constraint(equalToConstant: 28),

            thumbsDownButton.centerYAnchor.constraint(equalTo: historyToggleButton.centerYAnchor),
            thumbsDownButton.trailingAnchor.constraint(equalTo: replayButton.leadingAnchor, constant: -10),
            thumbsDownButton.widthAnchor.constraint(equalToConstant: 26),
            thumbsDownButton.heightAnchor.constraint(equalToConstant: 26),

            nextButton.centerYAnchor.constraint(equalTo: historyToggleButton.centerYAnchor),
            nextButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 12),
            nextButton.widthAnchor.constraint(equalToConstant: 28),
            nextButton.heightAnchor.constraint(equalToConstant: 28),

            thumbsUpButton.centerYAnchor.constraint(equalTo: historyToggleButton.centerYAnchor),
            thumbsUpButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 10),
            thumbsUpButton.widthAnchor.constraint(equalToConstant: 26),
            thumbsUpButton.heightAnchor.constraint(equalToConstant: 26),
        ])

        // History tray

        // Separator line
        historySeparator.wantsLayer = true
        historySeparator.layer?.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
        historySeparator.translatesAutoresizingMaskIntoConstraints = false
        historySeparator.isHidden = true
        view.addSubview(historySeparator)

        // Scroll view + table view
        historyScrollView.translatesAutoresizingMaskIntoConstraints = false
        historyScrollView.hasVerticalScroller = true
        historyScrollView.drawsBackground = false
        historyScrollView.backgroundColor = NSColor(white: 0.12, alpha: 1)
        view.addSubview(historyScrollView)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("HistoryColumn"))
        column.width = 360
        historyTableView.addTableColumn(column)
        historyTableView.headerView = nil
        historyTableView.rowHeight = 52
        historyTableView.backgroundColor = NSColor(white: 0.12, alpha: 1)
        historyTableView.dataSource = self
        historyTableView.delegate = self
        historyTableView.style = .plain
        historyTableView.selectionHighlightStyle = .none
        historyScrollView.documentView = historyTableView

        historyHeightConstraint = historyScrollView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            historySeparator.topAnchor.constraint(equalTo: view.topAnchor, constant: 134),
            historySeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            historySeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            historySeparator.heightAnchor.constraint(equalToConstant: 1),

            historyScrollView.topAnchor.constraint(equalTo: historySeparator.bottomAnchor),
            historyScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            historyScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            historyHeightConstraint,
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

        // Keep button column above the overlay
        view.addSubview(quitButton, positioned: .above, relativeTo: offlineOverlay)
        view.addSubview(settingsButton, positioned: .above, relativeTo: offlineOverlay)
        view.addSubview(aboutButton, positioned: .above, relativeTo: offlineOverlay)
        view.addSubview(stationsButton, positioned: .above, relativeTo: offlineOverlay)

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
        thumbsUpButton.contentTintColor = highlighted ? .systemGreen : .white
    }

    func showError(_ message: String) {
        // Don't overwrite the now-playing display with background errors
        if !currentSong.isEmpty {
            logger.debug("suppressing error overlay (track playing): \(message, privacy: .public)")
            return
        }
        loadingSpinner.stopAnimation(nil)
        loadingSpinner.isHidden = true
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
        replayButton.isEnabled = enabled
        replayButton.contentTintColor = tint
        playPauseButton.isEnabled = enabled
        playPauseButton.contentTintColor = tint
        nextButton.isEnabled = enabled
        nextButton.contentTintColor = tint
        thumbsUpButton.isEnabled = enabled
        thumbsUpButton.contentTintColor = tint
        thumbsDownButton.isEnabled = enabled
        thumbsDownButton.contentTintColor = tint
    }

    // MARK: - History Tray

    func setHistoryOpen(_ open: Bool, animated: Bool = false) {
        isHistoryOpen = open
        let chevronName = open ? "chevron.down" : "chevron.right"
        historyChevron.image = NSImage(systemSymbolName: chevronName, accessibilityDescription: nil)
        historySeparator.isHidden = !open
        historyHeightConstraint.constant = open ? 260 : 0
        if open {
            historyTableView.reloadData()
        }
        let newSize = NSSize(width: 360, height: open ? 394 : 134)
        self.preferredContentSize = newSize
    }

    func reloadHistory() {
        if isHistoryOpen {
            historyTableView.reloadData()
        }
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

    @objc private func replayTapped() { onReplay?() }
    @objc private func playPauseTapped() { onPlayPause?() }
    @objc private func nextTapped() { onNext?() }
    @objc private func thumbsUpTapped() { onThumbsUp?() }
    @objc private func thumbsDownTapped() { onThumbsDown?() }
    @objc private func stationsTapped() { onStations?() }

    @objc private func historyToggleTapped() {
        let newState = !isHistoryOpen
        setHistoryOpen(newState)
        onHistoryToggled?(newState)
    }

    @objc private func aboutTapped() { onAbout?() }
    @objc private func settingsMenuTapped() { onSettings?() }
    @objc private func quitTapped() { onQuit?() }

    // MARK: - History Row Actions

    @objc private func historyThumbsUpTapped(_ sender: NSButton) {
        guard let token = sender.identifier?.rawValue else { return }
        onHistoryThumbsUp?(token)
    }

    @objc private func historyThumbsDownTapped(_ sender: NSButton) {
        guard let token = sender.identifier?.rawValue else { return }
        onHistoryThumbsDown?(token)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return TrackHistory.shared.entries.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entries = TrackHistory.shared.entries
        guard row < entries.count else { return nil }
        let entry = entries[row]

        let cell = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 52))

        // Album art
        let art = NSImageView(frame: NSRect(x: 8, y: 6, width: 40, height: 40))
        art.wantsLayer = true
        art.layer?.cornerRadius = 4
        art.layer?.masksToBounds = true
        art.layer?.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
        art.imageScaling = .scaleProportionallyUpOrDown
        art.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        if let artUrl = entry.albumArtUrl {
            ImageCache.shared.image(for: artUrl) { image in
                if let image = image {
                    art.image = image
                }
            }
        }
        cell.addSubview(art)

        // Title
        let title = NSTextField(labelWithString: entry.songName)
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 56, y: 28, width: 200, height: 16)
        cell.addSubview(title)

        // Artist
        let artist = NSTextField(labelWithString: entry.artistName)
        artist.font = .systemFont(ofSize: 10)
        artist.textColor = .lightGray
        artist.lineBreakMode = .byTruncatingTail
        artist.frame = NSRect(x: 56, y: 10, width: 200, height: 14)
        cell.addSubview(artist)

        // Thumbs down button
        let isDisliked = entry.songRating == -1
        let downBtn = NSButton(frame: NSRect(x: 278, y: 16, width: 20, height: 20))
        downBtn.image = NSImage(systemSymbolName: isDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown", accessibilityDescription: "Dislike")
        downBtn.isBordered = false
        downBtn.contentTintColor = isDisliked ? .systemRed : .gray
        downBtn.identifier = NSUserInterfaceItemIdentifier(entry.trackToken)
        downBtn.target = self
        downBtn.action = #selector(historyThumbsDownTapped)
        cell.addSubview(downBtn)

        // Thumbs up button
        let isLiked = entry.songRating == 1
        let upBtn = NSButton(frame: NSRect(x: 306, y: 16, width: 20, height: 20))
        upBtn.image = NSImage(systemSymbolName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup", accessibilityDescription: "Like")
        upBtn.isBordered = false
        upBtn.contentTintColor = isLiked ? .systemGreen : .gray
        upBtn.identifier = NSUserInterfaceItemIdentifier(entry.trackToken)
        upBtn.target = self
        upBtn.action = #selector(historyThumbsUpTapped)
        cell.addSubview(upBtn)

        return cell
    }
}
#endif
