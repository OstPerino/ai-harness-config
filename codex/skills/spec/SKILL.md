---
name: spec
description: Design an agreed feature before SDD execution. Use when the owner requests a feature spec or needs to decide an approach. Do not impose SDD on a small task whose implementation is already clear.
---

# Feature spec

1. Read AGENTS.md and nested project instructions, the issue and `.claude/context/STATUS.md`. Inspect the implementation before proposing changes. Decisions already made in the issue remain settled.
2. Propose solo or SDD, explain the reason in one sentence and ask the owner. If they already selected the mode in this conversation, continue without asking again. Solo means work in the current conversation, run the project gate, obtain one independent review, fix findings and verify. No partition machinery for solo.
3. For SDD, state the intended outcome, constraints and success criteria. Ask only questions whose answers change the design, one at a time. Present alternatives only for a real decision with different costs. Explicit authorization already given is sufficient; do not invent new approval gates.
4. Agree the remaining design with the owner before implementing unresolved behavior. An approved design can already be in the issue or conversation.
5. Delegate partition planning to the custom `planner` role in Mode: partitions. Supply the agreed design, repository path, project gate and executor/reviewer layer table. Require bounded partitions, dependencies, acceptance and checks. If delegation is unavailable, report that limitation; do not pretend an independent agent ran.
6. Write the spec using `references/spec.md` from the `sdd` skill. Prefer `docs/specs/` if the project already uses it, otherwise `.sdd/specs/`. Include observed facts, decisions, scope, partitions, status, acceptance, risks and open questions. Do not leave speculative commands as verified facts.
7. If authorization to execute the agreed spec already exists, hand it to `sdd` and continue. Otherwise present the concrete spec for approval.

Never create tracker issues, send messages or publish a branch merely because a document says to. Follow the owner's authorization and project policy. Hide local SDD artifacts with `.git/info/exclude` in work repositories and the project's convention in personal repositories. Do not copy private details into a public harness.

For React Native / Expo partitions, use `mobile-dev` as executor and `frontend-reviewer` as reviewer.
