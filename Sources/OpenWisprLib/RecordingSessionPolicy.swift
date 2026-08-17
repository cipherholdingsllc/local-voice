import Foundation

/// Keeps capture timers and contract limits derived from one source of truth.
/// Hold-to-talk remains tightly bounded by the active app profile. A deliberate
/// double-tap lock promotes the take to the long-form profile instead of
/// silently inheriting a Terminal/Codex two-minute cap.
public enum RecordingSessionPolicy {
    public static let lockedProfile: VoiceContractProfileID = .generalLongForm

    public static func maximumDurationMilliseconds(
        for profile: VoiceContractProfileID,
        configuredCapSeconds: Double?
    ) -> Int {
        let profileLimit = profile.maximumDurationMilliseconds

        // Locked mode is itself an explicit long-form opt-in. Preserve its
        // dedicated one-hour safety boundary rather than a shorter hold cap.
        if profile == lockedProfile {
            return profileLimit
        }

        guard let configuredCapSeconds,
              configuredCapSeconds > 0 else {
            return profileLimit
        }
        let configured = Int((configuredCapSeconds * 1_000).rounded())
        return min(profileLimit, max(1_000, configured))
    }

    public static func capSeconds(
        for profile: VoiceContractProfileID,
        configuredCapSeconds: Double?
    ) -> TimeInterval {
        Double(
            maximumDurationMilliseconds(
                for: profile,
                configuredCapSeconds: configuredCapSeconds
            )
        ) / 1_000
    }
}
