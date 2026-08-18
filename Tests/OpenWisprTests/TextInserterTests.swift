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
            "Copied. Press Cmd-V now. Accessibility: Local Voice.app, not Vault."
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

    func testCopyNeedsAccessibilityLeavesTranscriptOnPasteboardAndUsesPasteStub() {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previous {
                pasteboard.setString(previous, forType: .string)
            }
        }

        let priorMarker = "lv-prior-clipboard-\(UUID().uuidString)"
        pasteboard.clearContents()
        pasteboard.setString(priorMarker, forType: .string)

        let inserter = TextInserter()
        inserter.accessibilityTrusted = { false }
        var pastePosterCallCount = 0
        inserter.pastePoster = {
            pastePosterCallCount += 1
            return false
        }
        let marker = "lv-paste-probe-\(UUID().uuidString)"
        let outcome = inserter.insert(text: marker)

        XCTAssertEqual(outcome, .copiedNeedsAccessibility)
        XCTAssertEqual(pastePosterCallCount, 1, "Tests must use the stub instead of posting a live Cmd-V")
        XCTAssertEqual(pasteboard.string(forType: .string), marker)

        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            marker,
            "AX-false quiet-copy must not restore the prior clipboard value"
        )
    }
}
