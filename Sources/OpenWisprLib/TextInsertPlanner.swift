import Foundation

/// Pure insert policy. CGEvent "post succeeded" is not delivery; restoring the
/// clipboard after a dropped Cmd-V is what made listen look live while the
/// focused field stayed empty.
public enum TextInsertStrategy: Equatable, Sendable {
    case blockedSecureField
    case copyNeedsAccessibility
    case insertIntoField
}

public enum TextInsertOutcome: Equatable, Sendable {
    case insertedViaAccessibility
    case insertedViaPaste
    case insertedViaUnicode
    case copiedNeedsAccessibility
    case blockedSecureField

    public var operatorMessage: String? {
        switch self {
        case .copiedNeedsAccessibility:
            return "Copied. Press Cmd-V now. Accessibility: Local Voice.app, not Vault."
        case .blockedSecureField:
            return "Can't type in a password field - transcript copied"
        case .insertedViaAccessibility, .insertedViaPaste, .insertedViaUnicode:
            return nil
        }
    }

    public var didConfirmFieldInsert: Bool {
        self == .insertedViaAccessibility
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
        // Always attempt AX write + Cmd-V. AXIsProcessTrusted() is a probe,
        // not a delivery guarantee, and treating a false probe as "copy only"
        // is what made the dashboard orange row skip typing.
        return .insertIntoField
    }

    public static func shouldRestoreClipboard(
        for outcome: TextInsertOutcome
    ) -> Bool {
        outcome == .insertedViaAccessibility
    }
}
