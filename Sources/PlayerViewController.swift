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

// MARK: - Tray Mode

enum TrayMode: String {
    case history
    case lyrics
}

// MARK: - GrabberView

private class GrabberView: NSView {
    var onDrag: ((CGFloat) -> Void)?  // delta Y
    var onDragEnd: (() -> Void)?
    private var dragStartY: CGFloat = 0

    private let pill = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(white: 0.4, alpha: 1).cgColor
        pill.layer?.cornerRadius = 1
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.widthAnchor.constraint(equalToConstant: 40),
            pill.heightAnchor.constraint(equalToConstant: 2),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartY = NSEvent.mouseLocation.y
    }

    override func mouseDragged(with event: NSEvent) {
        let screenY = NSEvent.mouseLocation.y
        let delta = screenY - dragStartY
        dragStartY = screenY
        // Dragging down (negative y in screen coords) increases tray height
        onDrag?(-delta)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnd?()
    }
}

// MARK: - SeekOverlay

private class SeekOverlay: NSView {
    var onSeek: ((Double) -> Void)?    // normalized 0-1 fraction
    var onSeekEnd: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    private let playhead = NSView()
    private var playheadCenterX: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        playhead.wantsLayer = true
        playhead.layer?.backgroundColor = NSColor(white: 0.75, alpha: 1).cgColor
        playhead.layer?.cornerRadius = 4
        playhead.isHidden = true
        playhead.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playhead)

        playheadCenterX = playhead.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 0)
        NSLayoutConstraint.activate([
            playhead.centerYAnchor.constraint(equalTo: centerYAnchor),
            playhead.widthAnchor.constraint(equalToConstant: 8),
            playhead.heightAnchor.constraint(equalToConstant: 8),
            playheadCenterX,
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        playhead.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        playhead.isHidden = true
    }

    func updatePlayheadPosition(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        playheadCenterX.constant = CGFloat(clamped) * bounds.width
    }

    private func fractionForEvent(_ event: NSEvent) -> Double {
        let local = convert(event.locationInWindow, from: nil)
        return min(max(Double(local.x / bounds.width), 0), 1)
    }

    override func mouseDown(with event: NSEvent) {
        let f = fractionForEvent(event)
        updatePlayheadPosition(f)
        playhead.isHidden = false
        onSeek?(f)
    }

    override func mouseDragged(with event: NSEvent) {
        let f = fractionForEvent(event)
        updatePlayheadPosition(f)
        onSeek?(f)
    }

    override func mouseUp(with event: NSEvent) {
        onSeekEnd?()
    }
}

class PlayerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    // UI Elements
    private let albumArt = NSImageView()
    private let songLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let seekOverlay = SeekOverlay()
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private var isSeeking = false
    private var lastKnownDuration: Double = 0
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

    // Lyrics UI
    private let lyricsButton = NSButton()
    private let lyricsChevron = NSButton()
    private let lyricsScrollView = NSScrollView()
    private let lyricsStackView = NSStackView()
    private var lyricsLineLabels: [NSTextField] = []
    private var currentLyricsLineIndex = -1
    private var syncedLines: [LyricsLine] = []
    private let lyricsStatusLabel = NSTextField(labelWithString: "")
    private let lyricsSpinner = NSProgressIndicator()

    // Shared tray
    weak var popover: NSPopover?  // set by AppDelegate for synchronous resize during drag
    private var trayHeightConstraint: NSLayoutConstraint!
    private let grabberBar = GrabberView()
    private(set) var trayMode: TrayMode = .history
    private(set) var isTrayOpen = false
    private var savedTrayHeight: CGFloat {
        let h = UserDefaults.standard.double(forKey: "trayHeight")
        return max(h > 0 ? CGFloat(h) : 260, 200)
    }

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
    var onLyrics: (() -> Void)?
    var onTrayResized: ((CGFloat) -> Void)?
    var onSeek: ((Double) -> Void)?  // normalized 0-1

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
        // Button column (right side): quit, settings, about, stations
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

        // Seek overlay (transparent hit target on top of progress bar)
        seekOverlay.translatesAutoresizingMaskIntoConstraints = false
        seekOverlay.onSeek = { [weak self] fraction in
            guard let self = self else { return }
            self.isSeeking = true
            self.setProgress(fraction)
            self.seekOverlay.updatePlayheadPosition(fraction)
            if self.lastKnownDuration > 0 {
                let current = fraction * self.lastKnownDuration
                let elapsedSec = Int(current)
                self.elapsedLabel.stringValue = String(format: "%d:%02d", elapsedSec / 60, elapsedSec % 60)
                let remaining = Int(self.lastKnownDuration - current)
                self.timeLabel.stringValue = String(format: "-%d:%02d", remaining / 60, remaining % 60)
            }
            self.onSeek?(fraction)
        }
        seekOverlay.onSeekEnd = nil  // seeking cleared by endSeeking() on seek completion
        view.addSubview(seekOverlay)

        // Bottom row: [historyToggle + chevron] [lyrics] ... [thumbsDown replay play next thumbsUp]

        // History toggle button (left side)
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

        // Lyrics button (right of history chevron) — emoji rendered as monochrome
        lyricsButton.title = ""
        lyricsButton.image = Self.monochromeEmoji("🗣️", size: 16)
        lyricsButton.imagePosition = .imageOnly
        lyricsButton.isBordered = false
        lyricsButton.contentTintColor = .lightGray
        lyricsButton.translatesAutoresizingMaskIntoConstraints = false
        lyricsButton.target = self
        lyricsButton.action = #selector(lyricsTapped)
        view.addSubview(lyricsButton)

        // Lyrics disclosure chevron
        lyricsChevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        lyricsChevron.isBordered = false
        lyricsChevron.contentTintColor = .lightGray
        lyricsChevron.symbolConfiguration = chevronConfig
        lyricsChevron.translatesAutoresizingMaskIntoConstraints = false
        lyricsChevron.target = self
        lyricsChevron.action = #selector(lyricsTapped)
        view.addSubview(lyricsChevron)

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

            // Seek overlay centered on progress bar, taller for hit targeting
            seekOverlay.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor),
            seekOverlay.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor),
            seekOverlay.trailingAnchor.constraint(equalTo: progressBar.trailingAnchor),
            seekOverlay.heightAnchor.constraint(equalToConstant: 20),

            // Bottom row — vertically centered between album art bottom (90) and pane bottom (134)
            historyToggleButton.topAnchor.constraint(equalTo: bottomRowY, constant: 99),
            historyToggleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            historyToggleButton.widthAnchor.constraint(equalToConstant: 24),
            historyToggleButton.heightAnchor.constraint(equalToConstant: 24),

            historyChevron.centerYAnchor.constraint(equalTo: historyToggleButton.centerYAnchor),
            historyChevron.leadingAnchor.constraint(equalTo: historyToggleButton.trailingAnchor, constant: -2),
            historyChevron.widthAnchor.constraint(equalToConstant: 12),
            historyChevron.heightAnchor.constraint(equalToConstant: 12),

            // Lyrics button + chevron right of history chevron
            lyricsButton.centerYAnchor.constraint(equalTo: historyToggleButton.centerYAnchor),
            lyricsButton.leadingAnchor.constraint(equalTo: historyChevron.trailingAnchor, constant: 4),
            lyricsButton.widthAnchor.constraint(equalToConstant: 24),
            lyricsButton.heightAnchor.constraint(equalToConstant: 24),

            lyricsChevron.centerYAnchor.constraint(equalTo: historyToggleButton.centerYAnchor),
            lyricsChevron.leadingAnchor.constraint(equalTo: lyricsButton.trailingAnchor, constant: -2),
            lyricsChevron.widthAnchor.constraint(equalToConstant: 12),
            lyricsChevron.heightAnchor.constraint(equalToConstant: 12),

            // Centered transport cluster: thumbsDown, replay, play, next, thumbsUp
            playPauseButton.centerYAnchor.constraint(equalTo: historyToggleButton.centerYAnchor),
            playPauseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 20),
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

        // Shared tray area

        // Separator line
        historySeparator.wantsLayer = true
        historySeparator.layer?.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
        historySeparator.translatesAutoresizingMaskIntoConstraints = false
        historySeparator.isHidden = true
        view.addSubview(historySeparator)

        // History scroll view + table view
        historyScrollView.translatesAutoresizingMaskIntoConstraints = false
        historyScrollView.hasVerticalScroller = true
        historyScrollView.drawsBackground = false
        historyScrollView.backgroundColor = NSColor(white: 0.12, alpha: 1)
        historyScrollView.isHidden = true
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

        // Lyrics scroll view + stack view
        lyricsScrollView.translatesAutoresizingMaskIntoConstraints = false
        lyricsScrollView.hasVerticalScroller = true
        lyricsScrollView.drawsBackground = false
        lyricsScrollView.backgroundColor = NSColor(white: 0.12, alpha: 1)
        lyricsScrollView.isHidden = true
        view.addSubview(lyricsScrollView)

        lyricsStackView.orientation = .vertical
        lyricsStackView.alignment = .leading
        lyricsStackView.spacing = 6
        lyricsStackView.translatesAutoresizingMaskIntoConstraints = false
        lyricsStackView.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

        let lyricsDocView = NSView()
        lyricsDocView.translatesAutoresizingMaskIntoConstraints = false
        lyricsDocView.addSubview(lyricsStackView)
        lyricsScrollView.documentView = lyricsDocView

        // Lyrics status label (centered in tray area, outside scroll view)
        lyricsStatusLabel.font = .systemFont(ofSize: 13)
        lyricsStatusLabel.textColor = .lightGray
        lyricsStatusLabel.alignment = .center
        lyricsStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        lyricsStatusLabel.isHidden = true
        view.addSubview(lyricsStatusLabel)

        // Lyrics spinner (centered in tray area, outside scroll view)
        lyricsSpinner.style = .spinning
        lyricsSpinner.controlSize = .small
        lyricsSpinner.translatesAutoresizingMaskIntoConstraints = false
        lyricsSpinner.isHidden = true
        view.addSubview(lyricsSpinner)

        // Grabber bar
        grabberBar.translatesAutoresizingMaskIntoConstraints = false
        grabberBar.isHidden = true
        grabberBar.onDrag = { [weak self] delta in
            self?.handleGrabberDrag(delta: delta)
        }
        grabberBar.onDragEnd = { [weak self] in
            self?.handleGrabberDragEnd()
        }
        view.addSubview(grabberBar)

        // Shared tray height constraint (applies to both scroll views)
        trayHeightConstraint = historyScrollView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            historySeparator.topAnchor.constraint(equalTo: view.topAnchor, constant: 134),
            historySeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            historySeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            historySeparator.heightAnchor.constraint(equalToConstant: 1),

            historyScrollView.topAnchor.constraint(equalTo: historySeparator.bottomAnchor),
            historyScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            historyScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            trayHeightConstraint,

            lyricsScrollView.topAnchor.constraint(equalTo: historySeparator.bottomAnchor),
            lyricsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lyricsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lyricsScrollView.heightAnchor.constraint(equalTo: historyScrollView.heightAnchor),

            // Lyrics doc view fills scroll view
            lyricsStackView.topAnchor.constraint(equalTo: lyricsDocView.topAnchor),
            lyricsStackView.leadingAnchor.constraint(equalTo: lyricsDocView.leadingAnchor),
            lyricsStackView.trailingAnchor.constraint(equalTo: lyricsDocView.trailingAnchor),
            lyricsStackView.bottomAnchor.constraint(equalTo: lyricsDocView.bottomAnchor),
            lyricsDocView.widthAnchor.constraint(equalTo: lyricsScrollView.widthAnchor),

            // Status label and spinner centered in tray area (outside scroll view)
            lyricsStatusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lyricsStatusLabel.topAnchor.constraint(equalTo: historySeparator.bottomAnchor, constant: 40),

            lyricsSpinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lyricsSpinner.topAnchor.constraint(equalTo: historySeparator.bottomAnchor, constant: 40),

            // Grabber bar below tray content
            grabberBar.topAnchor.constraint(equalTo: historyScrollView.bottomAnchor),
            grabberBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grabberBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            grabberBar.heightAnchor.constraint(equalToConstant: 8),
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
        lastKnownDuration = duration
        guard !isSeeking else { return }

        let fraction = current / duration
        setProgress(fraction)
        seekOverlay.updatePlayheadPosition(fraction)

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

    // MARK: - Tray

    func setTrayOpen(_ open: Bool, mode: TrayMode? = nil) {
        if let m = mode { trayMode = m }
        isTrayOpen = open

        let historyActive = open && trayMode == .history
        let lyricsActive = open && trayMode == .lyrics

        // Update both chevrons
        historyChevron.image = NSImage(systemSymbolName: historyActive ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        lyricsChevron.image = NSImage(systemSymbolName: lyricsActive ? "chevron.down" : "chevron.right", accessibilityDescription: nil)

        // Toggle visibility
        historyScrollView.isHidden = !historyActive
        lyricsScrollView.isHidden = !lyricsActive
        grabberBar.isHidden = !open
        historySeparator.isHidden = !open

        // Hide lyrics status/spinner when not in lyrics mode
        if !lyricsActive {
            lyricsStatusLabel.isHidden = true
            lyricsSpinner.stopAnimation(nil)
            lyricsSpinner.isHidden = true
        }

        // Highlight active button
        historyToggleButton.contentTintColor = historyActive ? .white : .lightGray
        lyricsButton.contentTintColor = lyricsActive ? .white : .lightGray

        // Set height
        let height: CGFloat = open ? savedTrayHeight : 0
        trayHeightConstraint.constant = height

        if open && trayMode == .history {
            historyTableView.reloadData()
        }

        // +9 for separator (1) + grabber (8) when open
        let totalHeight: CGFloat = 134 + (open ? height + 9 : 0)
        self.preferredContentSize = NSSize(width: 360, height: totalHeight)
    }

    // Backward-compatible wrapper used by AppDelegate
    func setHistoryOpen(_ open: Bool, animated: Bool = false) {
        setTrayOpen(open, mode: .history)
    }

    var isHistoryOpen: Bool {
        return isTrayOpen && trayMode == .history
    }

    func reloadHistory() {
        if isTrayOpen && trayMode == .history {
            historyTableView.reloadData()
        }
    }

    // MARK: - Grabber Drag

    private func handleGrabberDrag(delta: CGFloat) {
        let newHeight = trayHeightConstraint.constant + delta
        let clamped = min(max(newHeight, 0), 500)
        trayHeightConstraint.constant = clamped
        let totalHeight: CGFloat = 134 + clamped + 9
        let newSize = NSSize(width: 360, height: totalHeight)
        self.preferredContentSize = newSize
        // Resize popover synchronously without animation to prevent wiggle
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        popover?.contentSize = newSize
        view.layoutSubtreeIfNeeded()
        NSAnimationContext.endGrouping()
        onTrayResized?(clamped)
    }

    private func handleGrabberDragEnd() {
        let height = trayHeightConstraint.constant
        if height < 60 {
            // Snap close — don't save height
            setTrayOpen(false)
            onTrayResized?(0)
        } else {
            // Enforce minimum
            let finalHeight = max(height, 100)
            trayHeightConstraint.constant = finalHeight
            let totalHeight: CGFloat = 134 + finalHeight + 9
            self.preferredContentSize = NSSize(width: 360, height: totalHeight)
            UserDefaults.standard.set(Double(finalHeight), forKey: "trayHeight")
            onTrayResized?(finalHeight)
        }
    }

    // MARK: - Lyrics Display

    func showLyricsLoading() {
        clearLyricsContent()
        lyricsStatusLabel.isHidden = true
        lyricsSpinner.startAnimation(nil)
        lyricsSpinner.isHidden = false
    }

    func showLyrics(_ result: LyricsResult) {
        clearLyricsContent()
        lyricsSpinner.stopAnimation(nil)
        lyricsSpinner.isHidden = true

        switch result {
        case .synced(let lines):
            syncedLines = lines
            for line in lines {
                let label = makeLyricsLabel(line.text, color: .lightGray)
                lyricsStackView.addArrangedSubview(label)
                lyricsLineLabels.append(label)
            }
            lyricsStatusLabel.isHidden = true

        case .plain(let text):
            syncedLines = []
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    // Add spacing for blank lines
                    let spacer = NSView()
                    spacer.translatesAutoresizingMaskIntoConstraints = false
                    spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
                    lyricsStackView.addArrangedSubview(spacer)
                } else {
                    let label = makeLyricsLabel(trimmed)
                    lyricsStackView.addArrangedSubview(label)
                    lyricsLineLabels.append(label)
                }
            }
            lyricsStatusLabel.isHidden = true

        case .instrumental:
            lyricsStatusLabel.stringValue = "Instrumental"
            lyricsStatusLabel.isHidden = false

        case .notFound:
            lyricsStatusLabel.stringValue = "Lyrics not available"
            lyricsStatusLabel.isHidden = false
        }

        // Scroll to top
        lyricsScrollView.documentView?.scroll(.zero)
    }

    func updateLyricsTime(_ time: Double) {
        guard !syncedLines.isEmpty else { return }

        // Binary search for the current line
        var lo = 0, hi = syncedLines.count - 1
        var idx = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if syncedLines[mid].time <= time {
                idx = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        guard idx != currentLyricsLineIndex else { return }
        currentLyricsLineIndex = idx

        // Update highlighting
        for (i, label) in lyricsLineLabels.enumerated() {
            if i == idx {
                label.font = .systemFont(ofSize: 14, weight: .semibold)
                label.textColor = .white
            } else {
                label.font = .systemFont(ofSize: 13)
                label.textColor = .lightGray
            }
        }

        // Auto-scroll to center the current line, clamped to document bounds
        if idx < lyricsLineLabels.count, let docView = lyricsScrollView.documentView {
            let label = lyricsLineLabels[idx]
            let labelFrame = label.convert(label.bounds, to: docView)
            let visibleHeight = lyricsScrollView.contentView.bounds.height
            let docHeight = docView.frame.height
            let maxY = max(0, docHeight - visibleHeight)
            let targetY = min(max(0, labelFrame.midY - visibleHeight / 2), maxY)
            lyricsScrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            lyricsScrollView.reflectScrolledClipView(lyricsScrollView.contentView)
        }
    }

    func clearLyrics() {
        clearLyricsContent()
        lyricsSpinner.stopAnimation(nil)
        lyricsSpinner.isHidden = true
        lyricsStatusLabel.isHidden = true
    }

    private func clearLyricsContent() {
        for label in lyricsLineLabels {
            label.removeFromSuperview()
        }
        lyricsLineLabels.removeAll()
        // Remove any spacers too
        for view in lyricsStackView.arrangedSubviews {
            view.removeFromSuperview()
        }
        syncedLines = []
        currentLyricsLineIndex = -1
    }

    private func makeLyricsLabel(_ text: String, color: NSColor = .white) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = color
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// Render an emoji string into a template NSImage so contentTintColor applies.
    private static func monochromeEmoji(_ emoji: String, size: CGFloat) -> NSImage {
        let font = NSFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let strSize = (emoji as NSString).size(withAttributes: attrs)
        let image = NSImage(size: strSize, flipped: false) { rect in
            (emoji as NSString).draw(in: rect, withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
    }

    func endSeeking() {
        isSeeking = false
    }

    private func setProgress(_ value: Double) {
        // NSProgressIndicator animates value changes by default; suppress it.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        progressBar.doubleValue = value
        // Strip any animations NSProgressIndicator may have queued on its layer
        progressBar.layer?.removeAllAnimations()
        for sub in progressBar.layer?.sublayers ?? [] {
            sub.removeAllAnimations()
            sub.speed = Float.greatestFiniteMagnitude
        }
        CATransaction.commit()
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
        setProgress(0)
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
        if isTrayOpen && trayMode == .history {
            setTrayOpen(false)
            onHistoryToggled?(false)
        } else {
            setTrayOpen(true, mode: .history)
            onHistoryToggled?(true)
        }
    }

    @objc private func lyricsTapped() { onLyrics?() }
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
