import XCTest
@testable import OpenWisprLib

final class TranscriberTests: XCTestCase {
    func testModelSearchIncludesCurrentLegacyAndWhisperCppCaches() {
        let home = URL(fileURLWithPath: "/tmp/local-voice-home")
        let config = URL(fileURLWithPath: "/tmp/local-voice-config")
        let resources = URL(fileURLWithPath: "/tmp/local-voice-resources")

        let paths = Transcriber.modelSearchPaths(
            modelSize: "base.en",
            homeDirectory: home,
            configDirectory: config,
            resourceDirectory: resources
        )

        XCTAssertTrue(
            paths.contains(
                "/tmp/local-voice-config/models/ggml-base.en.bin"
            )
        )
        XCTAssertTrue(
            paths.contains(
                "/tmp/local-voice-home/.config/open-wispr/models/ggml-base.en.bin"
            )
        )
        XCTAssertTrue(
            paths.contains(
                "/tmp/local-voice-home/.cache/whisper-cpp/ggml-base.en.bin"
            )
        )
        XCTAssertTrue(
            paths.contains(
                "/tmp/local-voice-resources/models/ggml-base.en.bin"
            )
        )
    }


    func testBlankAudioMarker() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers("[BLANK_AUDIO]"), "")
    }

    func testBlankAudioWithWhitespace() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers("  [BLANK_AUDIO]  "), "")
    }

    func testMultipleMarkers() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers("[BLANK_AUDIO] [silence]"), "")
    }

    func testParenthesizedMarker() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers("(BLANK_AUDIO)"), "")
    }

    func testNonSpeechEventMarkers() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers("[Music] [Applause]"), "")
    }

    func testMarkerMixedWithText() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers("hello [BLANK_AUDIO] world"), "hello world")
    }

    func testMarkerAtStartOfText() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers("[BLANK_AUDIO] hello"), "hello")
    }

    func testMarkerAtEndOfText() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers("hello [BLANK_AUDIO]"), "hello")
    }

    func testNormalTextUnchanged() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers("hello world"), "hello world")
    }

    func testEmptyString() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers(""), "")
    }

    func testUnknownBracketsPreserved() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers("see [1] and (later)"), "see [1] and (later)")
    }

    func testKnownMarkerStrippedUnknownPreserved() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers("[BLANK_AUDIO] see [1]"), "see [1]")
    }

    func testMultiWordAudioEventMarkers() {
        XCTAssertEqual(Transcriber.stripWhisperMarkers("[MUSIC PLAYING]"), "")
        XCTAssertEqual(Transcriber.stripWhisperMarkers("(dramatic music)"), "")
        XCTAssertEqual(Transcriber.stripWhisperMarkers("[upbeat music playing]"), "")
        XCTAssertEqual(Transcriber.stripWhisperMarkers("(crowd cheering)"), "")
    }

    func testMultiWordMarkerMixedWithText() {
        XCTAssertEqual(
            Transcriber.stripWhisperMarkers("hello (dramatic music) world"),
            "hello world"
        )
    }

    func testBracketedSpeechWordsPreserved() {
        XCTAssertEqual(
            Transcriber.stripWhisperMarkers("(sound good)"),
            "(sound good)"
        )
        XCTAssertEqual(
            Transcriber.stripWhisperMarkers("note (later)"),
            "note (later)"
        )
    }
}
