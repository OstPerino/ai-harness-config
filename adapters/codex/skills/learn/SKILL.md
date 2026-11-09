---
name: learn
description: Save one non-obvious lesson from this session into the shared harness after approval of the exact change. Invoke only when the owner explicitly asks to learn or save a reusable rule.
---

# Learn

Use the finding in the user's request, or propose the single most valuable lesson from the current session. Reject obvious syntax, one-time service outages and rules already present.

Read `${CODEX_HOME:-$HOME/.codex}/harness/manifest.json` and use its `source_repo` field to locate the checkout. Confirm `shared/` and `scripts/render.sh` exist. If the checkout is unavailable, report it; never change an installed release snapshot.

Search the shared source for duplicates before proposing a change. Choose one place:

- All sessions: `shared/rules/`.
- One role: `shared/roles/<role>.md`.
- One process: `shared/skills/<skill>/` or the Codex-specific workflow under `adapters/codex/skills/`.
- One project: its AGENTS.md or project notes, without adding its details to the public harness.

Show the exact diff and why it belongs there. If the owner already approved that exact text, continue; otherwise wait for approval. Preserve pre-existing edits. Use the harness worktree convention; do not switch the live main checkout. Run `sh scripts/render.sh`, `sh scripts/render.sh --check` and the relevant gate. Explain that a shared change can affect both clients. Commit and install only within the authorization already given; ask only for genuinely missing authorization. Never change security hooks or permissions as an incidental learned rule.
