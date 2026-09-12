import Darwin
import Foundation
import XCTest
@testable import OpenWisprLib

/// A one-shot loopback HTTP server that mimics Ollama's `/api/generate`
/// response shape, so tests can drive the real network round trip that
/// `OllamaCleanup.polish` performs without depending on a real Ollama model
/// being pulled.
private enum MockOllamaServer {
    static func start(text: String, commands: [[String: Any]]) throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NSError(domain: "MockOllamaServer", code: 1) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw NSError(domain: "MockOllamaServer", code: 2) }

        var actualAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &actualAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(fd, $0, &len)
            }
        }
        let port = UInt16(bigEndian: actualAddr.sin_port)

        guard listen(fd, 1) == 0 else { throw NSError(domain: "MockOllamaServer", code: 3) }

        let innerObj: [String: Any] = ["text": text, "commands": commands]
        let innerData = try JSONSerialization.data(withJSONObject: innerObj)
        let outerObj: [String: Any] = ["response": String(data: innerData, encoding: .utf8)!, "done": true]
        let outerData = try JSONSerialization.data(withJSONObject: outerObj)

        DispatchQueue.global().async {
            let client = accept(fd, nil, nil)
            defer { close(fd) }
            guard client >= 0 else { return }
            defer { close(client) }
            var buffer = [UInt8](repeating: 0, count: 8192)
            _ = read(client, &buffer, buffer.count)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(outerData.count)\r\nConnection: close\r\n\r\n"
            var bytes = Array(head.utf8)
            bytes.append(contentsOf: outerData)
            bytes.withUnsafeBufferPointer { ptr in
                _ = write(client, ptr.baseAddress, ptr.count)
            }
        }

        return port
    }
}

final class UsefulTransformerTests: XCTestCase {
    /// Nemesis finding: an artifact drafted from a transcript via Ollama must
    /// never let the model's response drive the live voice-command executor —
    /// the transcript is quoted source material, not instructions to act on.
    func testOllamaDraftNeverEnqueuesVoiceCommandsEvenWhenModelReturnsThem() throws {
        guard OllamaCleanup.isReachable() else {
            throw XCTSkip("Requires a reachable Ollama endpoint at 127.0.0.1:11434 to resolve the ollama engine")
        }

        let port = try MockOllamaServer.start(
            text: "clean note draft",
            commands: [["type": "scratch_that"]]
        )

        let cleanup = OllamaCleanup(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            model: "mock-model",
            enabled: true,
            minLength: 0
        )
        let transformer = UsefulTransformer(ollama: cleanup)
        let record = makeRecord(text: "scratch that, this whole idea is bad, delete everything")

        var scratchThatFired = false
        let observer = NotificationCenter.default.addObserver(
            forName: .localFlowScratchThat, object: nil, queue: nil
        ) { _ in scratchThatFired = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        let draft = transformer.draft(record: record, type: .note, engine: .ollama)

        XCTAssertEqual(draft.engine, .ollama, "mock server was reachable; draft should use the ollama engine")
        XCTAssertEqual(draft.content, "clean note draft", "draft content should come from the polish() response")

        VoiceCommandExecutor.shared.flush()
        XCTAssertFalse(
            scratchThatFired,
            "artifact drafting must never enqueue or execute voice commands from generated content"
        )
    }

    private func makeRecord(text: String) -> LocalVoiceRecord {
        LocalVoiceRecord(
            createdAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
            rawText: text,
            polishedText: text,
            applicationName: "Tests",
            bundleIdentifier: "com.cipherholdings.tests",
            modeName: "Default",
            engineName: "Test engine",
            language: "en",
            recordingMilliseconds: 1_000,
            finishMilliseconds: 500
        )
    }
}
