import AppKit
import ApplicationServices
import Foundation
import IOKit.hid

public enum PrivacySettingsPane: String, CaseIterable, Sendable {
    case inputMonitoring
    case microphone
    case accessibility
}

/// Deep links for System Settings privacy panes.
///
/// The legacy `com.apple.preference.security?Privacy_ListenEvent` URL is still
/// accepted by `open`, but on macOS 15+ it often lands on Files & Folders
/// (or another unrelated privacy list) instead of Input Monitoring.
public enum PrivacySettingsURL {
    public static let inputMonitoringModern =
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
    public static let inputMonitoringLegacy =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    public static let microphoneModern =
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone"
    public static let microphoneLegacy =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    public static let accessibilityModern =
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
    public static let accessibilityLegacy =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    public static func candidates(for pane: PrivacySettingsPane) -> [String] {
        switch pane {
        case .inputMonitoring:
            return [inputMonitoringModern, inputMonitoringLegacy]
        case .microphone:
            return [microphoneModern, microphoneLegacy]
        case .accessibility:
            return [accessibilityModern, accessibilityLegacy]
        }
    }

    @discardableResult
    public static func open(_ pane: PrivacySettingsPane) -> Bool {
        for spec in candidates(for: pane) {
            if let url = URL(string: spec), NSWorkspace.shared.open(url) {
                return true
            }
        }
        return false
    }
}

/// Input Monitoring TCC helpers.
///
/// `CGPreflightListenEventAccess` is what the event tap needs. `IOHIDRequestAccess`
/// is what actually registers the .app in System Settings ? Input Monitoring on
/// recent macOS, but only if Info.plist carries `NSInputMonitoringUsageDescription`.
public enum InputMonitoringAccess {
    public static func isGranted() -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Call from Local Voice.app. A CLI `local-voice status` run from Terminal
    /// registers Terminal, not the GUI app.
    public static func registerWithTCC() {
        CGRequestListenEventAccess()
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public static func registerWithTCCAsync() {
        CGRequestListenEventAccess()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }
}

/// Post-event TCC helpers.
///
/// Quinn / Apple DTS: `kTCCServicePostEvent` is a separate bucket from
/// Accessibility and ListenEvent. It *shows* in System Settings → Accessibility
/// but `AXIsProcessTrusted()` does not probe it. On macOS 26, `CGEvent.post`
/// and `postToPid` silently no-op without this grant.
///
/// Call `request()` from Local Voice.app only. A Cursor/CLI call registers
/// the wrong process.
public enum PostEventAccess {
    public static func isGranted() -> Bool {
        CGPreflightPostEventAccess()
    }

    /// One-time system prompt for this binary. Does not open Settings.
    @discardableResult
    public static func request() -> Bool {
        CGRequestPostEventAccess()
    }
}
