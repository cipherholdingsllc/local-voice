import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

class TextInserter {
    let pasteKeyCode: CGKeyCode
    var accessibilityTrusted: () -> Bool = { AXIsProcessTrusted() }

    init() {
        self.pasteKeyCode = TextInserter.resolveKeyCode(for: "v") ?? 9
    }

    @discardableResult
    func insert(text: String) -> TextInsertOutcome {
        let guardResult = SecureFieldGuard.canInjectHere()
        let strategy = TextInsertPlanner.strategy(
            accessibilityTrusted: accessibilityTrusted(),
            secureFieldBlocked: !guardResult.allowed
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
            fputs(
                "TextInserter: Accessibility not granted — left transcript on clipboard\n",
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
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

    private static func resolveKeyCode(for target: Character) -> CGKeyCode? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let rawLayoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = unsafeBitCast(rawLayoutData, to: CFData.self)
        guard let layoutBytes = CFDataGetBytePtr(layoutData) else {
            return nil
        }

        let keyboardLayout = UnsafePointer<UCKeyboardLayout>(OpaquePointer(layoutBytes))
        let keyboardType = UInt32(LMGetKbdType())
        let wanted = String(target).lowercased()

        for keyCode in 0..<128 {
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var actualLength: Int = 0

            let status = UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &actualLength,
                &chars
            )

            guard status == noErr else { continue }

            let produced = String(utf16CodeUnits: chars, count: actualLength).lowercased()
            if produced == wanted {
                return CGKeyCode(keyCode)
            }
        }

        return nil
    }

    @discardableResult
    private func simulatePaste() -> Bool {
        let keyCode = pasteKeyCode

        guard let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

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
