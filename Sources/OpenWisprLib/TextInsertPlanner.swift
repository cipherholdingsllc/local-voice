import Foundation

/// Pure insert policy. Dictation types into the field. It does not copy.
public enum TextInsertStrategy: Equatable, Sendable {
    case blockedSecureField
    case insertIntoField
}

public enum TextInsertOutcome: Equatable, Sendable {
    case insertedViaAccessibility
    case insertedViaLiveComposer
    case insertedViaUnicode
    case transcribedOnly
    case blockedSecureField

    public var operatorMessage: String? {
        switch self {
        case .blockedSecureField:
            return "Can't type in a password field"
        case .transcribedOnly:
            return "Turn on Local Voice in System Settings → Accessibility. Do not toggle it off and on."
        case .insertedViaAccessibility, .insertedViaLiveComposer, .insertedViaUnicode:
            return nil
        }
    }

    public var didConfirmFieldInsert: Bool {
        self == .insertedViaAccessibility
            || self == .insertedViaLiveComposer
            || self == .insertedViaUnicode
    }
}

public enum TextInsertPlanner {
    public static func strategy(
        accessibilityTrusted: Bool,
        secureFieldBlocked: Bool,
        postEventTrusted: Bool = false
    ) -> TextInsertStrategy {
        if secureFieldBlocked {
            return .blockedSecureField
        }
        return .insertIntoField
    }

    public static func shouldRestoreClipboard(
        for outcome: TextInsertOutcome
    ) -> Bool {
        false
    }

    /// AX `Set kAXSelectedText == .success` is not proof the visible field
    /// changed. Electron/Cursor often returns success while `kAXValue` stays put.
    public static func accessibilityWriteLanded(
        before: String?,
        after: String?,
        inserted: String
    ) -> Bool {
        guard !inserted.isEmpty else { return false }
        guard let after, after.contains(inserted) else { return false }
        if let before, before == after { return false }
        return true
    }
}
