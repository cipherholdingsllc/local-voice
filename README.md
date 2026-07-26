# Local Voice

Private, system-wide dictation for macOS with a native iPhone companion. Local Voice is a Cipher Lab product built from the MIT-licensed `open-wispr` lineage and expanded around a shared local speech core.

## Product shape

- **Local Voice** is the general desktop and mobile product: system-wide dictation, history, app-aware modes, vocabulary, model control, and privacy diagnostics.
- **Exploit Poker Voice** is a separate domain surface that consumes the shared voice runtime with poker-specific prompts and latency rules.
- The products share engines and measured telemetry, but they do not share one overloaded GUI or silently cross product data.

## What is implemented

- Native SwiftUI command center with History, Modes, Dictionary, Models, Privacy, and Settings
- Menu-bar push-to-talk with configurable global hotkeys
- Persistent `whisper-server` pool to avoid model reloads between dictations
- Optional Parakeet MLX English fast path with Whisper fallback
- App-aware prompt profiles and secure-field blocking
- Raw/polished output, voice commands, and local vocabulary learning
- Local-only transcript history with explicit retention controls
- Latency breakdown and privacy self-test
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

Grant Microphone, Accessibility, and Input Monitoring when macOS asks. The default hotkey is Globe/Fn.

Useful commands:

```bash
.build/release/local-voice status
.build/release/local-voice set-hotkey rightoption
.build/release/local-voice set-language auto
.build/release/local-voice set-model large-v3-turbo-q5_0
```

Configuration lives at `~/.config/local-voice/config.json`. On first launch, Local Voice migrates a legacy `~/.config/open-wispr/config.json` if present.

### Optional Parakeet fast path

```bash
./scripts/install-parakeet.sh
```

English and automatic-language dictation prefer Parakeet when available and fall back to the persistent Whisper server. Other languages use Whisper.

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
