# Local Voice for iPhone

Native iOS companion for Local Voice. The project includes a containing app for capture/transcription and a custom keyboard for inserting a finished transcript.

## The iOS boundary

Apple does not grant microphone access to custom keyboard extensions, and an extension cannot rely on waking a suspended app to begin recording. The supported flow is:

1. Record in the **Local Voice** app.
2. Transcribe in that app with an on-device engine.
3. Save only the finished text to the shared App Group.
4. Return to the **Local Voice** keyboard and tap **Insert latest transcript**.

| Component | Responsibility | Microphone | Speech engine |
|---|---|---:|---:|
| Local Voice app | Capture, live partials, final transcript, copy/share | Yes | Yes |
| Local Voice keyboard | Preview and insert the last finished transcript | No | No |
| `group.com.cipherholdings.localvoice` | Finished transcript bridge | No | No |

## Current engine

The iPhone app uses Apple's Speech framework with:

- `requiresOnDeviceRecognition = true`
- `supportsOnDeviceRecognition` checked before capture
- partial results for live feedback
- no raw-audio persistence

This is a real local engine, not the old `WhisperKitTranscriberStub`. A bundled WhisperKit implementation remains a valid next engine if device benchmarks show a meaningful accuracy or language advantage.

## Open and build

1. Open `LocalFlow.xcodeproj` in Xcode.
2. Select the `LocalFlow` scheme; the internal scheme name is retained to avoid a destructive project rename.
3. Select an iPhone simulator or your connected iPhone.
4. Set your signing team on both targets.
5. Register `group.com.cipherholdings.localvoice` for both targets.
6. Run the containing app and grant Microphone and Speech Recognition.
7. For the keyboard: Settings → General → Keyboard → Keyboards → Add New Keyboard → Local Voice.

Simulator verification:

```bash
xcodebuild \
  -project LocalFlow.xcodeproj \
  -scheme LocalFlow \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The simulator proves compilation and layout. It does not prove live on-device recognition, App Group signing, or physical keyboard insertion.

## Install and distribution

- **Your own iPhone through Xcode:** no App Review. A free Personal Team build expires quickly and has capability limits.
- **Ad Hoc distribution:** paid Apple Developer membership, registered device IDs, no public App Store review.
- **TestFlight:** paid membership; external testers require beta review.
- **Public App Store:** full App Review.

The full app-plus-keyboard build uses App Groups. The fast Personal Team path
below deliberately omits that capability so the standalone recorder can reach
the phone first. Treat App Group provisioning and keyboard insertion as a
separate physical acceptance gate; use the paid Apple Developer Program for
normal external distribution.

### Fast Personal Team install

The paired iPhone appears in Xcode's destinations list. To install the standalone
recorder before App Group access is available:

```bash
./scripts/install-personal-team.sh APPLE_TEAM_ID IPHONE_DEVICE_ID
```

This explicitly removes App Group entitlements from the signed development
build. Recording, on-device transcription, copy, and share work; keyboard
transcript sharing does not. The script intentionally requires the signing team
and device ID as explicit arguments and never reads credentials.

## Project layout

```text
ios-spike/
├── LocalFlow.xcodeproj/          # internal project name
├── LocalFlowApp/                 # Local Voice containing app
├── LocalFlowKeyboard/            # transcript insertion keyboard
└── Shared/TranscriptBridge.swift # App Group transcript bridge
```

MIT licensed.
