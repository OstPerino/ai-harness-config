---
name: harness-stats
description: >
  Compares Claude Code sessions before and after a harness change using local
  transcripts: interrupts, frustration, tool errors, hook blocks and failures,
  typecheck reports, subagents, tokens. Run only on /harness-stats.
disable-model-invocation: true
argument-hint: "[--split YYYY-MM-DD] [--project SUBSTR] [--save]"
---

# harness-stats

Measures whether the harness made sessions smoother. Talk to the owner in Russian.

## Steps

1. Run `sh ~/.claude/skills/harness-stats/stats.sh $ARGUMENTS`. Without
   `--split` the split date is the mtime of `~/.claude/.ai-harness-managed.json`,
   i.e. the last `./install.sh`. Add `--save` when the owner wants a snapshot:
   transcripts older than `cleanupPeriodDays` are deleted by Claude Code.
2. Show the table as is, then read it in 3–5 lines:
   - fewer interrupts and frustration per 100 prompts, fewer broken hook runs —
     better;
   - hook blocks and typecheck reports after the split are the guards and the
     typecheck hook working; a spike means a false positive worth a look
     (`--project` narrows it down);
   - sample size: under ~10 sessions on a side, say the numbers are noise.
3. Compare with earlier snapshots in `~/.claude/harness-stats/*.json` if any.

## Rules

- Read-only: never edit transcripts or snapshots.
- Project names in the output can be work projects: never paste them into the
  harness repo, issues or commits.
