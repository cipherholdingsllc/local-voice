# Local Flow — Local Wispr Clone (Cipher Lab)

> MIT fork of [human37/open-wispr](https://github.com/human37/open-wispr) upgraded to A+ local dictation.

## Status (2026-07-03) — A+ drivers complete

| Phase | Features | State |
|-------|----------|-------|
| P1 Feel | #1 #6 #5 #3 | **verified build** |
| P2 Intelligence | #7 #8 #9 #10 | **shipped** |
| P3 Harden | #11 #12 #13 #14 | **shipped** |
| P4 Ship | #15 #16 | **shipped** |
| A+ gaps | #4 #6b #8 learn #14 panel #15 test #16 wizard | **shipped** |
| P5 iOS | #17-20 | simulator scaffold (`ios-spike/`) |

OzReceipt: `vault-staging/wizardoz/receipts/runs/OzReceipt-LocalWisprFlowClone.md`

## Quick start

```bash
brew install whisper-cpp ffmpeg
cd projects/cipher-lab/local-flow
swift build -c release
.build/release/open-wispr start
```

**Optional English fast path:**
```bash
./scripts/install-parakeet.sh
```
Do not paste comment lines into zsh — run the script alone.

Grant: Microphone · Accessibility · Input Monitoring.

Optional cleanup: `ollama serve`

## Dual STT (#4)

| Language | Engine |
|----------|--------|
| `en` / `auto` | Parakeet TDT-0.6b (if installed) → whisper-server fallback |
| Other | whisper-server (large-v3-turbo recommended) |

Menu shows active engine. Config: `"sttEngine": "auto"|"parakeet"|"whisper"`

## A+ five + drivers

1. Streaming STT + warm whisper-server (persistent model)
2. Ollama cleanup + per-app profiles + voice commands
3. Raw↔polished toggle (⌘T menu)
4. Visible privacy badge + self-test menu item
5. Vocabulary learning from corrections (`~/.config/open-wispr/learned-vocabulary.json`)
6. Latency Debug panel (menu)
7. First-run onboarding wizard

## Menu shortcuts

- **Toggle Raw ↔ Polished** — ⌘T
- **Latency Debug…** — per-stage ms breakdown
- **Run Privacy Self-Test** — verifies local models + offline STT

## Latency

Per-stage timings in stderr + Latency Debug panel.

## iOS (gated)

See `ios-spike/README.md`
