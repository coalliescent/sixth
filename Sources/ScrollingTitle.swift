#if !TESTING
import AppKit

class ScrollingTitle {
    private var animationTimer: Timer?
    private var repeatTimer: Timer?
    private var animationStart: CFTimeInterval = 0
    private var animationDuration: TimeInterval = 0
    private var scrollDistance: CGFloat = 0
    private var fullText = ""
    private var fullTextWidth: CGFloat = 0
    private var currentSong = ""
    private var currentArtist = ""
    private var isPlaying = false
    private weak var statusItem: NSStatusItem?
    private var button: NSStatusBarButton? { statusItem?.button }
    var isEnabled = true

    private let visibleWidth: CGFloat = 220
    private let scrollSpeed: CGFloat = 30 // pixels per second
    private let repeatInterval: TimeInterval = 30
    private let fps: TimeInterval = 1.0 / 30.0
    private let gapWidth: CGFloat = 40

    private var textFont: NSFont {
        NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        [.font: textFont, .foregroundColor: NSColor.controlTextColor]
    }

    func attach(to statusItem: NSStatusItem) {
        self.statusItem = statusItem
    }

    func update(song: String, artist: String) {
        stopAll()
        currentSong = song
        currentArtist = artist
        fullText = "🎵 \(artist) — \(song)"
        isPlaying = true

        if !isEnabled {
            return
        }

        let textWidth = measureText(fullText)
        fullTextWidth = textWidth
        if textWidth <= visibleWidth {
            showStaticTitle()
            return
        }

        // Scroll distance = one copy width + gap so second copy lands where first started
        scrollDistance = textWidth + gapWidth
        startAnimation()
    }

    func pause() {
        isPlaying = false
        stopAll()
        if isEnabled {
            showStaticStart()
        }
    }

    func resume() {
        guard !fullText.isEmpty else { return }
        isPlaying = true

        if !isEnabled {
            return
        }

        let textWidth = measureText(fullText)
        fullTextWidth = textWidth
        if textWidth <= visibleWidth {
            showStaticTitle()
            return
        }

        scrollDistance = textWidth + gapWidth
        startAnimation()
    }

    func setIdle() {
        stopAll()
        fullText = ""
        fullTextWidth = 0
        currentSong = ""
        currentArtist = ""
        isPlaying = false
        button?.image = nil
        button?.title = ""
        statusItem?.length = NSStatusItem.variableLength
    }

    // MARK: - Animation

    private func startAnimation() {
        stopAll()
        animationDuration = Double(scrollDistance) / Double(scrollSpeed)
        animationStart = CACurrentMediaTime()

        // Set fixed width for scrolling
        statusItem?.length = visibleWidth + 24 // padding for status item margins
        renderText(at: 0)

        animationTimer = Timer.scheduledTimer(withTimeInterval: fps, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let elapsed = CACurrentMediaTime() - animationStart
        let t = min(elapsed / animationDuration, 1.0)

        // Smoothstep: 3t² - 2t³
        let smooth = t * t * (3.0 - 2.0 * t)
        let offset = CGFloat(smooth) * scrollDistance

        renderText(at: offset)

        if t >= 1.0 {
            animationTimer?.invalidate()
            animationTimer = nil

            // Reset to start (visually identical) and schedule repeat
            renderText(at: 0)
            repeatTimer = Timer.scheduledTimer(withTimeInterval: repeatInterval, repeats: false) { [weak self] _ in
                guard let self = self, self.isPlaying else { return }
                self.startAnimation()
            }
        }
    }

    private func renderText(at offset: CGFloat) {
        guard let button = button else { return }

        let height = ceil(textFont.ascender - textFont.descender + textFont.leading) + 2
        let imageWidth = visibleWidth

        let image = NSImage(size: NSSize(width: imageWidth, height: height))
        image.lockFocus()

        let y = -textFont.descender
        // Draw two copies at exact pixel positions so scroll lands perfectly
        (fullText as NSString).draw(at: NSPoint(x: -offset, y: y), withAttributes: textAttributes)
        (fullText as NSString).draw(at: NSPoint(x: -offset + fullTextWidth + gapWidth, y: y), withAttributes: textAttributes)

        image.unlockFocus()
        image.isTemplate = true

        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
    }

    // MARK: - Static Display

    private func showStaticTitle() {
        guard let button = button else { return }
        button.image = nil
        button.imagePosition = .noImage
        button.title = " \(fullText)"
        button.font = nil
        statusItem?.length = NSStatusItem.variableLength
    }

    private func showStaticStart() {
        guard button != nil, !fullText.isEmpty else { return }

        let textWidth = measureText(fullText)
        if !isEnabled || textWidth <= visibleWidth {
            showStaticTitle()
            return
        }

        // Show beginning of text as image, fixed width
        statusItem?.length = visibleWidth + 24
        renderText(at: 0)
    }

    // MARK: - Helpers

    private func measureText(_ text: String) -> CGFloat {
        let size = (text as NSString).size(withAttributes: textAttributes)
        return ceil(size.width)
    }

    private func stopAll() {
        animationTimer?.invalidate()
        animationTimer = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}
#endif
