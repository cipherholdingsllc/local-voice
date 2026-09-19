import AppKit
import Foundation

/// Dashboard mic and menu-bar status item share one start/stop path.
/// A locked take is still `isPressed`, so stop always unlocks.
public enum CaptureButtonPolicy {
    public enum Action: Equatable {
        case start
        case stopAndUnlock
    }

    public static func action(isCapturing: Bool) -> Action {
        isCapturing ? .stopAndUnlock : .start
    }
}

/// Left/primary click is PTT. Menu stays on right-click or Control-click.
public enum StatusItemClickPolicy {
    public enum Kind: Equatable {
        case toggleCapture
        case showMenu
    }

    public static func kind(
        eventType: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Kind {
        if eventType == .rightMouseUp || eventType == .rightMouseDown {
            return .showMenu
        }
        if modifierFlags.contains(.control) {
            return .showMenu
        }
        return .toggleCapture
    }
}
