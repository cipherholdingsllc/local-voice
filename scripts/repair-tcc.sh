#!/usr/bin/env bash
# Operator helper: reveal the Applications copy and open the real privacy panes.
# Drag ~/Applications/Local Voice.app into Input Monitoring and Accessibility.
set -euo pipefail

APP="${HOME}/Applications/Local Voice.app"
if [[ ! -d "$APP" ]]; then
  echo "Local Voice.app is not installed at ${APP}" >&2
  exit 1
fi

open -R "$APP"
open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
sleep 0.4
open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"

cat <<EOF
Drag this copy into Input Monitoring, turn it on, then do the same in Accessibility:

  ${APP}

Do not grant the copy inside Repos/local-voice. Then quit Local Voice from the
menu bar extra and reopen it. Command Center should clear the red shortcut row.
EOF
