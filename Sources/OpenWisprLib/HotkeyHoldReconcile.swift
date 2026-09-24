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

/// Timing contract for Fn/globe `holdAndDoubleTapLock`.
///
/// A press is either a tap toward double-tap lock, or a dictation hold —
/// never both. `onKeyDown` fires only after `holdThreshold` while the key is
/// still down. From that moment, release always sends `onKeyUp` (finish the
/// take). Presses released before the threshold never start recording and
/// count as taps.
///
/// Do not add a later cancel window after `onKeyDown`. The old 0.22s start /
/// 0.40s cancel band started a speculative take then aborted it, so
/// short-to-medium holds felt like Fn did nothing.
enum HoldAndDoubleTapLockPolicy {
    static let holdThreshold: TimeInterval = 0.22
    static let doubleTapWindow: TimeInterval = 0.55

    enum ReleaseAction: Equatable {
        case finishDictation
        case countAsTap
        case maybeUnlock
    }

    static func classifyPress(heldFor: TimeInterval) -> ReleaseAction {
        heldFor >= holdThreshold ? .finishDictation : .countAsTap
    }

    static func releaseAction(
        holdConfirmed: Bool,
        lockEngaged: Bool
    ) -> ReleaseAction {
        if lockEngaged { return .maybeUnlock }
        if holdConfirmed { return .finishDictation }
        return .countAsTap
    }
}
