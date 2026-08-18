import AppKit
import ApplicationServices
import Foundation

class TextInserter {
    /// Virtual key code for V. Hardcoded (open-wispr #36). Layout lookup
    /// silently broke paste on non-QWERTY / non-latin sources.
    let pasteKeyCode: CGKeyCode = 9
    var accessibilityTrusted: () -> Bool = { AXIsProcessTrusted() }
    var postEventTrusted: () -> Bool = { PostEventAccess.isGranted() }
    /// Tests stub this so unit runs do not post Cmd-V into the focused app.
    var pastePoster: (() -> Bool)?
    /// Best-effort Cmd-V targeted at the capture app. Still dropped without PostEvent.
    var targetProcessIdentifier: pid_t?

    init() {}

    @discardableResult
    func insert(text: String) -> TextInsertOutcome {
        let guardResult = SecureFieldGuard.canInjectHere()
        let strategy = TextInsertPlanner.strategy(
            accessibilityTrusted: accessibilityTrusted(),
            secureFieldBlocked: !guardResult.allowed,
            postEventTrusted: postEventTrusted()
        )

        switch strategy {
        case .blockedSecureField:
            copyToPasteboard(text)
            if let reason = guardResult.reason {
                fputs("TextInserter: \(reason)\n", stderr)
            }
            return .blockedSecureField
        case .copyNeedsAccessibility:
            copyToPasteboard(text)
            // Best-effort Cmd-V while the dictation target is still focused.
            // Do not restore the clipboard if it does not land.
            _ = simulatePaste()
            fputs(
                "TextInserter: Accessibility not granted - left transcript on clipboard\n",
                stderr
            )
            return .copiedNeedsAccessibility
        case .insertIntoField:
            return insertIntoField(text)
        }
    }

    private func insertIntoField(_ text: String) -> TextInsertOutcome {
        let pasteboard = NSPasteboard.general
        let savedItems = savePasteboard(pasteboard)
        copyToPasteboard(text)

        if insertViaAccessibility(text) {
            restorePasteboardLater(pasteboard, items: savedItems)
            return .insertedViaAccessibility
        }

        if simulatePaste() {
            // Leave the transcript on the clipboard. Restoring the previous
            // clipboard after a dropped Cmd-V made the field look empty.
            return .insertedViaPaste
        }

        insertViaUnicode(text)
        return .insertedViaUnicode
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func restorePasteboardLater(
        _ pasteboard: NSPasteboard,
        items: [[(NSPasteboard.PasteboardType, Data)]]
    ) {
        let writeChangeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard pasteboard.changeCount == writeChangeCount else { return }
            self.restorePasteboard(pasteboard, items: items)
        }
    }

    @discardableResult
    private func insertViaAccessibility(_ text: String) -> Bool {
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

    private func savePasteboard(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, items: [[(NSPasteboard.PasteboardType, Data)]]) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let pasteboardItems = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(pasteboardItems)
    }

    @discardableResult
    private func simulatePaste() -> Bool {
        if let pastePoster {
            return pastePoster()
        }
        guard postEventTrusted() else {
            return false
        }
        let keyCode = pasteKeyCode

        guard let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        if let pid = targetProcessIdentifier, pid > 0 {
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    /// Fallback for paste-blocking apps (#11) — CGEvent unicode keystroke synthesis.
    private func insertViaUnicode(_ text: String) {
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
