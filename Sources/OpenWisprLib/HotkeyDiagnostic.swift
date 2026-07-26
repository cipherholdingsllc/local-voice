import AppKit
import ApplicationServices
import Foundation

public struct HotkeyDiagnosticReport: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let key: String
    public let inputMonitoringGranted: Bool
    public let accessibilityGranted: Bool
    public let monitorStarted: Bool
    public let downEvents: Int
    public let upEvents: Int
    public let passed: Bool
    public let detail: String
}

public enum HotkeyDiagnostic {
    public static func runFnProbe() -> HotkeyDiagnosticReport {
        dispatchPrecondition(condition: .onQueue(.main))
        let permissions = Permissions.snapshot()
        guard permissions.inputMonitoring else {
            return report(
                permissions: permissions,
                monitorStarted: false,
                downEvents: 0,
                upEvents: 0,
                detail: "Grant Input Monitoring before running the Fn probe."
            )
        }

        var downEvents = 0
        var upEvents = 0
        let manager = CGEventHotkeyManager(
            keyCode: 63,
            activationMode: .hold
        )
        let monitorStarted = manager.start(
            onKeyDown: { downEvents += 1 },
            onKeyUp: { upEvents += 1 }
        )
        guard monitorStarted else {
            return report(
                permissions: permissions,
                monitorStarted: false,
                downEvents: 0,
                upEvents: 0,
                detail: "The Fn event monitor could not start."
            )
        }
        defer { manager.stop() }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: 63,
                keyDown: true
              ),
              let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: 63,
                keyDown: false
              ) else {
            return report(
                permissions: permissions,
                monitorStarted: true,
                downEvents: downEvents,
                upEvents: upEvents,
                detail: "Synthetic Fn events could not be created."
            )
        }

        down.type = .flagsChanged
        down.flags = .maskSecondaryFn
        up.type = .flagsChanged
        up.flags = []

        down.post(tap: .cghidEventTap)
        pumpMainRunLoop(for: 0.08)
        up.post(tap: .cghidEventTap)
        pumpMainRunLoop(for: 0.08)

        let passed = downEvents == 1 && upEvents == 1
        return HotkeyDiagnosticReport(
            schemaVersion: "local-voice-hotkey-diagnostic.v1",
            key: "fn",
            inputMonitoringGranted: permissions.inputMonitoring,
            accessibilityGranted: permissions.accessibility,
            monitorStarted: true,
            downEvents: downEvents,
            upEvents: upEvents,
            passed: passed,
            detail: passed
                ? "The real Fn event tap observed synthetic down and up events."
                : "The event tap started but did not observe a complete Fn cycle."
        )
    }

    private static func report(
        permissions: LocalVoicePermissionSnapshot,
        monitorStarted: Bool,
        downEvents: Int,
        upEvents: Int,
        detail: String
    ) -> HotkeyDiagnosticReport {
        HotkeyDiagnosticReport(
            schemaVersion: "local-voice-hotkey-diagnostic.v1",
            key: "fn",
            inputMonitoringGranted: permissions.inputMonitoring,
            accessibilityGranted: permissions.accessibility,
            monitorStarted: monitorStarted,
            downEvents: downEvents,
            upEvents: upEvents,
            passed: false,
            detail: detail
        )
    }

    private static func pumpMainRunLoop(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(
                mode: .default,
                before: min(
                    deadline,
                    Date().addingTimeInterval(0.01)
                )
            )
        }
    }
}
