import AppKit
import QuartzCore

/// A fixed, non-activating state surface for system-wide dictation.
///
/// The glyph deliberately avoids literal microphones, equalizer bars, and
/// padlocks. Capture is represented by two sound-reactive signal blades around
/// a luminous core. Lock mode interlocks the same geometry rather than
/// introducing a second visual language — see `SignalBladesGlyph`.
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
    private var glyphView: SignalBladesGlyphView?
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
        detail: String? = nil,
        playEarcon: Bool = true
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.showOnMain(
                state: state,
                partialText: partialText,
                detail: detail,
                playEarcon: playEarcon
            )
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    func hide(ifState state: PillState) {
        DispatchQueue.main.async { [weak self] in
            guard self?.currentState == state else { return }
            self?.panel?.orderOut(nil)
        }
    }

    func updateLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.glyphView?.level = level
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
        detail: String?,
        playEarcon: Bool
    ) {
        ensurePanel()
        guard let panel else { return }

        currentState = state
        glyphView?.pillState = state
        glyphView?.setAccessibilityLabel(state.accessibilityLabel)
        chromeView?.accentColor = state.accentColor

        let trimmedPartial = partialText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = detail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let presentation = PillPresentation(
            title: trimmedPartial?.isEmpty == false
                ? trimmedPartial!
                : state.title,
            detail: {
                if let trimmedDetail, !trimmedDetail.isEmpty {
                    return trimmedDetail
                }
                if trimmedPartial?.isEmpty == false {
                    return nil
                }
                return state.detail
            }()
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

        let glyph = SignalBladesGlyphView(
            frame: NSRect(x: 13, y: 11, width: 26, height: 26)
        )
        glyph.setAccessibilityRole(.image)
        glyph.setAccessibilityLabel(PillState.listening.accessibilityLabel)
        chrome.addSubview(glyph)

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
        glyphView = glyph
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

    /// Concept C's metallic signal-blade system, unified around a restrained
    /// nickel-to-mint spectrum. Listening carries a small neon-green charge;
    /// finishing and locked step back toward metal. Error alone leaves the
    /// family for a warm alert tone.
    var accentColor: NSColor {
        switch self {
        case .listening:
            return NSColor(
                calibratedRed: 0.46,
                green: 0.96,
                blue: 0.62,
                alpha: 1
            )
        case .transcribing:
            return NSColor(
                calibratedRed: 0.62,
                green: 0.82,
                blue: 0.68,
                alpha: 1
            )
        case .locked:
            return NSColor(
                calibratedRed: 0.72,
                green: 0.88,
                blue: 0.76,
                alpha: 1
            )
        case .error:
            return NSColor(
                calibratedRed: 1.00,
                green: 0.34,
                blue: 0.36,
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

/// Renders Signal Blades, and owns the one thing a pure renderer cannot: the
/// temporal smoothing of microphone level across frames.
final class SignalBladesGlyphView: NSView {
    private var smoothedEnergy: CGFloat = 0
    private var lastDrawnEnergy: CGFloat = -1

    var level: Float = 0 {
        didSet {
            let target = SignalBladesGlyph.Energy.condition(level)
            smoothedEnergy = SignalBladesGlyph.Energy.smooth(
                previous: smoothedEnergy,
                target: target
            )
            let quantized = SignalBladesGlyph.Energy.quantize(smoothedEnergy)
            if abs(quantized - lastDrawnEnergy)
                >= SignalBladesGlyph.Energy.step {
                needsDisplay = true
            }
        }
    }

    var pillState: PillState = .listening {
        didSet {
            if pillState != oldValue { needsDisplay = true }
        }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let quantized = SignalBladesGlyph.Energy.quantize(smoothedEnergy)
        lastDrawnEnergy = quantized

        SignalBladesGlyph.draw(
            in: context,
            bounds: bounds,
            state: pillState,
            metrics: SignalBladesGlyph.Metrics.make(
                energy: quantized,
                state: pillState
            )
        )
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
            .withAlphaComponent(0.14)
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
        let tone = SignalBladesGlyph.rim(accentColor, 1)
        accentLayer.colors = [
            tone.withAlphaComponent(0).cgColor,
            tone.withAlphaComponent(0.30).cgColor,
            tone.withAlphaComponent(0).cgColor,
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
