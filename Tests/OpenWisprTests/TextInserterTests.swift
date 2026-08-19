import XCTest
@testable import OpenWisprLib

final class TextInserterTests: XCTestCase {

    func testSpeakDoesNotCopyAndAttemptsFieldInsert() {
        XCTAssertEqual(
            TextInsertPlanner.strategy(
                accessibilityTrusted: false,
                secureFieldBlocked: false
            ),
            .insertIntoField
        )
        XCTAssertFalse(
            TextInsertPlanner.shouldRestoreClipboard(for: .transcribedOnly)
        )
        XCTAssertEqual(
            TextInsertOutcome.transcribedOnly.operatorMessage,
            "Grant Accessibility to Local Voice in System Settings to type into the field."
        )
        XCTAssertFalse(TextInsertOutcome.transcribedOnly.didConfirmFieldInsert)
    }

    func testSecureFieldBlocksInjectionWithoutCopying() {
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

    func testTrustedAccessibilityInsertsIntoFieldWithoutClipboardRestore() {
        XCTAssertEqual(
            TextInsertPlanner.strategy(
                accessibilityTrusted: true,
                secureFieldBlocked: false
            ),
            .insertIntoField
        )
        XCTAssertFalse(
            TextInsertPlanner.shouldRestoreClipboard(for: .insertedViaAccessibility)
        )
        XCTAssertTrue(TextInsertOutcome.insertedViaAccessibility.didConfirmFieldInsert)
        XCTAssertTrue(TextInsertOutcome.insertedViaLiveComposer.didConfirmFieldInsert)
        XCTAssertTrue(TextInsertOutcome.insertedViaUnicode.didConfirmFieldInsert)
    }

    func testInsertLeavesExistingClipboardAlone() {
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
        inserter.postEventTrusted = { false }
        var axCalls = 0
        var unicodeCalls = 0
        inserter.accessibilityWriter = { _ in
            axCalls += 1
            return false
        }
        inserter.unicodeWriter = { _ in
            unicodeCalls += 1
        }
        let marker = "lv-no-copy-\(UUID().uuidString)"
        let outcome = inserter.insert(text: marker)

        XCTAssertEqual(outcome, .transcribedOnly)
        XCTAssertEqual(axCalls, 1)
        XCTAssertEqual(unicodeCalls, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), priorMarker)
    }

    func testPostEventGrantRecordsUnicodeInsertWithoutClipboard() {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previous {
                pasteboard.setString(previous, forType: .string)
            }
        }

        let priorMarker = "lv-unicode-clipboard-\(UUID().uuidString)"
        pasteboard.clearContents()
        pasteboard.setString(priorMarker, forType: .string)

        let inserter = TextInserter()
        inserter.accessibilityTrusted = { false }
        inserter.postEventTrusted = { true }
        var unicodeCalls = 0
        var typed = ""
        inserter.accessibilityWriter = { _ in false }
        inserter.unicodeWriter = { text in
            unicodeCalls += 1
            typed = text
        }
        let marker = "lv-unicode-\(UUID().uuidString)"
        let outcome = inserter.insert(text: marker)

        XCTAssertEqual(outcome, .insertedViaUnicode)
        XCTAssertEqual(unicodeCalls, 1)
        XCTAssertEqual(typed, marker)
        XCTAssertEqual(pasteboard.string(forType: .string), priorMarker)
    }

    func testAccessibilityInsertStillLeavesClipboardAlone() {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previous {
                pasteboard.setString(previous, forType: .string)
            }
        }

        let priorMarker = "lv-ax-clipboard-\(UUID().uuidString)"
        pasteboard.clearContents()
        pasteboard.setString(priorMarker, forType: .string)

        let inserter = TextInserter()
        inserter.accessibilityTrusted = { true }
        inserter.postEventTrusted = { false }
        var unicodeCalls = 0
        inserter.accessibilityWriter = { _ in true }
        inserter.unicodeWriter = { _ in unicodeCalls += 1 }
        let outcome = inserter.insert(text: "typed into field")

        XCTAssertEqual(outcome, .insertedViaAccessibility)
        XCTAssertEqual(unicodeCalls, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), priorMarker)
    }
}
