#if !TESTING
import AppKit

class LoginViewController: NSViewController {
    private let usernameField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let loginButton = NSButton()
    private let errorLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    var onLogin: ((String, String) -> Void)?

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
        let titleLabel = NSTextField(labelWithString: "Sign in to Pandora")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        usernameField.placeholderString = "Email"
        usernameField.font = .systemFont(ofSize: 13)
        usernameField.translatesAutoresizingMaskIntoConstraints = false
        usernameField.focusRingType = .none
        view.addSubview(usernameField)

        passwordField.placeholderString = "Password"
        passwordField.font = .systemFont(ofSize: 13)
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        passwordField.focusRingType = .none
        view.addSubview(passwordField)

        loginButton.title = "Sign In"
        loginButton.bezelStyle = .rounded
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        loginButton.target = self
        loginButton.action = #selector(loginTapped)
        loginButton.keyEquivalent = "\r"
        view.addSubview(loginButton)

        errorLabel.textColor = NSColor.systemRed
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.alignment = .center
        errorLabel.maximumNumberOfLines = 2
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.isHidden = true
        view.addSubview(errorLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            usernameField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            usernameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            usernameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),

            passwordField.topAnchor.constraint(equalTo: usernameField.bottomAnchor, constant: 8),
            passwordField.leadingAnchor.constraint(equalTo: usernameField.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: usernameField.trailingAnchor),

            loginButton.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 12),
            loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loginButton.widthAnchor.constraint(equalToConstant: 100),

            errorLabel.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            spinner.centerYAnchor.constraint(equalTo: loginButton.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: loginButton.trailingAnchor, constant: 8),
        ])
    }

    @objc private func loginTapped() {
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
        let password = passwordField.stringValue

        guard !username.isEmpty, !password.isEmpty else {
            showError("Please enter email and password")
            return
        }

        setLoading(true)
        onLogin?(username, password)
    }

    func showError(_ message: String) {
        setLoading(false)
        errorLabel.stringValue = message
        errorLabel.isHidden = false
    }

    func setLoading(_ loading: Bool) {
        loginButton.isEnabled = !loading
        usernameField.isEnabled = !loading
        passwordField.isEnabled = !loading
        if loading {
            spinner.isHidden = false
            spinner.startAnimation(nil)
            errorLabel.isHidden = true
        } else {
            spinner.isHidden = true
            spinner.stopAnimation(nil)
        }
    }
}
#endif
