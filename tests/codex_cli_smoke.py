import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix='harness-cli-') as temp:
        base = Path(temp).resolve()
        home = base / '.codex'
        env = dict(os.environ, HOME=str(base), CODEX_HOME=str(home), AGENTS_SKILLS_HOME=str(base / '.agents/skills'))
        brainstorming = base / '.agents/skills/brainstorming/SKILL.md'
        brainstorming.parent.mkdir(parents=True)
        brainstorming.write_text('---\nname: brainstorming\ndescription: Synthetic conflicting workflow fixture.\n---\nSynthetic instructions.\n')
        subprocess.run(['bash', str(ROOT / 'install.sh'), '--target', 'codex'], env=env, check=True, capture_output=True, text=True)
        with (base / 'server.log').open('w') as log:
            server = subprocess.Popen(['codex', '--no-daemon', '--strict-config', 'app-server', '--stdio'], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True, bufsize=1)
            selector = selectors.DefaultSelector()
            selector.register(server.stdout, selectors.EVENT_READ)

            def request(number, method, params):
                server.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': number, 'method': method, 'params': params}) + '\n')
                server.stdin.flush()
                while selector.select(20):
                    line = server.stdout.readline()
                    if not line:
                        raise RuntimeError('Codex app-server exited during ' + method)
                    message = json.loads(line)
                    if message.get('id') == number:
                        if 'error' in message:
                            raise RuntimeError(method + ': ' + str(message['error']))
                        return message['result']
                raise TimeoutError(method)

            try:
                request(1, 'initialize', {'clientInfo': {'name': 'harness-smoke', 'version': '1'}, 'capabilities': {'experimentalApi': True}})
                server.stdin.write('{"jsonrpc":"2.0","method":"initialized"}\n')
                server.stdin.flush()
                hooks = request(2, 'hooks/list', {'cwds': [str(ROOT)]})['data'][0]
                assert not hooks['errors'] and not hooks['warnings'], 'hook discovery errors'
                owned = [h for h in hooks['hooks'] if h.get('sourcePath') == str(home / 'hooks.json')]
                assert len(owned) == 3, 'expected three hooks'
                assert all(h['trustStatus'] == 'untrusted' for h in owned), 'fresh home must not have trusted hooks'
                skills = request(3, 'skills/list', {'cwds': [str(ROOT)], 'forceReload': True})['data'][0]
                assert not skills['errors'], 'skill discovery errors'
                installed = [s for s in skills['skills'] if str(home / 'harness/releases') in s['path']]
                assert len(installed) == 15, 'expected fifteen harness skills'
                conflicts = [s for s in skills['skills'] if s['name'] == 'brainstorming']
                assert conflicts and all(not s['enabled'] for s in conflicts), 'conflicting workflow is still enabled'
                thread = request(4, 'thread/start', {'cwd': str(ROOT), 'ephemeral': True})
                assert str(home / 'AGENTS.md') in thread['instructionSources'], 'global instructions missing'
                assert str(ROOT / 'AGENTS.md') in thread['instructionSources'], 'project instructions missing'
            finally:
                selector.close()
                server.stdin.close()
                server.terminate()
                try:
                    server.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait(timeout=5)
            prompt = subprocess.run(['codex', '--no-daemon', 'debug', 'prompt-input', 'Harness discovery only.'], cwd=ROOT, env=env, check=True, capture_output=True, text=True, timeout=30)
            data = json.loads(prompt.stdout)
            descriptions = []

            def walk(value):
                if isinstance(value, dict):
                    if isinstance(value.get('agent_type'), dict):
                        descriptions.append(value['agent_type'].get('description', ''))
                    for child in value.values():
                        walk(child)
                elif isinstance(value, list):
                    for child in value:
                        walk(child)

            walk(data)
            roles = [p.stem for p in (ROOT / 'codex/agents').glob('*.toml')]
            assert len(roles) == 13 and all(name + ': {' in '\n'.join(descriptions) for name in roles), 'custom roles absent from spawn tool'
            print('CLI smoke: 13 roles, 15 skills, 3 untrusted hooks, disabled brainstorming, native instructions and fresh thread: ok')
            print('Trusted hook execution, model turn, TUI quotas and laptop installation remain separate checks.')


if __name__ == '__main__':
    main()
