---
name: git-flow
description: "Conventional-commits git flow with emoji, scope splitting and trunk-based branches. Two modes — bootstrap (install a dependency-free sh commit-msg hook that validates and adds the emoji, in any repo) and reference (how to write commits and split them). Trigger when the user wants to set up commit conventions in a new repo ('настрой git-flow', 'поставь хуки коммитов', 'bootstrap git-flow'), asks how to format a commit, or when about to commit in a repo that uses this convention. Reads the project's docs/GIT_FLOW.md if present and defers to it."
---

# git-flow

Reusable trunk-based git flow: short branches off the default branch, frequent
merges, conventional commits with an emoji auto-inserted by a hook, commits split
by scope. Works in any repo — reads the project's own `docs/GIT_FLOW.md` and
`CLAUDE.md` when present and lets them override these defaults.

**First step, always:** if `docs/GIT_FLOW.md` exists, read it — the project's
written rules win over anything here. This skill is the portable default and the
bootstrapper; the repo's doc is the source of truth once it exists.

## Two modes

Decide which the user wants from their phrasing:

- **Bootstrap** — "set up git-flow", "install the hooks", new repo. Go to §Bootstrap.
- **Reference** — "how do I commit this", about to commit, splitting changes. Go to §Commit.

---

## Commit format

```
<type>(<scope>): <subject>
```

The emoji is **not typed by hand** — the `commit-msg` hook prepends it from the
type. Author writes `feat(web): add reactions`, history shows `✨ feat(web): …`.

| Type | Emoji | When |
|---|---|---|
| feat | ✨ | new functionality |
| fix | 🐛 | bug fix |
| refactor | ♻️ | behaviour unchanged |
| perf | ⚡️ | optimization — numbers in body required |
| test | ✅ | tests only |
| docs | 📝 | documentation |
| style | 🎨 | formatting, no logic |
| chore | 🔧 | config, deps |
| ci | 🚀 | pipelines, deploy |
| move | 🚚 | move / rename |
| remove | 🗑️ | deletion |
| wip | 🚧 | unfinished, behind a flag |
| init | 🎉 | repo initialization, once |

**Scope** — the area touched. Read it from the project: typical sets are per-app
(`web`, `server`, `contracts`, `infra`, `docs`). If the project defines a scope
list in `GIT_FLOW.md`, use exactly that.

**Subject** — imperative, English, no trailing period, ≤72 chars. What was done,
not what happened: `fix duplicate messages on reconnect`.

**Body** — required for `perf` (with a measurement), for `fix` when the cause
isn't obvious, and whenever behaviour changes in a non-obvious way. Body answers
*why*, never *what* — the diff shows what.

## Branches

Trunk-based: one long-lived default branch (check which — could be `main` or
`master`, never assume), short branches merged within a day. Unfinished work
lands behind a feature flag.

Branch name: `<type>/<kebab-slug>`, optionally `<type>/<issue>-<slug>` when tied
to an issue. Never commit straight to the default branch.

## Splitting commits by scope

Default: **separate commit per scope**. Contract, server and client changes ride
apart — history stays filterable (`git log --grep "(server)"`).

**Exception — a breaking contract change rides in one commit with its consumers.**
Otherwise the default branch holds states where types don't line up and the
project won't build, and `git bisect` trips on them later.

| Change | How |
|---|---|
| Added an **optional** field | separate |
| Added a **required** field | one commit with consumers |
| Renamed / removed a field | one commit with consumers |
| Change inside one app | one commit, its scope |

Rule of thumb: **after every commit on the default branch the project builds and
tests pass.**

## Commit workflow (reference mode)

1. Read `docs/GIT_FLOW.md` if present — obey its scope list and any overrides.
2. Group the working changes by scope. Decide split vs single per the table above.
3. For each group: stage only its files, commit `<type>(<scope>): <subject>`.
   Do **not** type the emoji — the hook adds it. If there's no hook (not yet
   bootstrapped), prepend the emoji yourself from the table.
4. Never commit to the default branch — branch first if on it.
5. End the commit message with any co-author trailer the project/harness requires.

---

## Bootstrap

Install the convention into a repo so validation and the emoji are automatic.
The hook is a dependency-free POSIX `sh` script: it works the same in JS, Rust,
Python or config-only repos. Ready-made files live in `templates/` next to this
skill — copy them, don't rewrite them, so every repo runs the same hook:

```
templates/
├── .githooks/commit-msg   → <repo>/.githooks/commit-msg   (validation + emoji)
├── .gitflow               → <repo>/.gitflow               (scope list)
└── .gitmessage            → <repo>/.gitmessage            (template for humans)
```

The type → emoji table lives only inside `commit-msg`: validation and emoji come
from the same `case`, so they can't drift. The hook checks: known type, scope
present and (if `.gitflow` lists scopes) in the list, header ≤ 72 chars. Merge,
revert and fixup/squash commits pass through untouched.

1. **Check for an existing hook setup** — husky, lefthook, pre-commit,
   `core.hooksPath`. If the repo already validates commits (e.g. husky +
   commitlint), don't install a second one; align its rules with this skill
   instead.
2. **Copy the templates** to the paths above; `chmod +x .githooks/commit-msg`.
3. **Fill the scope list:** replace `__SCOPES__` in `.gitflow` with
   space-separated scopes — read them from `docs/GIT_FLOW.md`, or derive them
   from the top-level layout (apps/packages/crates) and confirm with the user.
4. **Activate:** `git config core.hooksPath .githooks` and
   `git config commit.template .gitmessage`. This is per clone — in JS repos add
   `"prepare": "git config core.hooksPath .githooks"` to `package.json` so
   `install` does it; in other repos mention the command in the README.
5. If `docs/GIT_FLOW.md` doesn't exist, offer to create it from this skill so the
   repo carries its own source of truth (the doc wins over the skill afterwards).
   If it defines types beyond the table, extend `emoji_for` and `TYPES` in the
   repo's copy of the hook.

Never set the hook globally (`git config --global core.hooksPath`): it would
override the local hooks of every other repo, including work repos with their
own rules.

Verify before declaring done: make a deliberately malformed commit — it must be
rejected; make a valid one — the emoji must appear. Show the user the evidence.

## Principles

- **If a rule can't be enforced by automation, it will be broken.** Either a hook
  enforces it, or it's honestly a recommendation, not a rule.
- The repo's `docs/GIT_FLOW.md` is the source of truth once it exists; this skill
  is the portable seed and the installer.
- A commit is a line in a public changelog (release-please or similar generates
  from it) — phrase it for that reader.
