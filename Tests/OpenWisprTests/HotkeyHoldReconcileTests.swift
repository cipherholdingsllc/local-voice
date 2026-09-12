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
