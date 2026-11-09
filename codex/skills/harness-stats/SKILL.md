---
name: harness-stats
description: Inspect the installed Codex harness version, hooks, roles and skill counts. Invoke only on an explicit request for harness stats. Session before/after metrics require a separately validated Codex transcript adapter.
---

# Harness stats

Read `${CODEX_HOME:-$HOME/.codex}/harness/manifest.json`. Report the release id, source checkout, installed links, and owned hook groups. Inspect the hooks configuration and whether the client reports them trusted. Do not infer trust from a file being present.

The old Claude transcript parser is not a Codex parser. Before/after interruption, frustration, token and tool-error metrics are a checklist item in `docs/plans/2026-11-06-codex-adapter.md`; report them as unavailable until that adapter is implemented and verified. Never fabricate zeros or run a Claude parser on Codex history. Do not change transcripts or credentials.
