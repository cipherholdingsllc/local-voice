#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <APPLE_TEAM_ID> <IPHONE_DEVICE_ID>" >&2
  echo "This installs the standalone recorder with App Groups disabled." >&2
  exit 64
fi

TEAM_ID="$1"
DEVICE_ID="$2"
SPIKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${SPIKE_DIR}/.build/personal-team"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug-iphoneos/LocalVoice.app"

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
