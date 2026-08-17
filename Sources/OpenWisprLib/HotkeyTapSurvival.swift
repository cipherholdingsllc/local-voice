import Foundation

/// Cursor (and other Electron editors) install their own CGEvent taps when they
/// become frontmost. macOS then sends `tapDisabledByUserInput` to Local Voice.
/// Immediate re-enable often loses to the new tap; delayed retries recover fn.
public enum HotkeyTapSurvival {
    /// Immediate plus delayed retries. Cursor typically finishes installing
    /// its tap tens to hundreds of milliseconds after the disable event.
    public static let reenableDelays: [TimeInterval] = [0, 0.08, 0.25]

    public static let competingEditorReenableDelays: [TimeInterval] = [0, 0.08, 0.25, 0.6]

    public static func shouldRearmOnFrontmostChange(
        previousBundleID: String?,
        currentBundleID: String?
    ) -> Bool {
        previousBundleID != currentBundleID
    }

    /// Cursor's ToDesktop bundle, VS Code, and other Chromium editors.
    public static func isCompetingEditor(_ bundleID: String?) -> Bool {
        guard let raw = bundleID?.lowercased() else { return false }
        if raw.contains("todesktop") { return true }
        if raw.contains("cursor") { return true }
        if raw == "com.microsoft.vscode" { return true }
        if raw.hasPrefix("com.microsoft.vscode") { return true }
        if raw == "com.openai.codex" { return true }
        return false
    }

    public static func reenableDelays(forBundleID bundleID: String?) -> [TimeInterval] {
        isCompetingEditor(bundleID) ? competingEditorReenableDelays : reenableDelays
    }
}
