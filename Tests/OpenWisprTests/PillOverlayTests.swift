import XCTest
@testable import OpenWisprLib

final class PillOverlayTests: XCTestCase {
    func testListeningPresentationKeepsASingleLabel() {
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

    func testPreviewStatesMatchEveryRenderedPillState() {
        XCTAssertEqual(
            Set(PillPreviewState.allCases.map(\.rawValue)),
            Set(PillState.allCases.map(\.rawValue))
        )
    }

    // MARK: - Signal Blades geometry

    func testListeningApertureClosesAsVoiceEnergyRises() {
        let quiet = SignalBladesGlyph.Metrics.make(
            level: 0,
            state: .listening
        )
        let loud = SignalBladesGlyph.Metrics.make(
            level: 1,
            state: .listening
        )

        XCTAssertLessThan(loud.aperture, quiet.aperture)
        XCTAssertGreaterThan(loud.energy, quiet.energy)
    }

    func testListeningWidthStaysFixedAcrossVoiceEnergy() {
        let quiet = SignalBladesGlyph.Metrics.make(
            level: 0,
            state: .listening
        )
        let loud = SignalBladesGlyph.Metrics.make(
            level: 1,
            state: .listening
        )

        XCTAssertEqual(quiet.span, loud.span)
        XCTAssertEqual(quiet.thickness, loud.thickness)
    }

    func testLockedInterlocksAndOtherStatesUseDistinctFormations() {
        XCTAssertEqual(
            SignalBladesGlyph.Metrics.make(
                level: 0.5,
                state: .locked
            ).formation,
            .sealed
        )
        XCTAssertEqual(
            SignalBladesGlyph.Metrics.make(
                level: 0.5,
                state: .listening
            ).formation,
            .open
        )
        XCTAssertEqual(
            SignalBladesGlyph.Metrics.make(
                level: 0.5,
                state: .transcribing
            ).formation,
            .advancing
        )
        XCTAssertEqual(
            SignalBladesGlyph.Metrics.make(
                level: 0.5,
                state: .error
            ).formation,
            .fractured
        )
    }

    func testErrorFracturesTheBladesAndOpensTheApertureWidest() {
        let error = SignalBladesGlyph.Metrics.make(
            level: 0,
            state: .error
        )
        let listening = SignalBladesGlyph.Metrics.make(
            level: 0,
            state: .listening
        )

        XCTAssertEqual(error.formation, .fractured)
        XCTAssertGreaterThan(error.aperture, listening.aperture)
        XCTAssertGreaterThan(error.upperShift, 0)
        XCTAssertLessThan(error.lowerShift, 0)
    }

    /// Capture has ended, so a level-reactive glyph during transcription would
    /// be reporting microphone activity that is no longer being consumed.
    func testTranscribingIgnoresVoiceLevelEntirely() {
        let quiet = SignalBladesGlyph.Metrics.make(
            level: 0,
            state: .transcribing
        )
        let loud = SignalBladesGlyph.Metrics.make(
            level: 1,
            state: .transcribing
        )

        XCTAssertEqual(quiet.energy, 0)
        XCTAssertEqual(loud.energy, 0)
        XCTAssertEqual(quiet.aperture, loud.aperture)
        XCTAssertEqual(quiet.formation, .advancing)
    }

    func testLockedGeometryHoldsStillAcrossAudioLevels() {
        let quiet = SignalBladesGlyph.Metrics.make(
            level: 0,
            state: .locked
        )
        let loud = SignalBladesGlyph.Metrics.make(
            level: 1,
            state: .locked
        )

        XCTAssertEqual(quiet, loud)
        XCTAssertEqual(loud.energy, 0)
    }

    func testEnergyIsClampedAndGated() {
        XCTAssertEqual(SignalBladesGlyph.Energy.condition(-4), 0)
        XCTAssertEqual(
            SignalBladesGlyph.Energy.condition(9),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(SignalBladesGlyph.Energy.condition(.nan), 0)
        // Idle room tone must not move the mark.
        XCTAssertEqual(SignalBladesGlyph.Energy.condition(0.05), 0)
    }

    func testEnergyQuantizationSuppressesSubPixelJitter() {
        let a = SignalBladesGlyph.Energy.quantize(0.500)
        let b = SignalBladesGlyph.Energy.quantize(0.505)
        XCTAssertEqual(a, b, "jitter below one step must not redraw")

        let far = SignalBladesGlyph.Energy.quantize(0.60)
        XCTAssertNotEqual(a, far)
    }

    func testSmoothingAttacksFasterThanItReleases() {
        let attack = SignalBladesGlyph.Energy.smooth(
            previous: 0,
            target: 1
        )
        let release = SignalBladesGlyph.Energy.smooth(
            previous: 1,
            target: 0
        )

        XCTAssertGreaterThan(attack, 1 - release)
    }

    func testRimIsBrighterThanTheSignalBody() {
        let color = PillState.listening.accentColor
        let rim = SignalBladesGlyph.rim(color)
            .usingColorSpace(.deviceRGB)
        let body = SignalBladesGlyph.body(color)
            .usingColorSpace(.deviceRGB)

        XCTAssertNotNil(rim)
        XCTAssertNotNil(body)
        XCTAssertGreaterThan(rim!.brightnessComponent, body!.brightnessComponent)
    }
}
