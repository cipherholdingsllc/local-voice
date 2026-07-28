# Local Voice status

Verified snapshot: 2026-07-28

| Surface | Current state | Evidence |
|---|---|---|
| macOS command center | Implemented | Native SwiftUI window rendered from the real app |
| macOS local speech runtime | Implemented | Persistent Whisper server, Parakeet routing, fallback, latency telemetry |
| macOS product features | Implemented | History, file workspace, app modes, dictionary, model controls, privacy, settings |
| macOS floating state surface | Passing | Installed v0.54.0 Voice Aperture Listening and Locked voice-seal states rendered through the microphone-free preview harness and were visually inspected |
| macOS file transcription | Passing | Local audio/video queue, timestamped 30-second chunks, cancellation, bounded retention, and TXT/MD/JSON/SRT/VTT exports |
| macOS Fn hotkey | Automated pass; physical confirmation pending | Installed v0.54.0 stays alive after a normal app open; the microphone-free `local-voice-hotkey-diagnostic.v1` probe observed exactly one Fn down and one Fn up through the real event tap |
| macOS permission recovery | Passing | Upgrades no longer reset Accessibility, startup no longer blocks silently, Input Monitoring/Accessibility/Microphone are reported separately, and permission changes rebuild the hotkey monitor without restart |
| macOS automated checks | Passing | 164 Swift tests, including state-glyph geometry, bounded incremental preview audio, long-form cleanup routing, app-launch resolution, permission readiness, file normalization/export, routing failover, canonical voice contracts, bounded subprocesses, benchmark math, cache migration, and live model URL availability |
| macOS release artifact | Passing | Installed v0.54.0, strict local code-signature verification, installed/artifact SHA-256 match (`eb949770e3df9830def4229e0b04cfa3febf295ee47782dc172d7d4f00c69669`) |
| macOS shared contract | Passing | Installed runtime pair passes 4 schemas, 6 profiles, 8 fixtures, and 9 negative gates |
| macOS synthetic performance gate | Passing | Installed v0.54.0 Parakeet: 111.5 ms p95 / 6.25% WER; base Whisper: 63.1 ms p95 / 9.38% WER; large turbo baseline remains 715 ms p95 / 7.81% WER |
| macOS long-form finalization | Passing synthetic gate | Installed v0.54.0 finalized a 147.4-second synthetic fixture in 2,016.3 ms total; adaptive cleanup used 0.017 ms and the JSON report omitted transcript content |
| macOS OS-enforced external-egress gate | Passing | Packaged Parakeet, private-loopback Whisper, and timestamped file transcription pass while external outbound IP is denied |
| macOS Launch at Login | Implemented, operator-controlled | Native Service Management toggle is present in Settings; it is off by default and was not enabled during verification |
| iPhone app | Implemented, simulator and arm64 build verified | Native UI, branded app icon, Apple on-device Speech path |
| iPhone keyboard | Implemented, simulator-verified | Inserts the most recent App Group transcript; no microphone claim |
| Personal Team path | Prepared | Explicit installer disables App Groups and requires caller-supplied team/device IDs |
| Physical iPhone capture | Not yet verified | Requires signing team, device install, permissions, and live speech test |
| Exploit Poker UI integration | Deliberately deferred | Kimi's active Poker redesign remains isolated |

## What remains before calling it production-ready

1. Run a physical iPhone capture and keyboard insertion test.
2. Physically confirm Fn hold, release, double-tap lock, and cursor insertion
   with the installed v0.54.0 bundle.
3. Decide whether the shipping iPhone engine remains Apple Speech or gains a bundled WhisperKit model/profile.
4. Measure cold start, first partial, and finalization latency on the target iPhone.
5. Apply the shared voice contract to Exploit Poker after the Poker redesign is handed back.
6. Run an independent packet capture before a broad public privacy claim. The
   OS-enforced process-tree external-egress gate passes; the in-app self-test
   separately proves the actual local route.
7. Complete product signing, release identity, privacy copy, and the selected distribution path.
8. Select a stable macOS Apple signing identity for release upgrades; local
   development bundles remain ad-hoc signed unless the operator supplies one.

## Current product boundary

Local Voice owns general dictation, user history, language/model settings, and iPhone distribution. Exploit Poker owns poker-specific interface states and vocabulary. Shared runtime code may serve both, but no transcript history crosses products by default.

The Local Voice runtime emits only `general.*` contract profiles. Its
default-private history can store canonical v1 request/response receipts; if
local audio retention is explicitly enabled, the v1 receipt is suppressed
rather than falsely claiming that audio was not retained.
