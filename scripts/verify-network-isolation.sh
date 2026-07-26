#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="${1:-$REPO_DIR/.build/release/local-voice}"

case "$BINARY" in
  /*) ;;
  *) BINARY="$PWD/${BINARY#./}" ;;
esac

if [ ! -x "$BINARY" ]; then
  echo "Local Voice binary is not executable: $BINARY" >&2
  echo "Build it first or pass the packaged app binary as argument 1." >&2
  exit 2
fi

for dependency in /bin/sh /usr/bin/sandbox-exec /usr/bin/curl /usr/bin/nc /usr/bin/python3; do
  if [ ! -x "$dependency" ]; then
    echo "Required release-gate dependency is unavailable: $dependency" >&2
    exit 2
  fi
done

# This release-test profile permits host-local destinations so the private
# loopback whisper-server can operate, while denying every outbound IP
# connection whose destination is not this Mac. Child speech-engine processes
# inherit the profile.
SANDBOX_PROFILE='(version 1)
(allow default)
(deny network-outbound
  (require-not (remote ip "localhost:*")))'

CANARY_PORT="$(
  /usr/bin/python3 -c \
    'import socket; s=socket.socket(); s.bind(("0.0.0.0", 0)); print(s.getsockname()[1]); s.close()'
)"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    /bin/kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

/usr/bin/python3 -m http.server "$CANARY_PORT" \
  --bind 127.0.0.1 \
  --directory /private/tmp \
  >/dev/null 2>&1 &
SERVER_PID=$!

ready=0
attempt=0
while [ "$attempt" -lt 30 ]; do
  if /usr/bin/curl \
    --noproxy '*' \
    --fail \
    --silent \
    --max-time 1 \
    "http://127.0.0.1:$CANARY_PORT/" \
    >/dev/null; then
    ready=1
    break
  fi
  attempt=$((attempt + 1))
  /bin/sleep 0.1
done

if [ "$ready" -ne 1 ]; then
  echo "The local isolation canary server did not become ready." >&2
  exit 1
fi

# Positive control: the local server must be reachable without the profile.
/usr/bin/curl \
  --noproxy '*' \
  --fail \
  --silent \
  --max-time 2 \
  "http://127.0.0.1:$CANARY_PORT/" \
  >/dev/null

# The profile must preserve loopback.
/usr/bin/sandbox-exec \
  -p "$SANDBOX_PROFILE" \
  /usr/bin/curl \
  --noproxy '*' \
  --fail \
  --silent \
  --max-time 2 \
  "http://127.0.0.1:$CANARY_PORT/" \
  >/dev/null

# An unsandboxed TCP handshake proves the external canary is reachable. No HTTP
# request or application payload is sent. If this control cannot connect, the
# gate stops instead of confusing an offline Mac with policy enforcement.
set +e
/usr/bin/nc -z -w 2 1.1.1.1 443 >/dev/null 2>&1
EXTERNAL_CONTROL_STATUS=$?
set -e

if [ "$EXTERNAL_CONTROL_STATUS" -ne 0 ]; then
  echo "External reachability control failed; isolation policy is unproven." >&2
  exit 2
fi

# The same external TCP handshake must fail under the profile.
set +e
/usr/bin/sandbox-exec \
  -p "$SANDBOX_PROFILE" \
  /bin/sh \
  -c '/usr/bin/nc -z -w 2 1.1.1.1 443' \
  >/dev/null 2>&1
EXTERNAL_SANDBOX_STATUS=$?
set -e

if [ "$EXTERNAL_SANDBOX_STATUS" -eq 0 ]; then
  echo "Isolation canary failed: external outbound traffic was permitted." >&2
  exit 1
fi

cleanup
SERVER_PID=""
trap - EXIT INT TERM
echo "Isolation canary passed: loopback allowed, external outbound denied." >&2

AUTO_REPORT="$(
  /usr/bin/sandbox-exec \
    -p "$SANDBOX_PROFILE" \
    "$BINARY" benchmark auto base.en
)"

WHISPER_REPORT="$(
  /usr/bin/sandbox-exec \
    -p "$SANDBOX_PROFILE" \
    "$BINARY" benchmark whisper base.en
)"

validate_report() {
  report="$1"
  expected_route="$2"
  expected_engine="$3"

  printf '%s' "$report" |
    /usr/bin/python3 -c '
import json
import sys

expected_route = sys.argv[1]
expected_engine = sys.argv[2]
report = json.load(sys.stdin)
aggregate = report.get("aggregate", {})
samples = report.get("samples", [])
routes = [sample.get("route") for sample in samples]
engines = [sample.get("engine") for sample in samples]

if aggregate.get("passed") is not True:
    raise SystemExit("benchmark performance/accuracy gate failed")
if len(samples) != 8:
    raise SystemExit(f"expected 8 samples, received {len(samples)}")
if set(routes) != {expected_route}:
    raise SystemExit(f"unexpected route set: {routes}")
if not all(expected_engine in (engine or "") for engine in engines):
    raise SystemExit(f"unexpected engine set: {engines}")
' "$expected_route" "$expected_engine"
}

validate_report "$AUTO_REPORT" "local_process" "parakeet"
validate_report "$WHISPER_REPORT" "local_loopback" "whisper-server"

{
  printf '%s\n' "$AUTO_REPORT"
  printf '%s\n' "__LOCAL_VOICE_REPORT_BREAK__"
  printf '%s\n' "$WHISPER_REPORT"
} |
  /usr/bin/python3 -c '
import datetime
import json
import sys

auto_raw, whisper_raw = sys.stdin.read().split(
    "\n__LOCAL_VOICE_REPORT_BREAK__\n",
    1,
)
auto = json.loads(auto_raw)
whisper = json.loads(whisper_raw)

def summary(report):
    aggregate = report["aggregate"]
    first = report["samples"][0]
    return {
        "preference": report["enginePreference"],
        "configuredModel": report["configuredModel"],
        "engine": first["engine"],
        "route": first["route"],
        "coldStartMilliseconds": report["coldStartMilliseconds"],
        "medianFinishMilliseconds": aggregate["medianFinishMilliseconds"],
        "p95FinishMilliseconds": aggregate["p95FinishMilliseconds"],
        "meanRealtimeFactor": aggregate["meanRealtimeFactor"],
        "wordErrorRate": aggregate["wordErrorRate"],
        "passed": aggregate["passed"],
    }

receipt = {
    "schemaVersion": "local-voice-network-isolation.v1",
    "generatedAt": datetime.datetime.now(
        datetime.timezone.utc
    ).isoformat().replace("+00:00", "Z"),
    "binary": sys.argv[1],
    "enforcement": {
        "mechanism": "macOS sandbox-exec test profile",
        "loopbackAllowed": True,
        "externalOutboundIPDenied": True,
        "externalReachabilityControl": "TCP handshake to 1.1.1.1:443",
        "externalNetworkProbeUsed": True,
        "externalApplicationPayloadSent": False,
        "childProcessesInheritProfile": True,
    },
    "routes": [summary(auto), summary(whisper)],
    "passed": True,
    "limitations": [
        "sandbox-exec is deprecated and is used only as a repeatable release-test harness, not as product architecture.",
        "The gate denies external outbound IP connections for the tested process tree; it is not a universal packet-capture claim about unrelated OS services.",
        "The reachability control opens one TCP connection to 1.1.1.1:443 before enforcing the profile; it sends no HTTP request or application payload.",
        "The corpus is synthetic and does not test microphone capture, natural speech, cursor insertion, or iPhone behavior.",
    ],
}

json.dump(receipt, sys.stdout, indent=2, sort_keys=True)
sys.stdout.write("\n")
' "$BINARY"
