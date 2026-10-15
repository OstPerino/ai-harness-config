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
2. Find the spec: the path the owner gave, or the only spec in
   `.claude/context/specs/` with partitions not all `done`. Several candidates →
   ask which.
3. Validate the spec: it has the partitions table, and every status is one of
   `todo | brief | work | review | fix | done` (a `work`/`fix` cell may carry
   `(agent <id>)`). Missing table or unknown status → stop: «спека не готова
   для sdd — нужен скилл spec».
4. Resume from the first partition that isn't `done`, at its status. Report one
   line: `<feature>: P1 done, P2 review, P3 todo — продолжаю с P2 (review)`.

**Lost executor.** A partition in `work` or `fix` whose agent id isn't
reachable from this session (after `/clear` or a new session): dispatch a new
agent of the same type with the brief, the report and the review (whichever
exist) as input, in the same worktree. Tell the owner the previous executor's
context is lost and the fix round, if any, starts from the files.

## 2. First run in a repo

1. Ask one question: «Это рабочий репо или пет?» — and propose the answer from
   the path (`~/Job/*` → рабочий, otherwise пет).
2. Detect the layers from the repo layout (apps/packages/crates/services) and
   propose executor/reviewer per layer from the harness agents.
3. Find the gate: `package.json` scripts, CI workflow, `Makefile`, `justfile`.
   Nothing obvious → propose one from the manifests and ask:
   - Rust: `cargo fmt --check && cargo clippy -- -D warnings && cargo test`
   - Python: `ruff check && pytest`
   - Node without scripts: `npx tsc --noEmit && npx vitest run`
   Never leave the gate empty.
4. Fill `claude-md-sdd.md` with the defaults for the type and show it as one
   table for confirmation:

   | | пет | рабочий |
   |---|---|---|
   | PR | ведущий | я |
   | Атрибуция | да | нет (если правила репо не говорят иначе) |
   | Скрыть артефакты | `.gitignore` | `.git/info/exclude` |
   | Ветка фичи | `sdd/<фича>` | спросить шаблон (`feature/<KEY>-<slug>`) |

5. Write the section:
   - пет → `CLAUDE.md`;
   - рабочий, `CLAUDE.md` not tracked (`git ls-files --error-unmatch CLAUDE.md`
     fails) → `CLAUDE.md`;
   - рабочий, `CLAUDE.md` tracked → `CLAUDE.local.md`; don't touch `CLAUDE.md`.

## 3. Work-repo guard

For `Тип репо: рабочий`, before the first partition make sure
`.git/info/exclude` contains each of these lines; append the missing ones and
say which:

```
.claude/context/
.claude/worktrees/
CLAUDE.local.md
```

Add `CLAUDE.md` as a fourth line only if it is not tracked. Write bare
patterns: `#` in the middle of a line is not a comment in exclude files.

Never edit the project's `.gitignore` in a work repo — the team sees it.

Before every merge into the feature branch:
`git status --porcelain | grep -E '\.claude/|CLAUDE\.local\.md'` — any output
→ stop.

## 4. Feature branch

From `Основная ветка`, named by `Ветка фичи`. Create it if it doesn't exist;
the main working tree stays on it during the whole run. Uncommitted changes in
the main working tree that aren't yours → stop and ask.

## 5. Partition loop

Update the status cell in the spec at every transition. One partition at a
time unless `Параллельные партии: да` (§7).

### 5.1 Brief — `brief`

Create the worktree from the current head of the feature branch:

```bash
git worktree add <Worktree>/<feature>-<id> -b <feature-branch>-<id> <feature-branch>
```

Dispatch the planner:

```
Agent(subagent_type: "planner", prompt: """
Mode: brief
Spec: <abs path>. Partition: <id> <name>.
Worktree: <abs path>, branch <branch> from <feature-branch> @ <sha>.
Report path: <abs path>/.claude/context/sdd/<feature>/<id>-report.md
Brief path: <abs path>/.claude/context/sdd/<feature>/<id>-brief.md
Builds on: <earlier briefs/reports>. Stack: <summary>.
""")
```

Planner returned discrepancies instead of a brief → stop and show them to the
owner. Otherwise read the brief yourself: every step concrete, the gate and
baseline present, `CLAUDE.md` rules copied in full.

- **First brief of the feature** → show it to the owner in full and wait for
  approval.
- Later briefs → one line to the owner (`P3 бриф: <what it does>`), continue.

### 5.2 Executor — `work (agent <id>)`

```
Agent(subagent_type: "<executor from ## SDD>", prompt: """
Your only input is the brief: <abs path to brief>.
Work only in <worktree path>. Write the report to <report path>.
""")
```

Record the agent id in the status cell. The executor is **not released** until
its fix round is over.

Executor returned «правок ноль», «заблокирован» or a premise mismatch → stop
and tell the owner.

### 5.3 Gate

Run `Гейт` from `## SDD` inside the worktree, output to a file. Green → read
the summary lines. Red → read the whole failing output, never `head`/`tail` it.

- Red → `SendMessage` to the same executor with the failing output path. Not a
  fix round: there was no review yet.
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
review.** Minor findings go into the spec's open questions or the final
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

Mark `done`, release the executor, take the next partition.

## 6. Finishing the feature

1. **Final review**, one per layer touched, over
   `<Основная ветка>...<feature-branch>`, written to
   `final-review-<layer>.md` from `final-review.md`. Add `security-reviewer`
   only if the spec's «Безопасность» says `да` or the owner asks.
2. **Partition `fixes`** for Critical/Important from the final reviews: brief →
   executor → gate → merge. No review for `fixes`.
3. **`pr.md`** in `.claude/context/sdd/<feature>/` from `pr.md`; attribution
   line only for `Тип репо: пет`.
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
