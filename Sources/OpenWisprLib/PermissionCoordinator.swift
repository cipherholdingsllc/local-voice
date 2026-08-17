import Foundation

public enum LocalVoicePermissionCapability: String, CaseIterable, Sendable {
    case inputMonitoring
    case microphone
    case accessibility

    public var displayName: String {
        switch self {
        case .inputMonitoring: return "Input Monitoring"
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        }
    }
}

public enum LocalVoiceSigningMode: String, Sendable {
    case stable
    case adhoc
    case unknown

    public static var current: LocalVoiceSigningMode {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "LocalVoiceSigningMode"
        ) as? String else {
            return .unknown
        }
        return LocalVoiceSigningMode(rawValue: value) ?? .unknown
    }
}

public enum LocalVoicePermissionRepairAction: Equatable, Sendable {
    case openSettings(LocalVoicePermissionCapability)
    case requestMicrophone
}

public struct LocalVoicePermissionRepairPlan: Equatable, Sendable {
    public static let schemaVersion =
        "local-voice-permission-repair-plan.v1"

    public let missingCapabilities: [LocalVoicePermissionCapability]
    public let primaryCapability: LocalVoicePermissionCapability?
    public let primaryAction: LocalVoicePermissionRepairAction?
    public let instruction: String?
    public let signingWarning: String?

    public var isComplete: Bool {
        missingCapabilities.isEmpty
    }
}

public struct LocalVoicePermissionRefresh: Equatable, Sendable {
    public let previous: LocalVoicePermissionSnapshot?
    public let current: LocalVoicePermissionSnapshot

    public var changed: Bool {
        previous != current
    }

    public var inputMonitoringChanged: Bool {
        guard let previous else { return false }
        return previous.inputMonitoring != current.inputMonitoring
    }
}

public final class PermissionCoordinator {
    private let snapshotProvider: () -> LocalVoicePermissionSnapshot
    private let signingModeProvider: () -> LocalVoiceSigningMode

    public private(set) var latestSnapshot: LocalVoicePermissionSnapshot?
    public private(set) var hotkeyMonitorReady = false

    public init(
        snapshotProvider: @escaping () -> LocalVoicePermissionSnapshot = {
            Permissions.snapshot()
        },
        signingModeProvider: @escaping () -> LocalVoiceSigningMode = {
            LocalVoiceSigningMode.current
        }
    ) {
        self.snapshotProvider = snapshotProvider
        self.signingModeProvider = signingModeProvider
    }

    @discardableResult
    public func refresh() -> LocalVoicePermissionRefresh {
        let previous = latestSnapshot
        let current = snapshotProvider()
        latestSnapshot = current
        return LocalVoicePermissionRefresh(
            previous: previous,
            current: current
        )
    }

    public func repairPlan(
        for snapshot: LocalVoicePermissionSnapshot? = nil
    ) -> LocalVoicePermissionRepairPlan {
        let current = snapshot ?? latestSnapshot ?? snapshotProvider()
        let missing = LocalVoicePermissionCapability.allCases.filter {
            capability in
            switch capability {
            case .inputMonitoring:
                return !current.inputMonitoring
            case .microphone:
                return !current.microphone
            case .accessibility:
                return !current.accessibility
            }
        }
        // If the fn tap is already running, Repair must not steal focus
        // to Input Monitoring while Text insertion is the orange row.
        let repairTargets = missing.filter { capability in
            capability != .inputMonitoring || !hotkeyMonitorReady
        }
        let primary = repairTargets.first
        let primaryAction = primary.map(Self.repairAction)
        let instruction = primary.map { capability in
            let action = Self.instruction(
                for: capability,
                stepCount: repairTargets.count
            )
            let names = repairTargets.map(\.displayName).joined(separator: ", ")
            return "Needed: \(names). \(action)"
        }
        let signingWarning =
            signingModeProvider() == .adhoc
            ? "This personal development build is ad-hoc signed. macOS may require permission re-approval after a rebuild until Local Voice uses a stable signing certificate."
            : nil

        return LocalVoicePermissionRepairPlan(
            missingCapabilities: missing,
            primaryCapability: primary,
            primaryAction: primaryAction,
            instruction: instruction,
            signingWarning: signingWarning
        )
    }

    private static func repairAction(
        for capability: LocalVoicePermissionCapability
    ) -> LocalVoicePermissionRepairAction {
        switch capability {
        case .inputMonitoring, .accessibility:
            return .openSettings(capability)
        case .microphone:
            return .requestMicrophone
        }
    }

    public func updateHotkeyMonitorReady(_ ready: Bool) {
        hotkeyMonitorReady = ready
    }

    public var runtimeReady: Bool {
        latestSnapshot?.runtimeReady(
            hotkeyMonitorReady: hotkeyMonitorReady
        ) == true
    }

    private static func instruction(
        for capability: LocalVoicePermissionCapability,
        stepCount: Int
    ) -> String {
        let prefix = stepCount > 1
            ? "Step 1 of \(stepCount): "
            : ""
        switch capability {
        case .inputMonitoring:
            return prefix
                + "macOS System Settings, not Automic Vault. Open Privacy & Security → Input Monitoring (not Files & Folders). Vault or Computer Use Accessibility being on does not grant Local Voice. Drag ~/Applications/Local Voice.app into the list and turn it on. If a Local Voice row already exists, turn it off, click minus to remove it, then drag the Applications copy in again. Quit Local Voice from the menu bar extra and reopen. Repair will verify it and advance automatically."
        case .microphone:
            return prefix
                + "Allow Local Voice to use the microphone. Repair will verify it and advance automatically."
        case .accessibility:
            return prefix
                + "macOS System Settings, not Automic Vault. Open Privacy & Security → Accessibility. Vault or Computer Use Accessibility being on does not grant Local Voice. Drag ~/Applications/Local Voice.app into the list and turn it on. If a Local Voice row already exists, turn it off, click minus to remove it, then drag the Applications copy in again. Repair will verify text insertion automatically."
        }
    }
}
