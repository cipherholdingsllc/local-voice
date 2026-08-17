import AppKit
import AVFoundation
import ApplicationServices
import Foundation

public struct LocalVoicePermissionSnapshot: Equatable, Sendable {
    public let microphone: Bool
    public let accessibility: Bool
    public let inputMonitoring: Bool

    public init(
        microphone: Bool,
        accessibility: Bool,
        inputMonitoring: Bool
    ) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }

    public var hotkeyReady: Bool {
        inputMonitoring
    }

    public var dictationReady: Bool {
        microphone && accessibility && inputMonitoring
    }

    public var blockingSummary: String? {
        if !inputMonitoring {
            return "Input Monitoring is required for the fn hotkey"
        }
        if !microphone {
            return "Microphone access is required to dictate"
        }
        if !accessibility {
            return "Accessibility is required to insert text"
        }
        return nil
    }
}

public struct Permissions {
    public static func snapshot() -> LocalVoicePermissionSnapshot {
        LocalVoicePermissionSnapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: InputMonitoringAccess.isGranted()
        )
    }

    static func ensureMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("Microphone: granted")
        case .notDetermined:
            print("Microphone: requesting...")
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("Microphone: \(granted ? "granted" : "denied")")
                semaphore.signal()
            }
            semaphore.wait()
        default:
            print("Microphone: denied — grant in System Settings → Privacy & Security → Microphone")
        }
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        promptAccessibility()
        PrivacySettingsURL.open(.accessibility)
    }

    static func openInputMonitoringSettings() {
        InputMonitoringAccess.registerWithTCC()
        PrivacySettingsURL.open(.inputMonitoring)
    }

    static func openMicrophoneSettings() {
        PrivacySettingsURL.open(.microphone)
    }

    @discardableResult
    static func requestInputMonitoring(openSettings: Bool = true) -> Bool {
        if InputMonitoringAccess.isGranted() {
            print("Input Monitoring: granted")
            return true
        }
        print("Input Monitoring: requesting...")
        if openSettings {
            InputMonitoringAccess.registerWithTCC()
            PrivacySettingsURL.open(.inputMonitoring)
        } else {
            InputMonitoringAccess.registerWithTCCAsync()
        }
        let granted = InputMonitoringAccess.isGranted()
        if !granted {
            print("Input Monitoring: denied — grant in System Settings → Privacy & Security → Input Monitoring")
        }
        return granted
    }
}
