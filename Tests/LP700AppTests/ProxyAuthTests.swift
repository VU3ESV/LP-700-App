import XCTest
import Network
@testable import LP700App

/// The proxy login rule: `Authorization: Basic …` on every request to the server over
/// https/wss, never over http/ws; and a 401 maps to "login required" (nothing sent) or
/// "login rejected" (a login was sent). Credentials are injected — no test touches the
/// real Keychain (that would raise a macOS prompt) — and the password is a dummy.
final class ProxyAuthTests: XCTestCase {

    private let login = ProxyCredentials(username: "operator", password: "not-the-real-one")
    /// base64("operator:not-the-real-one")
    private let loginHeader = "Basic b3BlcmF0b3I6bm90LXRoZS1yZWFsLW9uZQ=="

    // MARK: - Header rule

    func testBasicAuthorizationIsBase64OfUserColonPassword() {
        XCTAssertEqual(login.basicAuthorization, loginHeader)
        // RFC 7617 §2 example, and its UTF-8 example (§2.1).
        XCTAssertEqual(ProxyCredentials(username: "Aladdin", password: "open sesame").basicAuthorization,
                       "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==")
        XCTAssertEqual(ProxyCredentials(username: "test", password: "123£").basicAuthorization,
                       "Basic dGVzdDoxMjPCow==")
    }

    // MARK: - Pasted passwords (a trailing newline broke the shared login on 2026-10-29)

    func testNormalizedPasswordDropsTrailingNewlineFromAPaste() {
        XCTAssertEqual(ProxyAuth.normalizedPassword("s3cret\n"), "s3cret")
        XCTAssertEqual(ProxyAuth.normalizedPassword("s3cret\r\n"), "s3cret")
        XCTAssertEqual(ProxyAuth.normalizedPassword("\ns3cret\n\n"), "s3cret")
    }

    func testNormalizedPasswordKeepsSpacesAndPlainPasswords() {
        XCTAssertEqual(ProxyAuth.normalizedPassword("s3cret"), "s3cret")
        XCTAssertEqual(ProxyAuth.normalizedPassword(" pass phrase "), " pass phrase ")
    }

    func testNormalizedPasswordRefusesControlCharactersAndEmpty() {
        XCTAssertNil(ProxyAuth.normalizedPassword("first\nsecond"))   // two lines pasted
        XCTAssertNil(ProxyAuth.normalizedPassword("tab\there"))
        XCTAssertNil(ProxyAuth.normalizedPassword("\u{7F}x"))
        XCTAssertNil(ProxyAuth.normalizedPassword("\n"))
        XCTAssertNil(ProxyAuth.normalizedPassword(""))
    }

    func testAttachedOverHTTPSAndWSS() {
        for s in ["https://192.168.86.43:8089/api/config", "wss://192.168.86.43:8089/ws",
                  "HTTPS://stationmonitor2.local:8089/healthz"] {
            let url = URL(string: s)!
            XCTAssertEqual(ProxyAuth.authorizationHeader(for: url, credentials: login), loginHeader, s)
            var request = URLRequest(url: url)
            ProxyAuth.authorize(&request, credentials: login)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), loginHeader, s)
        }
    }

    func testNeverAttachedOverHTTPOrWSEvenWithAStoredLogin() {
        for s in ["http://192.168.86.43:8089/api/config", "ws://192.168.86.43:8089/ws",
                  "http://localhost:8089/healthz"] {
            let url = URL(string: s)!
            XCTAssertNil(ProxyAuth.authorizationHeader(for: url, credentials: login), s)
            var request = URLRequest(url: url)
            ProxyAuth.authorize(&request, credentials: login)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), s)
        }
    }

    func testNothingAttachedWithoutALogin() {
        var request = URLRequest(url: URL(string: "https://192.168.86.43:8089/api/config")!)
        ProxyAuth.authorize(&request, credentials: nil)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testWebSocketUpgradeRequest() {
        let tls = WSClient.upgradeRequest(for: URL(string: "https://192.168.86.43:8089")!, credentials: login)
        XCTAssertEqual(tls.url?.absoluteString, "wss://192.168.86.43:8089/ws")
        XCTAssertEqual(tls.value(forHTTPHeaderField: "Authorization"), loginHeader)
        XCTAssertNil(tls.value(forHTTPHeaderField: "Origin"), "the proxy 403s a foreign Origin")

        let plain = WSClient.upgradeRequest(for: URL(string: "http://192.168.86.43:8089")!, credentials: login)
        XCTAssertEqual(plain.url?.absoluteString, "ws://192.168.86.43:8089/ws")
        XCTAssertNil(plain.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(plain.value(forHTTPHeaderField: "Origin"))
    }

    func testDescriptionRedactsPassword() {
        XCTAssertFalse(String(describing: login).contains(login.password))
        XCTAssertFalse(String(reflecting: login).contains(login.password))
    }

    // MARK: - 401 mapping

    func test401MapsToRequiredOrRejected() {
        var sent = URLRequest(url: URL(string: "https://192.168.86.43:8089/ws")!)
        ProxyAuth.authorize(&sent, credentials: login)
        let bare = URLRequest(url: URL(string: "https://192.168.86.43:8089/ws")!)

        XCTAssertEqual(ProxyAuthError(statusCode: 401, request: sent), .loginRejected)
        XCTAssertEqual(ProxyAuthError(statusCode: 401, request: bare), .loginRequired)
        XCTAssertEqual(ProxyAuthError(statusCode: 401, request: nil), .loginRequired)
        for status in [101, 200, 403, 404, 500] {
            XCTAssertNil(ProxyAuthError(statusCode: status, request: sent), "\(status)")
        }
    }

    func testErrorTexts() {
        XCTAssertEqual(ProxyAuthError.loginRequired.localizedDescription,
                       "Proxy login required. Save the proxy login in the connection settings (it is sent over https only).")
        XCTAssertEqual(ProxyAuthError.loginRejected.localizedDescription,
                       "Proxy login rejected. Check the username and password saved in the connection settings.")
    }

    func testHTTPStatusCheck() throws {
        let url = URL(string: "https://192.168.86.43:8089/api/config")!
        func response(_ status: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        }
        var sent = URLRequest(url: url)
        ProxyAuth.authorize(&sent, credentials: login)

        XCTAssertNoThrow(try ConfigClient.checkOK(response(200), for: sent))
        XCTAssertThrowsError(try ConfigClient.checkOK(response(401), for: sent)) {
            XCTAssertEqual($0 as? ProxyAuthError, .loginRejected)
        }
        XCTAssertThrowsError(try ConfigClient.checkOK(response(401), for: URLRequest(url: url))) {
            XCTAssertEqual($0 as? ProxyAuthError, .loginRequired)
        }
        XCTAssertThrowsError(try ConfigClient.checkOK(response(500), for: sent)) {
            XCTAssertEqual(($0 as? URLError)?.code, .badServerResponse)
        }
    }

    // MARK: - On the wire (local stub answering like the proxy)

    /// No credential storage: the stub's `WWW-Authenticate` must not send URLSession
    /// looking for a saved login.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCredentialStorage = nil
        return URLSession(configuration: config)
    }()

    /// The WebSocket client over plain ws with a login on hand: the upgrade carries neither
    /// `Authorization` nor `Origin`, the 401 surfaces as `.loginRequired`, and it is not
    /// retried at the normal 0.5 s backoff.
    func testWebSocket401OverPlainWS() async throws {
        let stub = Stub401Server()
        let port = try await stub.start()
        defer { stub.stop() }

        let client = WSClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!,
                              credentials: login, session: Self.session)
        let failed = expectation(description: "authFailed")
        let collector = Task { () -> (errors: [ProxyAuthError], attempts: Int) in
            var errors: [ProxyAuthError] = []
            var attempts = 0
            for await event in client.events {
                switch event {
                case .authFailed(let error):
                    errors.append(error)
                    if errors.count == 1 { failed.fulfill() }
                case .stateChanged(.reconnecting):
                    attempts += 1
                default:
                    break
                }
            }
            return (errors, attempts)
        }

        await client.start()
        await fulfillment(of: [failed], timeout: 8)
        try await Task.sleep(nanoseconds: 1_500_000_000)   // 3× the normal first backoff
        await client.stop()
        collector.cancel()
        let result = await collector.value

        XCTAssertEqual(result.errors, [.loginRequired])
        XCTAssertEqual(result.attempts, 1, "a 401 must wait out the longer auth backoff")
        let requests = stub.requests
        // One attempt. CFNetwork re-sends it once (same request, same Sec-WebSocket-Key)
        // after the `WWW-Authenticate` challenge finds no saved credential.
        XCTAssertFalse(requests.isEmpty)
        XCTAssertEqual(Set(requests).count, 1, "more than one distinct request")
        XCTAssertTrue(requests.first?.hasPrefix("GET /ws ") == true, requests.first ?? "")
        XCTAssertFalse(requests.joined().lowercased().contains("\r\nauthorization:"))
        XCTAssertFalse(requests.joined().lowercased().contains("\r\norigin:"))
    }

    /// Same for the REST client over plain http.
    func testHTTP401OverPlainHTTP() async throws {
        let stub = Stub401Server()
        let port = try await stub.start()
        defer { stub.stop() }

        let client = ConfigClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!,
                                  credentials: login, session: Self.session)
        do {
            _ = try await client.fetchConfig()
            XCTFail("expected a 401")
        } catch {
            XCTAssertEqual(error as? ProxyAuthError, .loginRequired)
        }
        let requests = stub.requests
        // One attempt. CFNetwork re-sends it once (same request, same Sec-WebSocket-Key)
        // after the `WWW-Authenticate` challenge finds no saved credential.
        XCTAssertFalse(requests.isEmpty)
        XCTAssertEqual(Set(requests).count, 1, "more than one distinct request")
        XCTAssertTrue(requests.first?.hasPrefix("GET /api/config ") == true, requests.first ?? "")
        XCTAssertFalse(requests.joined().lowercased().contains("\r\nauthorization:"))
    }
}

/// Answers every HTTP request with the proxy's 401 and records the request heads.
private final class Stub401Server: @unchecked Sendable {
    private let lock = NSLock()
    private var heads: [String] = []
    private var listener: NWListener?
    private var ready: CheckedContinuation<Void, Error>?

    var requests: [String] {
        lock.lock(); defer { lock.unlock() }
        return heads
    }

    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global())
            self?.receive(on: conn, buffer: Data())
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.lock(); ready = cont; lock.unlock()
            listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state) }
            listener.start(queue: .global())
        }
        return listener.port!.rawValue
    }

    private func listenerChanged(_ state: NWListener.State) {
        let result: Result<Void, Error>
        switch state {
        case .ready: result = .success(())
        case .failed(let error): result = .failure(error)
        default: return
        }
        lock.lock(); let cont = ready; ready = nil; lock.unlock()
        cont?.resume(with: result)
    }

    func stop() { listener?.cancel() }

    private func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.lock.lock()
                self.heads.append(String(decoding: buffer[..<end.upperBound], as: UTF8.self))
                self.lock.unlock()
                let body = "Unauthorized\n"
                let reply = "HTTP/1.1 401 Unauthorized\r\n"
                    + "WWW-Authenticate: Basic realm=\"StationMonitor2\"\r\n"
                    + "Content-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\n"
                    + "Connection: close\r\n\r\n" + body
                conn.send(content: Data(reply.utf8), completion: .contentProcessed { _ in conn.cancel() })
            } else if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receive(on: conn, buffer: buffer)
            }
        }
    }
}
