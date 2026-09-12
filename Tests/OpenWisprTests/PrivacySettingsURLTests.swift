import XCTest
@testable import OpenWisprLib

final class PrivacySettingsURLTests: XCTestCase {
    func testInputMonitoringPrefersPrivacySecurityExtension() {
        let urls = PrivacySettingsURL.candidates(for: .inputMonitoring)
        XCTAssertEqual(urls.first, PrivacySettingsURL.inputMonitoringModern)
        XCTAssertTrue(urls.first?.contains("PrivacySecurity.extension") == true)
        XCTAssertTrue(urls.first?.contains("Privacy_ListenEvent") == true)
        XCTAssertTrue(urls.contains(PrivacySettingsURL.inputMonitoringLegacy))
        XCTAssertNotEqual(
            urls.first,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
    }

    func testAccessibilityAndMicrophonePreferModernPane() {
        XCTAssertEqual(
            PrivacySettingsURL.candidates(for: .accessibility).first,
            PrivacySettingsURL.accessibilityModern
        )
        XCTAssertEqual(
            PrivacySettingsURL.candidates(for: .microphone).first,
            PrivacySettingsURL.microphoneModern
        )
    }

    func testEveryPaneHasAModernThenLegacyCandidate() {
        for pane in PrivacySettingsPane.allCases {
            let urls = PrivacySettingsURL.candidates(for: pane)
            XCTAssertEqual(urls.count, 2, pane.rawValue)
            XCTAssertTrue(
                urls[0].contains("PrivacySecurity.extension"),
                pane.rawValue
            )
            XCTAssertTrue(
                urls[1].contains("com.apple.preference.security"),
                pane.rawValue
            )
        }
    }
}
