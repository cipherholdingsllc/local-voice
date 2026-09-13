# Thought Compiler — first proof receipt

The product thesis in one loop: **a correction made once becomes an approved
capability that measurably improves a later AI task.** This document records
the first honest attempt. No invented metrics — each row names its evidence
class.

## The loop

1. **Correction** — operator dictates a correction or recurring instruction
   ("when I ask for X, I mean Y" / "always end PR bodies with a test plan").
2. **Capability** — History → Make Useful → `reusableInstruction` or
   `skillCandidate` → operator edits draft → **Approve** → **Install as Skill**
   (puzzle button on the artifact card).
3. **Install** — `SKILL.md` lands at `~/.config/devin/skills/<slug>/SKILL.md`
   with a canonical copy at `~/.config/local-voice/Skills/<slug>/SKILL.md`.
   Deleting the artifact removes both.
4. **Later task** — a comparable agent task runs with the skill loadable.
5. **Measurement** — before/after comparison recorded below.

## Evidence ledger — attempt 1 (2026-09-13)

Correction used: *"The product name is Whiski, spelled W-h-i-s-k-i. Never
Whicki or Wiski"* — a real recurring operator correction from the same day's
naming pass.

| Step | Evidence | Class | Result |
|------|----------|-------|--------|
| Correction captured | record `63B3F6D7-53FD-4E38-8A95-ABE6AB3DDA72` appended via `LocalVoiceStore.append` | automated application test (scripted injection, not real speech) | pass |
| Artifact drafted/approved | artifact `80BEA1A0-2503-4CED-AE80-0DD3384D33E0`, type `reusableInstruction`, `isApproved=true` | automated application test | pass |
| SKILL.md installed | `~/.config/devin/skills/whiski-naming/SKILL.md` + canonical `~/.config/local-voice/Skills/whiski-naming/SKILL.md`, frontmatter + provenance verified | automated application test | pass |
| Baseline task (no skill) | fresh agent, naming task → invented **"Murmur"** (wrong name) | automated application test | wrong output, as expected |
| Same task (with skill) | fresh agent, identical task → **"Wispr"** then **"Murmur"** (still wrong) | automated application test | **no difference** |
| Benefit/harm verdict | subagent diagnosis below | automated application test | **not yet demonstrated** |

## What attempt 1 actually showed

The mechanical half of the loop is verified end-to-end: correction → approved
artifact → loadable `SKILL.md` on disk. The propagation half is **not**:
`run_subagent` agents receive no skills index at all (their tool list has no
`skill` tool), so the installed capability could never reach them. The skill
was also installed mid-session, after this session's index was built.

The honest open question is whether the *next* interactive session surfaces
`whiski-naming` — `~/.config/devin/skills/` is a real indexed source (the
`computer` skill entered this session's index from that exact path), so a
fresh session should list it. That is the next measurement.

## Measurement rules

- Same task shape for baseline and treatment; record actual outputs.
- Verdict is one of: **helped** (fewer corrections/edits needed),
  **no difference**, **hurt** (skill caused a wrong action — delete or fix it).
- A single N=1 pass is a signal, not proof. Repeat before claiming validation.
- An A/B harness where the capability cannot reach the agent is not a valid
  treatment arm — check the propagation path first.
