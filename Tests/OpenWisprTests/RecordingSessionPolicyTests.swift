import XCTest
@testable import OpenWisprLib

final class RecordingSessionPolicyTests: XCTestCase {
    func testCommandHoldRetainsTwoMinuteProfileCap() {
        XCTAssertEqual(
            RecordingSessionPolicy.capSeconds(
                for: .generalCommand,
                configuredCapSeconds: 600
            ),
            120
        )
    }

    func testConfiguredHoldCapCanTightenButNotExpandProfile() {
        XCTAssertEqual(
            RecordingSessionPolicy.capSeconds(
                for: .generalDefault,
                configuredCapSeconds: 45
            ),
            45
        )
        XCTAssertEqual(
            RecordingSessionPolicy.capSeconds(
                for: .generalDefault,
                configuredCapSeconds: 3_600
            ),
            600
        )
    }

    func testLockedModeUsesMatchingOneHourRecorderAndContractLimit() {
        let profile = RecordingSessionPolicy.lockedProfile
        XCTAssertEqual(profile, .generalLongForm)
        XCTAssertEqual(profile.maximumDurationMilliseconds, 3_600_000)
        XCTAssertEqual(
            RecordingSessionPolicy.maximumDurationMilliseconds(
                for: profile,
                configuredCapSeconds: 600
            ),
            3_600_000
        )
        XCTAssertEqual(
            RecordingSessionPolicy.capSeconds(
                for: profile,
                configuredCapSeconds: 600
            ),
            3_600
        )
    }
}
