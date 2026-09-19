import Foundation

/// Lock-mode gestures for `holdAndDoubleTapLock`.
///
/// Permanent lock is **double-tap Fn**. Command+Fn is an explicit lock
/// engage for operators who treat that chord as "keep recording".
///
/// Lock is **opt-in**. `Config.lockModeEnabled` defaults false so Fn is
/// hold-to-talk only unless the operator enables lock from the menu or
/// `config.json`. Button stop still unlocks a locked take.
public enum LockGesturePolicy {
    public static func shouldEngageExplicitLock(
        activationMode: HotkeyActivationMode,
        alreadyLocked: Bool,
        commandDown: Bool,
        fnJustPressed: Bool
    ) -> Bool {
        guard activationMode == .holdAndDoubleTapLock else { return false }
        guard !alreadyLocked, commandDown, fnJustPressed else { return false }
        return true
    }
}

/// Final insert for a locked take always pastes, even if live AX partials died.
public enum LockedDictationFinalization {
    public static func shouldCommitViaLiveComposer(
        wasLockSession: Bool,
        hasLiveInsertion: Bool
    ) -> Bool {
        if wasLockSession { return false }
        return hasLiveInsertion
    }
}
