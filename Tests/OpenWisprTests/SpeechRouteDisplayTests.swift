import XCTest
@testable import OpenWisprLib

final class SpeechRouteDisplayTests: XCTestCase {
    func testWhisperServerBaseDoesNotActivateTurboOrParakeet() {
        XCTAssertFalse(
            SpeechRouteDisplay.isFeaturedCardActive(
                title: SpeechRouteDisplay.parakeetTitle,
                engineName: "whisper-server (base.en)",
                selectedModel: "base.en"
            )
        )
        XCTAssertFalse(
            SpeechRouteDisplay.isFeaturedCardActive(
                title: SpeechRouteDisplay.whisperTurboTitle,
                engineName: "whisper-server (base.en)",
                selectedModel: "base.en"
            )
        )
        XCTAssertTrue(
            SpeechRouteDisplay.isFeaturedCardActive(
                title: SpeechRouteDisplay.whisperBaseTitle,
                engineName: "whisper-server (base.en)",
                selectedModel: "base.en"
            )
        )
    }

    func testParakeetEngineActivatesOnlyParakeetCard() {
        XCTAssertTrue(
            SpeechRouteDisplay.isFeaturedCardActive(
                title: SpeechRouteDisplay.parakeetTitle,
                engineName: "parakeet-tdt-0.6b",
                selectedModel: "base.en"
            )
        )
        XCTAssertFalse(
            SpeechRouteDisplay.isFeaturedCardActive(
                title: SpeechRouteDisplay.whisperBaseTitle,
                engineName: "parakeet-tdt-0.6b",
                selectedModel: "base.en"
            )
        )
    }

    func testParakeetProcessUpButUnhealthyIsNotReadyCopy() {
        let detail = SpeechRouteDisplay.parakeetHealthDetail(
            running: true,
            healthy: false
        )
        XCTAssertTrue(detail.contains("Whisper is covering"))
        XCTAssertFalse(detail.hasPrefix("Running. Fast path"))
    }

    func testLastTakeTranscribedOnlyNamesTheEngine() {
        let detail = SpeechRouteDisplay.lastTakeDetail(
            outcome: .transcribedOnly,
            engineName: "whisper-server (base.en)"
        )
        XCTAssertTrue(detail.contains("whisper-server (base.en)"))
        XCTAssertTrue(detail.contains("not the field"))
    }

    func testLastTakeNamesTheDestinationApp() {
        let detail = SpeechRouteDisplay.lastTakeDetail(
            outcome: .insertedViaAccessibility,
            engineName: "parakeet-tdt-0.6b",
            destination: "Ghostty"
        )
        XCTAssertTrue(detail.contains("parakeet-tdt-0.6b"))
        XCTAssertTrue(detail.contains("Ghostty"))
        XCTAssertFalse(detail.contains("the field"))
    }
}
