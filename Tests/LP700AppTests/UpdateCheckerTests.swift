import XCTest
@testable import LP700App

/// The pure parts of UpdateChecker: version comparison, the automatic-check
/// rule, what a finished check stores, the dev-build skip and the parsing of
/// GitHub's answer. No network: `record` and `release(from:response:)` are fed
/// directly, and every test uses its own throw-away UserDefaults suite.
final class UpdateCheckerTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LP700AppTests.UpdateChecker.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private static let hour: TimeInterval = 60 * 60
    private static let now: TimeInterval = 1_800_000_000

    private func release(_ tag: String) -> UpdateChecker.Release {
        UpdateChecker.Release(tagName: tag, name: tag, htmlURL: nil, body: nil)
    }

    @MainActor
    private func makeChecker() -> UpdateChecker {
        UpdateChecker(configuration: .app, defaults: defaults) { _, _ in
            XCTFail("these tests never reach the network")
            throw UpdateChecker.Failure.unreadable
        }
    }

    // MARK: - Configuration

    func testChecksUpstreamRepository() {
        XCTAssertEqual(UpdateChecker.Configuration.app.repository, "VU3ESV/LP-700-App")
        XCTAssertEqual(UpdateChecker.Configuration.app.appName, "LP-700-App")
    }

    // MARK: - Version comparison

    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isVersion("v0.1.14", newerThan: "0.1.13"))
        XCTAssertTrue(UpdateChecker.isVersion("v0.2.0", newerThan: "0.1.13"))
        XCTAssertTrue(UpdateChecker.isVersion("1.10", newerThan: "1.2"))
        XCTAssertTrue(UpdateChecker.isVersion("v0.1.10", newerThan: "0.1.9"))
        XCTAssertFalse(UpdateChecker.isVersion("v0.1.13", newerThan: "0.1.13"))
        XCTAssertFalse(UpdateChecker.isVersion("2.0", newerThan: "2.0.0"))
        XCTAssertFalse(UpdateChecker.isVersion("v0.1.12", newerThan: "0.1.13"))
        // `git describe` stamps of a local build sit above the tag they follow.
        XCTAssertFalse(UpdateChecker.isVersion("v0.1.13", newerThan: "v0.1.13-2-g9860a5f"))
        XCTAssertEqual(UpdateChecker.versionComponents("v1.10.2-rc3"), [1, 10, 2, 3])
        XCTAssertEqual(UpdateChecker.displayVersion(" v0.1.13 "), "0.1.13")
    }

    // MARK: - The automatic-check rule

    func testAutomaticCheckRule() {
        let now = Self.now
        func due(enabled: Bool = true, lastSuccess: TimeInterval = 0,
                 lastFailure: TimeInterval? = nil, dialogOpen: Bool = false) -> Bool {
            UpdateChecker.shouldCheckAutomatically(
                enabled: enabled, lastSuccess: lastSuccess, lastFailure: lastFailure,
                dialogOpen: dialogOpen, now: now)
        }
        XCTAssertTrue(due(), "never checked successfully")
        XCTAssertFalse(due(enabled: false), "setting off")
        XCTAssertFalse(due(dialogOpen: true), "a dialog is already open")
        XCTAssertFalse(due(lastSuccess: now - 23 * Self.hour), "under 24 h since a success")
        XCTAssertTrue(due(lastSuccess: now - 24 * Self.hour), "24 h since a success")
        XCTAssertTrue(due(lastSuccess: now + Self.hour), "stored time in the future")
        XCTAssertFalse(due(lastFailure: now - 30 * 60), "inside the 1 h back-off")
        XCTAssertTrue(due(lastFailure: now - Self.hour), "back-off over")
        XCTAssertTrue(due(lastFailure: now + 30 * 60), "failure time in the future")
    }

    // MARK: - What a finished check stores

    @MainActor
    func testSuccessStoresTimeAndEndsBackoff() {
        let checker = makeChecker()
        _ = checker.record(.failure(.network("offline")), currentVersion: "0.1.13",
                           automatic: true, report: false, now: Self.now)
        XCTAssertEqual(checker.lastAutomaticFailure, Self.now)

        let outcome = checker.record(.success(release("v0.1.13")), currentVersion: "0.1.13",
                                     automatic: true, report: false, now: Self.now + 2 * Self.hour)
        XCTAssertEqual(outcome, .silent, "automatic + up to date says nothing")
        XCTAssertEqual(defaults.double(forKey: UpdateChecker.lastCheckKey), Self.now + 2 * Self.hour)
        XCTAssertNil(checker.lastAutomaticFailure)
    }

    @MainActor
    func testFailureStoresNothing() {
        let checker = makeChecker()
        for failure: UpdateChecker.Failure in [.network("timeout"), .rateLimited, .http(500), .unreadable] {
            let outcome = checker.record(.failure(failure), currentVersion: "0.1.13",
                                         automatic: true, report: false, now: Self.now)
            XCTAssertEqual(outcome, .silent, "automatic failures are silent")
        }
        XCTAssertNil(defaults.object(forKey: UpdateChecker.lastCheckKey))
        XCTAssertEqual(checker.lastAutomaticFailure, Self.now)
    }

    @MainActor
    func testManualFailureReportsAndLeavesBackoffAlone() {
        let checker = makeChecker()
        let outcome = checker.record(.failure(.rateLimited), currentVersion: "0.1.13",
                                     automatic: false, report: true, now: Self.now)
        XCTAssertEqual(outcome, .failed(.rateLimited))
        XCTAssertNil(checker.lastAutomaticFailure)
        XCTAssertNil(defaults.object(forKey: UpdateChecker.lastCheckKey))
    }

    @MainActor
    func testNewerReleaseAndSkippedVersion() {
        let checker = makeChecker()
        let newer = release("v0.1.14")
        XCTAssertEqual(checker.record(.success(newer), currentVersion: "0.1.13",
                                      automatic: true, report: false, now: Self.now),
                       .update(newer))

        defaults.set("v0.1.14", forKey: UpdateChecker.skippedTagKey)
        XCTAssertEqual(checker.record(.success(newer), currentVersion: "0.1.13",
                                      automatic: true, report: false, now: Self.now),
                       .silent, "a skipped version stays quiet on automatic checks")
        XCTAssertEqual(checker.record(.success(newer), currentVersion: "0.1.13",
                                      automatic: false, report: true, now: Self.now),
                       .update(newer), "a manual check still shows it")
        XCTAssertEqual(checker.record(.success(release("v0.1.13")), currentVersion: "0.1.13",
                                      automatic: false, report: true, now: Self.now),
                       .upToDate(release("v0.1.13")))
    }

    // MARK: - Development builds

    func testDevelopmentBuildsNeverCheckAutomatically() throws {
        XCTAssertTrue(UpdateChecker.isDevelopmentVersion("0.0.0-dev"))
        XCTAssertTrue(UpdateChecker.isDevelopmentVersion("1.2-DEV"))
        XCTAssertFalse(UpdateChecker.isDevelopmentVersion("0.1.13"))

        // build-app.sh stamps 0.0.0-dev when VERSION is not set.
        let dev = try makeBundle(version: "0.0.0-dev")
        XCTAssertNil(UpdateChecker.automaticCheckVersion(environment: [:], bundle: dev))
        XCTAssertEqual(UpdateChecker.currentVersion(environment: [:], bundle: dev), "0.0.0-dev",
                       "a manual check still compares the dev version")

        let released = try makeBundle(version: "0.1.13")
        XCTAssertEqual(UpdateChecker.automaticCheckVersion(environment: [:], bundle: released), "0.1.13")

        // The test hook replaces the version and is not subject to the dev rule.
        let hook = [UpdateChecker.testVersionVariable: "0.0.1"]
        XCTAssertEqual(UpdateChecker.automaticCheckVersion(environment: hook, bundle: dev), "0.0.1")
    }

    private func makeBundle(version: String) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LP700AppTests-\(UUID().uuidString).app")
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.vu3esv.lp700-app.tests.\(UUID().uuidString)",
            "CFBundleShortVersionString": version,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: root))
    }

    // MARK: - GitHub's answer

    func testParsesGitHubAnswer() throws {
        let url = URL(string: "https://api.github.com/repos/VU3ESV/LP-700-App/releases/latest")!
        func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        }
        let ok = Data(#"{"tag_name":"v0.1.13","name":"0.1.13","html_url":"https://github.com/VU3ESV/LP-700-App/releases/tag/v0.1.13","body":"notes"}"#.utf8)
        let parsed = try UpdateChecker.release(from: ok, response: response(200))
        XCTAssertEqual(parsed.tagName, "v0.1.13")
        XCTAssertEqual(parsed.version, "0.1.13")

        func failure(_ data: Data, _ http: HTTPURLResponse) -> UpdateChecker.Failure? {
            do { _ = try UpdateChecker.release(from: data, response: http); return nil }
            catch { return error as? UpdateChecker.Failure }
        }
        XCTAssertEqual(failure(Data(#"{"name":"x"}"#.utf8), response(200)), .unreadable)
        XCTAssertEqual(failure(Data(#"{"tag_name":""}"#.utf8), response(200)), .unreadable)
        XCTAssertEqual(failure(Data(), response(404)), .noRelease)
        XCTAssertEqual(failure(Data(), response(403, ["X-RateLimit-Remaining": "0"])), .rateLimited)
        XCTAssertEqual(failure(Data(), response(403)), .http(403))
        XCTAssertEqual(failure(Data(), response(500)), .http(500))
    }
}
