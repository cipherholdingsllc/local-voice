# Local Voice benchmark receipt

Measured 2026-07-25 PDT on the current development Mac with the committed
`local-voice-benchmark.v1` harness.

## Gate

The harness synthesizes eight fixed general, technical, and poker-adjacent
phrases using macOS text-to-speech, converts them to mono signed-16-bit PCM WAV
at 16 kHz, and exercises the real `STTRouter`.

Passing thresholds:

- p95 post-audio transcription finish latency at or below 1,000 ms
- aggregate synthetic word-error rate at or below 15%

## Results

| Preference | Actual engine | Route | Process warmup | Median | p95 | Realtime factor | WER | Gate |
|---|---|---|---:|---:|---:|---:|---:|---|
| `auto` | Parakeet TDT 0.6b v3 | local process | 2,313 ms | 106.7 ms | 131.0 ms | 0.036x | 6.25% | PASS |
| `whisper base.en` | persistent whisper-server | private loopback | 424 ms | 58.7 ms | 64.5 ms | 0.020x | 9.38% | PASS |
| `whisper large-v3-turbo-q5_0` | persistent whisper-server | private loopback | 1,049 ms | 699.6 ms | 715.4 ms | 0.238x | 7.81% | PASS |

The process-warmup figures were measured from fresh benchmark processes, but
operating-system file caches may already have been warm. They are not
post-reboot cold-start claims.

The final installed, ad-hoc-signed v0.50.1 app bundle was rerun through the
automatic gate after packaging with monotonic timing: 1,765.7 ms fresh-process
warmup, 110.3 ms median, 115.7 ms p95, 0.035x realtime factor, 6.25% WER,
Parakeet local-process route, PASS.

## Decision

- Automatic English dictation prefers Parakeet: it produced the best WER in
  this corpus while keeping p95 finish latency near 130 ms.
- `base.en` is the default failover: it was the fastest measured engine and
  stays comfortably inside the accuracy gate.
- `large-v3-turbo-q5_0` is an explicit accuracy/multilingual option. It passes
  the latency gate but is not the best everyday choice on this corpus.
- Startup warmup includes a real silent Parakeet inference so the first user
  utterance does not pay an MLX compile-on-first-use penalty.

## Defects closed by the run

- automatic English failover no longer skips the persistent Whisper server
- failed engines are circuit-broken per router, so the displayed active engine
  follows the route actually used
- Whisper uses a private ephemeral loopback port and never trusts a foreign
  process merely because it answers on a fixed port
- current, legacy OpenWispr, and standard whisper.cpp model caches are all
  discovered
- benchmark processes stop their Parakeet and Whisper children; a post-run
  process check found no orphan speech engines
- the privacy self-test now claims only a successful known-local route and
  explicitly leaves packet isolation to a separate release gate

## Limitations

This is a deterministic synthetic regression corpus, not a validated
human-speech performance study. It does not cover:

- the operator's microphone and natural delivery
- accents, background noise, crosstalk, or long-form dictation
- cursor insertion across target apps or secure-field behavior
- packet-level network isolation
- iPhone recognition, first partial, finalization, or keyboard insertion

Run:

```bash
.build/release/local-voice benchmark auto base.en
.build/release/local-voice benchmark whisper base.en
.build/release/local-voice benchmark whisper large-v3-turbo-q5_0
```
