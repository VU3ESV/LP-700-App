import XCTest
@testable import LP700App

/// Pins which Controls-card buttons are usable in CH Auto. The LP-500 user
/// guide v5.4 says Range and Alarm "can't be changed when the CH button is
/// in Auto", and a 2026-10-13 bench test on the LP-700 agreed; Channel and
/// Peak/Avg/Tune still work.
final class ControlsGateTests: XCTestCase {

    private func snapshot(autoChannel: Bool) throws -> Snapshot {
        let json = #"{"channel": 2, "auto_channel": \#(autoChannel), "range": "100W"}"#
        return try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }

    private func controls(autoChannel: Bool) throws -> ControlsModel {
        PowerSWRModel.make(snapshot: try snapshot(autoChannel: autoChannel),
                           allowControl: true,
                           connected: true,
                           setupOpen: false).controls
    }

    func testCHAutoGreysOutRangeAndAlarm() throws {
        let c = try controls(autoChannel: true)
        XCTAssertTrue(c.rangeDisabled)
        XCTAssertTrue(c.alarmDisabled)
        XCTAssertFalse(c.channelDisabled, "CH must stay usable so the operator can leave Auto")
        XCTAssertFalse(c.peakDisabled)
        XCTAssertNotNil(c.lockNote)
        XCTAssertEqual(c.rangeLabel, "100W", "the real range still shows while locked")
    }

    func testExplicitChannelEnablesRangeAndAlarm() throws {
        let c = try controls(autoChannel: false)
        XCTAssertFalse(c.rangeDisabled)
        XCTAssertFalse(c.alarmDisabled)
        XCTAssertNil(c.lockNote)
    }
}
