---
name: sdd
description: Execute an agreed feature spec through named planner, executor and reviewer roles, with resumable briefs and reports. Use after the owner selects SDD and authorizes implementation; not for solo changes.
---

# SDD execution

Read the approved spec, AGENTS.md, nested instructions and `.claude/context/STATUS.md`. Templates are in this skill's `references/` directory: `spec.md`, `brief.md`, `report.md`, `review.md`, `final-review.md`, `pr.md`, and `claude-md-sdd.md` (the filename is retained for compatibility; its Codex contents refer to AGENTS.md).

## Project contract

Read the project's SDD layer table: paths, executor, reviewer, gate, setup, base/feature branches, worktree policy, artifact policy, tracker, attribution, brief approval and centralized verification. If missing, propose a native AGENTS.md section using the template. Run a proposed gate once before calling it verified; record an existing failure rather than inheriting it silently.

Worktrees are a project choice, not a mandatory side effect of SDD. Honor projects that forbid them. Parallel partitions need disjoint ownership and isolated resources (ports, DB, Redis and E2E services) when those resources are used. If generation/build/typecheck is centralized, workers do not run it concurrently; the lead runs the prescribed commands after integration. Use `git -C <path>` for other trees. Keep the harness's main checkout on its base branch because live Claude links point into it.

## Resume

Keep a partition table in the spec with states `todo → brief → work → review → fix → done`, the agent id, branch/worktree and brief/report/review paths. Read that state before dispatching anything. Never redo a completed partition merely because the conversation was compacted. If an agent is no longer reachable, say its context was lost and start the same role with the existing brief/report/review. Agent ids are handles for the current runtime, not durable permission grants.

## Per partition

1. **Brief.** Establish the required isolated tree or file ownership and environment. Record the base SHA and gate baseline. Delegate to `planner` in Mode: brief with the spec, partition, exact paths and output paths. The brief includes acceptance, allowed files, project rules, commands, baseline and dependencies. Resolve discrepancies before work. Honor the project's approval policy; do not ask again when already authorized.
2. **Work.** Delegate the layer's executor with the brief as the task contract. Give its absolute path and allowed tree/files. No explanatory comment paragraphs in code; test names explain their purpose. Record the agent id. The executor writes its report with changed files, commands, results, remaining risks and deviations. Reuse that agent for fixes while reachable.
3. **Gate.** Run the project's checks according to its verification ownership. Do not merge a red partition or claim tests passed without observing their result.
4. **Review.** Delegate one independent layer reviewer with the exact diff/base SHA, brief and report. Include security review when the feature touches access control, secrets, network/file boundaries, raw SQL or similar high-risk behavior. Reviewer returns concrete findings with file, failure scenario, severity and correction; the lead saves the review. Reviewers must not fix the code themselves. Their prompt does not create a read-only sandbox: use a scratch copy or a separately restricted execution for mutation experiments. Preserve the project's files.
5. **Fix.** Give findings to the original executor, or fix them in the lead when that is authorized. Rerun relevant checks and inspect the corrections. Do not launch another review round unless the owner explicitly requests it. A new issue outside the agreed scope is a backlog item, not an excuse to expand the feature.
6. **Integrate.** Inspect incoming paths for accidental artifacts and secrets, integrate using the project's branch policy and run the gate. Update the spec status with evidence. Keep local notes untracked according to project rules. Commit only with current authorization.

Parallel work is allowed only for independent partitions when the project and owner permit it. Do not assign overlapping files to writers. Review an already reviewed subject only once; a distinct integration diff may need its own first review, but do not repackage a second pass as an integration review.

## Finish

Check acceptance one item at a time, update the checkpoint and prepare the PR description using `references/pr.md` when applicable. Include exact checks and unverified limitations. Push/open/merge only within existing user authorization and project policy. Actual-tool attribution follows the repository. Leave integration credentials and private work names out of public artifacts.

For React Native / Expo partitions, use `mobile-dev` as executor and `frontend-reviewer` as reviewer.
