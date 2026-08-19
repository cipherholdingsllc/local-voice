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
            return "Grant Accessibility to Local Voice in System Settings to type into the field."
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
}
