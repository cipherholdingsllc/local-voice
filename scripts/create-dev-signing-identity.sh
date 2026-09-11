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
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "'$CERT_NAME' already exists in the login keychain."
    exit 0
fi

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

security import "$TMPD/lv.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign

echo "Created '$CERT_NAME' in the login keychain."
echo "Future builds keep TCC grants: codesign DR is identifier + cert leaf."
