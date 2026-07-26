import AppKit

/// Latency debug panel (#14).
final class LatencyPanelController {
    static let shared = LatencyPanelController()

    private var panel: NSPanel?
    private var textView: NSTextView?

    func show() {
        DispatchQueue.main.async { [weak self] in
            self?.showOnMain()
        }
    }

    private func showOnMain() {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            p.title = "Local Flow — Latency"
            p.level = .floating
            p.isReleasedWhenClosed = false

            let scroll = NSScrollView(frame: p.contentView!.bounds)
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            let tv = NSTextView(frame: scroll.bounds)
            tv.isEditable = false
            tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            scroll.documentView = tv
            p.contentView?.addSubview(scroll)
            panel = p
            textView = tv
        }

        refresh()
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
    }

    func refresh() {
        let inst = LatencyInstrumentation.shared
        let lines = inst.lastSession.sorted { $0.key < $1.key }.map { key, ms in
            String(format: "%@: %.0f ms", key, ms)
        }
        let total = inst.totalMs()
        let body = (lines + ["", String(format: "TOTAL: %.0f ms", total), "", inst.summary()]).joined(separator: "\n")
        textView?.string = body.isEmpty ? "No timings yet — dictate once." : body
    }
}
