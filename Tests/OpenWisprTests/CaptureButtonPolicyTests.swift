import AppKit
import XCTest
@testable import OpenWisprLib

final class CaptureButtonPolicyTests: XCTestCase {
    func testIdlePrimaryClickStartsCapture() {
        XCTAssertEqual(CaptureButtonPolicy.action(isCapturing: false), .start)
    }

    func testRecordingOrLockedPrimaryClickStopsAndUnlocks() {
        XCTAssertEqual(CaptureButtonPolicy.action(isCapturing: true), .stopAndUnlock)
    }

    func testLeftClickIsPTTNotMenu() {
        XCTAssertEqual(
            StatusItemClickPolicy.kind(
                eventType: .leftMouseUp,
                modifierFlags: []
            ),
            .toggleCapture
        )
    }

    func testRightClickOpensMenu() {
        XCTAssertEqual(
            StatusItemClickPolicy.kind(
                eventType: .rightMouseUp,
                modifierFlags: []
            ),
            .showMenu
        )
    }

    func testControlClickOpensMenu() {
        XCTAssertEqual(
            StatusItemClickPolicy.kind(
                eventType: .leftMouseUp,
                modifierFlags: .control
            ),
            .showMenu
        )
    }
}

final class LockModeEnabledResolutionTests: XCTestCase {
    func testMissingLockModeKeyDefaultsFalse() {
        XCTAssertFalse(Config.effectiveLockModeEnabled(nil))
        XCTAssertEqual(Config.defaultLockModeEnabled, false)
        XCTAssertEqual(Config.defaultConfig.lockModeEnabled?.value, false)
        XCTAssertEqual(Config.defaultConfig.toggleMode?.value, false)
    }

    func testExplicitTrueEnablesLock() {
        XCTAssertTrue(Config.effectiveLockModeEnabled(FlexBool(true)))
    }

    func testFnDefaultsToHoldWhenLockDisabled() {
        let hk = HotkeyConfig(keyCode: 63, modifiers: [])
        XCTAssertEqual(
            hk.resolvedActivationMode(globalToggle: false, lockModeEnabled: false),
            .hold
        )
    }

    func testFnCanLockWhenOptedIn() {
        let hk = HotkeyConfig(keyCode: 63, modifiers: [])
        XCTAssertEqual(
            hk.resolvedActivationMode(globalToggle: false, lockModeEnabled: true),
            .holdAndDoubleTapLock
        )
    }

    func testExplicitLockModeStillRequiresOptIn() {
        let hk = HotkeyConfig(
            keyCode: 63,
            modifiers: [],
            activationMode: .holdAndDoubleTapLock
        )
        XCTAssertEqual(
            hk.resolvedActivationMode(globalToggle: false, lockModeEnabled: false),
            .hold
        )
        XCTAssertEqual(
            hk.resolvedActivationMode(globalToggle: false, lockModeEnabled: true),
            .holdAndDoubleTapLock
        )
    }

    func testGlobalToggleWinsOverLock() {
        let hk = HotkeyConfig(keyCode: 63, modifiers: [])
        XCTAssertEqual(
            hk.resolvedActivationMode(globalToggle: true, lockModeEnabled: true),
            .toggle
        )
    }

    func testConfigDecodesLockModeEnabled() throws {
        let json = """
        {
            "hotkey": {"keyCode": 63, "modifiers": []},
            "modelSize": "base.en",
            "language": "en",
            "lockModeEnabled": true
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertEqual(config.lockModeEnabled?.value, true)
        XCTAssertTrue(Config.effectiveLockModeEnabled(config.lockModeEnabled))
    }

    func testConfigDecodesWithoutLockModeEnabled() throws {
        let json = """
        {
            "hotkey": {"keyCode": 63, "modifiers": []},
            "modelSize": "base.en",
            "language": "en"
        }
        """.data(using: .utf8)!
        let config = try Config.decode(from: json)
        XCTAssertNil(config.lockModeEnabled)
        XCTAssertFalse(Config.effectiveLockModeEnabled(config.lockModeEnabled))
    }
}
