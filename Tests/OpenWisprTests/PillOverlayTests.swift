import XCTest
@testable import OpenWisprLib

final class PillOverlayTests: XCTestCase {
    func testListeningUsesOpenAperturePresentation() {
        XCTAssertEqual(PillState.listening.title, "Listening")
        XCTAssertNil(PillState.listening.detail)
        XCTAssertEqual(
            PillState.listening.accessibilityLabel,
            "Listening"
        )
    }

    func testLockedPresentationKeepsInstructionOutsidePrimaryLabel() {
        XCTAssertEqual(PillState.locked.title, "Locked")
        XCTAssertEqual(
            PillState.locked.detail,
            "double-tap fn to finish"
        )
        XCTAssertEqual(
            PillState.locked.accessibilityLabel,
            "Locked, double-tap fn to finish"
        )
    }

    func testListeningApertureExpandsWithVoiceEnergy() {
        let quiet = VoiceApertureMetrics.make(
            level: 0,
            state: .listening
        )
        let active = VoiceApertureMetrics.make(
            level: 0.8,
            state: .listening
        )

        XCTAssertGreaterThan(active.coreRadius, quiet.coreRadius)
        XCTAssertGreaterThan(active.innerRadius, quiet.innerRadius)
        XCTAssertGreaterThan(active.outerRadius, quiet.outerRadius)
        XCTAssertGreaterThan(active.glowRadius, quiet.glowRadius)
    }

    func testApertureLevelIsClampedToSafeDrawingRange() {
        let below = VoiceApertureMetrics.make(
            level: -4,
            state: .listening
        )
        let above = VoiceApertureMetrics.make(
            level: 9,
            state: .listening
        )

        XCTAssertEqual(below.normalizedLevel, 0)
        XCTAssertEqual(above.normalizedLevel, 1)
    }

    func testLockedSealGeometryStaysStableAcrossAudioLevels() {
        let quiet = VoiceApertureMetrics.make(
            level: 0,
            state: .locked
        )
        let active = VoiceApertureMetrics.make(
            level: 1,
            state: .locked
        )

        XCTAssertEqual(quiet.innerRadius, active.innerRadius)
        XCTAssertEqual(quiet.outerRadius, active.outerRadius)
        XCTAssertLessThan(
            active.coreRadius - quiet.coreRadius,
            0.3
        )
    }

    func testPreviewStatesMatchEveryRenderedPillState() {
        XCTAssertEqual(
            Set(PillPreviewState.allCases.map(\.rawValue)),
            Set(PillState.allCases.map(\.rawValue))
        )
    }
}
