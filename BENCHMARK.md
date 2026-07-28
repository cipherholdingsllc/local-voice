# Local Voice benchmark receipt

Measured 2026-07-25 PDT and refreshed 2026-07-28 on the current development Mac with the committed
`local-voice-benchmark.v1` and
`local-voice-long-form-latency.v1` harnesses.

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
| `auto` | Parakeet TDT 0.6b v3 | local process | 2,751 ms | 105.5 ms | 120.3 ms | 0.035x | 6.25% | PASS |
| `whisper base.en` | persistent whisper-server | private loopback | 460 ms | 55.6 ms | 63.3 ms | 0.019x | 9.38% | PASS |
| `whisper large-v3-turbo-q5_0` | persistent whisper-server | private loopback | 1,049 ms | 699.6 ms | 715.4 ms | 0.238x | 7.81% | PASS |

### Long-form finalization

The installed v0.57.1 long-form gate synthesized 147.4 seconds of speech,
warmed Parakeet, and exercised the same adaptive cleanup decision used after
hotkey release. Inference completed in 3,015.9 ms; the fast long-form cleanup
decision completed in 0.023 ms; total finalization was 3,015.9 ms against a
5,000 ms target. The gate passed.

This closes the measured regression shape in which a 119.3-second operator
dictation spent 3,176.2 ms in local inference but another 11,536.9 ms
regenerating the transcript through optional Ollama refinement. Long-form
dictation now preserves Parakeet's punctuated result instead of synchronously
regenerating the entire transcript. Short dictations still use local
refinement when enabled.

The process-warmup figures were measured from fresh benchmark processes, but
operating-system file caches may already have been warm. They are not
post-reboot cold-start claims.

The final installed, ad-hoc-signed v0.57.1 bundle passed the OS-enforced
external-egress gate. In that isolated run, Parakeet completed at 106.6 ms
median / 276.6 ms p95 / 6.25% WER, and persistent Whisper `base.en` completed
at 55.6 ms median / 63.3 ms p95 / 9.38% WER while external outbound IP
connections were denied. An immediate detailed Parakeet rerun returned to
120.3 ms p95, so the isolated tail was not repeatable. The same v2 gate also
passed the installed timestamped file-transcription path. See
[NETWORK_ISOLATION.md](NETWORK_ISOLATION.md).

## Decision

- Automatic English dictation prefers Parakeet: it produced the best WER in
  this corpus while keeping p95 finish latency near 130 ms.
- `base.en` is the default failover: it was the fastest measured engine and
  stays comfortably inside the accuracy gate.
- `large-v3-turbo-q5_0` is an explicit accuracy/multilingual option. It passes
  the latency gate but is not the best everyday choice on this corpus.
- Startup warmup includes a real silent Parakeet inference so the first user
  utterance does not pay an MLX compile-on-first-use penalty.
- Wake recovery re-arms Core Audio and re-runs the selected warm-model route
  away from the main thread after macOS sleep.
- live preview now transcribes bounded incremental PCM chunks with a 250 ms
  boundary overlap; a two-minute fixture schedules 134.75 seconds of preview
  audio rather than about 3,660 seconds of cumulative retranscription

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
- fixture-generation subprocesses have a 15-second deadline, graceful
  termination, and forced-kill escalation so a stuck macOS TTS process cannot
  hang the gate indefinitely
- the privacy self-test now claims only a successful known-local route and
  explicitly leaves packet isolation to a separate release gate

## Limitations

This is a deterministic synthetic regression corpus, not a validated
human-speech performance study. It does not cover:

- the operator's microphone and natural delivery
- accents, background noise, crosstalk, or natural long-form delivery
- cursor insertion across target apps or secure-field behavior
- independent packet capture beyond the OS-enforced process-tree egress gate
- iPhone recognition, first partial, finalization, or keyboard insertion

Run:

```bash
.build/release/local-voice benchmark auto base.en
.build/release/local-voice benchmark whisper base.en
.build/release/local-voice benchmark whisper large-v3-turbo-q5_0
.build/release/local-voice long-form-benchmark auto base.en
```
