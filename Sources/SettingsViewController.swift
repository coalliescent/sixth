#if !TESTING
import AppKit

class SettingsViewController: NSViewController {
    private var notificationsToggle: NSButton!
    private var scrollingTitleToggle: NSButton!
    private let closeButton = NSButton()
    private let signedInLabel = NSTextField(labelWithString: "")
    private let signOutButton = NSButton()

    var onSignOut: (() -> Void)?
    var onClose: (() -> Void)?
    var onNotificationsToggled: ((Bool) -> Void)?
    var onScrollingTitleToggled: ((Bool) -> Void)?

    var username: String = ""

    var notificationsEnabled: Bool = true {
        didSet { notificationsToggle?.state = notificationsEnabled ? .on : .off }
    }
    var scrollingTitleEnabled: Bool = true {
        didSet { scrollingTitleToggle?.state = scrollingTitleEnabled ? .on : .off }
    }

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
        // Close button (top-right, aligned with gear button position)
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.contentTintColor = .lightGray
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        view.addSubview(closeButton)

        // Notifications checkbox
        notificationsToggle = NSButton(checkboxWithTitle: "Song notifications", target: self, action: #selector(notifToggled))
        notificationsToggle.state = notificationsEnabled ? .on : .off
        notificationsToggle.translatesAutoresizingMaskIntoConstraints = false
        (notificationsToggle.cell as? NSButtonCell)?.attributedTitle = NSAttributedString(
            string: "Song notifications",
            attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13)]
        )
        view.addSubview(notificationsToggle)

        // Scrolling title checkbox
        scrollingTitleToggle = NSButton(checkboxWithTitle: "Scrolling title in menu bar", target: self, action: #selector(scrollToggled))
        scrollingTitleToggle.state = scrollingTitleEnabled ? .on : .off
        scrollingTitleToggle.translatesAutoresizingMaskIntoConstraints = false
        (scrollingTitleToggle.cell as? NSButtonCell)?.attributedTitle = NSAttributedString(
            string: "Scrolling title in menu bar",
            attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13)]
        )
        view.addSubview(scrollingTitleToggle)

        // Signed in label
        signedInLabel.font = .systemFont(ofSize: 11)
        signedInLabel.textColor = .lightGray
        signedInLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(signedInLabel)

        // Sign out button (borderless, link-styled)
        signOutButton.title = "Sign Out"
        signOutButton.isBordered = false
        signOutButton.translatesAutoresizingMaskIntoConstraints = false
        signOutButton.target = self
        signOutButton.action = #selector(signOutTapped)
        (signOutButton.cell as? NSButtonCell)?.attributedTitle = NSAttributedString(
            string: "Sign Out",
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .font: NSFont.systemFont(ofSize: 11),
            ]
        )
        view.addSubview(signOutButton)

        NSLayoutConstraint.activate([
            // Close button: top=38, trailing=-12
            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 38),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            // Row 1: notifications (top ~16)
            notificationsToggle.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            notificationsToggle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Row 2: scrolling title
            scrollingTitleToggle.topAnchor.constraint(equalTo: notificationsToggle.bottomAnchor, constant: 16),
            scrollingTitleToggle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Row 3: signed in + sign out
            signedInLabel.topAnchor.constraint(equalTo: scrollingTitleToggle.bottomAnchor, constant: 16),
            signedInLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            signOutButton.centerYAnchor.constraint(equalTo: signedInLabel.centerYAnchor),
            signOutButton.leadingAnchor.constraint(equalTo: signedInLabel.trailingAnchor, constant: 6),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateSignedInRow()
    }

    private func updateSignedInRow() {
        let hasUser = !username.isEmpty
        signedInLabel.stringValue = hasUser ? "Signed in as \(username)" : ""
        signedInLabel.isHidden = !hasUser
        signOutButton.isHidden = !hasUser
    }

    @objc private func notifToggled() {
        onNotificationsToggled?(notificationsToggle.state == .on)
    }

    @objc private func scrollToggled() {
        onScrollingTitleToggled?(scrollingTitleToggle.state == .on)
    }

    @objc private func signOutTapped() {
        onSignOut?()
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
#endif
