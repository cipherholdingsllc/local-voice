# Real-Speech Crucible

Operator speech is the source of truth. The synthetic `local-voice benchmark`
gate stays as a regression tool. This corpus answers: **where does information
disappear or become incorrect on Nate's real voice?**

Do not start by installing DeepFilterNet, Silero, RNNoise, or another ASR.

## Layout

| Path | Role |
|---|---|
| `Benchmarks/real-speech-crucible/manifest.json` | Frozen scripts, conditions, critical tokens |
| `~/Artifacts/local-voice/real-speech-crucible/audio/` | Operator WAVs (never git) |
| `~/Artifacts/local-voice/real-speech-crucible/traces/` | Per-run JSON (never git) |

Override with `LOCAL_VOICE_REAL_SPEECH_AUDIO` and `LOCAL_VOICE_REAL_SPEECH_TRACES`.

## Capture

One WAV per item. Same mic, no denoise, no trim, no recapture for a later engine.

```sh
mkdir -p ~/Artifacts/local-voice/real-speech-crucible/audio
local-voice real-speech-crucible status
local-voice real-speech-crucible capture RS-001
```

Read the spoken script out loud under the listed condition, then stop. Repeat
until `status` shows 12 present.

## Baseline (production path only)

```sh
local-voice real-speech-crucible run
```

Each fixture is traced in **production postProcess order**:

AUDIO CAPTURE (RMS / speech-activity gate)
? ENGINE / MODEL / ROUTE (`STTRouter.transcribeInteractive`)
? RAW ASR
? VOCABULARY
? COHESION (fillers, scratch-that)
? NEARBY CONTEXT (manifest names only; live focused-field sampling is off)
? POKER / FIGURE NORMALIZERS
? FINAL TEXT
? TranscriptAcceptanceGate (would live dictation drop this take?)

Ollama is **not** executed. The report names the cleanup route live dictation
would have chosen.

## Challengers (later, same frozen WAVs)

1. conservative adaptive normalization
2. Silero learned VAD
3. hybrid RMS + learned VAD
4. RNNoise
5. DeepFilterNet sandbox if licensing is explicitly cleared
6. alternate-engine rescue routing
7. operator-specific acoustic adaptation

Adopt only when measured operator WER, critical-token recall, quiet/mumbled
recall, false-correction rate, latency, privacy, and maintenance all improve.
