import AppKit
import SwiftUI

public final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = DashboardWindowController()

    private var previewMode = false

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Local Voice"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 980, height: 660)
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(
            calibratedRed: 0.043,
            green: 0.051,
            blue: 0.063,
            alpha: 1
        )
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show(
        store: LocalVoiceStore = .shared,
        actions: LocalVoiceDashboardActions = LocalVoiceDashboardActions()
    ) {
        guard let window else { return }
        let dashboard = LocalVoiceDashboard(store: store, actions: actions)
        window.contentViewController = NSHostingController(rootView: dashboard)
        NSApplication.shared.setActivationPolicy(.regular)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    public func showPreview() {
        previewMode = true
        guard let window else { return }
        let dashboard = LocalVoiceDashboard(
            store: .preview(),
            actions: LocalVoiceDashboardActions(),
            fileStore: .preview()
        )
        window.contentViewController = NSHostingController(rootView: dashboard)
        NSApplication.shared.setActivationPolicy(.regular)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        if previewMode {
            NSApplication.shared.terminate(nil)
        } else {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
