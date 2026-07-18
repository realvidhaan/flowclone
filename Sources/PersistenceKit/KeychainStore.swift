import Foundation
import Security
import os

/// Small wrapper over the macOS keychain for storing secrets (API keys). Values
/// are keyed by account name under the app's service identifier.
public enum KeychainStore {
    private static let service = "com.flowclone.app"
    private static let log = Logger(subsystem: "com.flowclone.app", category: "Keychain")

    public enum Account: String {
        case groqAPIKey = "groq-api-key"
    }

    /// The outcome of a keychain read, so callers can tell a genuinely-missing
    /// item apart from a transient failure (e.g. the keychain momentarily
    /// unavailable). `get()` flattens this to `String?`; callers that must not act
    /// on a false "no key" (like STT engine selection) use `read()` directly.
    public enum ReadOutcome {
        case value(String)
        case absent
        case failed(OSStatus)
    }

    public static func set(_ value: String?, for account: Account) {
        guard let value, !value.isEmpty else {
            delete(account)
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    /// Reads a secret, reporting whether it is present, genuinely absent, or the
    /// read itself failed. A failed read is logged (previously every non-success
    /// status silently became `nil`, hiding transient keychain errors).
    public static func read(_ account: Account) -> ReadOutcome {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                log.error("Keychain item \(account.rawValue, privacy: .public) present but unreadable")
                return .failed(status)
            }
            return .value(value)
        case errSecItemNotFound:
            return .absent
        default:
            log.error("Keychain read for \(account.rawValue, privacy: .public) failed: OSStatus \(status, privacy: .public)")
            return .failed(status)
        }
    }

    public static func get(_ account: Account) -> String? {
        if case .value(let value) = read(account) { return value }
        return nil
    }

    public static func delete(_ account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
