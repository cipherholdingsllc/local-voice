# Local Flow / Rekord — Failure Radar + A→A+ Upgrade Ledger
**Receipt:** OzReceipt-LocalWisprFlowClone · **Date:** 2026-07-06 · **Mode:** failure-radar-deep

---

## failure_radar_receipt

```yaml
receipt_id: failure_radar_receipt-local-flow-reliability
actual_risk_score: 11
mode_selected: deep
top_failure_families:
  - F-HOTKEY: fn/double-tap state machine false stops (silence bleed, tap detection)
  - F-HUD: cursor-chase UX breaks trust; operator wants fixed anchor
  - F-LATENCY: subprocess STT cold paths undercut "every time" feel
  - F-CONFIG: stale config.json (silenceTimeout 3) overrides code defaults
  - F-IOS: keyboard/mic split not production-hardened
counter_budget: 12
bug_cognizant_trigger_score: 7
```

### Risk inputs (0–2 each → 11/20)

| Input | Score | Note |
|-------|------:|------|
| Blast radius | 1 | Local app only |
| Irreversibility | 0 | No prod deploy |
| Auth/privacy | 1 | On-device; mic/accessibility |
| Multi-system | 1 | Parakeet Python + whisper-server + Ollama |
| Repeated blocker | 2 | Hold cutoff + lock silence stop — operator reported twice |
| Public surface | 0 | Private |
| Data loss | 1 | Bad inject / clipboard |
| Operator trust | 2 | "Work EVERY TIME" — feel is the product |
| Test gap | 1 | No automated fn/double-tap integration tests |
| Config drift | 2 | User config may still have silenceTimeout |

---

## YBR route

```yaml
selected_route: reliability-first-hotkey-hud-then-rebrand
why_this_route_wins: Core loop verified once; trust breaks on hotkey/HUD — fix before Rekord glass/journal
what_it_avoids: iOS ship, Parakeet CoreML rewrite, cloud auth before PTT is bulletproof
first_safe_action: rebuild with silence-off-in-lock + fixed HUD anchor; operator re-test 3 gestures
approval_level: L2
verification_gate: hold 60s · double-tap lock through 30s silence · double-tap unlock · HUD stays bottom-right
evidence_that_changes_route: [fn still drops while held, double-tap never locks on M4 hardware]
stop_condition: 3 consecutive failed gesture tests on hardware → escalate to dedicated hotkey subagent + CGEventTap logging
next_approval_phrase: "ship Rekord rebrand window"
```

---

## Root cause (your double-tap bug)

**Lock mode was still wired to silence auto-stop (~4s quiet → stop).** That matches "died when I stopped listening" exactly. Lock must end only on **double-tap fn** or **10 min session cap**.

**HUD** was following the cursor every 50ms — now **fixed bottom-right** (draggable if you grab it).

---

## 25 upgrades A → A+

### A+ (must ship for "every time")

| # | Upgrade | Why |
|---|---------|-----|
| A+1 | **Silence OFF in lock mode** | Lock until double-tap — **shipped this pass** |
| A+2 | **Silence OFF in hold mode** | Already shipped prior pass |
| A+3 | **Fixed HUD anchor** (bottom-right) | **shipped this pass** |
| A+4 | **Double-tap unlock while locked** | fn up/up path — **shipped this pass** |
| A+5 | **Hotkey integration test harness** | Log every flagsChanged + state transition to file |
| A+6 | **Config migration** | Strip `silenceTimeoutSeconds` from existing config on load if hold default |
| A+7 | **Lock visual state** | Orange pill + "Locked" — **shipped** |
| A+8 | **Menu: "End locked session"** | Escape hatch if double-tap fails |
| A+9 | **fn flag debounce** | Ignore <80ms spurious fn releases (Apple keyboard) |
| A+10 | **Rebuild + version bump in menu** | Operator knows they're on fixed build |

### A (high leverage)

| # | Upgrade | Why |
|---|---------|-----|
| A11 | HUD anchor picker in settings (4 corners) | User preference without cursor chase |
| A12 | Persist HUD drag position | Drag once, remember |
| A13 | Haptic on lock engage/disengage | macOS NSHapticFeedback |
| A14 | Double-tap timing UI tune slider | 400–700ms window per keyboard |
| A15 | Rekord rebrand + glass tokens | Next product window |
| A16 | Journal vault (local markdown) | Your stated north star |
| A17 | Parakeet CoreML (drop Python daemon) | Cold start + reliability |
| A18 | Settings window (not JSON-only) | Toggle lock/silence/HUD |
| A19 | `.app` bundle + login item | Daily driver |
| A20 | iOS container hardening | App Group + Darwin notify like Murmur |

### B+ (fast polish)

| # | Upgrade | Why |
|---|---------|-----|
| B+21 | Menu bar icon shows lock state | Glanceable |
| B+22 | Earcon distinct for lock vs hold | Audio affordance |
| B+23 | `silenceTimeout` only as optional "smart stop" in lock | Power user, default off |
| B+24 | Latency panel export | Share ms with Ultracode run |
| B+25 | OzReceipt closeout after 3 green gesture tests | Formal verified |

---

## agent-harness-portable

**Not on this checkout** (`feat/footnotes-hero-harness`). For token-min Ultracode run:

- **Stay in `~/CipherCowork/projects/cipher-lab/local-flow`** — don't switch worktrees mid-fix
- **Paste to Opus:** `UPGRADE_LEDGER_A_PLUS.md` + `Sources/OpenWisprLib/CGEventHotkeyManager.swift` + operator repro steps
- **Harness on main** is for multi-agent token routing, not this hotkey bug

---

## Operator: rebuild now

```bash
cd ~/CipherCowork/projects/cipher-lab/local-flow
swift build -c release
# Quit old instance first
.build/release/open-wispr start
```

**Optional:** remove stale silence from config:
```bash
# If you have "silenceTimeoutSeconds": 3 in config, delete that line
open ~/.config/open-wispr/config.json
```

### Test script (3 gestures)

1. **Hold fn 30s** with pauses — must not stop until release  
2. **Double-tap fn** — orange locked pill bottom-right — stay silent 20s — must still record — **double-tap fn** to stop  
3. **HUD** — stays bottom-right while you move mouse  

---

## Ultracode handoff (minimal tokens)

> Fix `CGEventHotkeyManager` holdAndDoubleTapLock if double-tap still fails on M4 fn. Add CGEvent file logger. Add menu "End locked session". No rebrand yet. Verify 3-test script.
