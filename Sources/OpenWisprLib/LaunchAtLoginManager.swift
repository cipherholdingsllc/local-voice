import Foundation
import ServiceManagement

public enum LaunchAtLoginManager {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static var statusSummary: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requires approval"
        case .notRegistered:
            return "disabled"
        case .notFound:
            return "unavailable"
        @unknown default:
            return "unknown"
        }
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}
