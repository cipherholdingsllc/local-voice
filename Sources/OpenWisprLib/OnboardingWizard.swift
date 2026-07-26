import AppKit

/// Guided first-run onboarding (#16).
final class OnboardingWizard {
    static let completionMarker: URL = {
        Config.configDir.appendingPathComponent(".onboarding-complete")
    }()

    static func needsOnboarding() -> Bool {
        !FileManager.default.fileExists(atPath: completionMarker.path)
    }

    static func markComplete() {
        try? FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        try? "1".write(to: completionMarker, atomically: true, encoding: .utf8)
    }

    static func showIfNeeded() {
        guard needsOnboarding() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            OnboardingWindowController.shared.show()
        }
    }
}

final class OnboardingWindowController: NSWindowController {
    static let shared = OnboardingWindowController()

    private var step = 0
    private let steps: [(title: String, body: String, action: () -> Void)] = [
        ("Welcome to Local Flow", "100% on-device dictation. No cloud. No accounts.\n\nWe'll set up three permissions.", {}),
        ("Microphone", "Local Flow needs your microphone to hear you speak.", { Permissions.ensureMicrophone() }),
        ("Accessibility", "Required to insert text at your cursor in any app.", {
            Permissions.promptAccessibility()
            Permissions.openAccessibilitySettings()
        }),
        ("Input Monitoring", "Required for fn/globe and custom hotkeys (CGEventTap).", {
            Permissions.ensureInputMonitoring()
        }),
        ("Ready", "Hold your hotkey (default: fn/globe), speak, release.\n\nOptional: run `ollama serve` for AI cleanup.", {}),
    ]

    private var titleLabel: NSTextField!
    private var bodyLabel: NSTextField!
    private var nextButton: NSButton!

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Local Flow Setup"
        super.init(window: panel)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.frame = NSRect(x: 24, y: 200, width: 392, height: 28)
        content.addSubview(titleLabel)

        bodyLabel = NSTextField(wrappingLabelWithString: "")
        bodyLabel.font = NSFont.systemFont(ofSize: 13)
        bodyLabel.frame = NSRect(x: 24, y: 80, width: 392, height: 110)
        content.addSubview(bodyLabel)

        nextButton = NSButton(title: "Continue", target: self, action: #selector(nextStep))
        nextButton.frame = NSRect(x: 320, y: 24, width: 96, height: 32)
        nextButton.bezelStyle = .rounded
        content.addSubview(nextButton)
    }

    func show() {
        step = 0
        renderStep()
        window?.center()
        showWindow(nil)
    }

    @objc private func nextStep() {
        if step < steps.count { steps[step].action() }
        step += 1
        if step >= steps.count {
            OnboardingWizard.markComplete()
            window?.close()
            return
        }
        renderStep()
    }

    private func renderStep() {
        guard step < steps.count else { return }
        let s = steps[step]
        titleLabel.stringValue = s.title
        bodyLabel.stringValue = s.body
        nextButton.title = step == steps.count - 1 ? "Get Started" : "Continue"
    }
}
