import AppKit
import QuartzCore

/// A fixed, non-activating state surface for system-wide dictation.
///
/// The glyph deliberately avoids literal microphones, equalizer bars, and
/// padlocks. Capture is represented by a sound-reactive triad whose kerf
/// closes as you speak. Lock mode seats the same geometry rather than
/// introducing a second visual language — see `TriadGlyph`.
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
    private var glyphView: TriadGlyphView?
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

        let glyph = TriadGlyphView(
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

    /// Capture runs hot and bright; commitment cools and deepens. The four
    /// states are separated by hue first so they survive the squint test,
    /// rather than by brightness alone.
    var accentColor: NSColor {
        switch self {
        case .listening:
            // Citrine: warm yellow, gold-adjacent. Live and electric without
            // tipping into highlighter, which is where a cooler yellow lands.
            return NSColor(
                calibratedRed: 1.00,
                green: 0.84,
                blue: 0.32,
                alpha: 1
            )
        case .transcribing:
            // Slate: the one deliberate break from the warm family. With
            // listening now yellow, a warm straw would collide with it, and
            // this state needs to read as work rather than as capture.
            return NSColor(
                calibratedRed: 0.58,
                green: 0.70,
                blue: 0.86,
                alpha: 1
            )
        case .locked:
            // Brick: deep and earthy. Quieter than listening on purpose —
            // this is the state you sit inside during a long dictation, so it
            // should settle rather than keep shouting.
            return NSColor(
                calibratedRed: 0.80,
                green: 0.34,
                blue: 0.19,
                alpha: 1
            )
        case .error:
            // Crimson, pushed toward pink. A plain red would sit close enough
            // to brick that a locked pill and a failed one could be confused
            // at a glance.
            return NSColor(
                calibratedRed: 0.97,
                green: 0.28,
                blue: 0.42,
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

/// Renders the Triad, and owns the one thing a pure renderer cannot: the
/// temporal smoothing of microphone level across frames.
final class TriadGlyphView: NSView {
    private var smoothedEnergy: CGFloat = 0
    private var lastDrawnEnergy: CGFloat = -1

    var level: Float = 0 {
        didSet {
            let target = TriadGlyph.Energy.condition(level)
            smoothedEnergy = TriadGlyph.Energy.smooth(
                previous: smoothedEnergy,
                target: target
            )
            let quantized = TriadGlyph.Energy.quantize(smoothedEnergy)
            if abs(quantized - lastDrawnEnergy) >= TriadGlyph.Energy.step {
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

        let quantized = TriadGlyph.Energy.quantize(smoothedEnergy)
        lastDrawnEnergy = quantized

        TriadGlyph.draw(
            in: context,
            bounds: bounds,
            state: pillState,
            metrics: TriadGlyph.Metrics.make(
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
        let tone = TriadGlyph.rim(accentColor, 1)
        accentLayer.colors = [
            tone.withAlphaComponent(0).cgColor,
            tone.withAlphaComponent(0.40).cgColor,
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
