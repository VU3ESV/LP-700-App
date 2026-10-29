import Foundation

// HTTP Basic auth for the authenticating TLS reverse proxy (Caddy, realm
// "StationMonitor2") that fronts lp700-server. The proxy answers 401 to a request
// without valid credentials — the WebSocket upgrade included — and 403 to one whose
// `Origin` header is not its own; this client sends no `Origin`, so only 401 applies.
//
// Trust is the system's: the proxy's certificate chains to a CA the operator trusts
// in the Keychain. There is deliberately no pinning or custom trust code here.

/// A proxy login. `description` never contains the password, so a stray
/// `print` / log interpolation / test failure message can't leak it.
struct ProxyCredentials: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    var username: String
    var password: String

    /// `Basic base64(username:password)` (RFC 7617, UTF-8).
    var basicAuthorization: String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }

    var description: String { "ProxyCredentials(username: \(username), password: <redacted>)" }
    var debugDescription: String { description }
}

enum ProxyAuth {
    /// A password as typed or pasted into the Proxy login field, ready to store:
    /// leading / trailing line breaks dropped (a copy from `security … -w` or a
    /// terminal brings a trailing newline, which made the stored login wrong for
    /// every app sharing the Keychain item). Nil when what is left is empty or
    /// still contains a control character: a paste accident, not a password.
    /// Spaces are kept.
    static func normalizedPassword(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        return trimmed
    }

    /// True for `https` / `wss`: the only schemes a login may travel over.
    static func isSecure(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https", "wss": return true
        default: return false
        }
    }

    /// The `Authorization` value for a request to `url`, or nil. Over `http` / `ws`
    /// this is always nil, even with a stored login: it would cross the LAN in clear.
    static func authorizationHeader(for url: URL, credentials: ProxyCredentials?) -> String? {
        guard let credentials, isSecure(url) else { return nil }
        return credentials.basicAuthorization
    }

    /// Adds `Authorization` to `request` when `authorizationHeader` allows it. Every
    /// request this app sends to the server (WebSocket upgrade, /api/…, /healthz) goes
    /// through here. It never sets `Origin`: the proxy rejects a foreign one.
    static func authorize(_ request: inout URLRequest, credentials: ProxyCredentials?) {
        guard let url = request.url,
              let value = authorizationHeader(for: url, credentials: credentials) else { return }
        request.setValue(value, forHTTPHeaderField: "Authorization")
    }
}

/// A 401 from the proxy, split by whether this client sent a login.
enum ProxyAuthError: Error, Equatable {
    /// 401 and no `Authorization` was sent: no login stored, or the URL is not https.
    case loginRequired
    /// 401 although `Authorization` was sent: wrong username or password.
    case loginRejected

    /// nil unless `statusCode` is 401. `request` is the one that was sent; whether it
    /// carried `Authorization` decides required vs rejected.
    init?(statusCode: Int, request: URLRequest?) {
        guard statusCode == 401 else { return nil }
        self = request?.value(forHTTPHeaderField: "Authorization") == nil ? .loginRequired : .loginRejected
    }
}

extension ProxyAuthError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .loginRequired:
            return "Proxy login required. Save the proxy login in the connection settings (it is sent over https only)."
        case .loginRejected:
            return "Proxy login rejected. Check the username and password saved in the connection settings."
        }
    }
}
