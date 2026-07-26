import AppKit
import QuartzCore

/// Floating mic/waveform pill — fixed anchor by default (not cursor-chasing).
final class PillOverlay {
    enum Anchor: String, Codable {
        case bottomRight
        case bottomLeft
        case topRight
        case topLeft
    }

    private var panel: NSPanel?
    private var levelView: WaveformLevelView?
    private var statusLabel: NSTextField?
    private var anchor: Anchor = .bottomRight
    private var followsCursor = false

    var isVisible: Bool { panel?.isVisible ?? false }

    func configure(anchor: Anchor = .bottomRight, followsCursor: Bool = false) {
        self.anchor = anchor
        self.followsCursor = followsCursor
    }

    func show(state: PillState, partialText: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.showOnMain(state: state, partialText: partialText)
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    func updateLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.levelView?.level = level
        }
    }

    func updatePartial(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel?.stringValue = text.isEmpty ? "Listening…" : text
        }
    }

    private func showOnMain(state: PillState, partialText: String?) {
        ensurePanel()
        guard let panel = panel else { return }

        levelView?.pillState = state
        statusLabel?.stringValue = partialText ?? state.label
        positionPanel()
        panel.orderFrontRegardless()
        EarconPlayer.play(for: state)
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let size = NSSize(width: 220, height: 44)
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 22
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.92).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.15).cgColor

        let wave = WaveformLevelView(frame: NSRect(x: 12, y: 10, width: 24, height: 24))
        container.addSubview(wave)
        levelView = wave

        let label = NSTextField(labelWithString: "Listening…")
        label.frame = NSRect(x: 44, y: 12, width: 160, height: 20)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.95, alpha: 1)
        label.lineBreakMode = .byTruncatingTail
        container.addSubview(label)
        statusLabel = label

        p.contentView = container
        panel = p
    }

    private func positionPanel() {
        guard let panel = panel else { return }

        if followsCursor {
            let mouse = NSEvent.mouseLocation
            var origin = NSPoint(x: mouse.x + 16, y: mouse.y - 52)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
                let frame = screen.visibleFrame
                origin.x = min(origin.x, frame.maxX - panel.frame.width - 8)
                origin.y = max(origin.y, frame.minY + 8)
            }
            panel.setFrameOrigin(origin)
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let frame = screen.visibleFrame
        let margin: CGFloat = 16
        let size = panel.frame.size

        let origin: NSPoint
        switch anchor {
        case .bottomRight:
            origin = NSPoint(x: frame.maxX - size.width - margin, y: frame.minY + margin)
        case .bottomLeft:
            origin = NSPoint(x: frame.minX + margin, y: frame.minY + margin)
        case .topRight:
            origin = NSPoint(x: frame.maxX - size.width - margin, y: frame.maxY - size.height - margin)
        case .topLeft:
            origin = NSPoint(x: frame.minX + margin, y: frame.maxY - size.height - margin)
        }
        panel.setFrameOrigin(origin)
    }
}

enum PillState {
    case listening
    case transcribing
    case locked
    case error

    var label: String {
        switch self {
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .locked: return "Locked — double-tap fn to stop"
        case .error: return "Error"
        }
    }
}

final class WaveformLevelView: NSView {
    var level: Float = 0 { didSet { needsDisplay = true } }
    var pillState: PillState = .listening { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor
        switch pillState {
        case .listening: color = .systemGreen
        case .locked: color = .systemOrange
        case .transcribing: color = .systemBlue
        case .error: color = .systemRed
        }
        color.setFill()
        let h = max(4, CGFloat(level) * bounds.height)
        let bar = NSRect(x: 8, y: (bounds.height - h) / 2, width: 8, height: h)
        NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4).fill()
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
        if let url = URL(string: "file:///System/Library/Sounds/\(name).aiff") {
            NSSound(contentsOf: url, byReference: true)?.play()
        }
    }
}
