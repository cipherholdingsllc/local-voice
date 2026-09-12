import Foundation

enum TranscriptAcceptanceGate {
    private static let hallucinationProneSingleWords: Set<String> = [
        "you",
        "yeah",
        "uh",
        "um",
        "yuh",
    ]

    static func shouldAccept(
        raw: String,
        polished: String,
        recordingMilliseconds: Double,
        captureMetrics: AudioCaptureMetrics
    ) -> Bool {
        let candidate = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = candidate.isEmpty ? fallback : candidate
        let words = normalizedWords(from: normalized)
        guard !words.isEmpty else { return false }

        if words.count == 1,
           hallucinationProneSingleWords.contains(words[0]),
           recordingMilliseconds >= 500 || captureMetrics.activeDuration >= 0.5 {
            return false
        }

        return true
    }

    private static func normalizedWords(from text: String) -> [String] {
        let lowercased = text.lowercased()
        let separators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted
        return lowercased
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
    }
}
