# Artifact schema

`artifacts.json` stores generated drafts produced by the **Make Useful** layer. It is plain JSON, local-only, and kept next to `history.json` in `~/.config/local-voice/`.

## Record fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Stable artifact identifier. |
| `sourceTranscriptId` | UUID | The `LocalVoiceRecord.id` this artifact was derived from. |
| `type` | String | One of `prompt`, `note`, `task`, `decision`, `ideaBrief`, `checklist`, `reusableInstruction`, `skillCandidate`. |
| `content` | String | The current operator-facing text — the generated draft, or the approved text after edits. |
| `generatedAt` | ISO-8601 date | When the artifact was first generated. |
| `approvedAt` | ISO-8601 date? | `null` until the user explicitly approves (Approve button in MakeUsefulView or the Artifacts card). |
| `exportedAt` | ISO-8601 date? | `null` until the first export to clipboard or file. |
| `exportCount` | Int | Number of times this artifact has been exported. |
| `engine` | String? | Which engine produced the draft: `"template"` or `"ollama"`. Absent on artifacts saved before this field existed. |
| `generatedContent` | String? | The machine-generated draft before operator edits. When it differs from `content`, the artifact was edited after generation (`userEdited` in code, `editedAfterGeneration` in the export header). |
| `reuseEvents` | Array | Append-only list of manual reuse outcomes: `{id, outcome, note?, at}` where `outcome` is `helpful`, `edited`, or `rejected`. These are operator-entered signals, not automatic outcome measurement. |

## Provenance

Each artifact belongs to one source transcript. A JSONL sidecar, `artifacts-provenance.jsonl`, is append-only: one line per export and one per recorded reuse outcome:

```json
{"artifactId":"...","action":"export","at":"2026-09-11T...","format":"markdown"}
{"artifactId":"...","action":"reuse:helpful","at":"2026-09-12T...","format":"markdown"}
```

Exported Markdown files carry a header:

```markdown
---
source: local-voice://record/<sourceTranscriptId>
transcriptId: <sourceTranscriptId>
artifactId: <id>
artifactType: <type>
generatedBy: <template|ollama|unknown>
approved: <true|false>
editedAfterGeneration: <true|false>
generatedAt: <ISO-8601>
exportedAt: <ISO-8601>
---
```

## Deletion policy

Deleting a source transcript (`LocalVoiceStore.delete(recordID:)`, surfaced as the trash button on a History card) deletes every derived artifact record and its exported `.md` file. Deleting an artifact directly removes its exported `.md` too. `artifacts-provenance.jsonl` is a ledger and is **not** rewritten — export and reuse lines survive the deletion of the rows they describe.

## Storage

- `~/.config/local-voice/artifacts.json` — array of artifact records.
- `~/.config/local-voice/Artifacts/` — exported `.md` files.
- `~/.config/local-voice/artifacts-provenance.jsonl` — append-only export/reuse log.
