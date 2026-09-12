# Whicki / Local Voice — 5-layer architecture

This is the data-flow architecture for Nate's personal voice-to-capability system, built on top of the existing `local-voice` substrate.

## Layers

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER E — COMPOUND                                                         │
│  Reuse approved artifacts in future agent sessions and measure savings.     │
│  Storage: ~/.config/local-voice/Artifacts/*.md                              │
│             ~/.config/local-voice/artifacts-provenance.jsonl                │
│  Surfaces: Artifacts tab · "Export" copies provenance Markdown to clipboard │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │  export(artifact) → Markdown + provenance header
┌──────────────────────────┴──────────────────────────────────────────────────┐
│  LAYER D — MAKE USEFUL                                                      │
│  Transform selected transcripts into reusable artifacts.                    │
│  Engines: Ollama (if reachable) · deterministic template fallback           │
│  Types: prompt / note / task                                                │
│  Storage: ~/.config/local-voice/artifacts.json                              │
│  Surfaces: "Make useful" action on history cards · MakeUsefulView           │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │  selected record + artifact type → draft → save
┌──────────────────────────┴──────────────────────────────────────────────────┐
│  LAYER C — CONNECT                                                          │
│  Surface related thoughts and recurring patterns across history.            │
│  Deterministic phrase/token index, related clusters, correction review      │
│  Surfaces: Connect dashboard · "Find related" on history cards              │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │  record → LocalVoiceStore.related(to:) → [record]
┌──────────────────────────┴──────────────────────────────────────────────────┐
│  LAYER B — REMEMBER                                                         │
│  Searchable, deletable transcript history with retention controls.          │
│  Storage: ~/.config/local-voice/history.json                                │
│  Surfaces: History tab · search · retention via Settings                    │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │  append(LocalVoiceRecord) · search · delete
┌──────────────────────────┴──────────────────────────────────────────────────┐
│  LAYER A — SPEAK                                                            │
│  Reliable local dictation with transparent engine status.                   │
│  Input: hold fn (or configured key) to talk · release to finish             │
│  Engines: Parakeet TDT v3 · whisper-server · whisper-cli fallback         │
│  Output: raw/polished text inserted into the frontmost app                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Data flow

1. **SPEAK** captures audio, runs the configured STT route, and returns raw/polished text.
2. The text is inserted into the active app and a `LocalVoiceRecord` is written to **REMEMBER** (`history.json`).
3. **CONNECT** is opt-in and builds deterministic related-thought clusters plus a correction review queue. Corrections require two distinct source records and explicit approval.
4. **MAKE USEFUL** takes a record + artifact type and, using Ollama if present or a deterministic template, drafts a `LocalVoiceArtifact`.
5. **COMPOUND** exports approved artifacts as Markdown with a provenance header and copies them to the clipboard, incrementing `exportCount` and appending to `artifacts-provenance.jsonl`.

## Storage map

| File | Layer | Purpose |
|------|-------|---------|
| `~/.config/local-voice/history.json` | B | Transcript records. |
| `~/.config/local-voice/connect-decisions.json` | C | Correction evidence and approval/dismissal decisions. |
| `~/.config/local-voice/artifacts.json` | D/E | Generated artifact drafts. |
| `~/.config/local-voice/artifacts-provenance.jsonl` | E | Append-only export log. |
| `~/.config/local-voice/Artifacts/*.md` | E | Exported Markdown artifacts. |
| `~/.config/local-voice/config.json` | A–E | User settings, retention, engine. |

## Nemesis constraints honored

- Every new feature is additive; the existing hold-to-dictate path was not changed.
- `UsefulTransformer` uses Ollama only if reachable; no forced cloud calls.
- Generated artifacts carry provenance headers so their source can always be traced.
- Connect is heuristic and only surfaces overlaps; no assumptions about Nate's intent.
