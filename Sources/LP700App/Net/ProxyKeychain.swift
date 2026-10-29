import Foundation
import Security
import os.log

// The proxy login lives in the login Keychain as a generic password:
// service "ShackProxy", account = the username, data = the password (UTF-8).
// It is looked up by service alone, so the username comes from the item.
//
// No `kSecUseDataProtectionKeychain`: an item made with `security
// add-generic-password` or Keychain Access is in the file-based login keychain,
// and the data-protection keychain needs entitlements an ad-hoc build lacks.
enum ProxyKeychain {
    static let service = "ShackProxy"

    private static let log = Logger(subsystem: "com.vu3esv.lp700-app", category: "proxy-login")

    private static var serviceQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service]
    }

    /// Username of the stored login, or nil if there is none. Asks for attributes only,
    /// so the secret is not decrypted and macOS shows no Keychain access prompt.
    static func storedAccount() -> String? {
        var query = serviceQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any],
              let account = attributes[kSecAttrAccount as String] as? String,
              !account.isEmpty else { return nil }
        return account
    }

    /// The stored login, or nil (none stored, or the operator denied access). Decrypts
    /// the secret, which can raise macOS's "allow access" prompt, so it first checks the
    /// item exists: with nothing stored there is no prompt. Blocks while a prompt is up.
    static func read() -> ProxyCredentials? {
        guard storedAccount() != nil else { return nil }
        var query = serviceQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            log.error("Keychain read of \(service, privacy: .public) failed: \(status)")
            return nil
        }
        guard let attributes = item as? [String: Any],
              let account = attributes[kSecAttrAccount as String] as? String, !account.isEmpty,
              let data = attributes[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8) else { return nil }
        return ProxyCredentials(username: account, password: password)
    }

    /// Update the login stored for this username, else add it. Lookup is by service, so
    /// a login under another username would shadow the new one: it is removed first.
    static func save(_ credentials: ProxyCredentials) throws {
        var item = serviceQuery
        item[kSecAttrAccount as String] = credentials.username
        let secret = Data(credentials.password.utf8)
        var status = SecItemUpdate(item as CFDictionary,
                                   [kSecValueData as String: secret] as CFDictionary)
        if status == errSecItemNotFound {
            try remove()
            item[kSecValueData as String] = secret
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ProxyKeychainError(status: status) }
    }

    /// Delete every "ShackProxy" login. Succeeds when there was none.
    static func remove() throws {
        // The file-based keychain can delete one match per call; repeat until none is left.
        for _ in 0..<16 {
            let status = SecItemDelete(serviceQuery as CFDictionary)
            if status == errSecItemNotFound { return }
            guard status == errSecSuccess else { throw ProxyKeychainError(status: status) }
        }
    }
}

struct ProxyKeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String?
        return "Keychain: \(message ?? "error \(status)")"
    }
}

/// The proxy login in memory, so the Keychain is read at connect time, not per request
/// or frame, and at most once per process for a stored login. "Nothing stored" is not
/// cached: that check is prompt-free, so a login added outside the app is picked up at
/// the next connect. Saving or removing here replaces the cached value.
@MainActor
enum ProxyLoginStore {
    private static var cached: ProxyCredentials?
    private static var loading: Task<ProxyCredentials?, Never>?
    /// Bumped by save/remove so a Keychain read that was in flight can't overwrite them.
    private static var generation = 0

    static func credentials() async -> ProxyCredentials? {
        if let cached { return cached }
        if let loading { return await loading.value }
        let started = generation
        // Off the main thread: a Keychain prompt blocks the calling thread until answered.
        let task = Task.detached(priority: .userInitiated) { ProxyKeychain.read() }
        loading = task
        let loaded = await task.value
        loading = nil
        guard started == generation else { return cached }
        cached = loaded
        return loaded
    }

    /// Username of the stored login, if any. Never decrypts the password.
    static var storedAccount: String? { cached?.username ?? ProxyKeychain.storedAccount() }

    static func save(_ credentials: ProxyCredentials) throws {
        try ProxyKeychain.save(credentials)
        generation &+= 1
        cached = credentials
    }

    static func remove() throws {
        try ProxyKeychain.remove()
        generation &+= 1
        cached = nil
    }
}
