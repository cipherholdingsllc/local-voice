# Local Flow — Build Plan v3 (A+ complete)

Base: `human37/open-wispr` MIT → `projects/cipher-lab/local-flow`

## Status: A+ drivers shipped (2026-07-03)

| # | Feature | Status |
|---|---------|--------|
| 4 | Dual STT (Parakeet + Whisper) | **Shipped** — `STTRouter`, auto by language |
| 6b | Persistent whisper-server | **Shipped** — `WhisperServerPool` port 8177 |
| 8 | Correction learning | **Shipped** — `VocabularyLearner` + learned-vocabulary.json |
| 14 | Latency debug panel | **Shipped** — menu → Latency Debug… |
| 15 | Airplane privacy test | **Shipped** — menu → Run Privacy Self-Test |
| 16 | Guided onboarding | **Shipped** — `OnboardingWizard` first-run |

## Architecture

```
Hotkey (CGEventTap)
  → AudioRecorder (chunks + VAD)
  → STTRouter
       ├─ English/auto → ParakeetDaemon (long-lived Python)
       └─ Multilingual → WhisperServerPool (persistent HTTP)
            └─ fallback → whisper-cli
  → TextPostProcessor
  → OllamaCleanup (per-app profile + vocab + voice commands)
  → TranscriptStore (raw↔polished)
  → TextInserter (paste → unicode fallback)
  → VocabularyLearner (post-insert correction observe)
```

## Parakeet setup (optional, English fast path)

```bash
./scripts/install-parakeet.sh
```

First run downloads ~2.5GB HF model. Daemon: `scripts/parakeet_daemon.py`

## Config keys

`sttEngine`: `auto` | `parakeet` | `whisper`

## Remaining (post-A+)

| Item | Notes |
|------|-------|
| iOS ship | Gated on Apple Developer org — `ios-spike/` ready |
| Parakeet CoreML native | Optional upgrade from Python daemon → `parakeet-coreml-swift` SPM |
| Latency budget proof | Hardware verify on M4 Pro — read Latency Debug panel |

## Stop condition

If streaming + warm cannot hit 1–2s → set `sttEngine: parakeet` and disable streaming chunks.
