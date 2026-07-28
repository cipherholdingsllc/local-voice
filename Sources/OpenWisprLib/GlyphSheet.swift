import AppKit
import CoreGraphics
import Foundation

/// Offscreen contact sheet for glyph review.
///
/// This exists because visual QA that depends on someone screenshotting a
/// floating window is not reproducible, and a QA image that does not come from
/// the shipping renderer proves nothing. The glyph here is painted by
/// `SignalBladesGlyph.draw` — the same call the live overlay makes — so the sheet
/// cannot drift from what users see. Only the surrounding chrome is redrawn,
/// because `PillChromeView` is layer-backed and has no offscreen path.
///
/// No window is opened and no user session is disturbed.
public enum GlyphSheet {
    public struct Options {
        public let scale: CGFloat
        public let states: [String]

        public init(scale: CGFloat = 3, states: [String] = []) {
            self.scale = max(1, min(8, scale))
            self.states = states
        }
    }

    private static let pillHeight: CGFloat = 48
    private static let pillWidth: CGFloat = 268
    private static let glyphOrigin = CGPoint(x: 13, y: 11)
    private static let glyphSide: CGFloat = 26

    public static func render(
        to url: URL,
        options: Options = Options()
    ) throws {
        let states: [PillState] = options.states.isEmpty
            ? PillState.allCases
            : options.states.compactMap { PillState(rawValue: $0) }
        guard !states.isEmpty else {
            throw SheetError.noStates
        }

        // Two rows per state: at rest, and at speaking level.
        let levels: [(String, Float)] = [("rest", 0.0), ("speaking", 0.72)]

        let gutter: CGFloat = 92
        let padX: CGFloat = 20
        let padY: CGFloat = 14
        let cellWidth = pillWidth + (padX * 2)
        let cellHeight = pillHeight + (padY * 2)
        let headerHeight: CGFloat = 44

        let sheetWidth = gutter + (CGFloat(states.count) * cellWidth)
        let sheetHeight = headerHeight
            + (CGFloat(levels.count) * cellHeight)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(sheetWidth * options.scale),
            pixelsHigh: Int(sheetHeight * options.scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw SheetError.allocationFailed
        }
        bitmap.size = NSSize(width: sheetWidth, height: sheetHeight)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let nsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw SheetError.allocationFailed
        }
        NSGraphicsContext.current = nsContext
        let context = nsContext.cgContext
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        NSColor(
            calibratedRed: 0.055,
            green: 0.055,
            blue: 0.068,
            alpha: 1
        ).setFill()
        NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight).fill()

        NSAttributedString(
            string: "LOCAL VOICE \(OpenWispr.version) — SIGNAL BLADES",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1),
                .kern: 1.8,
            ]
        ).draw(at: NSPoint(x: 22, y: sheetHeight - 29))

        for (row, level) in levels.enumerated() {
            let rowY = sheetHeight
                - headerHeight
                - (CGFloat(row + 1) * cellHeight)

            NSAttributedString(
                string: level.0,
                attributes: [
                    .font: NSFont.monospacedSystemFont(
                        ofSize: 11,
                        weight: .medium
                    ),
                    .foregroundColor: NSColor(
                        calibratedWhite: 0.5,
                        alpha: 1
                    ),
                ]
            ).draw(at: NSPoint(x: 22, y: rowY + (cellHeight / 2) - 6))

            for (column, state) in states.enumerated() {
                let origin = CGPoint(
                    x: gutter + (CGFloat(column) * cellWidth) + padX,
                    y: rowY + padY
                )
                drawPill(
                    in: context,
                    at: origin,
                    state: state,
                    level: level.1
                )
            }
        }

        guard let png = bitmap.representation(
            using: .png,
            properties: [:]
        ) else {
            throw SheetError.encodeFailed
        }
        try png.write(to: url, options: .atomic)
    }

    private static func drawPill(
        in context: CGContext,
        at origin: CGPoint,
        state: PillState,
        level: Float
    ) {
        let rect = CGRect(
            x: origin.x,
            y: origin.y,
            width: pillWidth,
            height: pillHeight
        )
        let body = CGPath(
            roundedRect: rect,
            cornerWidth: pillHeight / 2,
            cornerHeight: pillHeight / 2,
            transform: nil
        )
        let space = CGColorSpaceCreateDeviceRGB()

        if let gradient = CGGradient(
            colorsSpace: space,
            colors: [
                NSColor(
                    calibratedRed: 0.105,
                    green: 0.120,
                    blue: 0.150,
                    alpha: 0.98
                ).cgColor,
                NSColor(
                    calibratedRed: 0.040,
                    green: 0.048,
                    blue: 0.065,
                    alpha: 0.985
                ).cgColor,
            ] as CFArray,
            locations: [0, 1]
        ) {
            context.saveGState()
            context.addPath(body)
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: rect.maxY),
                end: CGPoint(x: 0, y: rect.minY),
                options: []
            )
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(body)
        context.setStrokeColor(
            NSColor.white.withAlphaComponent(0.14).cgColor
        )
        context.setLineWidth(0.75)
        context.strokePath()
        context.restoreGState()

        let hairline = CGRect(
            x: origin.x + 14,
            y: origin.y + pillHeight - 1,
            width: pillWidth - 28,
            height: 1
        )
        let tone = SignalBladesGlyph.rim(state.accentColor, 1)
        if let accent = CGGradient(
            colorsSpace: space,
            colors: [
                tone.withAlphaComponent(0).cgColor,
                tone.withAlphaComponent(0.30).cgColor,
                tone.withAlphaComponent(0).cgColor,
            ] as CFArray,
            locations: [0, 0.5, 1]
        ) {
            context.saveGState()
            context.addRect(hairline)
            context.clip()
            context.drawLinearGradient(
                accent,
                start: CGPoint(x: hairline.minX, y: 0),
                end: CGPoint(x: hairline.maxX, y: 0),
                options: []
            )
            context.restoreGState()
        }

        // The glyph itself, from the shipping renderer.
        let glyphBounds = CGRect(
            x: origin.x + glyphOrigin.x,
            y: origin.y + glyphOrigin.y,
            width: glyphSide,
            height: glyphSide
        )
        SignalBladesGlyph.draw(
            in: context,
            bounds: glyphBounds,
            state: state,
            metrics: SignalBladesGlyph.Metrics.make(
                level: level,
                state: state
            )
        )

        let label = NSMutableAttributedString(
            string: state.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 0.97, alpha: 0.97),
            ]
        )
        if let detail = state.detail {
            label.append(
                NSAttributedString(
                    string: "  ·  \(detail)",
                    attributes: [
                        .font: NSFont.systemFont(
                            ofSize: 11.5,
                            weight: .medium
                        ),
                        .foregroundColor: NSColor(
                            calibratedWhite: 0.82,
                            alpha: 0.78
                        ),
                    ]
                )
            )
        }
        label.draw(at: NSPoint(x: origin.x + 50, y: origin.y + 15))
    }

    public enum SheetError: LocalizedError {
        case allocationFailed
        case encodeFailed
        case noStates

        public var errorDescription: String? {
            switch self {
            case .allocationFailed:
                return "Could not allocate the glyph sheet canvas."
            case .encodeFailed:
                return "Could not encode the glyph sheet as PNG."
            case .noStates:
                return "No recognised pill states were requested."
            }
        }
    }
}
