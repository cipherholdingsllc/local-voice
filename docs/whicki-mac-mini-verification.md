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
- [ ] Confirm the artifact-type picker offers all eight types: **Prompt, Note, Task, Decision, Idea brief, Checklist, Instruction, Skill candidate**.
- [ ] Confirm the engine picker offers **Ollama / Template**; choose **Template** for a deterministic draft (or Ollama to exercise Ollama-if-reachable, falling back to Template otherwise).
- [ ] Tap **Generate** and confirm a draft appears in the editor, labeled "Inferred draft — edit before approving".
- [ ] Edit a line of the draft and confirm the label flips to "Edited".
- [ ] Tap **Save** and confirm "Saved to Artifacts." appears and an **Approve** button is shown.
- [ ] Tap **Approve** and confirm it becomes "Approved" (disabled).
- [ ] Tap **Export** and confirm the contents are copied to the clipboard and the button shows "Exported".

### E. COMPOUND

- [ ] Open the **Artifacts** tab and confirm the new card shows the correct type, an **Approved** tag, an engine tag (Ollama/Template), and an **Edited** tag.
- [ ] On a second generated artifact that is saved but not approved, confirm the card shows a **Draft** tag and a **checkmark-seal Approve** button; approve it there and confirm the tag flips to **Approved**.
- [ ] Paste the exported contents into a text editor.
- [ ] Confirm the Markdown begins with a provenance header including the engine, approval, and edit-state fields:

```markdown
---
source: local-voice://record/<transcript-id>
transcriptId: <transcript-id>
artifactId: <id>
artifactType: prompt
generatedBy: template        # or ollama
approved: true
editedAfterGeneration: true  # false if the draft was exported unedited
generatedAt: <ISO-8601>
exportedAt: <ISO-8601>
---
```

- [ ] On the artifact card, open the **Mark reused** menu, choose **Helpful**, and confirm a "Reuse 1" tag and a "Helpful" tag appear. Repeat with **Edited** or **Rejected** if desired.
- [ ] Confirm `artifacts.json` now carries `reuseEvents` on the artifact and `artifacts-provenance.jsonl` gained a `reuse:<outcome>` line:

```bash
cat ~/.config/local-voice/artifacts.json
tail -n 5 ~/.config/local-voice/artifacts-provenance.jsonl   # expect "export" and "reuse:helpful" actions
```

- [ ] Confirm the files on disk exist:

```bash
ls ~/.config/local-voice/Artifacts/
```

### F. Deletion policy

- [ ] Note the artifact ID of an exported artifact and its `Artifacts/<id>.md` file.
- [ ] In **History**, delete the source transcript via its trash button ("Delete transcript and derived artifacts").
- [ ] Confirm the derived artifacts disappear from the **Artifacts** tab and from `artifacts.json`, and the exported `.md` files are gone:

```bash
ls ~/.config/local-voice/Artifacts/ | grep <artifact-id>   # expect no match
grep <artifact-id> ~/.config/local-voice/artifacts.json    # expect no match
```

- [ ] Confirm `artifacts-provenance.jsonl` still contains the earlier export/reuse lines for the deleted artifact (append-only ledger, not rewritten).
- [ ] Separately, delete an artifact directly from its Artifacts card (trash) and confirm its exported `.md` file is removed too.

## What to report back

- Pass/fail for each of A, B, C, D, E, F.
- Exact macOS version and any permission/TCC issues.
- Contents of `~/.config/local-voice/artifacts.json` after the export test.
- The last lines of `~/.config/local-voice/artifacts-provenance.jsonl` after the reuse and deletion checks.
