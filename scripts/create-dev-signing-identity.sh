#!/usr/bin/env bash
#
# Create a self-signed "Local Voice Dev" codesigning identity in the login
# keychain. Ad-hoc builds anchor TCC grants (Accessibility, Input
# Monitoring, Post Event) to the build's cdhash, so every rebuild silently
# loses them. A stable cert keeps grants alive across upgrades.
#
# Safe to re-run: exits early when the identity already exists.
set -euo pipefail

CERT_NAME="Local Voice Dev"
LOGIN_KC="${HOME}/Library/Keychains/login.keychain-db"
HEADLESS_KC="${HOME}/Library/Keychains/local-voice-signing.keychain-db"
# Fixed password: this keychain holds only a self-signed dev identity, and a
# headless session cannot unlock interactively at all.
HEADLESS_PASS="local-voice-dev"

for KC in "$LOGIN_KC" "$HEADLESS_KC"; do
    if security find-certificate -c "$CERT_NAME" "$KC" >/dev/null 2>&1; then
        echo "'$CERT_NAME' already exists in $KC."
        exit 0
    fi
done

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMPD/key.pem" -out "$TMPD/cert.pem" \
    -days 3650 -subj "/CN=$CERT_NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false"

# macOS's `security import` only accepts the legacy PKCS12 profile.
# `-legacy` exists on OpenSSL 3; stock macOS LibreSSL already defaults
# to the compatible format and rejects the flag.
LEGACY_FLAG=""
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then
    LEGACY_FLAG="-legacy"
fi
PASS="local-voice-dev-$$"
# shellcheck disable=SC2086
openssl pkcs12 -export $LEGACY_FLAG -macalg SHA1 \
    -out "$TMPD/lv.p12" -inkey "$TMPD/key.pem" -in "$TMPD/cert.pem" \
    -passout "pass:$PASS"

if security import "$TMPD/lv.p12" -k "$LOGIN_KC" -P "$PASS" \
        -T /usr/bin/codesign 2>/dev/null; then
    echo "Created '$CERT_NAME' in the login keychain."
else
    # SSH/headless sessions cannot unlock the login keychain — fall back to a
    # dedicated signing keychain and add it to the user's search list so
    # codesign can resolve the identity.
    security create-keychain -p "$HEADLESS_PASS" "$HEADLESS_KC"
    security import "$TMPD/lv.p12" -k "$HEADLESS_KC" -P "$PASS" \
        -T /usr/bin/codesign
    security unlock-keychain -p "$HEADLESS_PASS" "$HEADLESS_KC"
    # Never auto-lock: codesign runs unattended during installs.
    security set-keychain-settings "$HEADLESS_KC"
    # Authorize codesign on the key's partition list — without this a
    # headless codesign dies with errSecInternalComponent.
    security set-key-partition-list -S apple-tool:,apple: \
        -s -k "$HEADLESS_PASS" "$HEADLESS_KC" >/dev/null
    EXISTING="$(security list-keychains | tr -d '"' | xargs)"
    # shellcheck disable=SC2086
    security list-keychains -s $EXISTING "$HEADLESS_KC"
    echo "Created '$CERT_NAME' in $HEADLESS_KC (headless fallback)."
fi

echo "Future builds keep TCC grants: codesign DR is identifier + cert leaf."
