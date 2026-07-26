# Local Voice remote-network isolation receipt

Measured 2026-07-25 PDT against the installed, ad-hoc-signed v0.52.0 bundle:

`/Users/ciphercowork/Applications/Local Voice.app`

## Gate

The release harness runs the real packaged benchmark and every speech-engine
child process under this macOS sandbox test profile:

```scheme
(version 1)
(allow default)
(deny network-outbound
  (require-not (remote ip "localhost:*")))
```

The profile preserves host-local destinations for the private ephemeral
Whisper loopback server while denying outbound IP connections to external
destinations.

Before testing speech, the harness proves its own enforcement:

1. An unsandboxed local HTTP control succeeds on `127.0.0.1`.
2. The same loopback control succeeds under the profile.
3. An unsandboxed TCP handshake to `1.1.1.1:443` succeeds.
4. The same handshake, launched through a child shell under the profile, is
   denied.

The external control sends no HTTP request or application payload. It is
required so an offline Mac cannot be mistaken for successful policy
enforcement.

## Results

| Preference | Actual engine | Route | Warmup | Median | p95 | Realtime factor | WER | Gate |
|---|---|---|---:|---:|---:|---:|---:|---|
| `auto` | Parakeet TDT 0.6b v3 | local process | 1,478.6 ms | 103.2 ms | 110.9 ms | 0.034x | 6.25% | PASS |
| `whisper base.en` | persistent whisper-server | private loopback | 344.2 ms | 52.3 ms | 58.6 ms | 0.018x | 9.38% | PASS |

The gate also verified eight samples per route, a single expected route and
engine for every sample, the existing p95/WER limits, and clean child-process
shutdown.

The v2 gate also generated a bounded 3.5-second AIFF fixture and exercised the
installed `transcribe-file` path under the same external-egress denial. It
produced one timestamped Parakeet segment with a
`local-voice-file-transcript.v1` export and a canonical shared voice receipt.
The receipt contained neither a source path nor retained temporary audio.

Durable JSON receipt:

`/Users/ciphercowork/Artifacts/local-voice/network-isolation-v0.52.0.json`

## Decision

The packaged Local Voice speech paths do not require external IP connectivity
for the tested synthetic workload:

- Parakeet completes through a local child process while external outbound IP
  is denied.
- persistent Whisper completes through its private loopback service while
  external outbound IP is denied.
- FFmpeg normalization and timestamped file transcription complete through the
  local process route while external outbound IP is denied.

This is stronger evidence than checking configuration or observing a local URL.
It is not a universal claim that every unrelated operating-system service is
offline.

## Run

```bash
./scripts/verify-network-isolation.sh \
  "/Users/ciphercowork/Applications/Local Voice.app/Contents/MacOS/local-voice"
```

The command emits a `local-voice-network-isolation.v2` JSON receipt and exits
nonzero if the canary, route, engine, performance, or accuracy gate fails.

## Limitations

- `sandbox-exec` is deprecated. It is used only as a repeatable release-test
  harness, not as shipping product architecture.
- The gate covers the tested Local Voice process tree. An independent packet
  capture remains appropriate before a broad public privacy claim.
- Models and runtime dependencies must already be available locally; downloads
  are outside this gate.
- The corpus is synthetic. It does not test microphone capture, natural speech,
  cursor insertion, or iPhone behavior.
