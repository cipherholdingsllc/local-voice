import XCTest
@testable import OpenWisprLib

final class HotkeyDiagnosticTests: XCTestCase {
    func testReportRoundTripsAsStableJSON() throws {
        let report = HotkeyDiagnosticReport(
            schemaVersion: "local-voice-hotkey-diagnostic.v1",
            key: "fn",
            inputMonitoringGranted: true,
            accessibilityGranted: true,
            monitorStarted: true,
            downEvents: 1,
            upEvents: 1,
            passed: true,
            detail: "ready"
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(
            HotkeyDiagnosticReport.self,
            from: data
        )

        XCTAssertEqual(decoded, report)
    }
}
