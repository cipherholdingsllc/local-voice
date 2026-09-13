# Whiski / Local Voice — 5-layer architecture

This is the data-flow architecture for Nate's personal voice-to-capability system, built on top of the existing `local-voice` substrate.

## North Star

Whiski turns dictated speech into compounding capability: every dictation can become a reviewed, reusable artifact (prompt, note, task, decision record, idea brief, checklist, reusable instruction, or skill candidate) that is exported with provenance and reused in future agent sessions. Everything stays local and operator-approved — the machine drafts, the human decides.

## Layers

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER E — COMPOUND                                                         │
│  Reuse approved artifacts in future agent sessions; record the outcome.     │
│  Storage: ~/.config/local-voice/Artifacts/*.md                              │
│             ~/.config/local-voice/artifacts-provenance.jsonl (append-only)  │
│  Surfaces: Artifacts tab · Export writes Markdown + copies to clipboard     │
│            "Mark reused" records manual outcomes (helpful/edited/rejected)  │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │  approve → export(artifact) → .md + provenance
┌──────────────────────────┴──────────────────────────────────────────────────┐
│  LAYER D — MAKE USEFUL                                                      │
│  Transform selected transcripts into editable, reusable artifact drafts.    │
│  Engines: Ollama (if reachable) · deterministic template fallback           │
│  Types: prompt · note · task · decision · ideaBrief · checklist ·           │
│         reusableInstruction · skillCandidate                                │
│  Storage: ~/.config/local-voice/artifacts.json                              │
│  Surfaces: "Make useful" on history cards · MakeUsefulView · Artifacts tab  │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │  record + type + engine → draft → edit → save
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
│  Engines: Parakeet TDT v3 · whisper-server · whisper-cli fallback           │
│  Output: raw/polished text inserted into the frontmost app                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Data flow

1. **SPEAK** captures audio, runs the configured STT route, and returns raw/polished text.
2. The text is inserted into the active app and a `LocalVoiceRecord` is written to **REMEMBER** (`history.json`).
3. **CONNECT** is opt-in and builds deterministic related-thought clusters plus a correction review queue. Corrections require two distinct source records and explicit approval.
4. **MAKE USEFUL** takes a record + artifact type + engine selection and drafts a `LocalVoiceArtifact` via `UsefulTransformer` — Ollama when reachable, otherwise a deterministic template. The draft is editable before saving; saving preserves the machine draft in `generatedContent` and the resolved engine in `engine` (`template` or `ollama`). When the saved `content` differs from `generatedContent`, `userEdited` is true — this is how inferred text is distinguished from operator-approved text.
5. **Approval** is explicit: the Approve control in MakeUsefulView or on an Artifacts card sets `approvedAt`. Cards show Draft/Approved status plus engine, edited, and reuse tags.
6. **COMPOUND** exports an artifact as Markdown to `Artifacts/<artifactId>.md` and copies it to the clipboard, incrementing `exportCount` and appending an `{"action":"export"}` line to `artifacts-provenance.jsonl`. The export header carries `source`, `transcriptId`, `artifactId`, `artifactType`, `generatedBy`, `approved`, `editedAfterGeneration`, `generatedAt`, and `exportedAt`. Approved `skillCandidate` and `reusableInstruction` artifacts additionally support **Install as Skill**: `ArtifactStore.exportSkill` writes `Skills/<slug>/SKILL.md` under the config dir and installs a copy at `~/.config/devin/skills/<slug>/SKILL.md` with `name`/`description` frontmatter and a provenance HTML comment, appending `{"action":"export:skill"}` to the ledger.
7. **Reuse** is recorded manually from the Artifacts card ("Mark reused" → helpful / edited / rejected), appending a `ReuseEvent` to the artifact and a `reuse:<outcome>` line to the provenance ledger.

## Deletion policy

`LocalVoiceStore.delete(recordID:)` removes a transcript and cascades: every artifact derived from it is deleted, including its exported `.md` file under `Artifacts/`. The `artifacts-provenance.jsonl` ledger is append-only and is **not** rewritten — it remains the durable record that an export or reuse event happened, even after the underlying rows are gone. Retention pruning of audio files is governed separately by `RecordingStore`/`maxRecordings`.

## Manual reuse records vs. automatic outcome measurement

`reuseEvents` are **operator-entered signals** — the user reports that an exported artifact was helpful, was edited before reuse, or was rejected. This slice does **not** implement automatic outcome measurement (observing downstream agent sessions, diffing reused text, or timing savings). That instrumentation is deferred; the manual record keeps the loop honest until it exists.

## Storage map

| File | Layer | Purpose |
|------|-------|---------|
| `~/.config/local-voice/history.json` | B | Transcript records. |
| `~/.config/local-voice/connect-decisions.json` | C | Correction evidence and approval/dismissal decisions. |
| `~/.config/local-voice/artifacts.json` | D/E | Generated artifact drafts, approval state, `generatedContent`/`engine`, and `reuseEvents`. |
| `~/.config/local-voice/artifacts-provenance.jsonl` | E | Append-only export/reuse ledger. |
| `~/.config/local-voice/Artifacts/*.md` | E | Exported Markdown artifacts with provenance headers. |
| `~/.config/local-voice/Skills/<slug>/SKILL.md` | E | Canonical installed-skill copy; deleted on artifact delete. |
| `~/.config/devin/skills/<slug>/SKILL.md` | E | Agent-loadable install target; deleted on artifact delete. |
| `~/.config/local-voice/config.json` | A–E | User settings, retention, engine. |

## Staged roadmap

- **Slice 1 — done (this branch):** dictate → history → Make Useful draft (all 8 types) → edit → save → approve → export Markdown+clipboard with provenance header → manual reuse record → transcript-delete cascade.
- **Next:** connect-surface digest — Connect clusters and approved corrections summarized as a reviewable digest.
- **Slice 3 — partial:** SKILL.md export for approved `skillCandidate`/`reusableInstruction` artifacts is implemented (`exportSkill` → `~/.config/devin/skills/`). The Thought Compiler proof receipt lives at `docs/thought-compiler-proof.md`.
- **Then:** sync approved artifacts to the Whiski repo so capability compounds outside this app.

## Nemesis constraints honored

- Every new feature is additive; the existing hold-to-dictate path was not changed.
- `UsefulTransformer` uses Ollama only if reachable; no forced cloud calls.
- Generated artifacts carry provenance headers so their source can always be traced.
- Connect is heuristic and only surfaces overlaps; no assumptions about Nate's intent.
- Reuse measurement is manual and labeled as such; no inferred claims about downstream outcomes.
