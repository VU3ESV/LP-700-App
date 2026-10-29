import Foundation

// REST helpers for /api/config and /api/log-level on the LP-700 server.
struct ServerConfig: Decodable, Equatable {
    var backend: String
    var allowControl: Bool
    var title: String

    enum CodingKeys: String, CodingKey {
        case backend
        case allowControl = "allow_control"
        case title
    }
}

struct LogLevelConfig: Codable, Equatable {
    var level: String
}

actor ConfigClient {
    private var baseURL: URL
    /// Proxy login, attached over https only (see `ProxyAuth`).
    private var credentials: ProxyCredentials?
    private let session: URLSession

    init(baseURL: URL, credentials: ProxyCredentials? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.session = session
    }

    func setBaseURL(_ url: URL) {
        baseURL = url
    }

    func setCredentials(_ credentials: ProxyCredentials?) {
        self.credentials = credentials
    }

    func fetchConfig() async throws -> ServerConfig {
        try await get(path: "/api/config")
    }

    func fetchLogLevel() async throws -> LogLevelConfig {
        try await get(path: "/api/log-level")
    }

    func setLogLevel(_ level: String) async throws -> LogLevelConfig {
        try await postJSON(path: "/api/log-level", body: LogLevelConfig(level: level))
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        ProxyAuth.authorize(&req, credentials: credentials)
        let (data, resp) = try await session.data(for: req)
        try Self.checkOK(resp, for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postJSON<Body: Encodable, R: Decodable>(path: String, body: Body) async throws -> R {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        ProxyAuth.authorize(&req, credentials: credentials)
        let (data, resp) = try await session.data(for: req)
        try Self.checkOK(resp, for: req)
        return try JSONDecoder().decode(R.self, from: data)
    }

    /// Throws `ProxyAuthError` for a 401 (decided by what `request` carried) and
    /// `URLError(.badServerResponse)` for any other non-2xx.
    static func checkOK(_ resp: URLResponse, for request: URLRequest) throws {
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if let authError = ProxyAuthError(statusCode: http.statusCode, request: request) {
            throw authError
        }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }
}
