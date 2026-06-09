import Foundation
import Security

/// Keychain 封裝：以 `kSecClassGenericPassword` 儲存敏感字串，
/// 採 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`（鎖屏不可讀、且排除 iCloud／iTunes 備份）。
/// set 前先 `SecItemDelete`，避免 duplicate item。
enum KeychainStore {
    static let service = "noblehall-cms-app.session"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func set(_ value: String?, for account: String) {
        // 先刪除既有項目，再視情況新增（避免 duplicate item）
        SecItemDelete(baseQuery(account) as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
