import XCTest
@testable import OpenWisprLib

final class HotkeyHoldReconcileTests: XCTestCase {
    func testMissedKeyUpEndsTheHold() {
        XCTAssertEqual(
            HotkeyHoldReconcile.action(
                keyHeld: true,
                physicallyDown: false,
                lockEngaged: false
            ),
            .endHold
        )
    }

    func testMissedKeyDownStartsTheHold() {
        XCTAssertEqual(
            HotkeyHoldReconcile.action(
                keyHeld: false,
                physicallyDown: true,
                lockEngaged: false
            ),
            .startHold
        )
    }

    func testLockModeDoesNotEndOnAMissedUp() {
        XCTAssertEqual(
            HotkeyHoldReconcile.action(
                keyHeld: true,
                physicallyDown: false,
                lockEngaged: true
            ),
            .none
        )
    }

    func testStableHeldOrReleasedIsANoOp() {
        XCTAssertEqual(
            HotkeyHoldReconcile.action(
                keyHeld: true,
                physicallyDown: true,
                lockEngaged: false
            ),
            .none
        )
        XCTAssertEqual(
            HotkeyHoldReconcile.action(
                keyHeld: false,
                physicallyDown: false,
                lockEngaged: false
            ),
            .none
        )
    }
}

final class HoldAndDoubleTapLockPolicyTests: XCTestCase {
    func testPressesShorterThanTheHoldThresholdAreTapsTowardLock() {
        XCTAssertEqual(
            HoldAndDoubleTapLockPolicy.classifyPress(heldFor: 0.10),
            .countAsTap
        )
        XCTAssertEqual(
            HoldAndDoubleTapLockPolicy.classifyPress(heldFor: 0.219),
            .countAsTap
        )
    }

    func testPressesAtOrPastTheHoldThresholdAreDictation() {
        XCTAssertEqual(
            HoldAndDoubleTapLockPolicy.classifyPress(heldFor: 0.22),
            .finishDictation
        )
        XCTAssertEqual(
            HoldAndDoubleTapLockPolicy.classifyPress(heldFor: 0.30),
            .finishDictation
        )
        XCTAssertEqual(
            HoldAndDoubleTapLockPolicy.classifyPress(heldFor: 0.40),
            .finishDictation
        )
    }

    func testConfirmedHoldReleaseAlwaysFinishesAndNeverCancels() {
        XCTAssertEqual(
            HoldAndDoubleTapLockPolicy.releaseAction(
                holdConfirmed: true,
                lockEngaged: false
            ),
            .finishDictation
        )
    }

    func testUnconfirmedReleaseCountsAsATapTowardLock() {
        XCTAssertEqual(
            HoldAndDoubleTapLockPolicy.releaseAction(
                holdConfirmed: false,
                lockEngaged: false
            ),
            .countAsTap
        )
    }

    func testLockedReleaseIsAnUnlockCheckNotACancel() {
        XCTAssertEqual(
            HoldAndDoubleTapLockPolicy.releaseAction(
                holdConfirmed: true,
                lockEngaged: true
            ),
            .maybeUnlock
        )
        XCTAssertEqual(
            HoldAndDoubleTapLockPolicy.releaseAction(
                holdConfirmed: false,
                lockEngaged: true
            ),
            .maybeUnlock
        )
    }
}
