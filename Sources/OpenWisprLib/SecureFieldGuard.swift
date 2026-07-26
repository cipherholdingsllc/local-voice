import ApplicationServices
import Foundation

/// Secure-field & blocked-app guardrails (#12).
enum SecureFieldGuard {
    static func canInjectHere() -> (allowed: Bool, reason: String?) {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let status = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard status == .success, let element = focused else {
            return (true, nil)
        }
        let ax = element as! AXUIElement

        var subroleValue: AnyObject?
        if AXUIElementCopyAttributeValue(ax, kAXSubroleAttribute as CFString, &subroleValue) == .success,
           let subrole = subroleValue as? String,
           subrole == kAXSecureTextFieldSubrole as String {
            return (false, "Can't type here — secure password field")
        }

        return (true, nil)
    }
}

enum FailurePresenter {
    static func message(for error: Error) -> String {
        if let te = error as? TranscriberError {
            switch te {
            case .whisperNotFound: return "Whisper not installed — run: brew install whisper-cpp"
            case .modelNotFound(let size): return "Model '\(size)' missing — run: open-wispr download-model \(size)"
            case .transcriptionFailed: return "Transcription failed — check mic and model"
            }
        }
        if let oe = error as? OllamaCleanupError {
            return oe.localizedDescription
        }
        let desc = error.localizedDescription.lowercased()
        if desc.contains("microphone") || desc.contains("audio") {
            return "Microphone denied — grant in System Settings → Privacy → Microphone"
        }
        return error.localizedDescription
    }
}
