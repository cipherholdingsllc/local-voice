# Connect decisions schema

Connect intelligence is opt-in and local-only. Derived related-thought clusters are rebuilt from `history.json`; only correction evidence and user decisions persist.

## File

`~/.config/local-voice/connect-decisions.json`

```json
{
  "schemaVersion": 1,
  "candidates": [
    {
      "key": "cipher cough\u001fcipheros",
      "from": "cipher cough",
      "to": "CipherOS",
      "sourceRecordIDs": ["<UUID>", "<UUID>"],
      "firstObservedAt": "<ISO-8601>",
      "lastObservedAt": "<ISO-8601>",
      "status": "pending",
      "decidedAt": null
    }
  ]
}
```

## Rules

- A candidate is visible only after two distinct source record IDs.
- `pending` candidates do not affect dictation.
- `approved` means the pair passed `VocabularyLearner.addReplacement` validation and was written as a user replacement.
- `dismissed` is a tombstone; later observations of the same normalized pair do not reopen it.
- Pending evidence expires with the configured history-retention window.
- Writes are atomic and capped at 500 candidates.
- Transcript text, token indexes, and clusters are not duplicated into this file.
