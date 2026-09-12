import Foundation

public enum UsefulEngine: String, Codable, CaseIterable, Sendable {
    case ollama
    case template
    case auto

    public var title: String {
        switch self {
        case .ollama: return "Ollama"
        case .template: return "Template"
        case .auto: return "Auto"
        }
    }
}

public final class UsefulTransformer {
    public static let shared = UsefulTransformer()

    private let ollama: OllamaCleanup

    public init(ollama: OllamaCleanup = OllamaCleanup(minLength: 0)) {
        self.ollama = ollama
    }

    public func effectiveEngine(_ engine: UsefulEngine) -> UsefulEngine {
        switch engine {
        case .ollama:
            return OllamaCleanup.isReachable() ? .ollama : .template
        case .template:
            return .template
        case .auto:
            return OllamaCleanup.isReachable() ? .ollama : .template
        }
    }

    public func draft(
        record: LocalVoiceRecord,
        type: ArtifactType,
        engine: UsefulEngine = .auto
    ) -> String {
        let resolved = effectiveEngine(engine)
        if resolved == .ollama {
            do {
                return try ollamaDraft(record: record, type: type)
            } catch {
                fputs("Ollama draft failed: \(error.localizedDescription). Falling back to template.\n", stderr)
                return templateDraft(record: record, type: type)
            }
        }
        return templateDraft(record: record, type: type)
    }

    private func ollamaDraft(record: LocalVoiceRecord, type: ArtifactType) throws -> String {
        let instruction: String
        switch type {
        case .prompt:
            instruction = "Turn the following raw voice transcript into a reusable, well-structured prompt for an AI assistant. Include a concise instruction and supporting context."
        case .note:
            instruction = "Turn the following raw voice transcript into a clean Markdown note."
        case .task:
            instruction = "Turn the following raw voice transcript into a concise Markdown task list or set of action items."
        }
        let systemPrompt = """
        \(instruction)

        Return ONLY valid JSON matching this schema:
        {"text":"the final text","commands":[]}

        Commands schema (execute, do not type literally):
        - {"type":"new_line"} — insert newline
        - {"type":"scratch_that"} — delete last insertion
        - {"type":"all_caps"} — uppercase last sentence
        - {"type":"send_it"} — press Return/Enter
        """
        return try ollama.polish(raw: record.text, systemPrompt: systemPrompt)
    }

    private func templateDraft(record: LocalVoiceRecord, type: ArtifactType) -> String {
        let (first, rest) = splitFirstSentence(record.text)
        switch type {
        case .prompt:
            return """
            # Prompt

            ## What to do
            \(first)

            ## Context
            \(rest.isEmpty ? "(No additional context provided.)" : rest)
            """
        case .note:
            return """
            # Note

            \(record.text)
            """
        case .task:
            return """
            # Task

            - [ ] \(first)

            \(rest.isEmpty ? "" : "Context: \(rest)")
            """
        }
    }

    private func splitFirstSentence(_ text: String) -> (String, String) {
        let delimiters: [String] = [". ", "? ", "! ", "\n"]
        var splitIndex: String.Index?
        for delimiter in delimiters {
            if let range = text.range(of: delimiter) {
                if splitIndex == nil || range.upperBound < splitIndex! {
                    splitIndex = range.upperBound
                }
            }
        }
        if let splitIndex {
            let first = String(text[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = String(text[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (first, rest)
        }
        return (text, "")
    }
}
