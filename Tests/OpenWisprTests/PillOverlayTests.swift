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

    // MARK: - Triad geometry

    func testKerfClosesAsVoiceEnergyRises() {
        let quiet = TriadGlyph.Metrics.make(level: 0, state: .listening)
        let loud = TriadGlyph.Metrics.make(level: 1, state: .listening)

        XCTAssertLessThan(loud.kerf, quiet.kerf)
        XCTAssertGreaterThan(loud.energy, quiet.energy)
    }

    /// The design claim that justifies the kerf compensation: speaking closes
    /// the gap without the mark appearing to grow or shrink. If someone drops
    /// the `1 - kerf/2` divisor this test is what catches it.
    func testOuterSilhouetteStaysFixedWhileKerfBreathes() {
        func extent(_ metrics: TriadGlyph.Metrics) -> (CGFloat, CGFloat) {
            let bounds = CGRect(x: 0, y: 0, width: 26, height: 26)
            let anchor = TriadGlyph.anchor(
                in: bounds,
                radius: metrics.radius
            )
            let drawn = metrics.radius / (1 - (metrics.kerf / 2))
            let ring = drawn / 2
            let base = (1 - metrics.kerf) * ring
            let centres = TriadGlyph.seatCentres(
                anchor: anchor,
                drawnRadius: drawn
            )
            let apex = TriadGlyph.pointUp(
                center: centres[0],
                radius: base * TriadGlyph.seatScales[0]
            ).apex.y
            let right = TriadGlyph.pointUp(
                center: centres[2],
                radius: base * TriadGlyph.seatScales[2]
            ).right.x
            return (apex, right)
        }

        let (quietTop, quietRight) = extent(
            TriadGlyph.Metrics.make(level: 0, state: .listening)
        )
        let (loudTop, loudRight) = extent(
            TriadGlyph.Metrics.make(level: 1, state: .listening)
        )

        XCTAssertEqual(quietTop, loudTop, accuracy: 0.05)
        XCTAssertEqual(quietRight, loudRight, accuracy: 0.05)
    }

    /// An equilateral triangle's centroid is not its bounding-box centre.
    /// Deriving vertices from a centred box puts the mark ~0.18·r low, which
    /// reads as a sag that is very hard to diagnose by eye.
    func testOpticalAnchorSitsAboveTheNaiveBoundingBoxPlacement() {
        let bounds = CGRect(x: 0, y: 0, width: 26, height: 26)
        let radius: CGFloat = 11.2
        let anchor = TriadGlyph.anchor(in: bounds, radius: radius)

        XCTAssertEqual(anchor.x, bounds.midX, accuracy: 0.0001)
        XCTAssertEqual(
            anchor.y,
            bounds.midY - (0.07 * radius),
            accuracy: 0.0001
        )

        let baseline = anchor.y - (radius / 2)
        let naiveBaseline = bounds.midY - (0.75 * radius)
        XCTAssertEqual(
            baseline - naiveBaseline,
            0.18 * radius,
            accuracy: 0.0001
        )
    }

    func testLockedSeatsEachChipletAndOtherStatesDoNot() {
        XCTAssertTrue(
            TriadGlyph.Metrics.make(level: 0.5, state: .locked).seated
        )
        for state in [PillState.listening, .transcribing, .error] {
            XCTAssertFalse(
                TriadGlyph.Metrics.make(level: 0.5, state: state).seated,
                "\(state) must not seat the chiplets"
            )
        }
    }

    func testErrorGhostsTheApexAndOpensTheKerfWidest() {
        let error = TriadGlyph.Metrics.make(level: 0, state: .error)
        let listening = TriadGlyph.Metrics.make(level: 0, state: .listening)

        XCTAssertTrue(error.apexGhosted)
        XCTAssertFalse(listening.apexGhosted)
        XCTAssertGreaterThan(error.kerf, listening.kerf)
    }

    /// Capture has ended, so a level-reactive glyph during transcription would
    /// be reporting microphone activity that is no longer being consumed.
    func testTranscribingIgnoresVoiceLevelEntirely() {
        let quiet = TriadGlyph.Metrics.make(level: 0, state: .transcribing)
        let loud = TriadGlyph.Metrics.make(level: 1, state: .transcribing)

        XCTAssertEqual(quiet.energy, 0)
        XCTAssertEqual(loud.energy, 0)
        XCTAssertEqual(quiet.kerf, loud.kerf)
        XCTAssertEqual(loud.glowIntensity, 0)
    }

    func testLockedGeometryHoldsStillAcrossAudioLevels() {
        let quiet = TriadGlyph.Metrics.make(level: 0, state: .locked)
        let loud = TriadGlyph.Metrics.make(level: 1, state: .locked)

        XCTAssertEqual(quiet.kerf, loud.kerf)
        XCTAssertLessThanOrEqual(loud.energy, 0.35)
    }

    func testEnergyIsClampedAndGated() {
        XCTAssertEqual(TriadGlyph.Energy.condition(-4), 0)
        XCTAssertEqual(TriadGlyph.Energy.condition(9), 1, accuracy: 0.0001)
        XCTAssertEqual(TriadGlyph.Energy.condition(.nan), 0)
        // Idle room tone must not move the mark.
        XCTAssertEqual(TriadGlyph.Energy.condition(0.05), 0)
    }

    func testEnergyQuantizationSuppressesSubPixelJitter() {
        let a = TriadGlyph.Energy.quantize(0.500)
        let b = TriadGlyph.Energy.quantize(0.505)
        XCTAssertEqual(a, b, "jitter below one step must not redraw")

        let far = TriadGlyph.Energy.quantize(0.60)
        XCTAssertNotEqual(a, far)
    }

    func testSmoothingAttacksFasterThanItReleases() {
        let attack = TriadGlyph.Energy.smooth(previous: 0, target: 1)
        let release = TriadGlyph.Energy.smooth(previous: 1, target: 0)

        XCTAssertGreaterThan(attack, 1 - release)
    }

    func testRimHoldsHueIdentityAtLowBodyAlpha() {
        let gold = PillState.locked.accentColor
        let rim = TriadGlyph.rim(gold)

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rim.usingColorSpace(.deviceRGB)?.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )

        // Full value is what keeps dim gold from compositing to brown.
        XCTAssertEqual(brightness, 1.0, accuracy: 0.001)
        XCTAssertLessThan(saturation, 1.0)
    }
}
