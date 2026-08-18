import XCTest
@testable import OpenWisprLib

final class TextInserterTests: XCTestCase {

    func testPasteKeyCodeResolvesForCurrentLayout() {
        let inserter = TextInserter()
        XCTAssertTrue(inserter.pasteKeyCode < 128, "Paste key code should be a valid virtual key code")
    }

    func testMissingAccessibilityCopiesInsteadOfFakingPaste() {
        XCTAssertEqual(
            TextInsertPlanner.strategy(
                accessibilityTrusted: false,
                secureFieldBlocked: false
            ),
            .copyNeedsAccessibility
        )
        XCTAssertFalse(
            TextInsertPlanner.shouldRestoreClipboard(for: .copiedNeedsAccessibility)
        )
        XCTAssertEqual(
            TextInsertOutcome.copiedNeedsAccessibility.operatorMessage,
            "Copied. Accessibility ON for Local Voice.app — not Vault."
        )
        XCTAssertFalse(TextInsertOutcome.copiedNeedsAccessibility.didConfirmFieldInsert)
    }

    func testSecureFieldBlocksInjectionEvenWhenAccessibilityIsOn() {
        XCTAssertEqual(
            TextInsertPlanner.strategy(
                accessibilityTrusted: true,
                secureFieldBlocked: true
            ),
            .blockedSecureField
        )
        XCTAssertFalse(
            TextInsertPlanner.shouldRestoreClipboard(for: .blockedSecureField)
        )
    }

    func testTrustedAccessibilityInsertsIntoFieldAndMayRestoreClipboard() {
        XCTAssertEqual(
            TextInsertPlanner.strategy(
                accessibilityTrusted: true,
                secureFieldBlocked: false
            ),
            .insertIntoField
        )
        XCTAssertTrue(
            TextInsertPlanner.shouldRestoreClipboard(for: .insertedViaAccessibility)
        )
        XCTAssertFalse(
            TextInsertPlanner.shouldRestoreClipboard(for: .insertedViaPaste)
        )
        XCTAssertTrue(TextInsertOutcome.insertedViaAccessibility.didConfirmFieldInsert)
        XCTAssertFalse(TextInsertOutcome.insertedViaPaste.didConfirmFieldInsert)
    }

    func testCopyNeedsAccessibilityLeavesTranscriptOnPasteboard() {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previous {
                pasteboard.setString(previous, forType: .string)
            }
        }

        let inserter = TextInserter()
        inserter.accessibilityTrusted = { false }
        let marker = "lv-paste-probe-\(UUID().uuidString)"
        let outcome = inserter.insert(text: marker)
        XCTAssertEqual(outcome, .copiedNeedsAccessibility)
        XCTAssertEqual(pasteboard.string(forType: .string), marker)
    }
}
