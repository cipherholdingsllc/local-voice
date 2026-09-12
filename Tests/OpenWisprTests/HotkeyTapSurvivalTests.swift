import XCTest
@testable import OpenWisprLib

final class HotkeyTapSurvivalTests: XCTestCase {
    func testRearmsWhenTheFrontmostAppChanges() {
        XCTAssertTrue(
            HotkeyTapSurvival.shouldRearmOnFrontmostChange(
                previousBundleID: "com.apple.Notes",
                currentBundleID: "com.todesktop.230313mzl4w4u92"
            )
        )
    }

    func testDoesNotRearmWhenTheSameAppStaysFrontmost() {
        XCTAssertFalse(
            HotkeyTapSurvival.shouldRearmOnFrontmostChange(
                previousBundleID: "com.todesktop.230313mzl4w4u92",
                currentBundleID: "com.todesktop.230313mzl4w4u92"
            )
        )
    }

    func testCursorToDesktopBundleIsACompetingEditor() {
        XCTAssertTrue(
            HotkeyTapSurvival.isCompetingEditor("com.todesktop.230313mzl4w4u92")
        )
        XCTAssertTrue(HotkeyTapSurvival.isCompetingEditor("com.microsoft.VSCode"))
        XCTAssertFalse(HotkeyTapSurvival.isCompetingEditor("com.apple.Notes"))
        XCTAssertFalse(HotkeyTapSurvival.isCompetingEditor(nil))
    }

    func testCursorGetsALongerReenableWindowThanNotes() {
        let cursor = HotkeyTapSurvival.reenableDelays(
            forBundleID: "com.todesktop.230313mzl4w4u92"
        )
        let notes = HotkeyTapSurvival.reenableDelays(forBundleID: "com.apple.Notes")
        XCTAssertGreaterThan(cursor.max() ?? 0, notes.max() ?? 0)
        XCTAssertGreaterThanOrEqual(cursor.max() ?? 0, 0.5)
        XCTAssertTrue(cursor.contains(0))
        XCTAssertTrue(notes.contains(0))
    }
}
