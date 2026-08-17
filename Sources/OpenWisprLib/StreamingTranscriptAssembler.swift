import Foundation

enum StreamingTranscriptAssembler {
    static func merge(existing: String, incoming: String) -> String {
        var current = existing.split(whereSeparator: \.isWhitespace).map(String.init)
        var next = incoming.split(whereSeparator: \.isWhitespace).map(String.init)

        guard !next.isEmpty else { return existing }
        guard !current.isEmpty else { return incoming }

        splitCamelGlueBoundary(current: &current, next: &next)

        let currentKeys = current.map(normalizedToken)
        let nextKeys = next.map(normalizedToken)

        if nextKeys.count >= currentKeys.count,
           Array(nextKeys.prefix(currentKeys.count)) == currentKeys {
            return incoming
        }
        if currentKeys.count >= nextKeys.count,
           Array(currentKeys.suffix(nextKeys.count)) == nextKeys {
            return existing
        }

        let maximumOverlap = min(12, currentKeys.count, nextKeys.count)
        var overlap = 0
        if maximumOverlap > 0 {
            for count in stride(from: maximumOverlap, through: 1, by: -1) {
                if Array(currentKeys.suffix(count))
                    == Array(nextKeys.prefix(count)) {
                    overlap = count
                    break
                }
            }
        }

        return (current + next.dropFirst(overlap)).joined(separator: " ")
    }

    /// `itThere` at a chunk edge is `it` plus `There`. Product names stay put.
    private static func splitCamelGlueBoundary(
        current: inout [String],
        next: inout [String]
    ) {
        guard let last = current.last, let first = next.first else { return }
        if let (left, right) = PauseContinuation.splitCamelGlue(last),
           normalizedToken(right) == normalizedToken(first) {
            current[current.count - 1] = left
            return
        }
        if let (left, right) = PauseContinuation.splitCamelGlue(first),
           normalizedToken(left) == normalizedToken(last) {
            next[0] = right
        }
    }

    private static func normalizedToken(_ token: String) -> String {
        token
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }
}
