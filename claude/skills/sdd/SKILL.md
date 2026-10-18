---
name: sdd
description: >
  Runs an approved spec through spec-driven development with the harness
  agents: planner writes each partition's brief, the executor from the
  project's ## SDD table works in its own worktree, the lead runs the gate,
  one reviewer pass, one fix round by the same executor, merge into the feature
  branch, final review per layer, then pr.md. Trigger on "запускай SDD",
  "погнали по спеке", "следующая партия", "продолжай SDD", "SDD статус", or
  right after the owner approves a spec. Requires a spec with a partitions
  table from the spec skill. On the first run in a repo it asks whether the
  repo is work or personal and writes the ## SDD section.
---

# sdd

You are the lead. You don't write the partition code — executors do. You keep
state in files, run the gate yourself, dispatch reviewers, merge partitions
into the feature branch and stop the moment something doesn't add up.

Templates: `~/.claude/skills/sdd/references/` — `claude-md-sdd.md`, `spec.md`,
`brief.md`, `report.md`, `review.md`, `final-review.md`, `pr.md`.

## 1. Start or resume

1. Read `## SDD` from `CLAUDE.md`, or from `CLAUDE.local.md` if the section is
   there. No section → **First run** (§2), then come back.
2. Find the spec: the path the owner gave; otherwise every `*.md` under
   `.sdd/specs/` and `docs/specs/` that has a «Партии» section.
   Candidates = specs with any row not `done` (including the `final`, `fixes`
   and `pr` rows). One → take it. Several → ask which. None → ask the owner for
   the path; never guess.
3. Validate the spec: it has the partitions table, and every status is one of
   `todo | brief | work | review | fix | done`, optionally followed by
   `(agent <id>[, gate red <n>])`. A spec without the table, or with an unknown
   status, is rejected with «спека не готова для sdd — нужен скилл spec» — also
   when the owner named it explicitly.
4. Resume from the first row that isn't `done`, at its status (table below).
   Report one line: `<feature>: P1 done, P2 review, P3 todo — продолжаю с P2
   (review)`.

**Resuming a status.** Every step is re-entrant: check what already exists on
disk before doing it again.

| status | already exists | do |
|---|---|---|
| `brief` | worktree (`git worktree list`) | reuse it; don't run `git worktree add` again |
| `brief` | `<id>-brief.md` | skip the planner, go to the approval / executor step |
| `work` | `<id>-report.md` and commits since the partition base | don't dispatch; go to the gate (§5.3) |
| `work` | commits but no report | ask the owner whether the executor still runs in another session; if not, lost executor (below) |
| `review` | `<id>-review.md` | don't dispatch a reviewer; go to the fix round |
| `fix` | «Фикс-раунд» section in the report | the fix round is over; go to the gate after fix (§5.5) |

**Lost executor.** A partition in `work`/`fix` with no report for the current
step and an agent id that isn't reachable from this session: dispatch a new
agent of the same type, in the same worktree, with the brief, the report and
the review (whichever exist) as input. Write the new id into the cell. Tell the
owner the previous executor's context is lost.

## 2. First run in a repo

1. Ask one question: «Это рабочий репо или пет?» — and propose the answer from
   the path (`~/Job/*` → рабочий, otherwise пет).
2. Detect the layers from the repo layout (apps/packages/crates/services) and
   propose executor/reviewer per layer from the harness agents.
3. Find the gate: `package.json` scripts, CI workflow, `Makefile`, `justfile`,
   a `tests/` runner script. Propose only commands whose tools are actually
   installed (`command -v`, devDependencies, lockfile) and that pass on the
   current base — run the proposal once before writing it down. Rust usually
   fits `cargo fmt --check && cargo clippy -- -D warnings && cargo test`. If
   nothing runnable exists (a shell/markdown repo, a Node repo without tests),
   say so and ask the owner for the gate. Never write a gate you haven't seen
   pass, and never leave it empty.
4. Find the worktree setup: what a fresh worktree needs before the gate runs —
   dependency install from the lockfile (`pnpm install --frozen-lockfile`,
   `npm ci`, `uv sync`), untracked config the gate reads (`.env`, generated
   clients). Write it as `Подготовка worktree`; `нет` if nothing is needed.
5. Fill `claude-md-sdd.md` with the defaults for the type and show it as one
   table for confirmation:

   | | пет | рабочий |
   |---|---|---|
   | PR | ведущий | я |
   | Атрибуция | да | нет (если правила репо не говорят иначе) |
   | Скрыть артефакты | `.gitignore` | `.git/info/exclude` |
   | Ветка фичи | `sdd/<фича>` | спросить шаблон (`feature/<KEY>-<slug>`) |

6. Write the section:
   - пет → `CLAUDE.md`;
   - рабочий, `CLAUDE.md` not tracked (`git ls-files --error-unmatch CLAUDE.md`
     fails) → `CLAUDE.md`;
   - рабочий, `CLAUDE.md` tracked → `CLAUDE.local.md`; don't touch `CLAUDE.md`.

## 3. Where SDD files live, and hiding them

- Worktrees: `.worktrees/<feature>-<id>` (key `Worktree`). Specs: `.sdd/specs/`
  or the repo's `docs/specs/`. Partition files: `.sdd/<feature>/`.
- Nothing goes under `.claude/`: Claude Code asks for permission on every write
  to a project's `.claude/` directory, even in bypass mode, and an executor
  writing code in a worktree there triggers a prompt per file.

Before the first partition, check that git ignores `.worktrees/` always, and
`.sdd/`, `CLAUDE.local.md` (and `CLAUDE.md` when it isn't tracked) unless
`Артефакты SDD: коммитить` (`git check-ignore -q <path>`); add the missing
ones and say which:

- **рабочий** → append to `.git/info/exclude`, one bare pattern per line (`#` in
  the middle of a line is not a comment there). Never edit the project's
  `.gitignore` — the team sees it.
- **пет** → append to `.gitignore` and commit it with the first partition merge.

With `Артефакты SDD: коммитить` the lead commits the spec status and the
partition files on the feature branch after each merge.

**Merge guard.** Before every merge into the feature branch, look at what the
partition brings, not at the main tree:

```bash
git diff --name-only <feature-branch>...<feature-branch>-<id> \
  | grep -E '^\.worktrees/|^\.sdd/|^CLAUDE\.local\.md$'
```

Add `|^CLAUDE\.md$` when `CLAUDE.md` is not tracked. Any output → stop: an
SDD artifact or a worktree is about to land in the branch from the executor.
Partition files are committed by the lead, never by executors.

## 4. Feature branch

From `Основная ветка`, named by `Ветка фичи`. Create it if it doesn't exist;
the main working tree stays on it during the whole run. Uncommitted changes in
the main working tree that aren't yours → stop and ask.

## 5. Partition loop

Update the status cell in the spec at every transition. One partition at a
time unless `Параллельные партии: да` (§7).

### 5.1 Brief — `brief`

Create the worktree from the current head of the feature branch (unless it
already exists — §1), then prepare it:

```bash
git worktree add <Worktree>/<feature>-<id> -b <feature-branch>-<id> <feature-branch>
cd <Worktree>/<feature>-<id> && <Подготовка worktree>
```

Run the gate once in the fresh worktree before the planner: it must be green on
the base, and it gives the planner the baseline numbers. Red on the base →
stop; the partition would inherit someone else's failure.

Dispatch the planner:

```
Agent(subagent_type: "planner", prompt: """
Mode: brief
Spec: <abs path>. Partition: <id> <name>.
Worktree: <abs path>, branch <branch> from <feature-branch> @ <sha>.
Report path: <abs path>/.sdd/<feature>/<id>-report.md
Brief path: <abs path>/.sdd/<feature>/<id>-brief.md
Builds on: <earlier briefs/reports>. Stack: <summary>.
""")
```

Planner returned discrepancies instead of a brief → stop and show them to the
owner. Otherwise read the brief yourself: every step concrete, the gate and
baseline present, `CLAUDE.md` rules copied in full.

Who approves follows `Утверждение брифов` in `## SDD` (default: the owner
approves the first brief of the feature, the lead the rest). The owner can also
grant it for the current session in chat. A brief approved by the lead → one
line to the owner (`P3 бриф: <what it does>`), continue. The lead may amend a
brief before dispatch; record the amendment in the brief and, if it changes
acceptance, in the spec.

### 5.2 Executor — `work (agent <id>)`

```
Agent(subagent_type: "<executor from ## SDD>", prompt: """
Your only input is the brief: <abs path to brief>.
Work only in <worktree path>. Write the report to <report path>.
No explanatory comments in code: no "why" paragraphs above functions, in tests
or configs. Test names say why a test exists; reasons go to the report.
""")
```

Record the agent id in the status cell and keep it there through `review` and
`fix`: after `/clear` it tells who gets the fix round. The executor is **not
released** until its fix round is over.

Executor returned «правок ноль», «заблокирован» or a premise mismatch → stop
and tell the owner.

### 5.3 Gate

Run `Гейт` from `## SDD` inside the worktree; write the output to
`.sdd/<feature>/<id>-gate.log` in the **main** working tree, not
inside the worktree (an untracked file there blocks `git worktree remove`).
Green → read the summary lines. Red → read the whole failing output, never
`head`/`tail` it.

- Red → `SendMessage` to the same executor with the log path, and record it in
  the cell: `work (agent <id>, gate red 1)`. Not a fix round: there was no
  review yet.
- Red twice in a row → stop; tell the owner what fails and why you think so.
  Use `systematic-debugging` if the cause isn't obvious.

Check the report against `report.md`: numbers present, a mutation row per new
test. Report without numbers → back to the executor.

### 5.4 Review — `review`

```
Agent(subagent_type: "<reviewer from ## SDD>", prompt: """
Review partition <id> <name>.
Brief: <path>. Report: <path>. Commits: <base>..<head> on <branch> in <worktree>.
Write the review to <path>/<id>-review.md using
~/.claude/skills/sdd/references/review.md. One pass: there is no re-review.
""")
```

### 5.5 Fix round — `fix (agent <id>)`, exactly one

- No Critical or Important → skip to 5.6.
- Few and obvious → fix them yourself in the worktree.
- Otherwise → `SendMessage` to the same executor: the review path, "only
  Critical and Important", "append a «Фикс-раунд» section to the report".

Then run the gate and read the diff of the fixes yourself. **No second
review.** Red after the fix round → the same executor gets the log (gate
retries are not fix rounds); red twice in a row → stop, as in §5.3. Minor findings go into the spec's open questions or the final
`pr.md`, not into code.

### 5.6 Merge — `done`

In the main working tree, on the feature branch:

```bash
git merge --no-ff <feature-branch>-<id> -m "Merge partition <id> <name>"
<gate>
git worktree remove <worktree path>
git branch -d <feature-branch>-<id>
```

Gate red after the merge → the partition is not done; fix on the feature branch
(yourself, or a new executor with the failing output) before the next partition.

**Conflicts:** resolve them yourself. Ask the owner only when the resolution
changes the behavior one of the partitions delivered (both partitions changed
the same function differently and you'd have to pick a behavior).

If the partition changed what the gate should run (a new test runner, a new
check), update `Гейт` in `## SDD` yourself in the same step — executors don't
touch `CLAUDE.md`.

Mark `done`, release the executor, take the next partition.

## 6. Finishing the feature

The finishing steps are rows of the partitions table — `final`, `fixes`, `pr` —
so they resume like partitions.

1. **Final review** (`final` row), one per layer touched, over
   `<Основная ветка>...<feature-branch>`, written to
   `final-review-<layer>.md` from `final-review.md`. Add `security-reviewer`
   only if the spec's «Безопасность» says `да` or the owner asks.
2. **Partition `fixes`** (`fixes` row; `done` right away if there is nothing
   to fix) for Critical/Important from the final reviews: brief →
   executor → gate → merge. No review for `fixes`.
3. **`pr.md`** (`pr` row) in `.sdd/<feature>/` from `pr.md`;
   the attribution line only when `Атрибуция: да`.
4. **PR** — only on the owner's command:
   - `PR: ведущий` → `issue-done` opens it (push, `gh pr create --base
     <Основная ветка> --head <feature-branch> --body-file <pr.md>`); merge only
     on a second command, after CI is green.
   - `PR: я` → give the owner the exact commands; push and open nothing.
5. Offer `project-checkpoint`.

## 7. Parallel partitions

Only with `Параллельные партии: да`: two `todo` partitions whose dependencies
are `done` and whose layers don't overlap may be briefed and executed at the
same time, each in its own worktree. Merge them one after another, gate after
each merge.

## Stop rules

Stop and write to the owner — don't push through — when:

- the gate is red on the base, before the executor started;
- a premise in a brief doesn't hold;
- the executor returns «правок ноль» or «заблокирован»;
- the gate is red twice in a row;
- a merge conflict changes the behavior of a partition;
- a `.claude/` file or `CLAUDE.local.md` is staged in a work repo;
- `e2e-dev` exhausted its 3 attempts on a scenario (pass its manual check on).

## Rules

- Executors and reviewers come only from the `## SDD` table; never a generic
  subagent.
- One review per partition, one fix round, no re-review.
- The executor stays alive until its fix round is over.
- Read the gate output whole when it's red.
- No PR, no push to a shared branch, no merge into `Основная ветка` without the
  owner's command.
- Before saying a partition or the feature is done, apply
  `verification-before-completion`. When a brief asks for tests before code,
  the executor follows `test-driven-development`.
