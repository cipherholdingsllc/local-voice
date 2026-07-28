#!/usr/bin/env bash
#
# Build, bundle, and install Local Voice into ~/Applications.
#
# This exists because the install step was previously performed by hand, which
# meant every downstream receipt (network isolation, hotkey diagnostics,
# benchmark runs) referenced an artifact nobody could reproduce. Note that
# scripts/install.sh installs the upstream open-wispr Homebrew build and is NOT
# this; scripts/dev.sh still refers to the pre-rebrand binary name.
#
# Usage:
#   ./scripts/install-local-voice.sh              # build, bundle, install
#   ./scripts/install-local-voice.sh --no-build   # bundle + install only
#   ./scripts/install-local-voice.sh --no-launch  # skip relaunch
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

BUILD=1
LAUNCH=1
for arg in "$@"; do
    case "$arg" in
        --no-build) BUILD=0 ;;
        --no-launch) LAUNCH=0 ;;
        *) echo "Unknown option: $arg" >&2; exit 64 ;;
    esac
done

APP_NAME="Local Voice.app"
STAGED="${REPO_ROOT}/${APP_NAME}"
DEST_DIR="${HOME}/Applications"
DEST="${DEST_DIR}/${APP_NAME}"
BINARY="${REPO_ROOT}/.build/release/local-voice"
ARTIFACTS="${HOME}/Artifacts/local-voice"

if [[ $BUILD -eq 1 ]]; then
    echo "==> Building release binary"
    swift build -c release --product local-voice
fi

if [[ ! -x "$BINARY" ]]; then
    echo "Release binary missing at ${BINARY}" >&2
    exit 1
fi

# Capture first, then parse. Piping into `head` under `set -o pipefail`
# SIGPIPEs the producer and fails the script with 141.
STATUS_OUT="$("$BINARY" status)"
VERSION="$(printf '%s\n' "$STATUS_OUT" | awk 'NR==1 {print $3}' | tr -d 'v')"
if [[ -z "$VERSION" ]]; then
    echo "Could not read version from the built binary" >&2
    exit 1
fi
echo "==> Version ${VERSION}"

echo "==> Bundling"
rm -rf "$STAGED"
bash scripts/bundle-app.sh "$BINARY" "$STAGED" "$VERSION"

mkdir -p "$ARTIFACTS" "$DEST_DIR"

# Back up whatever is installed before replacing it, and refuse to continue if
# the backup did not actually land.
if [[ -d "$DEST" ]]; then
    PREV_OUT="$("$DEST/Contents/MacOS/local-voice" status 2>/dev/null || true)"
    PREV="$(printf '%s\n' "$PREV_OUT" | awk 'NR==1 {print $3}' | tr -d 'v')"
    [[ -n "$PREV" ]] || PREV="unknown"
    BACKUP="${ARTIFACTS}/Installed-Local-Voice-v${PREV}-backup.app"
    echo "==> Backing up installed v${PREV} -> ${BACKUP}"
    rm -rf "$BACKUP"
    cp -Rp "$DEST" "$BACKUP"
    if [[ ! -x "${BACKUP}/Contents/MacOS/local-voice" ]]; then
        echo "Backup verification failed; refusing to replace ${DEST}" >&2
        exit 1
    fi
fi

echo "==> Stopping any running instance"
osascript -e 'quit app "Local Voice"' 2>/dev/null || true
sleep 1
pkill -x local-voice 2>/dev/null || true

echo "==> Installing to ${DEST}"
rm -rf "$DEST"
cp -Rp "$STAGED" "$DEST"

# Keep a release artifact alongside the install so the two can be compared.
RELEASE_COPY="${ARTIFACTS}/Local Voice-v${VERSION}.app"
rm -rf "$RELEASE_COPY"
cp -Rp "$STAGED" "$RELEASE_COPY"

INSTALLED_HASH="$(shasum -a 256 "${DEST}/Contents/MacOS/local-voice" | awk '{print $1}')"
ARTIFACT_HASH="$(shasum -a 256 "${RELEASE_COPY}/Contents/MacOS/local-voice" | awk '{print $1}')"

if [[ "$INSTALLED_HASH" != "$ARTIFACT_HASH" ]]; then
    echo "Installed and release-artifact hashes differ" >&2
    echo "  installed: ${INSTALLED_HASH}" >&2
    echo "  artifact:  ${ARTIFACT_HASH}" >&2
    exit 1
fi

echo "==> Verifying signature"
codesign --verify --strict "$DEST"

echo "==> Installed Local Voice v${VERSION}"
echo "    path:   ${DEST}"
echo "    sha256: ${INSTALLED_HASH}"

if [[ $LAUNCH -eq 1 ]]; then
    echo "==> Launching"
    open "$DEST"
fi
