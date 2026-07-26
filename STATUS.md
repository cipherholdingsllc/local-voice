# Local Voice status

Verified snapshot: 2026-07-25

| Surface | Current state | Evidence |
|---|---|---|
| macOS command center | Implemented | Native SwiftUI window rendered from the real app |
| macOS local speech runtime | Implemented | Persistent Whisper server, Parakeet routing, fallback, latency telemetry |
| macOS product features | Implemented | History, app modes, dictionary, model controls, privacy, settings |
| macOS automated checks | Passing | 108 Swift tests, including live model URL availability |
| macOS release artifact | Passing | Release build and strict local code-signature verification |
| iPhone app | Implemented, simulator and arm64 build verified | Native UI, branded app icon, Apple on-device Speech path |
| iPhone keyboard | Implemented, simulator-verified | Inserts the most recent App Group transcript; no microphone claim |
| Personal Team path | Prepared | Explicit installer disables App Groups and requires caller-supplied team/device IDs |
| Physical iPhone capture | Not yet verified | Requires signing team, device install, permissions, and live speech test |
| Exploit Poker UI integration | Deliberately deferred | Kimi's active Poker redesign remains isolated |

## What remains before calling it production-ready

1. Run a physical iPhone capture and keyboard insertion test.
2. Decide whether the shipping iPhone engine remains Apple Speech or gains a bundled WhisperKit model/profile.
3. Measure cold start, first partial, and finalization latency on the target iPhone.
4. Apply the shared voice contract to Exploit Poker after the Poker redesign is handed back.
5. Complete product signing, release identity, privacy copy, and the selected distribution path.

## Current product boundary

Local Voice owns general dictation, user history, language/model settings, and iPhone distribution. Exploit Poker owns poker-specific interface states and vocabulary. Shared runtime code may serve both, but no transcript history crosses products by default.
