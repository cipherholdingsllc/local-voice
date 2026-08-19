import AppKit
import ApplicationServices
import Foundation

class TextInserter {
    var accessibilityTrusted: () -> Bool = { AXIsProcessTrusted() }
    var postEventTrusted: () -> Bool = { PostEventAccess.isGranted() }
    /// Tests stub AX writes so unit runs do not mutate the focused field.
    var accessibilityWriter: ((String) -> Bool)?
    /// Tests stub keystroke injection so unit runs do not type into the focused app.
    var unicodeWriter: ((String) -> Void)?

    init() {}

    @discardableResult
    func insert(text: String) -> TextInsertOutcome {
        let guardResult = SecureFieldGuard.canInjectHere()
        if !guardResult.allowed {
            if let reason = guardResult.reason {
                fputs("TextInserter: \(reason)\n", stderr)
            }
            return .blockedSecureField
        }

        if insertViaAccessibility(text) {
            return .insertedViaAccessibility
        }

        // Unicode CGEvent.post is a silent no-op without Post Event.
        // Do not post, and do not claim a field insert, when that grant is missing.
        guard postEventTrusted() else {
            return .transcribedOnly
        }
        insertViaUnicode(text)
        return .insertedViaUnicode
    }

    @discardableResult
    private func insertViaAccessibility(_ text: String) -> Bool {
        if let accessibilityWriter {
            return accessibilityWriter(text)
        }
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let element = focused else {
            return false
        }
        let ax = element as! AXUIElement
        return AXUIElementSetAttributeValue(
            ax,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success
    }

    /// Type the transcript as keystrokes. Does not touch the clipboard.
    private func insertViaUnicode(_ text: String) {
        if let unicodeWriter {
            unicodeWriter(text)
            return
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for scalar in text.unicodeScalars {
            var chars = [UniChar(scalar.value)]
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
               let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }
}
