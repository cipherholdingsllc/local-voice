import AppKit
import ApplicationServices
import Foundation

/// CGEventTap-based hotkey manager — reliable fn/globe and modifier-only holds.
/// Requires Input Monitoring permission (CGPreflightListenEventAccess).
final class CGEventHotkeyManager {
    private let keyCode: UInt16
    private let requiredModifiers: UInt64
    private let activationMode: HotkeyActivationMode
    private var onKeyDown: (() -> Void)?
    private var onKeyUp: (() -> Void)?
    private var onKeyCancel: (() -> Void)?
    var onLockChanged: ((Bool) -> Void)?
    private(set) var isLockEngaged = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelf: Unmanaged<CGEventHotkeyManager>?
    private var modifierPhysicallyDown = false
    private var keyHeld = false
    private var holdConfirmed = false
    private var holdPendingWork: DispatchWorkItem?
    private var lastShortReleaseTime: TimeInterval = 0

    private static let holdThreshold: TimeInterval = 0.22
    private static let doubleTapWindow: TimeInterval = 0.55

    init(keyCode: UInt16, modifiers: UInt64 = 0, activationMode: HotkeyActivationMode = .hold) {
        self.keyCode = keyCode
        self.requiredModifiers = modifiers
        self.activationMode = activationMode
    }

    @discardableResult
    func start(
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void,
        onKeyCancel: (() -> Void)? = nil
    ) -> Bool {
        stop()
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onKeyCancel = onKeyCancel

        guard CGPreflightListenEventAccess() else {
            fputs(
                "CGEventHotkeyManager: Input Monitoring is not granted\n",
                stderr
            )
            return false
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passRetained(self)
        retainedSelf = selfPtr

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: CGEventHotkeyManager.eventCallback,
            userInfo: selfPtr.toOpaque()
        ) else {
            fputs("CGEventHotkeyManager: failed to create event tap — grant Input Monitoring\n", stderr)
            retainedSelf?.release()
            retainedSelf = nil
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func resetLockState() {
        isLockEngaged = false
        keyHeld = false
        holdConfirmed = false
    }

    func stop() {
        holdPendingWork?.cancel()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        retainedSelf?.release()
        retainedSelf = nil
        modifierPhysicallyDown = false
        keyHeld = false
        holdConfirmed = false
        isLockEngaged = false
        onKeyCancel = nil
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<CGEventHotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            manager.reconcileAfterTapReset()
            return Unmanaged.passUnretained(event)
        }

        manager.handle(event: event, type: type)
        return Unmanaged.passUnretained(event)
    }

    private func handle(event: CGEvent, type: CGEventType) {
        if isModifierOnlyKey(keyCode) {
            guard type == .flagsChanged else { return }
            guard UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode else { return }
            guard modifiersMatch(event) else { return }

            let isDown = Self.modifierFlagIsDown(flags: event.flags, keyCode: keyCode)
            guard isDown != modifierPhysicallyDown else { return }
            modifierPhysicallyDown = isDown

            if isDown {
                handleModifierDown()
            } else {
                handleModifierUp()
            }
            return
        }

        guard UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode else { return }
        guard modifiersMatch(event) else { return }

        switch type {
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            fireKeyDownIfNeeded()
        case .keyUp:
            fireKeyUpIfNeeded()
        default:
            break
        }
    }

    // MARK: - Modifier (fn / globe / cmd-only)

    private func handleModifierDown() {
        switch activationMode {
        case .hold, .toggle:
            if !keyHeld {
                keyHeld = true
                onKeyDown?()
            }
        case .holdAndDoubleTapLock:
            // When locked, still accept taps for double-tap unlock (down ignored; up handles unlock).
            if isLockEngaged { return }
            holdPendingWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.modifierPhysicallyDown, !self.isLockEngaged else { return }
                self.holdConfirmed = true
                if !self.keyHeld {
                    self.keyHeld = true
                    self.onKeyDown?()
                }
            }
            holdPendingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdThreshold, execute: work)
        case .doubleTapArm:
            handleDoubleTapArmDown()
        }
    }

    private func handleModifierUp() {
        holdPendingWork?.cancel()
        holdPendingWork = nil

        switch activationMode {
        case .hold:
            guard keyHeld else { return }
            keyHeld = false
            holdConfirmed = false
            onKeyUp?()
        case .toggle:
            break
        case .holdAndDoubleTapLock:
            if isLockEngaged {
                if isDoubleTap() {
                    toggleLock()
                }
                return
            }
            if holdConfirmed {
                holdConfirmed = false
                guard !isLockEngaged else { return }
                keyHeld = false
                onKeyUp?()
                return
            }
            if isDoubleTap() {
                toggleLock()
            }
        case .doubleTapArm:
            break
        }
    }

    private func toggleLock() {
        if isLockEngaged {
            isLockEngaged = false
            keyHeld = false
            onLockChanged?(false)
            onKeyUp?()
        } else {
            isLockEngaged = true
            keyHeld = true
            onLockChanged?(true)
            onKeyDown?()
        }
    }

    private func isDoubleTap() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let hit = (now - lastShortReleaseTime) < Self.doubleTapWindow
        lastShortReleaseTime = now
        return hit
    }

    // MARK: - Regular keys

    private func fireKeyDownIfNeeded() {
        guard !keyHeld else { return }
        switch activationMode {
        case .hold, .toggle:
            keyHeld = true
            onKeyDown?()
        case .holdAndDoubleTapLock, .doubleTapArm:
            handleDoubleTapArmDown()
        }
    }

    private func fireKeyUpIfNeeded() {
        switch activationMode {
        case .hold:
            guard keyHeld, !isLockEngaged else { return }
            keyHeld = false
            onKeyUp?()
        case .toggle, .holdAndDoubleTapLock, .doubleTapArm:
            break
        }
    }

    private func handleDoubleTapArmDown() {
        if isDoubleTap() {
            toggleLock()
        }
    }

    /// After macOS disables the tap, the next fn up/down can be lost.
    /// Reconcile against live modifier flags so AppDelegate cannot stay stuck.
    private func reconcileAfterTapReset() {
        holdPendingWork?.cancel()
        let physicallyDown: Bool
        if isModifierOnlyKey(keyCode) {
            physicallyDown = Self.modifierFlagIsDown(
                flags: CGEventSource.flagsState(.combinedSessionState),
                keyCode: keyCode
            )
        } else {
            physicallyDown = keyHeld
        }
        modifierPhysicallyDown = physicallyDown
        switch HotkeyHoldReconcile.action(
            keyHeld: keyHeld,
            physicallyDown: physicallyDown,
            lockEngaged: isLockEngaged
        ) {
        case .none:
            break
        case .startHold:
            keyHeld = true
            holdConfirmed = true
            onKeyDown?()
        case .endHold:
            keyHeld = false
            holdConfirmed = false
            onKeyUp?()
        }
    }

    static func modifierFlagIsDown(flags: CGEventFlags, keyCode: UInt16) -> Bool {
        switch keyCode {
        case 63: return flags.contains(.maskSecondaryFn)
        case 54, 55: return flags.contains(.maskCommand)
        case 56, 60: return flags.contains(.maskShift)
        case 58, 61: return flags.contains(.maskAlternate)
        case 59, 62: return flags.contains(.maskControl)
        default: return false
        }
    }

    private func modifiersMatch(_ event: CGEvent) -> Bool {
        guard requiredModifiers != 0 else { return true }
        let current = UInt64(event.flags.rawValue) & 0x00FF0000
        return current & requiredModifiers == requiredModifiers
    }

    private func isModifierOnlyKey(_ code: UInt16) -> Bool {
        [54, 55, 56, 58, 59, 60, 61, 62, 63].contains(code)
    }
}

public enum HotkeyActivationMode: String, Codable, Sendable {
    case hold
    case toggle
    /// Hold fn to talk; double-tap fn to lock until double-tap again.
    case holdAndDoubleTapLock
    case doubleTapArm
}
