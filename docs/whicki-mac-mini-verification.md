# Mac mini — Whicki first-slice verification checklist

Run this over `ssh macmini` (or the equivalent SSH alias). All `~/.config/local-voice` paths are relative to the Mac mini user as noted in `local-voice-doctor`.

## Pre-flight

- [ ] You are on the `fix/hold-stale-paste-reliability` branch (or `main` after merge).
- [ ] The repo is at `<repo-path>/local-voice` (adjust the commands below if different).

```bash
cd <repo-path>/local-voice
git log --oneline -5
```

## Build and install

- [ ] Release build completes.

```bash
swift build -c release --product local-voice
```

- [ ] Install/upgrade the `.app` into `~/Applications`.

```bash
./scripts/install-local-voice.sh --no-build --no-launch
# or, if the bundle-app unbound-variable fix is not in this checkout:
#   sed -i '' 's/set -euo pipefail/set -eo pipefail/' scripts/bundle-app.sh
```

## App launch and health

- [ ] Orphaned whisper-server processes are cleared and the app relaunched cleanly.

```bash
pkill -f whisper-server
pkill -x local-voice
sleep 2
open -a "Local Voice"
sleep 3
pgrep -fl local-voice
pgrep -fl whisper-server
```

Expected: one `local-voice` and one `whisper-server`.

- [ ] Permissions snapshot shows all grants `true`.

```bash
cat ~/.config/local-voice/permission-snapshot.json
```

Expected:

```json
{
  "accessibility": true,
  "inputMonitoring": true,
  "microphone": true,
  "postEvent": true,
  "tapStarted": true
}
```

If any are `false`, follow `local-voice-doctor` TCC reset/re-grant steps.

## Acceptance tests

### A. SPEAK → B. REMEMBER

- [ ] Hold `fn`, dictate a clear sentence, release, and confirm it inserts into the active app.
- [ ] Open the Local Voice dashboard and switch to the **History** tab.
- [ ] Type a keyword from the just-dictated sentence into the search field.
- [ ] Confirm the record appears.

### C. CONNECT

- [ ] Confirm **Connect intelligence** is off in Settings and plain dictation is unchanged.
- [ ] Open **Connect** and enable it; confirm the app reloads configuration.
- [ ] Find the record from step A and click the **Find related** (circular-arrows) button.
- [ ] Dictate two thoughts sharing a distinctive phrase; confirm one cluster appears in Connect.
- [ ] Make the same safe field correction in two separate dictations; confirm it appears only after the second source record.
- [ ] Confirm the candidate has not changed Dictionary output before approval.
- [ ] Approve it and confirm a user replacement appears in Dictionary.
- [ ] Dismiss a separate candidate, restart the app, and confirm it remains absent.
- [ ] Inspect `~/.config/local-voice/connect-decisions.json` and confirm schema version 1.

### D. MAKE USEFUL

- [ ] Click the **Make useful** (sparkles) button on the same record.
- [ ] Choose **Prompt** (or Note / Task) and tap **Generate**.
- [ ] Confirm a draft appears in the editor.
- [ ] Tap **Save**, then **Export**.
- [ ] Confirm the contents are copied to the clipboard and the status shows "Exported".

### E. COMPOUND

- [ ] Paste the exported contents into a text editor.
- [ ] Confirm the Markdown begins with a provenance header:

```markdown
---
source: local-voice://record/<transcript-id>
transcriptId: <transcript-id>
artifactId: <id>
artifactType: prompt
generatedAt: <ISO-8601>
exportedAt: <ISO-8601>
---
```

- [ ] Confirm the files on disk exist:

```bash
ls ~/.config/local-voice/Artifacts/
cat ~/.config/local-voice/artifacts.json
tail -n 5 ~/.config/local-voice/artifacts-provenance.jsonl
```

## What to report back

- Pass/fail for each of A, B, C, D, E.
- Exact macOS version and any permission/TCC issues.
- Contents of `~/.config/local-voice/artifacts.json` after the export test.
