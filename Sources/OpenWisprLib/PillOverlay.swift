import AppKit
import QuartzCore

/// A fixed, non-activating state surface for system-wide dictation.
///
/// The glyph deliberately avoids literal microphones, equalizer bars, and
/// padlocks. Listening is represented by an open, sound-reactive aperture.
/// Lock mode closes the same geometry into a voice seal, so the state change is
/// visible without introducing a second visual language.
final class PillOverlay {
    enum Anchor: String, Codable {
        case bottomRight
        case bottomLeft
        case topRight
        case topLeft
    }

    private static let height: CGFloat = 48
    private static let minimumWidth: CGFloat = 164
    private static let maximumWidth: CGFloat = 420

    private var panel: NSPanel?
    private var chromeView: PillChromeView?
    private var apertureView: VoiceApertureView?
    private var statusLabel: NSTextField?
    private var anchor: Anchor = .bottomRight
    private var followsCursor = false
    private var currentState: PillState = .listening

    var isVisible: Bool { panel?.isVisible ?? false }

    func configure(anchor: Anchor = .bottomRight, followsCursor: Bool = false) {
        self.anchor = anchor
        self.followsCursor = followsCursor
    }

    func show(
        state: PillState,
        partialText: String? = nil,
        playEarcon: Bool = true
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.showOnMain(
                state: state,
                partialText: partialText,
                playEarcon: playEarcon
            )
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    func updateLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.apertureView?.level = level
        }
    }

    func updatePartial(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let partial = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.applyPresentation(
                PillPresentation(
                    title: partial.isEmpty ? self.currentState.title : partial,
                    detail: nil
                )
            )
            self.positionPanel()
        }
    }

    private func showOnMain(
        state: PillState,
        partialText: String?,
        playEarcon: Bool
    ) {
        ensurePanel()
        guard let panel else { return }

        currentState = state
        apertureView?.pillState = state
        apertureView?.setAccessibilityLabel(state.accessibilityLabel)
        chromeView?.accentColor = state.accentColor

        let trimmedPartial = partialText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let presentation = PillPresentation(
            title: trimmedPartial?.isEmpty == false
                ? trimmedPartial!
                : state.title,
            detail: trimmedPartial?.isEmpty == false ? nil : state.detail
        )
        applyPresentation(presentation)
        positionPanel()
        panel.orderFrontRegardless()
        if playEarcon {
            EarconPlayer.play(for: state)
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let size = NSSize(
            width: Self.minimumWidth,
            height: Self.height
        )
        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .floating
        newPanel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.isMovableByWindowBackground = true

        let chrome = PillChromeView(
            frame: NSRect(origin: .zero, size: size)
        )
        chrome.autoresizingMask = [.width, .height]

        let aperture = VoiceApertureView(
            frame: NSRect(x: 14, y: 12, width: 24, height: 24)
        )
        aperture.setAccessibilityRole(.image)
        aperture.setAccessibilityLabel(PillState.listening.accessibilityLabel)
        chrome.addSubview(aperture)

        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(
            x: 50,
            y: 14,
            width: size.width - 64,
            height: 20
        )
        label.isSelectable = false
        label.usesSingleLineMode = true
        label.lineBreakMode = .byTruncatingTail
        chrome.addSubview(label)

        newPanel.contentView = chrome
        panel = newPanel
        chromeView = chrome
        apertureView = aperture
        statusLabel = label
    }

    private func applyPresentation(_ presentation: PillPresentation) {
        guard
            let panel,
            let chromeView,
            let statusLabel
        else { return }

        let attributed = presentation.attributedString
        let measuredWidth = ceil(
            attributed.boundingRect(
                with: NSSize(
                    width: Self.maximumWidth,
                    height: Self.height
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).width
        )
        let width = min(
            Self.maximumWidth,
            max(Self.minimumWidth, measuredWidth + 68)
        )

        panel.setContentSize(
            NSSize(width: width, height: Self.height)
        )
        chromeView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: width, height: Self.height)
        )
        statusLabel.frame = NSRect(
            x: 50,
            y: 14,
            width: width - 64,
            height: 20
        )
        statusLabel.attributedStringValue = attributed
        statusLabel.setAccessibilityLabel(presentation.accessibilityLabel)
    }

    private func positionPanel() {
        guard let panel else { return }

        if followsCursor {
            let mouse = NSEvent.mouseLocation
            var origin = NSPoint(x: mouse.x + 16, y: mouse.y - 56)
            if let screen = NSScreen.screens.first(
                where: { $0.frame.contains(mouse) }
            ) ?? NSScreen.main {
                let frame = screen.visibleFrame
                origin.x = min(
                    origin.x,
                    frame.maxX - panel.frame.width - 8
                )
                origin.y = max(origin.y, frame.minY + 8)
            }
            panel.setFrameOrigin(origin)
            return
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        let frame = screen.visibleFrame
        let margin: CGFloat = 16
        let size = panel.frame.size

        let origin: NSPoint
        switch anchor {
        case .bottomRight:
            origin = NSPoint(
                x: frame.maxX - size.width - margin,
                y: frame.minY + margin
            )
        case .bottomLeft:
            origin = NSPoint(
                x: frame.minX + margin,
                y: frame.minY + margin
            )
        case .topRight:
            origin = NSPoint(
                x: frame.maxX - size.width - margin,
                y: frame.maxY - size.height - margin
            )
        case .topLeft:
            origin = NSPoint(
                x: frame.minX + margin,
                y: frame.maxY - size.height - margin
            )
        }
        panel.setFrameOrigin(origin)
    }
}

enum PillState: String, CaseIterable {
    case listening
    case transcribing
    case locked
    case error

    var title: String {
        switch self {
        case .listening: return "Listening"
        case .transcribing: return "Finishing"
        case .locked: return "Locked"
        case .error: return "Needs attention"
        }
    }

    var detail: String? {
        switch self {
        case .locked: return "double-tap fn to finish"
        default: return nil
        }
    }

    var accessibilityLabel: String {
        [title, detail].compactMap { $0 }.joined(separator: ", ")
    }

    var accentColor: NSColor {
        switch self {
        case .listening:
            return NSColor(
                calibratedRed: 0.98,
                green: 0.43,
                blue: 0.36,
                alpha: 1
            )
        case .transcribing:
            return NSColor(
                calibratedRed: 0.43,
                green: 0.68,
                blue: 0.98,
                alpha: 1
            )
        case .locked:
            return NSColor(
                calibratedRed: 0.98,
                green: 0.72,
                blue: 0.31,
                alpha: 1
            )
        case .error:
            return NSColor(
                calibratedRed: 0.98,
                green: 0.32,
                blue: 0.38,
                alpha: 1
            )
        }
    }
}

struct PillPresentation: Equatable {
    let title: String
    let detail: String?

    var accessibilityLabel: String {
        [title, detail].compactMap { $0 }.joined(separator: ", ")
    }

    var attributedString: NSAttributedString {
        let value = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor(
                    calibratedWhite: 0.97,
                    alpha: 1
                ),
                .kern: 0.08,
            ]
        )
        if let detail {
            value.append(
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
                        .kern: 0.04,
                    ]
                )
            )
        }
        return value
    }
}

struct VoiceApertureMetrics: Equatable {
    let normalizedLevel: CGFloat
    let coreRadius: CGFloat
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let glowRadius: CGFloat

    static func make(
        level: Float,
        state: PillState
    ) -> VoiceApertureMetrics {
        let raw = level.isFinite ? CGFloat(level) : 0
        let normalized = min(1, max(0, raw))

        switch state {
        case .listening:
            return VoiceApertureMetrics(
                normalizedLevel: normalized,
                coreRadius: 2.25 + (normalized * 0.45),
                innerRadius: 4.7 + (normalized * 0.55),
                outerRadius: 7.4 + (normalized * 1.2),
                glowRadius: 5.2 + (normalized * 2.4)
            )
        case .locked:
            return VoiceApertureMetrics(
                normalizedLevel: normalized,
                coreRadius: 2.35 + (normalized * 0.25),
                innerRadius: 4.85,
                outerRadius: 8.25,
                glowRadius: 6.6 + (normalized * 1.2)
            )
        case .transcribing:
            return VoiceApertureMetrics(
                normalizedLevel: normalized,
                coreRadius: 2.2,
                innerRadius: 4.9,
                outerRadius: 7.9,
                glowRadius: 5.8
            )
        case .error:
            return VoiceApertureMetrics(
                normalizedLevel: normalized,
                coreRadius: 2.2,
                innerRadius: 4.7,
                outerRadius: 7.9,
                glowRadius: 5.5
            )
        }
    }
}

/// The Voice Aperture: one continuous visual grammar for every capture state.
final class VoiceApertureView: NSView {
    var level: Float = 0 {
        didSet {
            if abs(level - oldValue) > 0.01 {
                needsDisplay = true
            }
        }
    }

    var pillState: PillState = .listening {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.saveGState()
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let metrics = VoiceApertureMetrics.make(
            level: level,
            state: pillState
        )
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let accent = pillState.accentColor

        drawGlow(
            center: center,
            radius: metrics.glowRadius,
            color: accent,
            intensity: 0.12 + (metrics.normalizedLevel * 0.1)
        )

        switch pillState {
        case .listening:
            drawListening(
                center: center,
                metrics: metrics,
                accent: accent
            )
        case .locked:
            drawLocked(
                center: center,
                metrics: metrics,
                accent: accent
            )
        case .transcribing:
            drawTranscribing(
                center: center,
                metrics: metrics,
                accent: accent
            )
        case .error:
            drawError(
                center: center,
                metrics: metrics,
                accent: accent
            )
        }

        drawPearl(
            center: center,
            radius: metrics.coreRadius,
            color: accent
        )
        context.restoreGState()
    }

    private func drawListening(
        center: NSPoint,
        metrics: VoiceApertureMetrics,
        accent: NSColor
    ) {
        let energy = metrics.normalizedLevel
        strokeArc(
            center: center,
            radius: metrics.innerRadius,
            startAngle: 116,
            endAngle: 244,
            color: accent.withAlphaComponent(0.42 + (energy * 0.22)),
            width: 1.15
        )
        strokeArc(
            center: center,
            radius: metrics.innerRadius,
            startAngle: -64,
            endAngle: 64,
            color: accent.withAlphaComponent(0.42 + (energy * 0.22)),
            width: 1.15
        )
        strokeArc(
            center: center,
            radius: metrics.outerRadius,
            startAngle: 108,
            endAngle: 252,
            color: accent.withAlphaComponent(0.76 + (energy * 0.18)),
            width: 1.45
        )
        strokeArc(
            center: center,
            radius: metrics.outerRadius,
            startAngle: -72,
            endAngle: 72,
            color: accent.withAlphaComponent(0.76 + (energy * 0.18)),
            width: 1.45
        )
    }

    private func drawLocked(
        center: NSPoint,
        metrics: VoiceApertureMetrics,
        accent: NSColor
    ) {
        strokeCircle(
            center: center,
            radius: metrics.outerRadius,
            color: accent.withAlphaComponent(0.94),
            width: 1.45
        )
        strokeCircle(
            center: center,
            radius: metrics.innerRadius,
            color: accent.withAlphaComponent(0.28),
            width: 1
        )

        let closure = NSBezierPath()
        closure.move(
            to: NSPoint(
                x: center.x,
                y: center.y + metrics.outerRadius - 1.1
            )
        )
        closure.line(
            to: NSPoint(
                x: center.x,
                y: center.y + metrics.outerRadius + 1.6
            )
        )
        closure.lineWidth = 1.45
        closure.lineCapStyle = .round
        accent.withAlphaComponent(0.94).setStroke()
        closure.stroke()
    }

    private func drawTranscribing(
        center: NSPoint,
        metrics: VoiceApertureMetrics,
        accent: NSColor
    ) {
        strokeArc(
            center: center,
            radius: metrics.outerRadius,
            startAngle: 34,
            endAngle: 326,
            color: accent.withAlphaComponent(0.9),
            width: 1.45
        )
        strokeCircle(
            center: center,
            radius: metrics.innerRadius,
            color: accent.withAlphaComponent(0.26),
            width: 1
        )
    }

    private func drawError(
        center: NSPoint,
        metrics: VoiceApertureMetrics,
        accent: NSColor
    ) {
        strokeArc(
            center: center,
            radius: metrics.outerRadius,
            startAngle: 22,
            endAngle: 146,
            color: accent.withAlphaComponent(0.92),
            width: 1.45
        )
        strokeArc(
            center: center,
            radius: metrics.outerRadius,
            startAngle: 202,
            endAngle: 326,
            color: accent.withAlphaComponent(0.92),
            width: 1.45
        )

        let slash = NSBezierPath()
        slash.move(
            to: NSPoint(
                x: center.x - 4.4,
                y: center.y + 4.4
            )
        )
        slash.line(
            to: NSPoint(
                x: center.x + 4.4,
                y: center.y - 4.4
            )
        )
        slash.lineWidth = 1.25
        slash.lineCapStyle = .round
        accent.withAlphaComponent(0.72).setStroke()
        slash.stroke()
    }

    private func drawPearl(
        center: NSPoint,
        radius: CGFloat,
        color: NSColor
    ) {
        color.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        ).fill()

        let highlightRadius = max(0.65, radius * 0.32)
        NSColor.white.withAlphaComponent(0.68).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - (radius * 0.38) - highlightRadius,
                y: center.y + (radius * 0.28),
                width: highlightRadius * 2,
                height: highlightRadius * 2
            )
        ).fill()
    }

    private func drawGlow(
        center: NSPoint,
        radius: CGFloat,
        color: NSColor,
        intensity: CGFloat
    ) {
        let glow = color.withAlphaComponent(intensity)
        let clear = color.withAlphaComponent(0)
        guard let gradient = NSGradient(
            starting: glow,
            ending: clear
        ) else { return }

        gradient.draw(
            in: NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            ),
            relativeCenterPosition: .zero
        )
    }

    private func strokeArc(
        center: NSPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat,
        color: NSColor,
        width: CGFloat
    ) {
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle
        )
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func strokeCircle(
        center: NSPoint,
        radius: CGFloat,
        color: NSColor,
        width: CGFloat
    ) {
        let path = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }
}

final class PillChromeView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let accentLayer = CAGradientLayer()

    var accentColor: NSColor = PillState.listening.accentColor {
        didSet { updateAccent() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        gradientLayer.colors = [
            NSColor(
                calibratedRed: 0.13,
                green: 0.14,
                blue: 0.16,
                alpha: 0.97
            ).cgColor,
            NSColor(
                calibratedRed: 0.068,
                green: 0.075,
                blue: 0.09,
                alpha: 0.97
            ).cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)

        accentLayer.startPoint = CGPoint(x: 0, y: 0.5)
        accentLayer.endPoint = CGPoint(x: 1, y: 0.5)
        updateAccent()

        layer?.addSublayer(gradientLayer)
        layer?.addSublayer(accentLayer)
        layer?.cornerRadius = frameRect.height / 2
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.75
        layer?.borderColor = NSColor.white
            .withAlphaComponent(0.16)
            .cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = bounds.height / 2
        accentLayer.frame = NSRect(
            x: 14,
            y: bounds.height - 1,
            width: max(0, bounds.width - 28),
            height: 1
        )
        accentLayer.cornerRadius = 0.5
    }

    private func updateAccent() {
        accentLayer.colors = [
            accentColor.withAlphaComponent(0).cgColor,
            accentColor.withAlphaComponent(0.36).cgColor,
            accentColor.withAlphaComponent(0).cgColor,
        ]
        accentLayer.locations = [0, 0.5, 1]
    }
}

public enum PillPreviewState: String, CaseIterable {
    case listening
    case transcribing
    case locked
    case error
}

/// A microphone-free presentation harness for visual QA.
public final class PillOverlayPreviewSession {
    private let overlay = PillOverlay()

    public init() {}

    @discardableResult
    public func show(
        state: PillPreviewState,
        level: Float = 0.58
    ) -> Bool {
        guard let pillState = PillState(rawValue: state.rawValue) else {
            return false
        }
        // Keep QA previews away from the live product pill, which owns the
        // bottom-right anchor.
        overlay.configure(anchor: .topRight, followsCursor: false)
        overlay.show(
            state: pillState,
            playEarcon: false
        )
        overlay.updateLevel(level)
        return true
    }
}

enum EarconPlayer {
    static func play(for state: PillState) {
        let name: String
        switch state {
        case .listening, .locked: name = "Tink"
        case .transcribing: name = "Pop"
        case .error: name = "Basso"
        }
        if let url = URL(
            string: "file:///System/Library/Sounds/\(name).aiff"
        ) {
            NSSound(contentsOf: url, byReference: true)?.play()
        }
    }
}
