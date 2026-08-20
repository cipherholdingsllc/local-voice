import Foundation

/// Creating the CGEvent tap is how macOS registers Local Voice.app in
/// Input Monitoring. Skipping tapCreate when preflight is false is a
/// chicken-egg: the app never appears in the list, so the grant never happens.
public enum EventTapRegistration {
    public static func shouldAttemptCreate(preflightGranted: Bool) -> Bool {
        _ = preflightGranted
        return true
    }
}
