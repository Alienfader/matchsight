import Foundation
import Security

/// Keychain wrapper for CopaHUD secrets. Carried over from the mirror app's
/// SecretsStore; the shared-secret accessors are replaced with the API-Football
/// key and the Meta Model API key (AI analyst, development builds).
enum SecretsStore {
  static let service = "com.alienfader.copahud"
  static let apiFootballKeyAccount = "API_FOOTBALL_KEY"
  static let metaModelKeyAccount = "META_MODEL_API_KEY"
  static let metaProxyURLAccount = "META_PROXY_URL"
  static let metaProxyTokenAccount = "META_PROXY_TOKEN"

  static func read(account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Stores the value with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
  /// Survives reinstall; never synced to iCloud.
  @discardableResult
  static func write(account: String, value: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }
    let baseQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]

    let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return true }
    if updateStatus == errSecItemNotFound {
      var addQuery = baseQuery
      addQuery.merge(attributes) { _, new in new }
      return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }
    return false
  }

  @discardableResult
  static func delete(account: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  /// The paid API-Football key. Nil until the user enters it in Settings.
  static var apiFootballKey: String? {
    read(account: apiFootballKeyAccount)
  }

  @discardableResult
  static func setApiFootballKey(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return delete(account: apiFootballKeyAccount) }
    return write(account: apiFootballKeyAccount, value: trimmed)
  }

  /// Meta Model API key for the AI analyst. Nil → the mock analyst runs.
  static var metaModelKey: String? {
    read(account: metaModelKeyAccount)
  }

  @discardableResult
  static func setMetaModelKey(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return delete(account: metaModelKeyAccount) }
    return write(account: metaModelKeyAccount, value: trimmed)
  }

  /// CopaHUD AI proxy (Cloudflare Worker that holds the Meta key).
  static var metaProxyURL: String? {
    read(account: metaProxyURLAccount)
  }

  @discardableResult
  static func setMetaProxyURL(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return delete(account: metaProxyURLAccount) }
    return write(account: metaProxyURLAccount, value: trimmed)
  }

  /// Token the proxy expects in `X-CopaHUD-Token`.
  static var metaProxyToken: String? {
    read(account: metaProxyTokenAccount)
  }

  @discardableResult
  static func setMetaProxyToken(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return delete(account: metaProxyTokenAccount) }
    return write(account: metaProxyTokenAccount, value: trimmed)
  }
}
