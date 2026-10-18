---
name: spec
description: >
  Turns a feature request or a GitHub/Jira issue in an existing repository into
  an approved SDD spec: dialogue one question at a time, approaches, design in
  sections, then planner cuts it into partitions with owners. Trigger on
  "распиши план по #N", "сделай спеку для фичи", "давай сделаем фичу X",
  "разложи задачу перед кодом", "plan-feature 7", or any request to design a
  multi-partition change before coding. Use before sdd — sdd runs only from a
  spec this skill produced. Not for a brand-new project idea (project-architect)
  and not for one-partition fixes whose issue body is already the spec
  (issue-start).
---

# spec

Turn one feature into a spec that `sdd` can execute: what exists, the
boundary, the decisions, partitions with owners, acceptance. The spec is
written **with** the owner, not for them — every decision in it was either
said by the owner or approved by them.

<HARD-GATE>
Until the owner approves the written spec: no code, no briefs, no worktrees, no
issues in the tracker, no `sdd`. Reading code is allowed and expected.
</HARD-GATE>

## 1. Load the project

- `CLAUDE.md` (and `CLAUDE.local.md`), especially the `## SDD` section: the
  layer table, tracker, `Issue на партию`.
- `.claude/context/STATUS.md` if present.
- The issue: `gh issue view <N>` for `Трекер: github`, the Jira MCP for
  `Трекер: jira <KEY>`. The issue body holds decisions already made — don't
  reopen them.
- No `## SDD` section yet: continue — `sdd` will set it up on its first run.
  For partition owners use the harness agents (`frontend-dev`, `node-dev`,
  `devops-dev`, `test-dev`, `e2e-dev`) and say that the table is provisional.

## 2. Size it, out loud

- **One partition** — the issue body already says what to change, one layer,
  one executor delivery. Say "это одна партия — иду через issue-start" and
  hand over to `issue-start`. Stop here.
- **Feature** — several partitions, or non-trivial decisions. Say "это фича —
  пишу спеку" so the owner can override. Continue.

When in doubt, it's a feature.

## 3. Write back your understanding

A short note: the intended outcome, constraints, success criteria. Separate
**what the owner said** from **what you assume**. Ask the owner to correct it
before going further.

## 4. Questions — one per message

Only questions whose answer changes the design: purpose, boundary, behavior at
the edges, constraints. Prefer multiple choice with your recommendation first.
Don't ask what the code or `CLAUDE.md` already answers — read it.

## 5. Approaches — only for a real fork

If there are two or more viable designs with different costs, present 2–3 with
trade-offs and lead with your recommendation. No fork — skip this step and say
so.

## 6. Design in sections

Present the design section by section, scaled to complexity (a few sentences to
~300 words each): data and contracts, server, client, infra, migration,
testing — whichever apply. Ask after each section; revise until the owner says
it's right.

## 7. Partitions — dispatch planner

```
Agent(subagent_type: "planner", prompt: """
Mode: partitions
Project: <repo path>. Spec being written: <abs path of .sdd/specs/<feature>.md>.
Issue: <ref>. Stack: <summary>.
Agreed design:
<the approved sections, verbatim>
""")
```

Planner returns partitions (id, name, executor, reviewer, depends on), premises
with check commands, the security flag, open questions. Read it critically:
partitions that can't be green alone, owners not in the `## SDD` table, tests
pushed into a trailing partition — send those back or fix them yourself and say
so.

## 8. Assemble the spec — and re-check premises yourself

Fill `~/.claude/skills/sdd/references/spec.md` and write it to
`.sdd/specs/<feature>.md` (or `docs/specs/<date>-<feature>.md` if the
repo already keeps specs there — `sdd` looks in both).

**Before writing, make sure git ignores `.sdd/`** — unless `## SDD` says
`Артефакты SDD: коммитить`. SDD files never go under `.claude/`: Claude Code
asks for permission on every write there. Work repo
(`## SDD` says `рабочий`, or the path is under `~/Job/`) → append to
`.git/info/exclude`, never to `.gitignore`. Pet repo → append to `.gitignore`.
Say what you added. A spec left untracked in a work repo ends up in someone's
`git add .`.

**Run every premise check yourself before writing "Что есть".** Planner's grep
was hours ago, the spec will be executed later still; a stale premise is the
main cause of empty partitions. Write today's date in the section header.

All partitions start as `todo`.

## 9. Owner approval

Give the path and ask the owner to read the spec. Revise on feedback. On
approval:

- `Issue на партию: да` → offer to create one issue per partition in the
  tracker, listing titles. Create them only after an explicit "да" — it is an
  outward action. Write the issue refs into the table.
- Say: «Спека утверждена: <path>. Запускаю `sdd`?»

## Rules

- One question per message.
- The spec is in Russian, like the rest of the SDD artifacts.
- Never dispatch a generic subagent for planning — partitions come from
  `planner`.
- Keep the spec thin: a map for executors, not a line-by-line script. If it is
  longer than the code it describes, cut it.
- The issue body stays the source of decisions; the spec adds the
  implementation layer and links to the issue instead of copying it.
