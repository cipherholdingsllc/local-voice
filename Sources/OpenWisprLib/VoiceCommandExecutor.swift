import AppKit
import Carbon.HIToolbox
import Foundation

/// Voice edit-commands via structured JSON (#9).
public final class VoiceCommandExecutor {
    public static let shared = VoiceCommandExecutor()
    private var pending: [[String: Any]] = []

    public func enqueue(_ commands: [[String: Any]]) {
        pending.append(contentsOf: commands)
    }

    public func flush() {
        let batch = pending
        pending.removeAll()
        for cmd in batch {
            guard let type = cmd["type"] as? String else { continue }
            execute(type: type)
        }
    }

    private func execute(type: String) {
        switch type {
        case "new_line":
            postKey(keyCode: CGKeyCode(kVK_Return))
        case "scratch_that":
            NotificationCenter.default.post(name: .localFlowScratchThat, object: nil)
        case "all_caps":
            NotificationCenter.default.post(name: .localFlowAllCaps, object: nil)
        case "send_it":
            postKey(keyCode: CGKeyCode(kVK_Return))
        default:
            break
        }
    }

    private func postKey(keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

extension Notification.Name {
    static let localFlowScratchThat = Notification.Name("localFlow.scratchThat")
    static let localFlowAllCaps = Notification.Name("localFlow.allCaps")
    static let localFlowToggleRawPolished = Notification.Name("localFlow.toggleRawPolished")
}
