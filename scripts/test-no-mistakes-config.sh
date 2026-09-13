#!/bin/bash
set -uo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "no-mistakes repo gate config semantic checks"
echo "-------------------------------"

RESULT=$(python3 - <<'PYEOF'
import sys
import glob
import yaml

with open(".no-mistakes.yaml") as f:
    config = yaml.safe_load(f)

checks = []

def check(name, condition):
    checks.append((name, bool(condition)))

check(
    "disable_project_settings is true",
    config.get("disable_project_settings") is True,
)

required_protected_paths = {
    ".github/**",
    ".no-mistakes.yaml",
    "Formula/**",
    "scripts/install.sh",
    "scripts/uninstall.sh",
    "scripts/deploy.sh",
    "scripts/create-dev-signing-identity.sh",
}
protected_paths = set(config.get("protected_paths") or [])
check(
    "protected_paths includes workflows, gate-config, formula, install/uninstall/deploy/signing scripts",
    required_protected_paths <= protected_paths,
)

for pattern in protected_paths:
    check(
        f"protected path pattern resolves to a real repo path: {pattern}",
        len(glob.glob(pattern, recursive=True)) > 0,
    )

auto_fix = config.get("auto_fix") or {}
check("auto_fix.review is 0 (no unattended review auto-fix)", auto_fix.get("review") == 0)
for key in ("rebase", "test", "document", "lint", "ci"):
    value = auto_fix.get(key)
    check(f"auto_fix.{key} is a bounded positive integer", isinstance(value, int) and 0 < value <= 3)

draft_prs = (config.get("providers") or {}).get("github", {}).get("draft_pull_requests")
check("draft pull requests are disabled", draft_prs is False)

for name, ok in checks:
    print(f"{'OK' if ok else 'FAIL'}\t{name}")

sys.exit(0 if all(ok for _, ok in checks) else 1)
PYEOF
)
STATUS=$?

while IFS=$'\t' read -r status name; do
    [ -z "$name" ] && continue
    if [ "$status" = "OK" ]; then
        pass "$name"
    else
        fail "$name"
    fi
done <<< "$RESULT"

if [ "$STATUS" -ne 0 ] && [ "$FAIL" -eq 0 ]; then
    fail "python3/pyyaml semantic check crashed (see output above)"
    echo "$RESULT"
fi

echo ""
echo "-------------------------------"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
