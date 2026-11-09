#!/usr/bin/env python3
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
from read_only_python import readonly

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
    result = subprocess.run(['sh', str(BASE / 'legacy' / name)], input=json.dumps(event), text=True, capture_output=True, env=env, timeout=3)
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


def readonly_shell(command):
    if any(char in command for char in ('$', '`', '>', '<', '\n', '\\')):
        return False
    lexer = shlex.shlex(command, posix=True, punctuation_chars=';&|()')
    lexer.whitespace_split = True
    lexer.commenters = ''
    groups = [[]]
    for word in lexer:
        if word in (';', '&&', '||', '|'):
            if not groups[-1]:
                return False
            groups.append([])
        else:
            groups[-1].append(word)
    for words in groups:
        if not words or words[0] not in ('cat', 'rg'):
            return False
        if words[0] == 'rg' and any(word.startswith(('--pre', '--hostname-bin')) for word in words[1:]):
            return False
        if any(word and all(char in ';&|()' for char in word) for word in words):
            return False
    return True


def main():
    event = json.load(sys.stdin)
    if not isinstance(event, dict):
        raise ValueError('event must be an object')
    phase = sys.argv[1]
    cwd_value = event.get('cwd')
    if not isinstance(cwd_value, str) or not Path(cwd_value).is_absolute():
        raise ValueError('missing absolute cwd')
    cwd = Path(cwd_value).resolve()
    repository = subprocess.run(['git', '-C', str(cwd), 'rev-parse', '--show-toplevel'], text=True, capture_output=True, timeout=2)
    root = Path(repository.stdout.strip()).resolve() if repository.returncode == 0 else cwd
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
    tool = {'exec_command': 'Bash', 'shell_command': 'Bash', 'shell': 'Bash'}.get(tool, tool)
    if tool == 'Bash':
        data = dict(data)
        command = data.get('command', data.get('cmd'))
        if isinstance(command, list) and all(isinstance(part, str) for part in command):
            import shlex
            command = shlex.join(command)
        data['command'] = command
        event = dict(event, tool_name=tool, tool_input=data)
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
        failures = []
        for value in paths:
            path = resolved(value, cwd)
            if path.suffix not in ('.rs', '.ts', '.tsx', '.mts', '.cts', '.vue') and path.name not in ('Cargo.toml', 'tsconfig.json'):
                continue
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
            target = path if path.is_file() else project / marker
            result = subprocess.run(['sh', str(BASE / 'legacy/typecheck.sh')], input=json.dumps({'tool_input': {'file_path': str(target)}}), text=True, capture_output=True, timeout=280)
            if result.returncode:
                failures.append(result.stderr or 'typecheck failed')
        if failures:
            print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': '\n'.join(failures)}}))
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
        import shlex
        expanded = os.path.expandvars(command).replace('~/', str(Path.home()) + '/')
        installed = [Path(os.environ.get('CODEX_HOME', Path.home() / '.codex')), Path(os.environ.get('AGENTS_SKILLS_HOME', Path.home() / '.agents/skills'))]
        roots = [resolved(str(path), cwd) for path in installed]
        mentions_install = bool(re.search(r'(\.codex/(?:config\.toml|hooks|agents|AGENTS\.md|harness/(?:releases|manifest))|\.agents/skills)', command)) or any(str(path) in expanded or str(root) in expanded for path, root in zip(installed, roots))
        for token in shlex.split(expanded):
            candidate = resolved(token.split('=', 1)[-1], actual_cwd)
            if any(candidate == root or root in candidate.parents for root in roots):
                mentions_install = True
        if mentions_install and re.search(r'(>|\b(?:tee|cp|mv|rm|install|ln|python\w*|node|perl|ruby)\b|\bsed\s+-i)', command) and not readonly(command) and not readonly_shell(command):
            deny('Command may modify configured harness paths')
        for script in ('guard-net.sh', 'guard-rm.sh', 'guard-write.sh'):
            run_legacy(script, shell)
    if tool.startswith('mcp__jira__'):
        output = run_legacy('jira-write-guard.sh', event)
        if output:
            decision = json.loads(output).get('hookSpecificOutput', {}).get('permissionDecision')
            if decision == 'ask':
                deny('This Jira write needs approval; Codex PreToolUse does not support ask. Configure a reviewed project exception before using this operation.')
            print(output, end='')
    if tool.startswith(('mcp__telegram__', 'mcp__telegram-mcp__')):
        name = tool.split('__')[-1]
        if re.match(r'(delete|ban|leave|block|set_privacy|update_profile|edit_admin)', name):
            deny('Destructive Telegram operation is disabled')
        if re.match(r'(send|reply|forward|edit|save_draft)', name):
            deny('Telegram writes are paused; Codex PreToolUse cannot request approval. A reviewed integration is required before sending messages.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, IndexError, subprocess.TimeoutExpired) as error:
        if len(sys.argv) > 1 and sys.argv[1] == 'pre':
            deny('Harness hook cannot validate input: ' + str(error))
        print('harness hook: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
