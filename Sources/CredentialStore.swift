import Foundation

#if !TESTING
import Security
#endif

enum CredentialStore {
#if UI_TESTING
    // File-based credentials for UI testing (no keychain prompts)
    static func saveCredentials(username: String, password: String) -> Bool { true }
    static func deleteCredentials() {}

    static func loadCredentials() -> (username: String, password: String)? {
        let path = NSString(string: "~/.config/sixth/test-credentials.json").expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let username = dict["username"],
              let password = dict["password"] else {
            return nil
        }
        return (username, password)
    }
#elseif !TESTING
    private static let service = "com.sixth.pandora"
    private static let usernameKey = "pandora-username"
    private static let passwordKey = "pandora-password"

    // MARK: - Save

    static func saveCredentials(username: String, password: String) -> Bool {
        let userOk = saveItem(key: usernameKey, value: username)
        let passOk = saveItem(key: passwordKey, value: password)
        return userOk && passOk
    }

    // MARK: - Load

    static func loadCredentials() -> (username: String, password: String)? {
        guard let username = loadItem(key: usernameKey),
              let password = loadItem(key: passwordKey) else {
            return nil
        }
        return (username, password)
    }

    // MARK: - Delete

    static func deleteCredentials() {
        deleteItem(key: usernameKey)
        deleteItem(key: passwordKey)
    }

    // MARK: - Keychain Helpers

    private static func saveItem(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing first
        deleteItem(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func loadItem(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func deleteItem(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
#else
    // MARK: - File-based credentials for testing

    static func loadTestCredentials() -> (username: String, password: String)? {
        let path = NSString(string: "~/.config/sixth/test-credentials.json").expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let username = dict["username"],
              let password = dict["password"] else {
            return nil
        }
        return (username, password)
    }
#endif
}
