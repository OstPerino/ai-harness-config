---
name: learn
description: >
  Turns a non-obvious finding from the current session into a rule in the
  harness repo (agent, skill or global rules) after the owner approves the
  exact text. Manual only: /learn [finding].
disable-model-invocation: true
argument-hint: "[finding]"
---

# learn

Move one finding from this session into the harness repo under git, so it
survives `/clear` and reaches every future session. Talk to the owner in Russian.

## When it applies

Only when the owner types `/learn`, with or without text.

## Steps

### 1. Pick the finding

- Text after `/learn` (`$ARGUMENTS`) is the finding.
- No text: take the single most valuable non-obvious thing from this session.
  Several candidates — list them in one line each and ask which one.
- Reject and say why: typos, plain syntax, one-off failures (a service was
  down), anything a model already knows without being told.

### 2. Locate the harness repo

```sh
home="${CLAUDE_HOME:-$HOME/.claude}"
target=$(readlink "$home/CLAUDE.md")
repo=$(dirname "$(dirname "$target")")
test -d "$repo/claude" && test -f "$repo/tests/lint-harness.sh" && echo "$repo"
```

Empty `target` (not a symlink) or a failed check — stop and tell the owner.
Never fall back to writing under `~/.claude`. Shell variables do not survive
between Bash calls: write the printed absolute path literally as `<repo>` in
every later command.

### 3. Search for a duplicate

`git -C <repo> grep -n -i -E '<kw1>|<kw2>' -- claude` with two or three
keywords of the finding (the command, flag or error text, not generic words).
On a hit show `file:line` with the line and offer one of: keep as is, widen the
wording in place, or move it up (a rule in one agent that applies to every role
goes to `claude/CLAUDE.md`). A move is one change across two files: add in the
new place, remove the old line.

### 4. Choose one place

| scope of the finding | destination |
|---|---|
| every agent and session | `claude/CLAUDE.md` |
| one role | `claude/agents/<agent>.md`, its checklist or Hard rules section |
| one process | `claude/skills/<skill>/SKILL.md` or its `references/` |
| a standalone technique with its own triggers | new `claude/skills/<name>/SKILL.md` |

Name the section and the line it goes after. Read the destination before
drafting.

A finding about one project, not the harness (its build, its domain, its
paths): say so and offer that project's `CLAUDE.md` instead
(`git rev-parse --show-toplevel` in the session's working directory). Search
that `CLAUDE.md` for a duplicate first. Same show-approve-write flow; skip the
harness lint; commit per that repo's rules.

### 5. Draft the text

Think it through as Problem / Solution / Example / When to use, then:

- Agent, skill or `claude/CLAUDE.md`: one or two lines in the destination's
  style — imperative, a concrete action, an example command.
- New skill or a `references/` page: the full four-part block, with the new
  skill's frontmatter (`name` equal to the directory, a triggers-only
  `description`).
- Language of the destination: agents and skills in English, `claude/CLAUDE.md`
  in Russian.

### 6. Show and wait

Show the owner: path, section, the exact change as one `diff` block (a move
shows both the removal and the addition), and one line on why this place. Write only after an explicit «да». If the owner
edits the text, show the result again and wait for «да» again. «нет» — stop,
nothing is written.

### 7. Write and verify

- Before writing: `git -C <repo> branch --show-current`. Not `main` — stop
  and tell the owner that the main checkout is off `main`; nothing is written.
- `git -C <repo> status --porcelain -- <file>...` for each touched file.
  Uncommitted changes — warn and ask before touching it.
- Write with Edit at the agreed place in each touched file.
- Run `sh <repo>/tests/lint-harness.sh` and show its output in full. Red — fix
  your own edit, show the fixed diff and wait for «да» again; never
  `git checkout` the file.
- Show `git -C <repo> diff -- <file>...`.

### 8. Offer the commit

Propose `docs(<scope>): <subject>` with scope by place — `agents`, `skills`,
`rules` (`claude/CLAUDE.md`) — and the attribution trailer from the global
rules. The main checkout is on `main` (step 7); ask which way:

- commit to `main` in the main checkout;
- or a branch: `git -C <repo> worktree add <repo>/.worktrees/learn-<slug> -b
  learn/<slug>`, apply the same edit there, undo it in the main checkout with
  Edit (not `git checkout`), run the lint and commit in the new worktree; say
  that the rule takes effect only after that branch is merged.

Never switch the branch of the main checkout (`checkout`, `switch`). Commit
only after a separate «да», adding each touched file by name.

## Rules

- Nothing is written before «да» to the exact text.
- One finding — one rule in one place; a move changes two files and is shown,
  checked and committed as one change.
- Never write to `~/.claude` directly; never write to `claude/settings.d/**` or
  `claude/hooks/**` — those are guarded config, changed by `devops-dev`, not a
  learned rule. Offer the rule for `claude/agents/devops-dev.md` instead (step
  4, one role).
- The repo is public: no work project names, employers, work tracker keys or
  `~/Job/*` paths in the text. Generalize the specifics.
