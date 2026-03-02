#if !TESTING
import AppKit

class AboutViewController: NSViewController {
    private let closeButton = NSButton()

    var onClose: (() -> Void)?

    override func loadView() {
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 360, height: 134))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        self.view = effect
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        // Close button (top-right, aligned with about button position)
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.contentTintColor = .lightGray
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        view.addSubview(closeButton)

        // Title
        let titleLabel = NSTextField(labelWithString: "Sixth")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Description
        let descLabel = NSTextField(labelWithString: "A lightweight Pandora client for macOS.")
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .lightGray
        descLabel.alignment = .center
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descLabel)

        // GitHub link
        let linkLabel = NSTextField(labelWithString: "")
        linkLabel.isEditable = false
        linkLabel.isSelectable = true
        linkLabel.isBordered = false
        linkLabel.drawsBackground = false
        linkLabel.allowsEditingTextAttributes = true
        linkLabel.translatesAutoresizingMaskIntoConstraints = false

        let url = "https://github.com/coalliescent/sixth"
        let linkStr = NSMutableAttributedString(string: url)
        linkStr.addAttributes([
            .link: URL(string: url)!,
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.linkColor,
        ], range: NSRange(location: 0, length: url.count))
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        linkStr.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: url.count))
        linkLabel.attributedStringValue = linkStr
        view.addSubview(linkLabel)

        NSLayoutConstraint.activate([
            // Close button: top=66, trailing=-12
            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 66),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            // Centered content
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),

            descLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            linkLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            linkLabel.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 10),
            linkLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
        ])
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
#endif
