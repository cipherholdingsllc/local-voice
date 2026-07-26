#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_PNG="${REPO_DIR}/ios-spike/LocalFlowApp/Assets.xcassets/AppIcon.appiconset/LocalVoiceIcon.png"
ICONSET_ROOT="$(mktemp -d /tmp/local-voice-icon.XXXXXX)"
ICONSET_DIR="${ICONSET_ROOT}/LocalVoice.iconset"
trap 'rm -rf "${ICONSET_ROOT}"' EXIT

mkdir -p "$(dirname "${SOURCE_PNG}")"
mkdir -p "${ICONSET_DIR}"

swift "${REPO_DIR}/scripts/generate-app-icon.swift" "${SOURCE_PNG}"

render_icon() {
    local pixels="$1"
    local filename="$2"
    sips -z "${pixels}" "${pixels}" "${SOURCE_PNG}" \
        --out "${ICONSET_DIR}/${filename}" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

iconutil -c icns "${ICONSET_DIR}" -o "${REPO_DIR}/Resources/AppIcon.icns"
echo "Built Local Voice iOS and macOS app icons."
