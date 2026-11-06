#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
sh "$ROOT/scripts/render.sh" --check
python3 - "$ROOT" <<'PY'
from pathlib import Path
import ast, json, sys, tomllib
root=Path(sys.argv[1])
roles=list((root/'codex/agents').glob('*.toml'))
assert len(roles)==13
for p in roles:
 d=tomllib.loads(p.read_text())
 assert d['name']==p.stem and d['description'] and d['developer_instructions']
 assert not any(k in d for k in ('sandbox_mode','approval_policy','mcp_servers'))
 assert '~/.claude/skills' not in d['developer_instructions']
for p in (root/'codex/skills').glob('*/SKILL.md'):
 s=p.read_text()
 assert 'Agent(subagent_type:' not in s and '{{' not in s, p
 assert 'disable-model-invocation:' not in s, p
 assert s.startswith('---\nname: '), p
for name in ['learn','harness-stats','Telegram']:
 assert 'allow_implicit_invocation: false' in (root/'codex/skills'/name/'agents/openai.yaml').read_text()
assert not (root/'codex/skills/harness-stats/stats.sh').exists()
for p in [root/'scripts/install-codex.py',root/'codex/hooks/dispatch.py']:
 ast.parse(p.read_text())
assert 'project_doc_fallback_filenames' not in (root/'codex/AGENTS.md').read_text()
assert '.claude/context/STATUS.md' in (root/'codex/AGENTS.md').read_text()
print('codex contracts: ok')
PY
