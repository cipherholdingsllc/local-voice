import Foundation

/// Ollama cleanup pass (#7-9) — optional second-stage polish.
public final class OllamaCleanup {
    public let baseURL: URL
    public let model: String
    public let enabled: Bool
    public let minLength: Int

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!, model: String = "llama3.2:latest", enabled: Bool = true, minLength: Int = 20) {
        self.baseURL = baseURL
        self.model = model
        self.enabled = enabled
        self.minLength = minLength
    }

    public func polish(raw: String, systemPrompt: String, vocabulary: [String] = []) throws -> String {
        guard enabled, raw.count >= minLength else { return raw }

        let vocabBlock = vocabulary.isEmpty ? "" : "\nCustom vocabulary (preserve exactly): \(vocabulary.joined(separator: ", "))"
        let prompt = """
        \(systemPrompt)\(vocabBlock)

        Return ONLY valid JSON matching this schema:
        {"text":"polished text","commands":[]}

        Commands schema (execute, do not type literally):
        - {"type":"new_line"} — insert newline
        - {"type":"scratch_that"} — delete last insertion
        - {"type":"all_caps"} — uppercase last sentence
        - {"type":"send_it"} — press Return/Enter

        Raw transcript:
        \(raw)
        """

        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "format": "json",
            "options": ["keep_alive": -1],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let sem = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseObj: URLResponse?
        var requestError: Error?
        URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data
            responseObj = response
            requestError = error
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 35)
        if let requestError { throw requestError }
        guard let data = responseData, let response = responseObj as? HTTPURLResponse, response.statusCode == 200 else {
            throw OllamaCleanupError.unavailable
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw OllamaCleanupError.parseFailed
        }

        guard let parsed = try JSONSerialization.jsonObject(with: Data(responseText.utf8)) as? [String: Any],
              let text = parsed["text"] as? String else {
            return raw
        }

        if let commands = parsed["commands"] as? [[String: Any]] {
            VoiceCommandExecutor.shared.enqueue(commands)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isReachable(baseURL: URL = URL(string: "http://127.0.0.1:11434")!) -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 { ok = true }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 3)
        return ok
    }
}

enum DictationCleanupRoute: String, Equatable {
    case disabled
    case tooShort
    case synchronousOllama
    case fastLongForm
}

/// Keeps optional prose refinement inside a predictable interaction budget.
///
/// Parakeet already returns punctuated text. For long-form dictation, waiting
/// for a second model to regenerate the entire transcript dominates perceived
/// latency, so Local Voice preserves the local STT result and returns it
/// immediately. Short messages still receive the configured Ollama pass.
enum DictationCleanupPolicy {
    static let minimumPolishCharacters = 20
    static let maximumSynchronousCharacters = 700
    static let maximumSynchronousRecordingMilliseconds = 45_000.0

    static func route(
        enabled: Bool,
        characterCount: Int,
        recordingMilliseconds: Double
    ) -> DictationCleanupRoute {
        guard enabled else { return .disabled }
        guard characterCount >= minimumPolishCharacters else {
            return .tooShort
        }
        guard
            characterCount <= maximumSynchronousCharacters,
            recordingMilliseconds
                <= maximumSynchronousRecordingMilliseconds
        else {
            return .fastLongForm
        }
        return .synchronousOllama
    }
}

enum OllamaCleanupError: LocalizedError {
    case unavailable
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Ollama is not running. Start with: ollama serve"
        case .parseFailed: return "Ollama response could not be parsed"
        }
    }
}
