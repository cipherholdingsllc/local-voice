import Foundation

/// Pure hold-state machine used when a CGEvent tap dies and comes back.
///
/// If the tap misses a key-up, AppDelegate's `isPressed` stays true and every
/// later fn hold is swallowed. If it misses a key-down, the user is holding
/// fn and nothing is listening.
enum HotkeyHoldReconcile {
    enum Action: Equatable {
        case none
        case startHold
        case endHold
    }

    static func action(
        keyHeld: Bool,
        physicallyDown: Bool,
        lockEngaged: Bool
    ) -> Action {
        if lockEngaged {
            return .none
        }
        if keyHeld && !physicallyDown {
            return .endHold
        }
        if !keyHeld && physicallyDown {
            return .startHold
        }
        return .none
    }
}
