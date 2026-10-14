---
name: plan-feature
description: "Turn a large GitHub issue into a thin, agent-ready implementation spec in .claude/context/specs/ before coding. Trigger when a big issue needs a plan ('распиши план по #N', 'сделай спеку для задачи', 'plan-feature 7', 'разложи фичу перед кодом') — for chat, sync, auth-shaped work. Skip for small issues whose body is already spec enough. Reads the repo's CLAUDE.md and the issue body."
---

# plan-feature

Convert one substantial issue into a **thin** implementation spec the coding
agent can follow — decisions, module map, progress checklist, open questions.
Not every issue needs this: if the issue body already reads as a spec and the
work is a session or two, skip it and just start.

Use for issues that span multiple sessions or carry non-trivial decisions
(realtime chat, synchronization, auth, offline queue).

## Where the spec lives

`.claude/context/specs/<slug>.md` — agent working memory, typically gitignored.
If a `specs/` convention already exists in the repo, follow it.

Don't duplicate what's already in the issue body verbatim — link to it
(`gh issue view <N>`) and add the layer the issue lacks: the *how*, the module
boundaries, the order of work, the traps.

## Checklist

### 1. Read the inputs

- The issue: `gh issue view <N>` — decisions, acceptance criteria, dependencies.
- `CLAUDE.md` — invariants the plan must respect.
- Existing code in the area, if any — follow current patterns, don't invent parallel ones.

### 2. Write the spec — keep it thin

Sections (drop empty ones):

- **Why** — 1–3 sentences. What the issue delivers.
- **Scope** — in / explicitly out. The "out" prevents scope creep as much as the "in".
- **Approach** — the real content. Which modules/files, which patterns, where the
  boundaries are, the order to build in. Record forks and why this branch was
  taken. A map, not a line-by-line script — if the spec is longer than the code
  it describes, it's too fat.
- **Invariants in play** — which `CLAUDE.md` rules this feature must not break,
  and where they bite.
- **Progress** — checklist; `[x]` only for done-and-verified.
- **Open questions** — surface the unresolved, don't bury it.

### 3. Design for isolation

Break the feature into units with one clear purpose each, communicating through
defined interfaces, testable independently. For each unit: what it does, how it's
used, what it depends on. If a unit needs the whole rest of the system to be
understood, the boundaries are wrong.

### 4. Hand off

Point the coding agent at: the spec, then the issue body. Update the spec's
progress checklist as work lands (via `project-checkpoint` or directly).

## Principles

- **Thin.** A map for an agent, not a contract for a vendor.
- **"Out of scope" is as important as "in scope."**
- **Record why, not just what** — decisions without reasons get re-litigated.
- The issue body stays the source of decisions; the spec adds the implementation layer.
