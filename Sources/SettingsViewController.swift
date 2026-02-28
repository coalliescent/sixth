#if !TESTING
import AppKit

class SettingsViewController: NSViewController {
    private var notificationsToggle: NSButton!
    private var scrollingTitleToggle: NSButton!
    private let signOutButton = NSButton()
    private let backButton = NSButton()

    var onSignOut: (() -> Void)?
    var onBack: (() -> Void)?
    var onNotificationsToggled: ((Bool) -> Void)?
    var onScrollingTitleToggled: ((Bool) -> Void)?

    var notificationsEnabled: Bool = true {
        didSet { notificationsToggle?.state = notificationsEnabled ? .on : .off }
    }
    var scrollingTitleEnabled: Bool = true {
        didSet { scrollingTitleToggle?.state = scrollingTitleEnabled ? .on : .off }
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor
        self.view = container
        self.preferredContentSize = NSSize(width: 360, height: 180)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        // Header
        let headerLabel = NSTextField(labelWithString: "Settings")
        headerLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        headerLabel.textColor = .white
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.isBordered = false
        backButton.contentTintColor = .white
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.target = self
        backButton.action = #selector(backTapped)
        view.addSubview(backButton)

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

        // Sign out
        signOutButton.title = "Sign Out"
        signOutButton.bezelStyle = .rounded
        signOutButton.translatesAutoresizingMaskIntoConstraints = false
        signOutButton.target = self
        signOutButton.action = #selector(signOutTapped)
        view.addSubview(signOutButton)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 20),
            backButton.heightAnchor.constraint(equalToConstant: 20),

            headerLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            headerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            notificationsToggle.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 20),
            notificationsToggle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            scrollingTitleToggle.topAnchor.constraint(equalTo: notificationsToggle.bottomAnchor, constant: 16),
            scrollingTitleToggle.leadingAnchor.constraint(equalTo: notificationsToggle.leadingAnchor),

            signOutButton.topAnchor.constraint(equalTo: scrollingTitleToggle.bottomAnchor, constant: 24),
            signOutButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            signOutButton.widthAnchor.constraint(equalToConstant: 100),
        ])
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

    @objc private func backTapped() {
        onBack?()
    }
}
#endif
