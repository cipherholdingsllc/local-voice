import ApplicationServices
import Foundation

/// Replaces the in-progress dictation span in the focused field.
///
/// Wispr Flow's bar is text appearing where the user is working. Local Voice
/// previously showed chunk partials only in the HUD pill and pasted once at
/// the end. This composer writes the live span through Accessibility, then
/// swaps it for the cleaned final. If AX write fails or focus moves, it
/// disables itself for the take so we never backspace someone else's text.
public final class LiveFieldComposer {
    public private(set) var hasLiveInsertion = false
    public private(set) var insertedText = ""

    private var focused: AXUIElement?
    private var startUTF16: Int?
    private var disabled = false

    public init() {}

    public func reset() {
        focused = nil
        startUTF16 = nil
        insertedText = ""
        hasLiveInsertion = false
        disabled = false
    }

    public func begin() {
        reset()
        let guardResult = SecureFieldGuard.canInjectHere()
        guard guardResult.allowed else {
            disabled = true
            return
        }
        guard let element = Self.focusedElement() else {
            disabled = true
            return
        }
        guard let range = Self.selectedRange(of: element) else {
            disabled = true
            return
        }
        focused = element
        startUTF16 = range.location
    }

    @discardableResult
    public func updatePartial(_ text: String) -> Bool {
        replaceInserted(with: text)
    }

    @discardableResult
    public func commitFinal(_ text: String) -> Bool {
        let ok = replaceInserted(with: text)
        focused = nil
        startUTF16 = nil
        insertedText = ok ? "" : insertedText
        return ok
    }

    @discardableResult
    public func cancel() -> Bool {
        let ok = replaceInserted(with: "")
        reset()
        disabled = true
        return ok
    }

    @discardableResult
    private func replaceInserted(with text: String) -> Bool {
        guard !disabled else { return false }
        guard let element = focused, let start = startUTF16 else { return false }
        guard Self.isStillFocused(element) else {
            disabled = true
            return false
        }
        if text == insertedText, hasLiveInsertion || text.isEmpty {
            return true
        }
        let length = insertedText.utf16.count
        let range = CFRange(location: start, length: length)
        guard Self.setSelectedRange(element, range) else {
            disabled = true
            return false
        }
        let before = Self.stringValue(of: element)
        guard Self.setSelectedText(element, text) else {
            disabled = true
            return false
        }
        if !text.isEmpty {
            let after = Self.stringValue(of: element)
            guard TextInsertPlanner.accessibilityWriteLanded(
                before: before,
                after: after,
                inserted: text
            ) else {
                disabled = true
                return false
            }
        }
        insertedText = text
        hasLiveInsertion = !text.isEmpty
        return true
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success else { return nil }
        return focused.map { $0 as! AXUIElement }
    }

    private static func isStillFocused(_ element: AXUIElement) -> Bool {
        guard let current = focusedElement() else { return false }
        return CFEqual(element, current)
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &ref
        ) == .success, let axValue = ref else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    @discardableResult
    private static func setSelectedRange(_ element: AXUIElement, _ range: CFRange) -> Bool {
        var mutable = range
        guard let value = AXValueCreate(.cfRange, &mutable) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        ) == .success
    }

    @discardableResult
    private static func setSelectedText(_ element: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success
    }

    private static func stringValue(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }
}
