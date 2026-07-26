import AppKit
import Foundation

/// Per-app prompt profiles (#7) — bundle ID routes to cleanup style.
public enum AppPromptProfiles {
    public struct Profile: Codable, Sendable {
        public let bundleID: String
        public let name: String
        public let systemPrompt: String
    }

    public static let defaults: [Profile] = [
        Profile(
            bundleID: "com.tinyspeck.slackmacgap",
            name: "Slack",
            systemPrompt: "Clean up casual Slack message. Keep tone friendly and concise. Fix grammar lightly."
        ),
        Profile(
            bundleID: "com.google.Gmail",
            name: "Gmail",
            systemPrompt: "Polish into professional email prose. Complete sentences, proper punctuation."
        ),
        Profile(
            bundleID: "com.apple.mail",
            name: "Mail",
            systemPrompt: "Polish into professional email prose. Complete sentences, proper punctuation."
        ),
        Profile(
            bundleID: "com.microsoft.VSCode",
            name: "VS Code",
            systemPrompt: "Code-aware cleanup. Preserve identifiers, paths, and technical terms. Do not auto-capitalize code tokens."
        ),
        Profile(
            bundleID: "com.openai.codex",
            name: "Technical",
            systemPrompt: "Technical cleanup. Preserve identifiers, paths, commands, model names, and code terms."
        ),
        Profile(
            bundleID: "com.apple.Terminal",
            name: "Terminal",
            systemPrompt: "Command-aware cleanup. Preserve flags, paths, and shell syntax. No auto-capitalization."
        ),
        Profile(
            bundleID: "com.googlecode.iterm2",
            name: "iTerm",
            systemPrompt: "Command-aware cleanup. Preserve flags, paths, and shell syntax. No auto-capitalization."
        ),
    ]

    public static func profile(for bundleID: String?, custom: [Profile] = []) -> Profile {
        let all = custom + defaults
        if let id = bundleID, let match = all.first(where: { $0.bundleID == id }) {
            return match
        }
        return Profile(
            bundleID: "default",
            name: "Default",
            systemPrompt: "Clean up dictated text. Fix grammar and punctuation. Preserve meaning."
        )
    }

    public static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
