# Local Voice

Private, system-wide dictation for macOS with a native iPhone companion. Local Voice is a Cipher Lab product built from the MIT-licensed `open-wispr` lineage and expanded around a shared local speech core.

## Product shape

- **Local Voice** is the general desktop and mobile product: system-wide dictation, history, app-aware modes, vocabulary, model control, and privacy diagnostics.
- **Exploit Poker Voice** is a separate domain surface that consumes the shared voice runtime with poker-specific prompts and latency rules.
- The products share engines and measured telemetry, but they do not share one overloaded GUI or silently cross product data.

## What is implemented

- Native SwiftUI command center with History, Files, Modes, Dictionary, Models, Privacy, and Settings
- Menu-bar push-to-talk with configurable global hotkeys, live Fn readiness,
  guided permission repair, and an optional Launch at Login control
- Concept C Signal Blades floating state surface with a restrained metallic-
  mint Listening formation, an interlocked Locked seal, distinct
  finishing/error states, and a microphone-free visual QA harness driven by
  the shipping renderer
- Persistent `whisper-server` pool on a private ephemeral loopback port to
  avoid model reloads between dictations
- Automatic Core Audio re-arm and local-model re-warm after system wake
- Optional Parakeet MLX English fast path with Whisper fallback
- Bounded incremental live-preview chunks and an adaptive long-form cleanup
  route that avoids retranscribing cumulative audio or regenerating an entire
  long transcript through Ollama before insertion
- App-aware prompt profiles and secure-field blocking
- Raw/polished output, voice commands, and local vocabulary learning
- Local-only transcript history with explicit retention controls
- Canonical `voice-request.v1` / `voice-response.v1` receipts on default-private
  history records, with one-click JSON copy from the History interface
- Local audio/video file queue with drag-and-drop, bounded four-hour
  processing, timestamped chunks, cancellation, and TXT, Markdown, JSON, SRT,
  and WebVTT exports
- Latency breakdown, repeatable local benchmark, and truthful local-route
  privacy self-test
- First-run permissions and model onboarding
- Native iOS app with Apple on-device speech recognition
- iOS keyboard extension that inserts transcripts completed in the main app
- Reproducible Local Voice app icon and an explicit Personal Team install path

No GPL or AGPL source was copied into this repository. Copyleft projects in the research set were used only as product and UX signal.

## macOS

Requirements: Apple Silicon Mac, macOS 13+, Swift 5.9+, `whisper-cpp`, and `ffmpeg`.

```bash
brew install whisper-cpp ffmpeg
swift build -c release --product local-voice
.build/release/local-voice download-model large-v3-turbo-q5_0
.build/release/local-voice start
```

Grant Microphone, Accessibility, and Input Monitoring when macOS asks. The
default hotkey is Globe/Fn. Local Voice never resets these permissions during
an upgrade. If macOS permission state changes while the app is open, the
hotkey monitor recovers automatically without a restart.

Open the installed `.app` once to start the menu-bar service. Settings includes
an optional **Launch at login** control so the Fn hotkey is ready after future
sign-ins. The Command Center reports Microphone, Fn hotkey, and text-insertion
readiness separately instead of claiming the app is ready when capture is
unavailable.

Local development bundles use ad-hoc signing by default. Release builds should
set `LOCAL_VOICE_CODESIGN_IDENTITY` to an operator-selected stable Apple signing
identity so macOS can preserve its trust decision across binary updates. The
build never searches the Keychain or guesses a signing identity.

Useful commands:

```bash
.build/release/local-voice status
.build/release/local-voice hotkey-diagnose
.build/release/local-voice set-hotkey rightoption
.build/release/local-voice set-language auto
.build/release/local-voice set-model large-v3-turbo-q5_0
.build/release/local-voice benchmark auto base.en
.build/release/local-voice long-form-benchmark auto base.en
.build/release/local-voice pill-preview listening
.build/release/local-voice pill-preview locked
.build/release/local-voice glyph-sheet signal-blades.png 4
.build/release/local-voice contract-fixture
.build/release/local-voice transcribe-file recording.m4a json
```

Build and install the reproducible local app bundle with:

```bash
./scripts/install-local-voice.sh
```

Configuration lives at `~/.config/local-voice/config.json`. On first launch, Local Voice migrates a legacy `~/.config/open-wispr/config.json` if present.
Model discovery also preserves the legacy OpenWispr cache and supports the
standard `~/.cache/whisper-cpp` cache.

### Shared voice contract

Every successfully saved default-private history record carries a canonical
request/response receipt with the selected general-use profile, actual engine
and route, timing, retention, and network-egress facts. Use the braces button
on a History card to copy it, or run `local-voice contract-fixture` to emit a
deterministic pair for cross-repository validation.

Local Voice fails closed if asked to emit the isolated `poker.exploit` profile.
When the operator explicitly enables retained audio, the v1 receipt is
intentionally omitted because that contract version requires
`audioRetained: false`; the app never emits a privacy claim it cannot support.

### File transcription

The Files workspace accepts WAV, AIFF, CAF, MP3, M4A, AAC, FLAC, OGG, WebM,
MP4, MOV, and M4V recordings. FFmpeg converts the selected source into
temporary mono 16 kHz PCM-16 chunks, the existing warm local engine router
transcribes them, and the temporary audio is deleted when processing finishes
or is cancelled. Local Voice does not copy or persist the source path.

Jobs are processed sequentially, bounded to four hours and 8 GB, and retained
under the same local transcript-history preference and retention period as
dictation history. Completed transcripts export as plain text, Markdown, a
machine-readable `local-voice-file-transcript.v1` receipt, SRT, or WebVTT.
Every non-empty timestamped chunk includes its canonical shared voice
request/response receipt.

### Optional Parakeet fast path

```bash
./scripts/install-parakeet.sh
```

English and automatic-language dictation prefer Parakeet when available and fall back to the persistent Whisper server. Other languages use Whisper.

## Performance gate

`local-voice benchmark` generates eight repeatable macOS text-to-speech
fixtures, transcribes them through the selected real engine, and reports
word-error rate, median/p95 finish latency, realtime factor, cold process
warmup, engine, and privacy route as JSON. It exits nonzero when p95 exceeds
1,000 ms or synthetic WER exceeds 15%.

`local-voice long-form-benchmark` reproduces the warm post-release path with a
long synthetic fixture and exits nonzero if total finalization exceeds 5,000
ms or the fixture fails to select the bounded fast long-form route. The JSON
report omits transcript content.

See [BENCHMARK.md](BENCHMARK.md) for the current measured matrix and its
limitations. Synthetic speech is a regression fixture; it is not a substitute
for human-microphone, accent, noise, insertion, or packet-isolation testing.

## Remote-network isolation gate

The packaged speech routes can be rerun under an OS-enforced test profile that
preserves private loopback while denying external outbound IP connectivity:

```bash
./scripts/verify-network-isolation.sh \
  "$HOME/Applications/Local Voice.app/Contents/MacOS/local-voice"
```

The harness proves the policy with positive and negative connectivity controls,
then requires both Parakeet `local_process` and persistent Whisper
`local_loopback` to pass the benchmark. It emits a machine-readable JSON
receipt. See [NETWORK_ISOLATION.md](NETWORK_ISOLATION.md) for evidence and
claim boundaries.

## iPhone

Open [the iOS project](ios-spike/LocalFlow.xcodeproj) in Xcode. The app target performs microphone capture and on-device transcription. The keyboard extension only inserts the most recent finished transcript because iOS does not grant microphone access to keyboard extensions.

See [the iOS implementation notes](ios-spike/README.md) for simulator, device, signing, and distribution details.

## Verification

```bash
SWIFTPM_DISABLE_SANDBOX=1 swift test
swift build -c release --product local-voice
xcodebuild \
  -project ios-spike/LocalFlow.xcodeproj \
  -scheme LocalFlow \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Lineage and license

MIT licensed. The desktop foundation began as a fork of [human37/open-wispr](https://github.com/human37/open-wispr); the current Local Voice product shell, runtime orchestration, mobile app, and Cipher-specific features are maintained here.
