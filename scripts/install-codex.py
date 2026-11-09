#!/usr/bin/env python3
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
CONFIG_MARKERS = ('# >>> ai-harness-config', '# <<< ai-harness-config')
RULE_MARKERS = ('<!-- >>> ai-harness-config -->', '<!-- <<< ai-harness-config -->')


def fail(message):
    raise ValueError(message)


def read(path, default=''):
    return path.read_text() if path.exists() else default


def strip_block(text, markers):
    start, end = markers
    lines = text.splitlines(keepends=True)
    opening = [i for i, line in enumerate(lines) if line.rstrip('\r\n') == start]
    closing = [i for i, line in enumerate(lines) if line.rstrip('\r\n') == end]
    if not opening and not closing:
        return text, ''
    if len(opening) != 1 or len(closing) != 1 or opening[0] >= closing[0]:
        fail('Malformed managed block: ' + start)
    a, b = opening[0], closing[0] + 1
    return ''.join(lines[:a] + lines[b:]), ''.join(lines[a:b])


def add_block(text, body, markers):
    if not body:
        return text
    return text + ('' if not text or text.endswith('\n') else '\n') + markers[0] + '\n' + body.rstrip('\n') + '\n' + markers[1] + '\n'


def strip_config_block(text, owned):
    remaining, block = strip_block(text, CONFIG_MARKERS)
    if block == owned:
        return remaining
    if owned and block:
        prefix = ''.join(owned.splitlines(keepends=True)[:-1])
        if block.startswith(prefix):
            extra = ''.join(block[len(prefix):].splitlines(keepends=True)[:-1])
            expected = tomllib.loads(owned)
            additions = tomllib.loads(extra)
            if extra.lstrip().startswith('[') and additions and not expected.keys() & additions.keys():
                if tomllib.loads(block) == dict(expected, **additions):
                    return text.replace(block, extra, 1)
    fail('Managed block was modified or has no owner: config_block')


def json_text(data):
    return json.dumps(data, ensure_ascii=False, indent=2) + '\n'


def atomic(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        if path.exists():
            os.fchmod(fd, path.stat().st_mode & 0o777)
        else:
            os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def tree_hash(source):
    digest = hashlib.sha256()
    for path in sorted(source.rglob('*')):
        if path.is_symlink():
            fail('Release source contains a symlink: ' + str(path))
        if any(part == '__pycache__' or part.endswith('.pyc') for part in path.relative_to(source).parts):
            continue
        if path.is_file():
            digest.update(str(path.relative_to(source)).encode() + b'\0' + path.read_bytes() + b'\0')
    return digest.hexdigest()[:24]


def no_symlink_parents(path):
    for parent in (path, *path.parents):
        if parent.is_symlink():
            fail('Refusing symlinked installation path: ' + str(parent))


def restore(args, home, skills):
    state = home / 'harness'
    backup = Path(os.path.abspath(args.restore))
    if backup.parent != state / 'backups':
        fail('Restore requires a backup directory from this Codex home')
    no_symlink_parents(backup / 'journal.json')
    journal = json.loads((backup / 'journal.json').read_text())
    if not isinstance(journal, list):
        fail('Invalid restore journal')
    allowed = {home / n for n in ('config.toml', 'hooks.json', 'AGENTS.md', 'harness/manifest.json')}
    seen = set()
    for item in journal:
        if not isinstance(item, dict) or not isinstance(item.get('path'), str):
            fail('Invalid restore entry')
        path = Path(item['path'])
        if str(path) != os.path.abspath(path) or path in seen or (path not in allowed and path.parent not in (home / 'agents', skills)):
            fail('Invalid restore destination')
        seen.add(path)
        no_symlink_parents(path.parent)
        if path.exists() and path.is_dir() and not path.is_symlink():
            fail('Restore destination is a directory: ' + str(path))
        if item.get('kind') == 'file':
            copy = item.get('copy')
            if not isinstance(copy, str) or not copy.isdigit():
                fail('Invalid restore copy')
            no_symlink_parents(backup / copy)
            if not (backup / copy).is_file():
                fail('Missing restore copy')
        elif item.get('kind') == 'symlink':
            if not isinstance(item.get('target'), str) or not item['target'] or '\x00' in item['target']:
                fail('Invalid restore symlink')
        elif item.get('kind') != 'absent':
            fail('Invalid restore kind')
    if args.dry_run:
        print('restore:', backup)
        return
    for item in reversed(journal):
        path = Path(item['path'])
        if path.is_symlink() or path.is_file():
            path.unlink()
        if item['kind'] == 'file':
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(backup / item['copy'], path)
        elif item['kind'] == 'symlink':
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(item['target'])
    print('restored:', backup)


def install(args, home, skills, staging):
    state = home / 'harness'
    for path in (home, home / 'agents', state / 'releases', state / 'backups', skills):
        no_symlink_parents(path)
    if (state / 'install.lock').exists():
        fail('Interrupted operation owns ' + str(state / 'install.lock'))
    if args.restore:
        restore(args, home, skills)
        return
    manifest_path = state / 'manifest.json'
    no_symlink_parents(manifest_path)
    old = json.loads(read(manifest_path, '{}'))
    if not isinstance(old, dict):
        fail('Invalid manifest')
    if args.uninstall and not old:
        print('codex: not installed')
        return
    if old and (old.get('version') != 1 or old.get('skills_home') != str(skills) or not isinstance(old.get('links'), list) or not isinstance(old.get('hooks'), dict)):
        fail('Invalid manifest or changed skills directory')
    for filename in ('config.toml', 'hooks.json', 'AGENTS.md'):
        if (home / filename).is_symlink():
            fail('Refusing managed writes through symlink: ' + filename)
    if manifest_path.is_symlink():
        fail('Refusing a symlinked manifest')
    config_path, hooks_path, rules_path = (home / n for n in ('config.toml', 'hooks.json', 'AGENTS.md'))
    original_config = read(config_path)
    tomllib.loads(original_config)
    config = strip_config_block(original_config, old.get('config_block', ''))
    rules, rules_block = strip_block(read(rules_path), RULE_MARKERS)
    for field, block in [('rules_block', rules_block)]:
        if block != old.get(field, ''):
            fail('Managed block was modified or has no owner: ' + field)
    hooks = json.loads(read(hooks_path, '{}'))
    if not isinstance(hooks, dict) or not isinstance(hooks.get('hooks', {}), dict):
        fail('Invalid hooks.json')
    previous_hooks = old.get('hooks', {})
    if any(not isinstance(entries, list) for entries in previous_hooks.values()):
        fail('Invalid manifest hooks')
    for event, entries in hooks.get('hooks', {}).items():
        if not isinstance(entries, list):
            fail('Invalid hook groups: ' + event)
    old_links = {}
    for item in old.get('links', []):
        if not isinstance(item, dict) or item.get('kind') not in ('agent', 'skill') or not isinstance(item.get('name'), str) or Path(item['name']).name != item['name'] or item['name'] in ('', '.', '..'):
            fail('Invalid owned link in manifest')
        path = (home / 'agents' if item['kind'] == 'agent' else skills) / item['name']
        target = item.get('target', '')
        if not isinstance(target, str) or not Path(target).resolve().is_relative_to((state / 'releases').resolve()):
            fail('Owned target is outside releases')
        old_links[path] = target
    desired = {}
    release_id = None
    release_source = None
    if not args.uninstall:
        subprocess.run(['sh', str(ROOT / 'scripts/render.sh'), '--check'], check=True, stdout=subprocess.DEVNULL)
        release_source = ROOT / 'codex'
        release_id = tree_hash(release_source)
        if args.release:
            if not re_release(args.release):
                fail('Invalid release id')
            release_source = state / 'releases' / args.release
            if not release_source.is_dir() or tree_hash(release_source) != args.release:
                fail('Release missing or modified')
            release_id = args.release
        snapshot = staging / 'content'
        shutil.copytree(release_source, snapshot, symlinks=True, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        if tree_hash(snapshot) != release_id:
            fail('Release source changed while taking its snapshot; retry after edits finish')
        release_source = snapshot
        release = state / 'releases' / release_id
        no_symlink_parents(release)
        if release.exists() and tree_hash(release) != release_id:
            fail('Existing release was modified')
        for path in sorted((release_source / 'agents').glob('*.toml')):
            agent = tomllib.loads(path.read_text())
            if not all(isinstance(agent.get(k), str) and agent[k] for k in ('name', 'description', 'developer_instructions')):
                fail('Invalid agent: ' + path.name)
            desired[home / 'agents' / path.name] = (str(release / 'agents' / path.name), 'agent')
        for path in sorted((release_source / 'skills').iterdir()):
            if path.is_dir() and (path / 'SKILL.md').is_file():
                desired[skills / path.name] = (str(release / 'skills' / path.name), 'skill')
        for path, (target, _) in desired.items():
            if path.is_symlink():
                if str(path.readlink()) != old_links.get(path):
                    fail('Foreign or modified symlink: ' + str(path))
            elif path.exists():
                fail('Foreign file/directory: ' + str(path))
        rules = add_block(rules, (release_source / 'AGENTS.md').read_text(), RULE_MARKERS)
        brainstorming = skills / 'brainstorming/SKILL.md'
        config_body = ''
        if brainstorming.exists():
            settings = tomllib.loads(config).get('skills', {}).get('config', [])
            existing = [s for s in settings if s.get('path') == str(brainstorming)]
            if existing and any(s.get('enabled', True) for s in existing):
                fail('Existing brainstorming config enables the conflicting workflow; review it first')
            if not existing:
                config_body = '[[skills.config]]\npath = ' + json.dumps(str(brainstorming)) + '\nenabled = false\n'
        config = add_block(config, config_body, CONFIG_MARKERS)
        command = shlex.quote(sys.executable) + ' ' + shlex.quote(str(release / 'hooks/dispatch.py'))
        new_hooks = {
            'SessionStart': [{'matcher': 'startup|resume|clear|compact|fork', 'hooks': [{'type': 'command', 'command': command + ' session', 'timeout': 10}]}],
            'PreToolUse': [{'matcher': '.*', 'hooks': [{'type': 'command', 'command': command + ' pre', 'timeout': 15}]}],
            'PostToolUse': [{'matcher': '^(apply_patch|Edit|Write|MultiEdit)$', 'hooks': [{'type': 'command', 'command': command + ' post', 'timeout': 300}]}],
        }
    else:
        new_hooks = {}
    tomllib.loads(config)
    owned_hooks = {}
    merged = dict(hooks)
    merged['hooks'] = dict(hooks.get('hooks', {}))
    for event in sorted(set(previous_hooks) | set(new_hooks)):
        current = list(merged['hooks'].get(event, []))
        for entry in previous_hooks.get(event, []):
            if entry in current:
                current.remove(entry)
        owned_hooks[event] = []
        for entry in new_hooks.get(event, []):
            if entry not in current:
                current.append(entry)
                owned_hooks[event].append(entry)
        if current:
            merged['hooks'][event] = current
        else:
            merged['hooks'].pop(event, None)
    manifest = {'version': 1, 'release': release_id, 'source_repo': str(ROOT), 'skills_home': str(skills), 'links': [{'kind': kind, 'name': p.name, 'target': target} for p, (target, kind) in desired.items()], 'hooks': owned_hooks, 'config_block': strip_block(config, CONFIG_MARKERS)[1], 'rules_block': strip_block(rules, RULE_MARKERS)[1]}
    writes = {config_path: config, hooks_path: json_text(merged), rules_path: rules, manifest_path: json_text(manifest)}
    if args.uninstall:
        writes[manifest_path] = None
    changes = {}
    for path, text in writes.items():
        if text is None:
            if path.exists():
                changes[path] = None
        elif read(path) != text:
            changes[path] = text
    link_changes = {}
    for path, (target, _) in desired.items():
        if not path.is_symlink() or str(path.readlink()) != target:
            link_changes[path] = target
    for path, target in old_links.items():
        if path not in desired and path.is_symlink() and str(path.readlink()) == target:
            link_changes[path] = None
    for path in changes:
        if path.exists() and not path.is_file():
            fail('Not a regular file: ' + str(path))
    print('codex:', 'uninstall' if args.uninstall else release_id, 'files=' + str(len(changes)), 'links=' + str(len(link_changes)))
    if args.dry_run or not (changes or link_changes):
        return
    state.mkdir(parents=True, exist_ok=True)
    lock = state / 'install.lock'
    try:
        lock.mkdir()
    except FileExistsError:
        fail('Another install or interrupted operation owns ' + str(lock))
    backup = None
    journal = []
    try:
        backups = state / 'backups'
        backups.mkdir(exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix='install-', dir=backups))
        for i, path in enumerate(list(changes) + list(link_changes)):
            entry = {'path': str(path), 'kind': 'absent'}
            if path.is_symlink():
                entry.update(kind='symlink', target=str(path.readlink()))
            elif path.is_file():
                shutil.copy2(path, backup / str(i))
                entry.update(kind='file', copy=str(i))
            journal.append(entry)
        atomic(backup / 'journal.json', json_text(journal))
        if not args.uninstall and not release.exists():
            stage = Path(tempfile.mkdtemp(prefix='.release-', dir=state))
            try:
                shutil.copytree(release_source, stage / 'content', ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
                if tree_hash(stage / 'content') != release_id:
                    fail('Staged release hash differs from its content id')
                (state / 'releases').mkdir(exist_ok=True)
                os.replace(stage / 'content', release)
            finally:
                shutil.rmtree(stage)
        count = 0
        for path, text in changes.items():
            if path == manifest_path:
                continue
            atomic(path, text)
            count += 1
            if os.environ.get('HARNESS_TEST_FAIL_AFTER') == str(count):
                raise OSError('Injected installation failure')
        for path, target in link_changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.is_symlink():
                path.unlink()
            if target is not None:
                path.symlink_to(target)
        if manifest_path in changes:
            if changes[manifest_path] is None:
                manifest_path.unlink()
            else:
                atomic(manifest_path, changes[manifest_path])
    except BaseException:
        if backup is not None:
            for entry in reversed(journal):
                path = Path(entry['path'])
                if path.is_symlink() or path.is_file():
                    path.unlink()
                if entry['kind'] == 'file':
                    path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(backup / entry['copy'], path)
                elif entry['kind'] == 'symlink':
                    path.symlink_to(entry['target'])
        raise
    finally:
        lock.rmdir()
    print('backup:', backup)
    if not args.uninstall:
        print('Restart Codex; review and trust the installed definitions with /hooks. No trust records or sandbox settings were changed.')


def re_release(value):
    return len(value) == 24 and all(c in '0123456789abcdef' for c in value)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--uninstall', action='store_true')
    parser.add_argument('--restore')
    parser.add_argument('--release')
    args = parser.parse_args()
    if sum([args.uninstall, bool(args.restore), bool(args.release)]) > 1:
        fail('Choose one operation')
    home = Path(os.path.abspath(os.environ.get('CODEX_HOME', Path.home() / '.codex')))
    skills = Path(os.path.abspath(os.environ.get('AGENTS_SKILLS_HOME', Path.home() / '.agents/skills')))
    if skills != Path.home() / '.agents/skills':
        fail('AGENTS_SKILLS_HOME must be the native discovery root HOME/.agents/skills; use an isolated HOME for a separate installation')
    locks = sorted({hashlib.sha256(str(p).encode()).hexdigest() for p in (home, skills)})
    descriptors = []
    try:
        for name in locks:
            path = Path('/tmp').resolve() / ('ai-harness-install-' + str(os.getuid()) + '-' + name + '.lock')
            fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
            descriptors.append(fd)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                fail('Another install owns this Codex home or skills directory')
        with tempfile.TemporaryDirectory(prefix='harness-plan-') as temp:
            install(args, home, skills, Path(temp))
    finally:
        for fd in descriptors:
            os.close(fd)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, TypeError, KeyError, AttributeError, subprocess.CalledProcessError) as error:
        print('install-codex:', error, file=sys.stderr)
        raise SystemExit(1)
