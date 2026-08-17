#!/usr/bin/env bash
# Prove the app bundle Info.plist carries the TCC keys Input Monitoring needs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lv-tcc-plist.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

cat > "$TMP/dummy.c" <<'C'
int main(void) { return 0; }
C
cc -o "$TMP/local-voice" "$TMP/dummy.c"

APP="$TMP/Local Voice.app"
LOCAL_VOICE_CODESIGN_IDENTITY=- \
  bash "$ROOT/scripts/bundle-app.sh" "$TMP/local-voice" "$APP" "0.0.0-prove"

PLIST="$APP/Contents/Info.plist"
fail() { echo "FAIL: $*" >&2; exit 1; }

need_key() {
  local key="$1"
  plutil -extract "$key" raw "$PLIST" >/dev/null 2>&1 \
    || fail "missing Info.plist key $key"
}

need_key NSMicrophoneUsageDescription
need_key NSInputMonitoringUsageDescription
need_key NSAccessibilityUsageDescription
need_key LocalVoiceSigningMode

MODE="$(plutil -extract LocalVoiceSigningMode raw "$PLIST")"
[[ "$MODE" == "adhoc" ]] || fail "LocalVoiceSigningMode expected adhoc, got $MODE"

IM="$(plutil -extract NSInputMonitoringUsageDescription raw "$PLIST")"
[[ "$IM" == *Input\ Monitoring* ]] || fail "usage description does not mention Input Monitoring"

SWIFT="$ROOT/Sources/OpenWisprLib/PrivacySettingsURL.swift"
rg -q 'PrivacySecurity.extension\?Privacy_ListenEvent' "$SWIFT" \
  || fail "PrivacySettingsURL is missing the Sequoia+ Input Monitoring URL"
if rg -n 'candidates\(for pane' -A 12 "$SWIFT" | rg -q 'preference.security\?Privacy_ListenEvent' \
  && ! rg -n 'case .inputMonitoring' -A 3 "$SWIFT" | rg -q 'inputMonitoringModern'; then
  fail "legacy Input Monitoring URL must not be preferred"
fi

echo "PASS: tcc-plist prove"
