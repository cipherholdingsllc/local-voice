#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <APPLE_TEAM_ID> <IPHONE_DEVICE_ID>" >&2
  echo "       $0 --preflight <IPHONE_DEVICE_ID>" >&2
  echo "This installs the standalone recorder with App Groups disabled." >&2
}

MODE="install"
TEAM_ID=""
if [ "$#" -eq 2 ] && [ "$1" = "--preflight" ]; then
  MODE="preflight"
  DEVICE_ID="$2"
elif [ "$#" -eq 2 ]; then
  TEAM_ID="$1"
  DEVICE_ID="$2"
else
  usage
  exit 64
fi

if [ -z "${DEVICE_ID}" ]; then
  echo "IPHONE_DEVICE_ID cannot be empty." >&2
  exit 64
fi

if [ "${MODE}" = "install" ]; then
  case "${TEAM_ID}" in
    ""|*[!A-Z0-9]*)
      echo "APPLE_TEAM_ID must contain only uppercase letters and digits." >&2
      exit 64
      ;;
  esac
  if [ "${#TEAM_ID}" -ne 10 ]; then
    echo "APPLE_TEAM_ID must be the 10-character team identifier from Xcode." >&2
    exit 64
  fi
fi

SPIKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${SPIKE_DIR}/.build/personal-team"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug-iphoneos/LocalVoice.app"

DEVICE_INFO="$(
  xcrun devicectl device info details \
    --device "${DEVICE_ID}" \
    --timeout 5 \
    2>&1 || true
)"
if ! grep -Fq "udid: ${DEVICE_ID}" <<<"${DEVICE_INFO}"; then
  echo "iPhone preflight failed: ${DEVICE_ID} is not a paired physical device." >&2
  echo "Connect and trust the iPhone, then find its ID with:" >&2
  echo "  xcrun xcdevice list" >&2
  exit 69
fi

DEVICE_NAME="$(
  awk -F': ' '/• name:/{print $2; exit}' <<<"${DEVICE_INFO}"
)"
DEVICE_OS="$(
  awk -F': ' '/• osVersionNumber:/{print $2; exit}' <<<"${DEVICE_INFO}"
)"
DEVELOPER_MODE="$(
  awk -F': ' '/• developerModeStatus:/{print $2; exit}' <<<"${DEVICE_INFO}"
)"
SIGNING_IDENTITIES="$(
  security find-identity -v -p codesigning 2>&1 || true
)"
VALID_IDENTITY_COUNT="$(
  awk '/valid identities found/{print $1; exit}' <<<"${SIGNING_IDENTITIES}"
)"
VALID_IDENTITY_COUNT="${VALID_IDENTITY_COUNT:-0}"

echo "Local Voice iPhone preflight"
echo "  Device: ${DEVICE_NAME:-unknown} (${DEVICE_OS:-unknown})"
echo "  Device ID: ${DEVICE_ID}"
echo "  Developer Mode: ${DEVELOPER_MODE:-unknown}"
echo "  Valid signing identities: ${VALID_IDENTITY_COUNT}"

BLOCKERS=0
if [ "${DEVELOPER_MODE}" != "enabled" ]; then
  BLOCKERS=$((BLOCKERS + 1))
  echo
  echo "BLOCKER: Developer Mode is not enabled."
  echo "On the iPhone: Settings → Privacy & Security → Developer Mode."
  echo "Enable it, restart when prompted, then confirm after restart."
fi

if [ "${VALID_IDENTITY_COUNT}" -lt 1 ]; then
  BLOCKERS=$((BLOCKERS + 1))
  echo
  echo "BLOCKER: this Mac has no valid Apple Development signing identity."
  echo "In Xcode: Settings → Accounts → add/select your Apple ID and Personal Team."
  echo "Then use Manage Certificates to create an Apple Development certificate."
fi

if [ "${BLOCKERS}" -gt 0 ]; then
  echo
  echo "Preflight found ${BLOCKERS} blocker(s); no build or install was attempted."
  exit 78
fi

if [ "${MODE}" = "preflight" ]; then
  echo
  echo "Preflight passed. Run the install command with your explicit Apple Team ID."
  exit 0
fi

echo "Building Local Voice for Personal Team ${TEAM_ID}..."
echo "App Group transcript sharing is disabled in this build."

xcodebuild \
  -project "${SPIKE_DIR}/LocalFlow.xcodeproj" \
  -scheme LocalFlow \
  -configuration Debug \
  -destination "id=${DEVICE_ID}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_ENTITLEMENTS= \
  build

if [ ! -d "${APP_PATH}" ]; then
  echo "Signed app was not produced at ${APP_PATH}" >&2
  exit 1
fi

xcrun devicectl device install app \
  --device "${DEVICE_ID}" \
  "${APP_PATH}"

echo "Installed Local Voice on ${DEVICE_ID}."
echo "Open it on the iPhone and grant Microphone and Speech Recognition."
