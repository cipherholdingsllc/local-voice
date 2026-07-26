import Foundation

/// Long-lived Parakeet MLX daemon (#4) — JSON-lines over stdin/stdout.
public final class ParakeetDaemon: STTEngine {
    public static let shared = ParakeetDaemon()
    public let name = "parakeet-tdt-0.6b"

    private var process: Process?
    private var stdinHandle: FileHandle?
    private let lock = NSLock()
    private var ready = false
    private let scriptPath: String

    private init() {
        scriptPath = ParakeetDaemon.resolveScriptPath()
    }

    public func isAvailable() -> Bool {
        FileManager.default.fileExists(atPath: scriptPath) && (process?.isRunning == true || canLaunchPython())
    }

    public func warmup() throws {
        try ensureRunning()
    }

    public func ensureRunning() throws {
        lock.lock()
        defer { lock.unlock() }
        if process?.isRunning == true, ready { return }
        stopLocked()

        guard canLaunchPython() else {
            throw ParakeetError.pythonMissing
        }

        let proc = Process()
        let python = Self.resolvePython()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = [scriptPath]
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        process = proc
        stdinHandle = inPipe.fileHandleForWriting

        let outHandle = outPipe.fileHandleForReading
        for _ in 0..<120 {
            if let line = readLine(from: outHandle), line.contains("\"ready\"") {
                ready = true
                return
            }
            if proc.isRunning == false { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw ParakeetError.startTimeout
    }

    public func transcribe(audioURL: URL) throws -> String {
        try ensureRunning()
        lock.lock()
        defer { lock.unlock() }
        guard let stdin = stdinHandle, let proc = process, proc.isRunning else {
            throw ParakeetError.notRunning
        }

        let req = "{\"cmd\":\"transcribe\",\"path\":\"\(audioURL.path)\"}\n"
        guard let reqData = req.data(using: .utf8) else { throw ParakeetError.encodeFailed }
        stdin.write(reqData)

        guard let out = proc.standardOutput as? Pipe else { throw ParakeetError.noOutput }
        let handle = out.fileHandleForReading
        guard let line = readLine(from: handle),
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParakeetError.parseFailed
        }
        if let err = json["error"] as? String { throw ParakeetError.workerError(err) }
        return (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        if let stdin = stdinHandle {
            try? stdin.write(contentsOf: Data("{\"cmd\":\"quit\"}\n".utf8))
        }
        process?.terminate()
        process = nil
        stdinHandle = nil
        ready = false
    }

    private func readLine(from handle: FileHandle) -> String? {
        var buffer = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8)?.trimmingCharacters(in: .newlines) }
            buffer.append(chunk)
            if let str = String(data: buffer, encoding: .utf8), str.contains("\n") {
                return str.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces)
            }
        }
    }

    private func canLaunchPython() -> Bool {
        Self.resolvePython() != ""
    }

    private static func resolvePython() -> String {
        let legacyConfigDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/open-wispr")
        for configDir in [Config.configDir, legacyConfigDir] {
            let marker = configDir.appendingPathComponent("parakeet-python.txt")
            if let raw = try? String(contentsOf: marker, encoding: .utf8) {
                let marked = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !marked.isEmpty,
                   FileManager.default.isExecutableFile(atPath: marked),
                   canImportParakeet(python: marked) {
                    return marked
                }
            }

            let venvPython = configDir
                .appendingPathComponent("parakeet-venv/bin/python")
                .path
            if FileManager.default.isExecutableFile(atPath: venvPython),
               canImportParakeet(python: venvPython) {
                return venvPython
            }
        }

        for path in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: path),
               canImportParakeet(python: path) {
                return path
            }
        }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["python3"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !out.isEmpty, canImportParakeet(python: out) { return out }
        return out.isEmpty ? "" : out
    }

    private static func canImportParakeet(python: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = ["-c", "from parakeet_mlx import from_pretrained"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func resolveScriptPath() -> String {
        var candidates = [
            FileManager.default.currentDirectoryPath + "/scripts/parakeet_daemon.py",
        ]
        if let resourcePath = Bundle.main.resourceURL?
            .appendingPathComponent("parakeet_daemon.py").path {
            candidates.insert(resourcePath, at: 0)
        }
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return candidates[0]
    }
}

enum ParakeetError: LocalizedError {
    case pythonMissing
    case startTimeout
    case notRunning
    case encodeFailed
    case noOutput
    case parseFailed
    case workerError(String)

    var errorDescription: String? {
        switch self {
        case .pythonMissing: return "Parakeet not installed — run: ./scripts/install-parakeet.sh"
        case .startTimeout: return "Parakeet daemon failed to start — re-run: ./scripts/install-parakeet.sh"
        case .notRunning: return "Parakeet daemon not running"
        case .encodeFailed: return "Failed to encode Parakeet request"
        case .noOutput: return "Parakeet daemon produced no output"
        case .parseFailed: return "Parakeet response parse failed"
        case .workerError(let m): return "Parakeet: \(m)"
        }
    }
}
