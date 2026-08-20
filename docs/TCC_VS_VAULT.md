# Local Voice permissions — macOS TCC, not Automic Vault

Automic Vault stores secrets. It cannot grant Local Voice Input Monitoring,
Accessibility, or Microphone. Those grants live only in **System Settings ?
Privacy & Security**, one row per app, one row per code signature.

## Leave these on

- **Automic Vault ? Accessibility** — so Vault can inject / Approve Once.
  If it is already on, leave it. Do not toggle it for Local Voice.
- **Computer / Cursor Computer Use ? Accessibility** — so agents can click
  the Mac. If it is already on, leave it. A Vault Secret Gate for Computer
  is credentials, not TCC.

## Local Voice needs its own rows

Grant these to **Local Voice**, path `~/Applications/Local Voice.app`:

| Pane | Why |
|---|---|
| Input Monitoring | fn listen |
| Accessibility | paste into the focused field |
| Microphone | capture audio |

If a Local Voice row already exists after an ad-hoc rebuild, turn it off,
click minus, then **drag** the Applications copy in. The `+` picker often
ignores ad-hoc apps. Granting `~/Repos/local-voice/Local Voice.app` does
nothing for the running Applications copy.

## Do not

- Toggle Automic Vault or Computer Accessibility off/on as a ritual
- Trust CLI `local-voice status` (that is Terminal's TCC)
- Reinstall / ad-hoc resign after a grant (new CDHash drops the grant)

## Verify

Read `~/.config/local-voice/permission-snapshot.json` from the running GUI
app. Done looks like `inputMonitoring: true`, `accessibility: true`, and a
new row in `~/.config/local-voice/history.json` after that snapshot.
