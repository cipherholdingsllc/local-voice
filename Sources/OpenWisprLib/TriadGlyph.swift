import AppKit
import CoreGraphics

/// The Triad: one continuous visual grammar for every capture state.
///
/// Three chiplets held in formation by a visible kerf. Energy closes the kerf;
/// the outer silhouette stays constant, so the mark never appears to resize.
/// On `.locked` each chiplet opens its own inverted void — the form recurses
/// one level into itself at the moment of commitment.
///
/// Drawing is a pure function of `(bounds, state, energy)` so the same code
/// paints the live overlay and the offscreen QA contact sheet. Divergence
/// between what ships and what QA reviews is therefore impossible by
/// construction.
enum TriadGlyph {

    // MARK: - Level conditioning

    /// Raw microphone level is RMS-ish, noisy, and perceptually non-linear.
    /// Geometry is never driven from it directly.
    enum Energy {
        /// Noise-gate + perceptual expansion. Pure; safe for tests.
        static func condition(_ level: Float) -> CGFloat {
            let raw = level.isFinite ? CGFloat(level) : 0
            let clamped = min(1, max(0, raw))
            let gated = max(0, (clamped - 0.06) / 0.94)
            return pow(gated, 0.62)
        }

        /// Quantization step. Below this, no geometry moves at all, which is
        /// what stops thin diagonals shimmering under sustained speech.
        static let step: CGFloat = 1.0 / 24.0

        static func quantize(_ energy: CGFloat) -> CGFloat {
            (energy / step).rounded() * step
        }

        /// Asymmetric smoothing: ~12 ms attack, ~78 ms release at 60 fps.
        static func smooth(
            previous: CGFloat,
            target: CGFloat
        ) -> CGFloat {
            let coefficient: CGFloat = target > previous ? 0.55 : 0.12
            return previous + coefficient * (target - previous)
        }
    }

    // MARK: - Metrics

    struct Metrics: Equatable {
        /// Conditioned, quantized energy in `0...1`.
        let energy: CGFloat
        /// Outer circumradius of the assembled triad, in points.
        let radius: CGFloat
        /// Kerf as a fraction of the drawn circumradius.
        let kerf: CGFloat
        /// Whether each chiplet carries its own inverted void.
        let seated: Bool
        /// Whether the apex chiplet is reduced to a ghost outline.
        let apexGhosted: Bool
        /// Alpha multiplier applied to the body.
        let bodyAlpha: CGFloat
        let glowRadius: CGFloat
        let glowIntensity: CGFloat

        /// Convenience for tests and for stateless offscreen rendering, where
        /// there is no previous frame to smooth against.
        static func make(level: Float, state: PillState) -> Metrics {
            make(
                energy: Energy.quantize(Energy.condition(level)),
                state: state
            )
        }

        /// `rawEnergy` must already be conditioned, smoothed, and quantized.
        static func make(energy rawEnergy: CGFloat, state: PillState) -> Metrics {
            let raw = min(1, max(0, rawEnergy))
            // Committed states do not take direction from the microphone.
            let authority: CGFloat
            switch state {
            case .listening: authority = 1.0
            case .locked: authority = 0.35
            case .transcribing, .error: authority = 0
            }
            let energy = raw * authority

            let radius: CGFloat = 11.2
            let kerf: CGFloat
            switch state {
            case .listening: kerf = 0.240 - (0.055 * energy)
            case .locked, .transcribing: kerf = 0.185
            case .error: kerf = 0.300
            }

            return Metrics(
                energy: energy,
                radius: radius,
                kerf: kerf,
                seated: state == .locked,
                apexGhosted: state == .error,
                bodyAlpha: state == .transcribing ? 0.75 : 1.0,
                glowRadius: (0.62 * radius) + (2.2 * energy),
                glowIntensity: state == .transcribing
                    ? 0
                    : 0.10 + (0.09 * energy)
            )
        }
    }

    // MARK: - Colour

    /// Specular. Carries hue identity for the whole mark, which is what lets
    /// the body sit dim without reading brown.
    static func rim(_ color: NSColor, _ alpha: CGFloat = 1) -> NSColor {
        let (h, s, _) = components(color)
        return NSColor(
            deviceHue: h,
            saturation: s * 0.55,
            brightness: 1.0,
            alpha: alpha
        )
    }

    /// Gradient base stop.
    static func deep(_ color: NSColor, _ alpha: CGFloat = 1) -> NSColor {
        let (h, s, b) = components(color)
        var hue = h - (4.0 / 360.0)
        if hue < 0 { hue += 1 }
        return NSColor(
            deviceHue: hue,
            saturation: min(1, s * 1.06),
            brightness: b * 0.80,
            alpha: alpha
        )
    }

    /// Body tone with a hue pre-shift that cancels the blue contamination the
    /// dark chrome introduces as alpha drops. Without it, dim gold reads brown.
    static func body(_ color: NSColor, _ alpha: CGFloat) -> NSColor {
        let (h, s, b) = components(color)
        let drift = max(0, (0.45 - alpha) / 0.45)
        var hue = h + ((7.0 / 360.0) * drift)
        if hue > 1 { hue -= 1 }
        return NSColor(
            deviceHue: hue,
            saturation: s,
            brightness: min(1, b * (1 + (0.10 * drift))),
            alpha: alpha
        )
    }

    private static func components(
        _ color: NSColor
    ) -> (CGFloat, CGFloat, CGFloat) {
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            return (0, 0, 1)
        }
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }

    // MARK: - Geometry

    private static let cos30: CGFloat = 0.8660254

    struct Triangle {
        let apex: CGPoint
        let left: CGPoint
        let right: CGPoint
    }

    static func pointUp(center: CGPoint, radius r: CGFloat) -> Triangle {
        Triangle(
            apex: CGPoint(x: center.x, y: center.y + r),
            left: CGPoint(x: center.x - (cos30 * r), y: center.y - (r / 2)),
            right: CGPoint(x: center.x + (cos30 * r), y: center.y - (r / 2))
        )
    }

    static func pointDown(center: CGPoint, radius r: CGFloat) -> Triangle {
        Triangle(
            apex: CGPoint(x: center.x, y: center.y - r),
            left: CGPoint(x: center.x - (cos30 * r), y: center.y + (r / 2)),
            right: CGPoint(x: center.x + (cos30 * r), y: center.y + (r / 2))
        )
    }

    static func rotated(
        _ triangle: Triangle,
        about pivot: CGPoint,
        degrees: CGFloat
    ) -> Triangle {
        let radians = degrees * .pi / 180
        func turn(_ point: CGPoint) -> CGPoint {
            let dx = point.x - pivot.x
            let dy = point.y - pivot.y
            return CGPoint(
                x: pivot.x + (dx * cos(radians)) - (dy * sin(radians)),
                y: pivot.y + (dx * sin(radians)) + (dy * cos(radians))
            )
        }
        return Triangle(
            apex: turn(triangle.apex),
            left: turn(triangle.left),
            right: turn(triangle.right)
        )
    }

    /// A 60° apex must be truncated at this scale, and every join must be
    /// round: a mitered 60° corner projects a needle twice the stroke width
    /// past the intended silhouette, which is the first thing to shimmer.
    static func path(_ t: Triangle, corner: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard corner > 0.01 else {
            path.addLines(between: [t.apex, t.left, t.right])
            path.closeSubpath()
            return path
        }
        path.move(
            to: CGPoint(
                x: (t.apex.x + t.left.x) / 2,
                y: (t.apex.y + t.left.y) / 2
            )
        )
        path.addArc(tangent1End: t.left, tangent2End: t.right, radius: corner)
        path.addArc(tangent1End: t.right, tangent2End: t.apex, radius: corner)
        path.addArc(tangent1End: t.apex, tangent2End: t.left, radius: corner)
        path.closeSubpath()
        return path
    }

    /// The optical anchor for a triad of circumradius `r` inside `bounds`.
    ///
    /// An equilateral triangle's centroid is not its bounding-box centre, and
    /// deriving vertices from a centred box puts the mark ~0.18·r too low —
    /// about 2 pt here, which reads as a sag nobody can name.
    static func anchor(in bounds: CGRect, radius r: CGFloat) -> CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY - (0.07 * r))
    }

    /// Relative size of each chiplet. The reference form this evokes uses
    /// three identical clones; hierarchy is the cheapest way to not be it.
    static let seatScales: [CGFloat] = [1.09, 0.95, 0.95]

    static func seatCentres(
        anchor p: CGPoint,
        drawnRadius: CGFloat
    ) -> [CGPoint] {
        let ring = drawnRadius / 2
        return [
            CGPoint(x: p.x, y: p.y + ring),
            CGPoint(x: p.x - (cos30 * ring), y: p.y - (ring / 2)),
            CGPoint(x: p.x + (cos30 * ring), y: p.y - (ring / 2)),
        ]
    }

    // MARK: - Drawing

    static func draw(
        in context: CGContext,
        bounds: CGRect,
        state: PillState,
        metrics: Metrics
    ) {
        let accent = state.accentColor
        let p = anchor(in: bounds, radius: metrics.radius)

        // Kerf shrinks the assembled silhouette; compensate so only the
        // internal gap breathes and the outer extent stays put.
        let drawn = metrics.radius / (1 - (metrics.kerf / 2))
        let ring = drawn / 2
        let baseRadius = (1 - metrics.kerf) * ring

        if metrics.glowIntensity > 0 {
            glow(
                in: context,
                at: p,
                radius: metrics.glowRadius,
                color: accent,
                intensity: metrics.glowIntensity
            )
        }

        let space = CGColorSpaceCreateDeviceRGB()
        let centres = seatCentres(anchor: p, drawnRadius: drawn)

        for (index, centre) in centres.enumerated() {
            let r = baseRadius * seatScales[index]
            let side = r * 1.7320508
            let triangle = pointUp(center: centre, radius: r)
            let outline = path(triangle, corner: 0.11 * side)
            let isApex = index == 0

            if metrics.apexGhosted, isApex {
                context.saveGState()
                context.addPath(outline)
                context.setStrokeColor(
                    accent.withAlphaComponent(0.18).cgColor
                )
                context.setLineWidth(1.0)
                context.setLineJoin(.round)
                context.strokePath()
                context.restoreGState()
                continue
            }

            let shape = CGMutablePath()
            shape.addPath(outline)
            let seatRadius = 0.34 * r
            let seat = rotated(
                pointDown(center: centre, radius: seatRadius),
                about: centre,
                degrees: -6
            )
            let seatPath = path(
                seat,
                corner: 0.10 * (seatRadius * 1.7320508)
            )
            if metrics.seated {
                shape.addPath(seatPath)
            }

            // Base-dark to apex-light, per chiplet. Deliberately inverted from
            // a conventional top-lit bevel so the mark reads as emissive
            // rather than as a stamped metal plate, and so each chiplet is
            // lit independently instead of sharing one bevelled surface.
            let stops = [
                deep(accent, (0.58 + (0.18 * metrics.energy)) * metrics.bodyAlpha)
                    .cgColor,
                body(accent, 0.94 * metrics.bodyAlpha).cgColor,
                rim(accent, 1.0 * metrics.bodyAlpha).cgColor,
            ] as CFArray

            if let gradient = CGGradient(
                colorsSpace: space,
                colors: stops,
                locations: [0, 0.62, 1]
            ) {
                context.saveGState()
                context.addPath(shape)
                context.clip(using: .evenOdd)
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: centre.x, y: centre.y - (r / 2)),
                    end: CGPoint(x: centre.x, y: centre.y + r),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
                context.restoreGState()
            }

            // Rim rides the two upper edges only. The baseline is the one
            // axis-aligned stroke, so it snaps hard and would pile weight
            // exactly where a point-up form is already bottom-heavy.
            context.saveGState()
            context.setStrokeColor(
                rim(accent, (isApex ? 0.95 : 0.80) * metrics.bodyAlpha).cgColor
            )
            context.setLineWidth(0.5)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.move(to: triangle.left)
            context.addLine(to: triangle.apex)
            context.addLine(to: triangle.right)
            context.strokePath()
            context.restoreGState()

            if metrics.seated {
                context.saveGState()
                context.addPath(seatPath)
                context.setStrokeColor(rim(accent, 0.90).cgColor)
                context.setLineWidth(0.45)
                context.setLineJoin(.round)
                context.strokePath()
                context.restoreGState()
            }
        }
    }

    static func glow(
        in context: CGContext,
        at centre: CGPoint,
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
            startCenter: centre,
            startRadius: 0,
            endCenter: centre,
            endRadius: radius,
            options: .drawsAfterEndLocation
        )
        context.restoreGState()
    }
}
