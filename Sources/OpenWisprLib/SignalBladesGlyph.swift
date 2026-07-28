import AppKit
import CoreGraphics

/// Signal Blades: one continuous state language for Local Voice.
///
/// Two opposing, aerodynamic blades hold a luminous speech core. Listening
/// leaves the core exposed and lets the aperture close subtly with voice
/// energy. Locked interlocks the same blades into a quiet seal. Finishing
/// aligns them into a forward-moving pair, while error fractures the formation
/// without introducing a stock microphone, padlock, spinner, or warning icon.
///
/// Drawing is a pure function of `(bounds, state, energy)` so the live overlay
/// and the offscreen QA contact sheet always use the exact same renderer.
enum SignalBladesGlyph {

    // MARK: - Level conditioning

    /// Raw microphone level is noisy and perceptually non-linear. Geometry is
    /// never driven from it directly.
    enum Energy {
        static func condition(_ level: Float) -> CGFloat {
            let raw = level.isFinite ? CGFloat(level) : 0
            let clamped = min(1, max(0, raw))
            let gated = max(0, (clamped - 0.06) / 0.94)
            return pow(gated, 0.62)
        }

        /// Below one step, the blades do not redraw. This prevents the thin
        /// specular edges from shimmering during sustained speech.
        static let step: CGFloat = 1.0 / 24.0

        static func quantize(_ energy: CGFloat) -> CGFloat {
            (energy / step).rounded() * step
        }

        /// Fast attack, slower release at a nominal 60 fps.
        static func smooth(
            previous: CGFloat,
            target: CGFloat
        ) -> CGFloat {
            let coefficient: CGFloat = target > previous ? 0.55 : 0.12
            return previous + coefficient * (target - previous)
        }
    }

    enum Formation: Equatable {
        case open
        case sealed
        case advancing
        case fractured
    }

    // MARK: - Metrics

    struct Metrics: Equatable {
        let energy: CGFloat
        /// Fixed horizontal reach. Voice energy changes only the aperture and
        /// light, never the mark's overall width.
        let span: CGFloat
        /// Distance from the speech core to the inner edge of each blade.
        let aperture: CGFloat
        let thickness: CGFloat
        let formation: Formation
        let upperShift: CGFloat
        let lowerShift: CGFloat
        let coreRadius: CGFloat
        let bodyAlpha: CGFloat
        let glowRadius: CGFloat
        let glowIntensity: CGFloat

        static func make(level: Float, state: PillState) -> Metrics {
            make(
                energy: Energy.quantize(Energy.condition(level)),
                state: state
            )
        }

        /// `rawEnergy` must already be conditioned, smoothed, and quantized.
        static func make(energy rawEnergy: CGFloat, state: PillState) -> Metrics {
            let raw = min(1, max(0, rawEnergy))
            let energy = state == .listening ? raw : 0

            let aperture: CGFloat
            let thickness: CGFloat
            let formation: Formation
            let upperShift: CGFloat
            let lowerShift: CGFloat
            let coreRadius: CGFloat
            let bodyAlpha: CGFloat
            let glowIntensity: CGFloat

            switch state {
            case .listening:
                aperture = 4.15 - (1.35 * energy)
                thickness = 2.65
                formation = .open
                upperShift = 0
                lowerShift = 0
                coreRadius = 1.95 + (0.38 * energy)
                bodyAlpha = 0.92 + (0.08 * energy)
                glowIntensity = 0.11 + (0.12 * energy)
            case .locked:
                aperture = 0.72
                thickness = 3.30
                formation = .sealed
                upperShift = 0.35
                lowerShift = -0.35
                coreRadius = 1.18
                bodyAlpha = 0.96
                glowIntensity = 0.09
            case .transcribing:
                aperture = 2.05
                thickness = 2.35
                formation = .advancing
                upperShift = 0.55
                lowerShift = 0.55
                coreRadius = 1.08
                bodyAlpha = 0.76
                glowIntensity = 0.055
            case .error:
                aperture = 4.90
                thickness = 2.55
                formation = .fractured
                upperShift = 1.55
                lowerShift = -1.55
                coreRadius = 0.78
                bodyAlpha = 0.88
                glowIntensity = 0.085
            }

            return Metrics(
                energy: energy,
                span: 11.2,
                aperture: aperture,
                thickness: thickness,
                formation: formation,
                upperShift: upperShift,
                lowerShift: lowerShift,
                coreRadius: coreRadius,
                bodyAlpha: bodyAlpha,
                glowRadius: 7.0 + (2.0 * energy),
                glowIntensity: glowIntensity
            )
        }
    }

    // MARK: - Colour

    static func rim(_ color: NSColor, _ alpha: CGFloat = 1) -> NSColor {
        let (red, green, blue) = components(color)
        return NSColor(
            calibratedRed: red + ((1 - red) * 0.68),
            green: green + ((1 - green) * 0.68),
            blue: blue + ((1 - blue) * 0.68),
            alpha: alpha
        )
    }

    static func body(_ color: NSColor, _ alpha: CGFloat = 1) -> NSColor {
        let (red, green, blue) = components(color)
        return NSColor(
            calibratedRed: min(1, (red * 0.82) + 0.10),
            green: min(1, (green * 0.82) + 0.10),
            blue: min(1, (blue * 0.82) + 0.12),
            alpha: alpha
        )
    }

    static func deep(_ color: NSColor, _ alpha: CGFloat = 1) -> NSColor {
        let (red, green, blue) = components(color)
        return NSColor(
            calibratedRed: red * 0.30,
            green: green * 0.34,
            blue: blue * 0.42,
            alpha: alpha
        )
    }

    private static func components(
        _ color: NSColor
    ) -> (CGFloat, CGFloat, CGFloat) {
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            return (0.75, 0.85, 1)
        }
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }

    // MARK: - Geometry

    enum Direction {
        case left
        case right

        var sign: CGFloat {
            self == .right ? 1 : -1
        }
    }

    static func bladePath(
        center: CGPoint,
        metrics: Metrics,
        upper: Bool,
        direction: Direction
    ) -> CGPath {
        let vertical: CGFloat = upper ? 1 : -1
        let horizontal = direction.sign
        let shift = upper ? metrics.upperShift : metrics.lowerShift
        let span = metrics.span
        let aperture = metrics.aperture
        let thickness = metrics.thickness

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + (x * horizontal) + shift,
                y: center.y + (y * vertical)
            )
        }

        let trail = point(-span, aperture * 0.18)
        let tip = point(span, aperture * 0.58)
        let path = CGMutablePath()
        path.move(to: trail)
        path.addCurve(
            to: tip,
            control1: point(-span * 0.48, aperture + thickness),
            control2: point(span * 0.46, aperture + (thickness * 0.58))
        )
        path.addCurve(
            to: trail,
            control1: point(span * 0.25, aperture + 0.10),
            control2: point(-span * 0.46, aperture + 0.03)
        )
        path.closeSubpath()
        return path
    }

    static func directions(for formation: Formation) -> (Direction, Direction) {
        switch formation {
        case .advancing:
            return (.right, .right)
        case .open, .sealed, .fractured:
            return (.right, .left)
        }
    }

    // MARK: - Drawing

    static func draw(
        in context: CGContext,
        bounds: CGRect,
        state: PillState,
        metrics: Metrics
    ) {
        let accent = state.accentColor
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        glow(
            in: context,
            at: center,
            radius: metrics.glowRadius,
            color: accent,
            intensity: metrics.glowIntensity
        )

        let directions = directions(for: metrics.formation)
        let upper = bladePath(
            center: center,
            metrics: metrics,
            upper: true,
            direction: directions.0
        )
        let lower = bladePath(
            center: center,
            metrics: metrics,
            upper: false,
            direction: directions.1
        )

        drawBlade(
            upper,
            in: context,
            bounds: bounds,
            color: accent,
            alpha: metrics.bodyAlpha,
            upper: true
        )
        drawBlade(
            lower,
            in: context,
            bounds: bounds,
            color: accent,
            alpha: metrics.bodyAlpha,
            upper: false
        )

        switch metrics.formation {
        case .sealed:
            drawSeal(
                in: context,
                center: center,
                span: metrics.span,
                color: accent
            )
        case .advancing:
            drawPhaseLine(
                in: context,
                center: center,
                span: metrics.span,
                color: accent
            )
        case .fractured:
            drawFracture(
                in: context,
                center: center,
                color: accent
            )
        case .open:
            break
        }

        drawCore(
            in: context,
            center: center,
            radius: metrics.coreRadius,
            color: accent,
            intensity: metrics.formation == .fractured ? 0.52 : 1
        )
    }

    private static func drawBlade(
        _ path: CGPath,
        in context: CGContext,
        bounds: CGRect,
        color: NSColor,
        alpha: CGFloat,
        upper: Bool
    ) {
        let space = CGColorSpaceCreateDeviceRGB()
        let colors: [CGColor]
        let locations: [CGFloat]
        if upper {
            colors = [
                deep(color, 0.76 * alpha).cgColor,
                body(color, 0.94 * alpha).cgColor,
                rim(color, 1.0 * alpha).cgColor,
            ]
            locations = [0, 0.56, 1]
        } else {
            colors = [
                rim(color, 1.0 * alpha).cgColor,
                body(color, 0.94 * alpha).cgColor,
                deep(color, 0.76 * alpha).cgColor,
            ]
            locations = [0, 0.44, 1]
        }

        guard let gradient = CGGradient(
            colorsSpace: space,
            colors: colors as CFArray,
            locations: locations
        ) else { return }

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.midX, y: bounds.minY),
            end: CGPoint(x: bounds.midX, y: bounds.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(rim(color, 0.82 * alpha).cgColor)
        context.setLineWidth(0.52)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawCore(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        color: NSColor,
        intensity: CGFloat
    ) {
        let haloRadius = radius * 2.5
        guard let halo = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                rim(color, 0.40 * intensity).cgColor,
                color.withAlphaComponent(0).cgColor,
            ] as CFArray,
            locations: [0, 1]
        ) else { return }

        context.saveGState()
        context.drawRadialGradient(
            halo,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: haloRadius,
            options: .drawsAfterEndLocation
        )
        context.restoreGState()

        context.saveGState()
        context.setFillColor(rim(color, 0.98 * intensity).cgColor)
        context.fillEllipse(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.72).cgColor)
        context.setLineWidth(0.45)
        context.strokeEllipse(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        context.restoreGState()
    }

    private static func drawSeal(
        in context: CGContext,
        center: CGPoint,
        span: CGFloat,
        color: NSColor
    ) {
        let seam = CGMutablePath()
        seam.move(to: CGPoint(x: center.x - (span * 0.56), y: center.y))
        seam.addCurve(
            to: CGPoint(x: center.x + (span * 0.56), y: center.y),
            control1: CGPoint(x: center.x - (span * 0.20), y: center.y + 0.5),
            control2: CGPoint(x: center.x + (span * 0.20), y: center.y - 0.5)
        )
        context.saveGState()
        context.addPath(seam)
        context.setStrokeColor(rim(color, 0.54).cgColor)
        context.setLineWidth(0.55)
        context.setLineCap(.round)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawPhaseLine(
        in context: CGContext,
        center: CGPoint,
        span: CGFloat,
        color: NSColor
    ) {
        context.saveGState()
        context.move(
            to: CGPoint(x: center.x - (span * 0.48), y: center.y)
        )
        context.addLine(
            to: CGPoint(x: center.x + (span * 0.64), y: center.y)
        )
        context.setStrokeColor(rim(color, 0.46).cgColor)
        context.setLineWidth(0.62)
        context.setLineCap(.round)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawFracture(
        in context: CGContext,
        center: CGPoint,
        color: NSColor
    ) {
        context.saveGState()
        context.move(to: CGPoint(x: center.x - 2.2, y: center.y + 2.4))
        context.addLine(to: CGPoint(x: center.x - 0.55, y: center.y + 0.55))
        context.move(to: CGPoint(x: center.x + 0.55, y: center.y - 0.55))
        context.addLine(to: CGPoint(x: center.x + 2.2, y: center.y - 2.4))
        context.setStrokeColor(rim(color, 0.74).cgColor)
        context.setLineWidth(0.72)
        context.setLineCap(.round)
        context.strokePath()
        context.restoreGState()
    }

    private static func glow(
        in context: CGContext,
        at center: CGPoint,
        radius: CGFloat,
        color: NSColor,
        intensity: CGFloat
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                color.withAlphaComponent(intensity).cgColor,
                color.withAlphaComponent(0).cgColor,
            ] as CFArray,
            locations: [0, 1]
        ) else { return }

        context.saveGState()
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: .drawsAfterEndLocation
        )
        context.restoreGState()
    }
}
