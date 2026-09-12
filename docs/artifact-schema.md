# Artifact schema

`artifacts.json` stores generated drafts produced by the **Make Useful** layer. It is plain JSON, local-only, and kept next to `history.json` in `~/.config/local-voice/`.

## Record fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Stable artifact identifier. |
| `sourceTranscriptId` | UUID | The `LocalVoiceRecord.id` this artifact was derived from. |
| `type` | String | One of `prompt`, `note`, `task`. |
| `content` | String | The generated, human-editable draft. |
| `generatedAt` | ISO-8601 date | When the artifact was first generated. |
| `approvedAt` | ISO-8601 date? | `null` until the user explicitly approves/saves. |
| `exportedAt` | ISO-8601 date? | `null` until the first export to clipboard or file. |
| `exportCount` | Int | Number of times this artifact has been exported. |

## Provenance

Each artifact belongs to one source transcript. A JSONL sidecar, `artifacts-provenance.jsonl`, appends one line per export with:

```json
{"artifactId":"...","action":"export","at":"2026-09-11T...","format":"markdown"}
```

Exported Markdown files carry a header:

```markdown
---
source: local-voice://record/<sourceTranscriptId>
transcriptId: <sourceTranscriptId>
artifactId: <id>
artifactType: <type>
generatedAt: <ISO-8601>
---
```

## Storage

- `~/.config/local-voice/artifacts.json` — array of artifact records.
- `~/.config/local-voice/Artifacts/` — exported `.md` files.
- `~/.config/local-voice/artifacts-provenance.jsonl` — export log.
