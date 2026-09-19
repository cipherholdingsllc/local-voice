import Foundation
import OpenWisprLib

@main
enum LockedLongDictationProve {
    static func expect(_ cond: Bool, _ message: String) {
        if !cond {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func expectEqual<T: Equatable>(_ got: T, _ want: T, _ label: String) {
        expect(got == want, "\(label)\n  got:  \(got)\n  want: \(want)")
    }

    static func main() {
        expectEqual(
            InferenceTimeout.httpSeconds(durationSeconds: 10),
            120,
            "just-above-chunk takes stay on the historic 120s floor"
        )
        expectEqual(
            InferenceTimeout.httpSeconds(durationSeconds: 88),
            88 * 2.5 + 90,
            "88s take scales past the 120s floor"
        )
        let threeMinute = InferenceTimeout.httpSeconds(durationSeconds: 180)
        expect(threeMinute > 120, "3-minute lock must outrun the 120s HTTP ceiling")
        expectEqual(threeMinute, 180 * 2.5 + 90, "3-minute scale")
        expect(
            InferenceTimeout.cliSeconds(durationSeconds: 180) >= threeMinute,
            "CLI budget must cover a long locked WAV"
        )
        expect(
            InferenceTimeout.httpSeconds(durationSeconds: 2, isChunk: true)
                <= InferenceTimeout.chunkMaximumSeconds,
            "chunk STT cannot occupy the server for the full-file timeout"
        )

        expect(
            InferenceTimeout.shouldRecoverFromEmptyTranscript(
                recordingMilliseconds: 180_000
            ),
            "empty long-form persistent STT must fall through to CLI"
        )
        expect(
            !InferenceTimeout.shouldRecoverFromEmptyTranscript(
                recordingMilliseconds: 88_000
            ),
            "short takes may still return empty"
        )
        expect(
            InferenceTimeout.isTimeout(URLError(.timedOut)),
            "URLSession timedOut is treated as an inference timeout"
        )

        let locked = RecordingSessionPolicy.lockedProfile
        expectEqual(locked, VoiceContractProfileID.generalLongForm, "lock profile")
        expectEqual(
            RecordingSessionPolicy.capSeconds(
                for: locked,
                configuredCapSeconds: 120
            ),
            3_600,
            "lock promotion must not inherit a 2-minute hold cap"
        )
        expectEqual(
            RecordingSessionPolicy.remainingCapSeconds(
                fullCapSeconds: 3_600,
                elapsedSeconds: 125
            ),
            3_475,
            "lock cap is remaining from session start"
        )

        expect(
            LockGesturePolicy.shouldEngageExplicitLock(
                activationMode: .holdAndDoubleTapLock,
                alreadyLocked: false,
                commandDown: true,
                fnJustPressed: true
            ),
            "Command+Fn engages lock"
        )
        expect(
            !LockGesturePolicy.shouldEngageExplicitLock(
                activationMode: .holdAndDoubleTapLock,
                alreadyLocked: false,
                commandDown: true,
                fnJustPressed: false
            ),
            "Command during an Fn hold must not lock"
        )
        expect(
            !LockedDictationFinalization.shouldCommitViaLiveComposer(
                wasLockSession: true,
                hasLiveInsertion: true
            ),
            "locked finalize pastes even if live AX still has a span"
        )

        print("PASS: locked-long-dictation prove")
    }
}
