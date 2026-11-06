#!/usr/bin/env python3
import json
import os
from pathlib import Path
import re
import subprocess
import sys

BASE = Path(__file__).resolve().parents[1]


def deny(reason):
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny', 'permissionDecisionReason': reason}}))
    raise SystemExit(0)


def resolved(value, cwd):
    p = Path(os.path.expanduser(value))
    return (p if p.is_absolute() else cwd / p).resolve()


def protected(path):
    home = Path.home().resolve()
    codex = Path(os.environ.get('CODEX_HOME', home / '.codex')).resolve()
    skills = Path(os.environ.get('AGENTS_SKILLS_HOME', home / '.agents/skills')).resolve()
    fixed = [codex / 'config.toml', codex / 'hooks.json', codex / 'AGENTS.md', codex / 'auth.json', codex / 'harness/manifest.json']
    roots = [codex / 'hooks', codex / 'agents', codex / 'harness/releases', skills, home / '.ssh', home / '.aws', home / '.gnupg', home / '.config/gh', home / 'Library/Keychains']
    if path in fixed or any(path == p or p in path.parents for p in roots):
        return True
    if any(part in ('.env', '.claude.json', '.netrc', '.npmrc', '.git-credentials') or part.startswith('.env.') for part in path.parts):
        return True
    for parent in [path.parent, *path.parents]:
        if parent.name in ('.codex', '.claude') and path.name in ('config.toml', 'hooks.json', 'settings.json', 'settings.local.json'):
            return True
    return False


def run_legacy(name, event):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(event.get('project_root', event['cwd'])))
    result = subprocess.run(['sh', str(BASE / 'legacy' / name)], input=json.dumps(event), text=True, capture_output=True, env=env)
    if result.returncode:
        deny((result.stderr or result.stdout or name + ' failed').strip())
    return result.stdout


def patch_paths(command):
    if not isinstance(command, str) or not command.startswith('*** Begin Patch\n') or command.rstrip().splitlines()[-1] != '*** End Patch':
        raise ValueError('invalid patch framing')
    paths = []
    for line in command.splitlines():
        for op in ('Add File', 'Update File', 'Delete File', 'Move to'):
            prefix = '*** ' + op + ': '
            if line.startswith(prefix):
                value = line[len(prefix):]
                if not value or '\x00' in value:
                    raise ValueError('empty patch path')
                paths.append(value)
    if not paths:
        raise ValueError('patch has no paths')
    return list(dict.fromkeys(paths))


def main():
    event = json.load(sys.stdin)
    if not isinstance(event, dict):
        raise ValueError('event must be an object')
    phase = sys.argv[1]
    cwd_value = event.get('cwd')
    if not isinstance(cwd_value, str) or not Path(cwd_value).is_absolute():
        raise ValueError('missing absolute cwd')
    cwd = Path(cwd_value).resolve()
    root = cwd
    for p in (cwd, *cwd.parents):
        if (p / '.git').exists():
            root = p
            break
    event['project_root'] = str(root)
    if phase == 'session':
        env = dict(os.environ, CLAUDE_PROJECT_DIR=str(root))
        result = subprocess.run(['sh', str(BASE / 'legacy/session-status.sh')], text=True, capture_output=True, env=env, cwd=cwd)
        if result.stdout:
            print(result.stdout, end='')
        return
    tool = event.get('tool_name')
    data = event.get('tool_input')
    if not isinstance(tool, str) or not isinstance(data, dict):
        raise ValueError('missing tool_name/tool_input')
    paths = []
    if tool in ('apply_patch', 'Edit', 'Write', 'MultiEdit'):
        if 'command' in data:
            paths = patch_paths(data['command'])
        elif isinstance(data.get('file_path'), str):
            paths = [data['file_path']]
        else:
            raise ValueError('missing patch or file_path')
    if phase == 'post':
        if not paths:
            return
        seen = set()
        for value in paths:
            path = resolved(value, cwd)
            marker = 'Cargo.toml' if path.suffix == '.rs' or path.name == 'Cargo.toml' else 'tsconfig.json'
            project = None
            for parent in (path.parent, *path.parents):
                if (parent / marker).is_file():
                    project = parent
                    break
                if (parent / '.git').exists():
                    break
            key = (project, marker)
            if project is None or key in seen:
                continue
            seen.add(key)
            if path.is_file():
                result = subprocess.run(['sh', str(BASE / 'legacy/typecheck.sh')], input=json.dumps({'tool_input': {'file_path': str(path)}}), text=True, capture_output=True)
                if result.returncode:
                    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': result.stderr or 'typecheck failed'}}))
        return
    if phase != 'pre':
        raise ValueError('unknown hook phase')
    for value in paths:
        path = resolved(value, cwd)
        if protected(path):
            deny('Protected file: ' + value)
        run_legacy('guard-write.sh', dict(event, tool_name='Write', tool_input={'file_path': str(path)}))
    if tool == 'Bash':
        command = data.get('command')
        if not isinstance(command, str) or not command:
            raise ValueError('missing shell command')
        actual_cwd = resolved(data.get('workdir', str(cwd)), cwd)
        shell = dict(event, cwd=str(actual_cwd))
        if re.search(r'(\.env(?:\.[\w.-]+)?\b|[~$/]\.ssh\b|[~$/]\.aws\b|[~$/]\.gnupg\b|auth\.json|\.netrc|\.git-credentials|\.npmrc)', command, re.I):
            deny('Command references a protected credential path')
        if re.search(r'(\.codex/(?:config\.toml|hooks|agents|AGENTS\.md|harness/(?:releases|manifest))|\.agents/skills)', command) and re.search(r'(>|\b(?:tee|cp|mv|rm|install|ln|python\w*|node|perl|ruby)\b|\bsed\s+-i)', command):
            deny('Command may modify installed harness configuration')
        for script in ('guard-net.sh', 'guard-rm.sh', 'guard-write.sh'):
            run_legacy(script, shell)
    if tool.startswith('mcp__jira__'):
        output = run_legacy('jira-write-guard.sh', event)
        if output:
            print(output, end='')
    if tool.startswith(('mcp__telegram__', 'mcp__telegram-mcp__')):
        name = tool.split('__')[-1]
        if re.match(r'(delete|ban|leave|block|set_privacy|update_profile|edit_admin)', name):
            deny('Destructive Telegram operation is disabled')
        if re.match(r'(send|reply|forward|edit|save_draft)', name):
            print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'ask', 'permissionDecisionReason': 'Confirm recipient and exact message text'}}))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, IndexError) as error:
        if len(sys.argv) > 1 and sys.argv[1] == 'pre':
            deny('Harness hook cannot validate input: ' + str(error))
        print('harness hook: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
