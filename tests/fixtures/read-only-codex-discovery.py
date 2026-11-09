import json
import subprocess
import selectors
import tempfile
from pathlib import Path

binary = 'codex'
root = Path('/synthetic-project')
with tempfile.TemporaryFile(mode='w+') as log:
    p = subprocess.Popen([str(binary), '--no-daemon', '--strict-config', 'app-server', '--stdio'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True, bufsize=1)
    selector = selectors.DefaultSelector()
    selector.register(p.stdout, selectors.EVENT_READ)

    def request(number, method, params):
        p.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': number, 'method': method, 'params': params}) + '\n')
        p.stdin.flush()
        while selector.select(20):
            line = p.stdout.readline()
            if not line:
                raise RuntimeError('app-server exited')
            value = json.loads(line)
            if value.get('id') == number:
                return value['result']
        raise TimeoutError(method)

    try:
        request(1, 'initialize', {'clientInfo': {'name': 'harness-check', 'version': '1'}})
        p.stdin.write('{"jsonrpc":"2.0","method":"initialized"}\n')
        p.stdin.flush()
        hooks = request(2, 'hooks/list', {'cwds': [str(root)]})
        for item in hooks.get('data', []):
            if item.get('sourcePath') == str(Path.home() / '.codex/hooks.json'):
                print(item.get('trustStatus'))
        print(request(3, 'skills/list', {'cwds': [str(root)]}))
    finally:
        selector.close()
        p.stdin.close()
        p.terminate()
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()
