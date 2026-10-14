---
name: issue-start
description: "Begin work on a GitHub issue the right way — read the issue as a spec, create a conventional branch, load project rules, and set up before writing code. Trigger when the user wants to start an issue ('начнём issue N', 'бери issue 7', 'issue-start 7', 'давай делать задачу N', 'приступай к #N'). Reads the repo's CLAUDE.md, docs/ and issue labels to adapt to the project."
---

# issue-start

Set up work on one issue so the actual coding follows the project's rules from the
first line. Generic across repos — everything project-specific is read from the
repo, not hardcoded.

The issue **body is the spec.** In well-run repos it holds decisions with reasons
and acceptance criteria. Read it fully before touching anything.

## Checklist

Create a todo per step and do them in order.

### 1. Load project context

- Read `CLAUDE.md` (root) — invariants, stack, code rules. These are binding.
- Read `docs/GIT_FLOW.md` and `docs/CODE_STYLE.md` if present.
- Read `.claude/context/STATUS.md` if present — current state, gotchas, what not to touch.
- Note the default branch name (`main` vs `master` — check, don't assume).

### 2. Read the issue

```
gh issue view <N>
```

- Absorb the decisions and their reasons — do **not** re-litigate settled choices.
- Note the acceptance criteria (the "готово когда" / "done when" checklist).
  These are what `issue-done` will verify — keep them in view the whole time.
- Note the scope label (`scope:server`, `scope:web`, …) — it drives the branch
  and commit scope.
- Note dependencies ("depends on #X", "wave B"). If a dependency isn't merged,
  surface it — the issue may not be startable yet.

### 3. Isolation decision

- If other work is happening in parallel (other agents, other issues in flight),
  work in an isolated git worktree so changes don't collide.
- Solo and sequential: a normal branch in the working tree is fine.

### 4. Create the branch

Off the default branch, per `GIT_FLOW.md` convention:

```
<type>/<N>-<kebab-slug>      e.g. feat/7-realtime-chat
```

`type` from the issue's `type:` label (feat/fix/chore). Never start work on the
default branch.

### 5. Set expectations, then work

- If the issue is large (many acceptance criteria, non-trivial decisions),
  consider `plan-feature` first to turn it into a spec in `.claude/context/specs/`.
- Follow the project's testing rule. If `CODE_STYLE.md` mandates TDD for
  logic-with-edge-cases (sync, idempotency, auth, queues), **write the failing
  test before the implementation** for those parts. Vend/CRUD can be tested after.
- Honour every invariant from `CLAUDE.md`. If the issue seems to require breaking
  one, stop and raise it — don't silently violate it.
- Work the acceptance criteria one by one; each should end verifiable.

## Handing off to issue-done

When the acceptance criteria are met and the tree is green, `issue-done` handles
commits, PR and the pre-merge checklist. Don't commit ad-hoc here beyond normal
work-in-progress on the branch.

## Principles

- **The issue body is the contract.** Decisions in it were already made with
  reasons — implement them, don't second-guess settled ones.
- **Invariants are non-negotiable.** They're in `CLAUDE.md` because they're
  expensive to add back later.
- Project rules always win over this skill's generic defaults.
