import Foundation

/// Operator-facing speech-route copy. Featured model cards and Command Center
/// health rows read this so "ACTIVE" cannot light up two Whisper cards at once.
public enum SpeechRouteDisplay {
    public static let parakeetTitle = "Parakeet TDT v3"
    public static let whisperTurboTitle = "Whisper large-v3-turbo"
    public static let whisperBaseTitle = "Whisper base.en"

    public static func isFeaturedCardActive(
        title: String,
        engineName: String,
        selectedModel: String
    ) -> Bool {
        let engine = engineName.lowercased()
        let model = selectedModel.lowercased()
        let usingParakeet = engine.contains("parakeet")
        let usingWhisper = engine.contains("whisper")
        switch title {
        case parakeetTitle:
            return usingParakeet
        case whisperTurboTitle:
            return usingWhisper && model.contains("large-v3-turbo")
        case whisperBaseTitle:
            return usingWhisper && model.contains("base.en")
        default:
            return false
        }
    }

    public static func engineHealthDetail(
        engineName: String,
        selectedModel: String
    ) -> String {
        "Now using \(engineName). Selected Whisper model: \(selectedModel)."
    }

    public static func parakeetHealthDetail(
        running: Bool,
        healthy: Bool
    ) -> String {
        switch (running, healthy) {
        case (true, true):
            return "Running. Fast path is available."
        case (true, false):
            return "Process is up, last Parakeet attempt failed. Whisper is covering."
        case (false, _):
            return "Not running. Whisper is covering dictation."
        }
    }

    public static func lastTakeDetail(
        outcome: TextInsertOutcome,
        engineName: String,
        destination: String? = nil
    ) -> String {
        let dest = destination?.trimmingCharacters(in: .whitespacesAndNewlines)
        let destLabel = (dest?.isEmpty == false) ? dest! : "the field"
        switch outcome {
        case .insertedViaAccessibility, .insertedViaLiveComposer, .insertedViaUnicode:
            return "Last take: \(engineName) typed into \(destLabel)."
        case .transcribedOnly:
            return "Last take: \(engineName) transcribed. Words are in history, not \(destLabel)."
        case .blockedSecureField:
            return "Last take: blocked in a password field."
        }
    }
}
