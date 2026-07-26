import XCTest
@testable import OpenWisprLib

final class LocalVoiceCommandResolverTests: XCTestCase {
    func testLaunchServicesWithoutArgumentsStartsBundledApp() {
        let command = LocalVoiceCommandResolver.resolve(
            rawCommand: nil,
            executablePath:
                "/Users/test/Applications/Local Voice.app/Contents/MacOS/local-voice"
        )

        XCTAssertEqual(command, "start")
    }

    func testProcessSerialNumberStartsBundledApp() {
        let command = LocalVoiceCommandResolver.resolve(
            rawCommand: "-psn_0_12345",
            executablePath:
                "/Users/test/Applications/Local Voice.app/Contents/MacOS/local-voice"
        )

        XCTAssertEqual(command, "start")
    }

    func testBareCLIWithoutArgumentsStillShowsHelp() {
        let command = LocalVoiceCommandResolver.resolve(
            rawCommand: nil,
            executablePath: "/opt/homebrew/bin/local-voice"
        )

        XCTAssertNil(command)
    }

    func testExplicitCLICommandIsPreserved() {
        let command = LocalVoiceCommandResolver.resolve(
            rawCommand: "status",
            executablePath:
                "/Users/test/Applications/Local Voice.app/Contents/MacOS/local-voice"
        )

        XCTAssertEqual(command, "status")
    }
}

final class LocalVoicePermissionSnapshotTests: XCTestCase {
    func testInputMonitoringIsTheFnHotkeyGate() {
        let snapshot = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: true,
            inputMonitoring: false
        )

        XCTAssertFalse(snapshot.hotkeyReady)
        XCTAssertFalse(snapshot.dictationReady)
        XCTAssertEqual(
            snapshot.blockingSummary,
            "Input Monitoring is required for the fn hotkey"
        )
    }

    func testAccessibilityIsReportedAfterHotkeyAndMicrophone() {
        let snapshot = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: false,
            inputMonitoring: true
        )

        XCTAssertTrue(snapshot.hotkeyReady)
        XCTAssertFalse(snapshot.dictationReady)
        XCTAssertEqual(
            snapshot.blockingSummary,
            "Accessibility is required to insert text"
        )
    }

    func testAllPermissionsMakeDictationReady() {
        let snapshot = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: true,
            inputMonitoring: true
        )

        XCTAssertTrue(snapshot.hotkeyReady)
        XCTAssertTrue(snapshot.dictationReady)
        XCTAssertNil(snapshot.blockingSummary)
    }
}
