import XCTest
@testable import OpenWisprLib

final class EventTapRegistrationTests: XCTestCase {
    func testPreflightFalseStillAttemptsTapCreate() {
        XCTAssertTrue(
            EventTapRegistration.shouldAttemptCreate(preflightGranted: false)
        )
        XCTAssertTrue(
            EventTapRegistration.shouldAttemptCreate(preflightGranted: true)
        )
    }

    func testPrefersHIDTapThenFallsBackToSession() {
        let locations = EventTapRegistration.tapLocationsInPriorityOrder()
        XCTAssertEqual(locations.first, .cghidEventTap)
        XCTAssertEqual(locations.last, .cgSessionEventTap)
        XCTAssertEqual(locations.count, 2)
    }

    func testPermissionProbeRoundTripsAndNamesTheApplicationsCopy() {
        let snapshot = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: false,
            inputMonitoring: false
        )
        let probe = LocalVoicePermissionProbe.make(
            snapshot: snapshot,
            hotkeyMonitorReady: false,
            tapAttempted: true,
            tapStarted: false,
            bundlePath: "/Users/ciphercowork/Applications/Local Voice.app"
        )

        XCTAssertEqual(probe.schemaVersion, LocalVoicePermissionProbe.schemaVersion)
        XCTAssertTrue(probe.tapAttempted)
        XCTAssertFalse(probe.tapStarted)
        XCTAssertTrue(probe.bundlePath.contains("Applications/Local Voice.app"))
        XCTAssertFalse(probe.bundlePath.contains("Repos/local-voice"))
        XCTAssertFalse(probe.postEvent)
        XCTAssertEqual(probe.schemaVersion, "local-voice-permission-probe.v2")
    }
}
