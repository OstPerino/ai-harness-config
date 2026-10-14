---
name: issue-done
description: "Finish an issue correctly — verify acceptance criteria, run lint/typecheck/test/build green, commit split by scope, open a PR that closes the issue, and give a pre-merge checklist. Trigger when the user says work on an issue is finished ('issue готов', 'issue-done', 'закрываем задачу', 'финалим #N', 'делай PR по задаче'). Reads the repo's CLAUDE.md, docs/GIT_FLOW.md and the issue's acceptance criteria."
---

# issue-done

Bring an issue to a mergeable state. Nothing is "done" until the acceptance
criteria are met with evidence and the checks are green — assertions after
evidence, never before.

## Checklist

Create a todo per step, in order.

### 1. Verify against acceptance criteria

```
gh issue view <N>
```

Go through the issue's "done when" checklist item by item. For each, have concrete
evidence it holds — a passing test, actual output, a manual check. **Do not mark
an item done because the code "should" satisfy it.** If an item can't be verified
yet, it's not done — say so plainly.

### 2. Run the gates and read the output

Run what the project's CI gates on (from `CODE_STYLE.md` / CI config), typically:

- lint / format (`biome`, `eslint`, …)
- typecheck
- tests (the relevant suite)
- build

**Read the actual output.** Green means you saw green. A failing gate means the
issue is not done — fix, don't rationalize. Never claim success you didn't observe.

### 3. Commit, split by scope

Invoke `git-flow` (reference mode) for the exact convention. In short:

- Group changes by scope; separate commit per scope by default.
- **Exception:** a breaking contract change rides in one commit with its consumers,
  so the default branch never holds a non-building state.
- Emoji is inserted by the hook — don't type it (prepend manually only if no hook).
- After each commit, the branch still builds and tests pass.

Reference the issue in the commit where it makes sense (`(#N)`), but the closing
happens via the PR.

### 4. Open the PR

- Push the branch.
- PR title in the same commit convention.
- Body: what changed and why, and **`Closes #N`** so merge closes the issue.
- If the project template asks for it, note which acceptance criteria were verified
  and how.
- Merge strategy per `GIT_FLOW.md` — often a merge commit (not squash) so
  per-scope commits survive for filtering. Don't merge here unless asked; opening
  the PR and running CI is the deliverable.

### 5. Pre-merge checklist (to the user, in chat)

```
✅ Issue #N ready:
- Acceptance criteria: <met / which remain, honestly>
- Gates: lint ✓ typecheck ✓ tests ✓ build ✓  (only ticks you actually saw)
- Commits: <n>, split by scope <list>
- PR: <url>, Closes #N
- Not covered / follow-ups: <anything deferred, with why>
```

If anything is not truly done, say it here rather than implying completion.

## Principles

- **Evidence before assertions.** "Tests pass" means you ran them and read green.
- **Acceptance criteria are the definition of done**, not your sense that it works.
- A red gate is a stop, not a footnote.
- Honest partial-completion beats a false "done" — surface what's left.
