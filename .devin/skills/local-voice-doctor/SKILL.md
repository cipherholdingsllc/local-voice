---
name: local-voice-doctor
description: Diagnose and fix Local Voice — fn hotkey dead or intermittent, dictation transcribes but never pastes, TCC grants that show ON but the app denies, orphaned whisper-server processes. Works on this Mac or over SSH (ssh macmini).
argument-hint: "[symptom or machine]"
---

Diagnose and repair Local Voice. For the Mac mini, run the same commands through `ssh macmini` (its paths are under `/Users/ciphercowork`, config dir `~/.config/local-voice`).

## Read state first — in this order

1. `cat ~/.config/local-voice/permission-snapshot.json` — the app's own probe, the authoritative per-app grant state:
   - `inputMonitoring` — fn/other hotkeys reach the app (event tap).
   - `accessibility` — app can write text into other apps (primary insert path).
   - `postEvent` — app can synthesize keystrokes (unicode fallback insert).
   - `microphone` — audio capture.
   - `tapAttempted`/`tapStarted`/`hotkeyMonitorReady` — event tap alive.
2. `pgrep -fl local-voice` — app running.
3. `pgrep -fl whisper-server` — should be at most one app-owned process; more = orphans.
4. `"/Users/*/Applications/Local Voice.app/Contents/MacOS/local-voice" status` — run the binary inside the .app to see the app's own TCC state (CLI in a terminal reports the terminal's grants, not the app's).
5. Unified log when needed: `log show --last 10m --predicate 'process == "local-voice"'`.

## Symptom → cause → fix

**Hears you (history grows) but never pastes text.**
`accessibility:false` and/or `postEvent:false`. If System Settings shows the row ON but the probe says false, the grant is bound to a previous build's signature — ad-hoc rebuilds change the cdhash and the old grant silently stops matching. Fix:

```bash
tccutil reset Accessibility com.cipherholdings.localvoice   # single-client reset only, never "reset All"
# System Settings → Privacy & Security → Accessibility → row disappears → "+" → add ~/Applications/Local Voice.app
# (repeat for Post Event if it has a separate row/prompt)
pkill -x local-voice && open ~/Applications/"Local Voice.app"
```

**fn key ignored or intermittent.**
Stale event-tap state: a missed key-up wedges the hold flag and later presses get swallowed. `tapStarted:false` or `hotkeyMonitorReady:false` in the probe confirms. v0.57.16+ self-heals (second physical down flushes the stale gesture; programmatic stops suppress until real release). Older builds: restart the app.

**whisper-server processes accumulate.**
Pre-0.57.16 SIGTERM bypassed AppKit teardown. Kill extras: `pkill -f whisper-server` then relaunch the app (it spawns its own).

**Permissions keep breaking after every rebuild/install.**
The build is ad-hoc signed; each new signature is a new TCC subject. Create the stable identity once per machine and reinstall:

```bash
./scripts/create-dev-signing-identity.sh
./scripts/install-local-voice.sh    # auto-detects "Local Voice Dev"
```

On headless/SSH machines the identity lives in `~/Library/Keychains/local-voice-signing.keychain-db` — unlock it first (`security unlock-keychain`) and the bundle script passes `--keychain` automatically.

**`bundle-app.sh` fails with `KEYCHAIN_ARGS[@]: unbound variable`.**
The `set -u` shell flag treats an empty `KEYCHAIN_ARGS` array as unbound on the `codesign` line. Fix: `scripts/bundle-app.sh` was updated in this branch to `set -eo pipefail`. If you see this on a pre-fix checkout, edit `scripts/bundle-app.sh` line 2 from `set -euo pipefail` to `set -eo pipefail`, or rebase onto this branch.

## Rules

- Never `tccutil reset All`, never sudo, never toggle other apps' rows.
- After any grant change, restart the app and re-read `permission-snapshot.json` — do not trust the Settings UI alone.
- History without insert = permission problem, not a speech problem.
