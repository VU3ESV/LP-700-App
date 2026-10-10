import XCTest
@testable import LP700App

/// `MeterViewModel.configuredServerURL(_:)` is the one rule that decides whether a saved
/// "serverURL" preference is usable. All three entry points — the standalone window's
/// bootstrap, the in-process `LP700Plugin.activate()` and the hosted `HostedRootView` —
/// go through it, so they auto-connect (or ask for a URL) under identical conditions.
final class ServerURLTests: XCTestCase {

    func testAcceptsURLsWithAHost() {
        XCTAssertEqual(MeterViewModel.configuredServerURL("http://192.168.86.240:8089")?.host,
                       "192.168.86.240")
        XCTAssertEqual(MeterViewModel.configuredServerURL("http://localhost:8089")?.port, 8089)
        XCTAssertEqual(MeterViewModel.configuredServerURL("https://raspberrypi.local:8089")?.host,
                       "raspberrypi.local")
    }

    func testRejectsEmptyAndHostlessStrings() {
        XCTAssertNil(MeterViewModel.configuredServerURL(""))
        XCTAssertNil(MeterViewModel.configuredServerURL("   "))
        // "localhost:8089" parses as scheme "localhost" with no host — the sheet rejects it
        // as an invalid URL, so bootstrap must not try to connect to it either.
        XCTAssertNil(MeterViewModel.configuredServerURL("localhost:8089"))
        XCTAssertNil(MeterViewModel.configuredServerURL("http://"))
    }

    func testIgnoresSurroundingWhitespace() {
        XCTAssertEqual(MeterViewModel.configuredServerURL("  http://host:8089 \n")?.absoluteString,
                       "http://host:8089")
    }

    func testRoundTripsAnAbsoluteStringUnchanged() {
        let s = "http://192.168.86.240:8089"
        XCTAssertEqual(MeterViewModel.configuredServerURL(s)?.absoluteString, s)
    }
}
