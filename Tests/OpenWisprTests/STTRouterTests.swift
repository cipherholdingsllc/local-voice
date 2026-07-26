import Foundation
import XCTest
@testable import OpenWisprLib

final class STTRouterTests: XCTestCase {
    func testAutomaticEnglishPrefersParakeet() throws {
        let parakeet = EngineStub(
            name: "parakeet",
            route: .localProcess,
            transcript: "parakeet"
        )
        let whisper = EngineStub(
            name: "whisper-server",
            route: .localLoopback,
            transcript: "whisper"
        )
        let cli = EngineStub(
            name: "whisper-cli",
            route: .localProcess,
            transcript: "cli"
        )
        let router = makeRouter(
            preferred: .auto,
            parakeet: parakeet,
            whisper: whisper,
            cli: cli
        )

        router.warmup()
        let text = try router.transcribe(audioURL: fixtureURL())

        XCTAssertEqual(text, "parakeet")
        XCTAssertEqual(parakeet.warmupCount, 1)
        XCTAssertEqual(parakeet.transcribeCount, 1)
        XCTAssertEqual(whisper.warmupCount, 0)
        XCTAssertEqual(whisper.transcribeCount, 0)
        XCTAssertEqual(router.activeExecutionRoute(), .localProcess)
    }

    func testAutomaticEnglishWarmsWhisperWhenParakeetIsUnavailable() throws {
        let parakeet = EngineStub(
            name: "parakeet",
            route: .localProcess,
            available: false
        )
        let whisper = EngineStub(
            name: "whisper-server",
            route: .localLoopback,
            transcript: "whisper"
        )
        let router = makeRouter(
            preferred: .auto,
            parakeet: parakeet,
            whisper: whisper
        )

        router.warmup()
        let text = try router.transcribe(audioURL: fixtureURL())

        XCTAssertEqual(text, "whisper")
        XCTAssertEqual(parakeet.warmupCount, 0)
        XCTAssertEqual(whisper.warmupCount, 1)
        XCTAssertEqual(whisper.transcribeCount, 1)
        XCTAssertEqual(router.activeExecutionRoute(), .localLoopback)
    }

    func testParakeetWarmupFailureWarmsWhisperFallback() {
        let parakeet = EngineStub(
            name: "parakeet",
            route: .localProcess,
            warmupError: TestError.expected
        )
        let whisper = EngineStub(
            name: "whisper-server",
            route: .localLoopback
        )
        let router = makeRouter(
            preferred: .auto,
            parakeet: parakeet,
            whisper: whisper
        )

        router.warmup()

        XCTAssertEqual(parakeet.warmupCount, 1)
        XCTAssertEqual(whisper.warmupCount, 1)
    }

    func testParakeetTranscriptionFailureUsesPersistentWhisperBeforeCLI() throws {
        let parakeet = EngineStub(
            name: "parakeet",
            route: .localProcess,
            transcribeError: TestError.expected
        )
        let whisper = EngineStub(
            name: "whisper-server",
            route: .localLoopback,
            modelName: "base.en",
            persistent: true,
            transcript: "persistent whisper"
        )
        let cli = EngineStub(
            name: "whisper-cli",
            route: .localProcess,
            transcript: "one shot"
        )
        let router = makeRouter(
            preferred: .auto,
            parakeet: parakeet,
            whisper: whisper,
            cli: cli
        )

        let text = try router.transcribe(audioURL: fixtureURL())

        XCTAssertEqual(text, "persistent whisper")
        XCTAssertEqual(parakeet.transcribeCount, 1)
        XCTAssertEqual(whisper.transcribeCount, 1)
        XCTAssertEqual(cli.transcribeCount, 0)
        XCTAssertEqual(router.activeEngineName(), "whisper-server")
        XCTAssertEqual(router.activeEngineModelName(), "base.en")
        XCTAssertTrue(router.activeEngineIsPersistent())
        XCTAssertEqual(router.activeExecutionRoute(), .localLoopback)
    }

    func testExplicitWhisperSkipsParakeet() throws {
        let parakeet = EngineStub(
            name: "parakeet",
            route: .localProcess,
            transcript: "parakeet"
        )
        let whisper = EngineStub(
            name: "whisper-server",
            route: .localLoopback,
            transcript: "whisper"
        )
        let router = makeRouter(
            preferred: .whisper,
            parakeet: parakeet,
            whisper: whisper
        )

        router.warmup()
        let text = try router.transcribe(audioURL: fixtureURL())

        XCTAssertEqual(text, "whisper")
        XCTAssertEqual(parakeet.warmupCount, 0)
        XCTAssertEqual(parakeet.transcribeCount, 0)
        XCTAssertEqual(whisper.warmupCount, 1)
        XCTAssertEqual(whisper.transcribeCount, 1)
    }

    func testWhisperFailureFallsBackToCLIAndUpdatesActiveEngine() throws {
        let parakeet = EngineStub(
            name: "parakeet",
            route: .localProcess,
            available: false
        )
        let whisper = EngineStub(
            name: "whisper-server",
            route: .localLoopback,
            transcribeError: TestError.expected
        )
        let cli = EngineStub(
            name: "whisper-cli",
            route: .localProcess,
            transcript: "one shot"
        )
        let router = makeRouter(
            preferred: .auto,
            parakeet: parakeet,
            whisper: whisper,
            cli: cli
        )

        let text = try router.transcribe(audioURL: fixtureURL())

        XCTAssertEqual(text, "one shot")
        XCTAssertEqual(whisper.transcribeCount, 1)
        XCTAssertEqual(cli.transcribeCount, 1)
        XCTAssertEqual(router.activeEngineName(), "whisper-cli")
        XCTAssertEqual(router.activeExecutionRoute(), .localProcess)
    }

    func testPrivacySelfTestReportsLocalRouteWithoutClaimingPacketIsolation() {
        let parakeet = EngineStub(
            name: "parakeet",
            route: .localProcess,
            transcript: ""
        )
        let router = makeRouter(
            preferred: .auto,
            parakeet: parakeet,
            whisper: EngineStub(
                name: "whisper-server",
                route: .localLoopback
            )
        )

        let result = PrivacySelfTest.run(router: router)

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.localEngineAvailable)
        XCTAssertTrue(result.transcriptionSucceeded)
        XCTAssertEqual(result.route, .localProcess)
        XCTAssertFalse(result.packetIsolationVerified)
        XCTAssertTrue(result.message.contains("Packet isolation is a separate release gate"))
    }

    func testPrivacySelfTestReportsActualFallbackRoute() {
        let parakeet = EngineStub(
            name: "parakeet",
            route: .localProcess,
            transcribeError: TestError.expected
        )
        let whisper = EngineStub(
            name: "whisper-server",
            route: .localLoopback,
            transcript: ""
        )
        let router = makeRouter(
            preferred: .auto,
            parakeet: parakeet,
            whisper: whisper
        )

        let result = PrivacySelfTest.run(router: router)

        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.route, .localLoopback)
        XCTAssertTrue(result.message.contains("local loopback"))
    }

    func testShutdownPropagatesToEveryEngine() {
        let parakeet = EngineStub(name: "parakeet", route: .localProcess)
        let whisper = EngineStub(
            name: "whisper-server",
            route: .localLoopback
        )
        let cli = EngineStub(name: "whisper-cli", route: .localProcess)
        let router = makeRouter(
            preferred: .auto,
            parakeet: parakeet,
            whisper: whisper,
            cli: cli
        )

        router.shutdown()

        XCTAssertEqual(parakeet.shutdownCount, 1)
        XCTAssertEqual(whisper.shutdownCount, 1)
        XCTAssertEqual(cli.shutdownCount, 1)
    }

    func testFileWorkerCanPreserveSharedParakeetOnShutdown() {
        let parakeet = EngineStub(
            name: "parakeet",
            route: .localProcess
        )
        let whisper = EngineStub(
            name: "whisper-server",
            route: .localLoopback
        )
        let cli = EngineStub(
            name: "whisper-cli",
            route: .localProcess
        )
        let router = makeRouter(
            preferred: .auto,
            parakeet: parakeet,
            whisper: whisper,
            cli: cli
        )

        router.shutdown(preserveParakeet: true)

        XCTAssertEqual(parakeet.shutdownCount, 0)
        XCTAssertEqual(whisper.shutdownCount, 1)
        XCTAssertEqual(cli.shutdownCount, 1)
    }

    private func makeRouter(
        preferred: STTEngineKind,
        parakeet: EngineStub,
        whisper: EngineStub,
        cli: EngineStub = EngineStub(
            name: "whisper-cli",
            route: .localProcess,
            transcript: "cli"
        )
    ) -> STTRouter {
        STTRouter(
            language: "en",
            preferredEngine: preferred,
            parakeet: parakeet,
            whisper: whisper,
            whisperFallback: cli
        )
    }

    private func fixtureURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("stt-router-test.wav")
    }
}

private enum TestError: Error {
    case expected
}

private final class EngineStub: STTEngine {
    let name: String
    let modelName: String?
    let executionRoute: STTExecutionRoute
    let isPersistent: Bool
    private let available: Bool
    private let transcript: String
    private let warmupError: Error?
    private let transcribeError: Error?

    private(set) var warmupCount = 0
    private(set) var transcribeCount = 0
    private(set) var shutdownCount = 0

    init(
        name: String,
        route: STTExecutionRoute,
        modelName: String? = nil,
        persistent: Bool = false,
        available: Bool = true,
        transcript: String = "",
        warmupError: Error? = nil,
        transcribeError: Error? = nil
    ) {
        self.name = name
        self.modelName = modelName
        self.executionRoute = route
        self.isPersistent = persistent
        self.available = available
        self.transcript = transcript
        self.warmupError = warmupError
        self.transcribeError = transcribeError
    }

    func isAvailable() -> Bool {
        available
    }

    func warmup() throws {
        warmupCount += 1
        if let warmupError { throw warmupError }
    }

    func transcribe(audioURL: URL) throws -> String {
        transcribeCount += 1
        if let transcribeError { throw transcribeError }
        return transcript
    }

    func shutdown() {
        shutdownCount += 1
    }
}
