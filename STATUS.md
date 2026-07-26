# Local Voice status

Verified snapshot: 2026-07-25

| Surface | Current state | Evidence |
|---|---|---|
| macOS command center | Implemented | Native SwiftUI window rendered from the real app |
| macOS local speech runtime | Implemented | Persistent Whisper server, Parakeet routing, fallback, latency telemetry |
| macOS product features | Implemented | History, file workspace, app modes, dictionary, model controls, privacy, settings |
| macOS file transcription | Passing | Local audio/video queue, timestamped 30-second chunks, cancellation, bounded retention, and TXT/MD/JSON/SRT/VTT exports |
| macOS automated checks | Passing | 140 Swift tests, including file normalization/export, routing failover, canonical voice contracts, bounded subprocesses, benchmark math, cache migration, and live model URL availability |
| macOS release artifact | Passing | Installed v0.52.0, strict local code-signature verification, installed/artifact SHA-256 match |
| macOS shared contract | Passing | Installed runtime pair passes 4 schemas, 6 profiles, 8 fixtures, and 9 negative gates |
| macOS synthetic performance gate | Passing | Installed v0.52.0 Parakeet: 110.9 ms p95 / 6.25% WER; base Whisper: 58.6 ms p95 / 9.38% WER; large turbo baseline: 715 ms p95 / 7.81% WER |
| macOS OS-enforced external-egress gate | Passing | Packaged Parakeet, private-loopback Whisper, and timestamped file transcription pass while external outbound IP is denied |
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

The Local Voice runtime emits only `general.*` contract profiles. Its
default-private history can store canonical v1 request/response receipts; if
local audio retention is explicitly enabled, the v1 receipt is suppressed
rather than falsely claiming that audio was not retained.
