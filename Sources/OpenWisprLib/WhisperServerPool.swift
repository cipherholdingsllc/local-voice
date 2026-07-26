import Foundation

/// Persistent whisper-server process (#6b) — model stays resident between dictations.
public final class WhisperServerPool: STTEngine {
    public let name = "whisper-server"
    public let modelSize: String
    private let language: String
    private var process: Process?
    private let port: Int
    private let queue = DispatchQueue(label: "local-flow.whisper-server")
    private var isWarmed = false

    public init(modelSize: String, language: String, port: Int = 8177) {
        self.modelSize = modelSize
        self.language = language
        self.port = port
    }

    public func isAvailable() -> Bool {
        guard Transcriber.findWhisperBinary() != nil,
              Transcriber.findModel(modelSize: modelSize) != nil else { return false }
        return process?.isRunning == true || ping()
    }

    public func warmup() throws {
        try ensureRunning()
        guard !isWarmed else { return }
        if let url = try? makeSilentWAV() {
            defer { try? FileManager.default.removeItem(at: url) }
            _ = try? transcribe(audioURL: url)
            isWarmed = true
        }
    }

    public func ensureRunning() throws {
        if process?.isRunning == true, ping() { return }
        stop()
        guard let serverPath = Self.findServerBinary(),
              let modelPath = Transcriber.findModel(modelSize: modelSize) else {
            throw WhisperServerError.notConfigured
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: serverPath)
        proc.arguments = [
            "-m", modelPath,
            "-l", language == "auto" ? "en" : language,
            "--host", "127.0.0.1",
            "--port", String(port),
            "-nt",
        ]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        process = proc

        for _ in 0..<40 {
            if ping() { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw WhisperServerError.startTimeout
    }

    public func transcribe(audioURL: URL) throws -> String {
        try ensureRunning()
        let boundary = "LocalFlow-\(UUID().uuidString)"
        var body = Data()
        let fileData = try Data(contentsOf: audioURL)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/inference")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120

        let sem = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                responseError = WhisperServerError.httpError(http.statusCode)
            } else {
                responseError = error
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 125)
        if let responseError { throw responseError }
        guard let data = responseData else { throw WhisperServerError.emptyResponse }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return Transcriber.stripWhisperMarkers(text)
        }
        let plain = String(data: data, encoding: .utf8) ?? ""
        return Transcriber.stripWhisperMarkers(plain)
    }

    public func stop() {
        process?.terminate()
        process = nil
        isWarmed = false
    }

    private func ping() -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
        request.timeoutInterval = 0.5
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse { ok = http.statusCode < 500 }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1)
        return ok
    }

    private static func findServerBinary() -> String? {
        for path in ["/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private func makeSilentWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("warm-\(UUID().uuidString).wav")
        let sampleRate = 16000
        let frameCount = 4000
        let header = WAVHeader(sampleRate: sampleRate, dataSize: frameCount * 2)
        var data = header.data
        data.append(Data(count: frameCount * 2))
        try data.write(to: url)
        return url
    }
}

enum WhisperServerError: LocalizedError {
    case notConfigured
    case startTimeout
    case httpError(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "whisper-server or model not found"
        case .startTimeout: return "whisper-server failed to start"
        case .httpError(let c): return "whisper-server HTTP \(c)"
        case .emptyResponse: return "whisper-server returned empty response"
        }
    }
}

private struct WAVHeader {
    let sampleRate: Int
    let dataSize: Int

    var data: Data {
        var d = Data()
        d.append(contentsOf: "RIFF".utf8)
        d.append(UInt32(36 + dataSize).leData)
        d.append(contentsOf: "WAVE".utf8)
        d.append(contentsOf: "fmt ".utf8)
        d.append(UInt32(16).leData)
        d.append(UInt16(1).leData)
        d.append(UInt16(1).leData)
        d.append(UInt32(sampleRate).leData)
        d.append(UInt32(sampleRate * 2).leData)
        d.append(UInt16(2).leData)
        d.append(UInt16(16).leData)
        d.append(contentsOf: "data".utf8)
        d.append(UInt32(dataSize).leData)
        return d
    }
}

private extension UInt32 {
    var leData: Data { withUnsafeBytes(of: littleEndian) { Data($0) } }
}
private extension UInt16 {
    var leData: Data { withUnsafeBytes(of: littleEndian) { Data($0) } }
}
