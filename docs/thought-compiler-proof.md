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

## Evidence ledger

| Step | Evidence | Class | Date | Result |
|------|----------|-------|------|--------|
| Correction captured | | human-observed workflow | | |
| Artifact drafted/approved | | human-observed workflow | | |
| SKILL.md installed | | automated application test | | |
| Baseline task (no skill) | | later real-world reuse | | |
| Same task (with skill) | | later real-world reuse | | |
| Benefit/harm verdict | | human judgment | | |

## Measurement rules

- Same task shape for baseline and treatment; record actual outputs.
- Verdict is one of: **helped** (fewer corrections/edits needed),
  **no difference**, **hurt** (skill caused a wrong action — delete or fix it).
- A single N=1 pass is a signal, not proof. Repeat before claiming validation.
