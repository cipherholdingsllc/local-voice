# Local Voice status

Verified snapshot: 2026-07-25

| Surface | Current state | Evidence |
|---|---|---|
| macOS command center | Implemented | Native SwiftUI window rendered from the real app |
| macOS local speech runtime | Implemented | Persistent Whisper server, Parakeet routing, fallback, latency telemetry |
| macOS product features | Implemented | History, app modes, dictionary, model controls, privacy, settings |
| macOS automated checks | Passing | 122 Swift tests, including routing failover, bounded benchmark subprocesses, benchmark math, cache migration, and live model URL availability |
| macOS release artifact | Passing | Release build and strict local code-signature verification |
| macOS synthetic performance gate | Passing | Final installed v0.50.2 Parakeet: 119.3 ms p95 / 6.25% WER; base Whisper: 66.1 ms p95 / 9.38% WER; large turbo: 715 ms p95 / 7.81% WER |
| macOS OS-enforced external-egress gate | Passing | Packaged Parakeet and private-loopback Whisper both pass while external outbound IP is denied |
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
5. Run an independent packet capture before a broad public privacy claim. The
   OS-enforced process-tree external-egress gate passes; the in-app self-test
   separately proves the actual local route.
6. Complete product signing, release identity, privacy copy, and the selected distribution path.

## Current product boundary

Local Voice owns general dictation, user history, language/model settings, and iPhone distribution. Exploit Poker owns poker-specific interface states and vocabulary. Shared runtime code may serve both, but no transcript history crosses products by default.
