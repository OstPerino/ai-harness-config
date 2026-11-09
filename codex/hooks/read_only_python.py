import ast
import json
import re
import shlex
from pathlib import Path

MODULES = {'collections', 'hashlib', 'json', 'os', 'pathlib', 're', 'selectors', 'subprocess', 'sys', 'tempfile', 'tomllib'}
BUILTINS = {'print', 'str', 'bytes', 'int', 'float', 'bool', 'len', 'sum', 'any', 'all', 'isinstance', 'dict', 'list', 'tuple', 'set', 'sorted', 'range', 'enumerate', 'zip', 'Path', 'RuntimeError', 'TimeoutError'}
METHODS = {'home', 'resolve', 'absolute', 'exists', 'is_file', 'is_dir', 'is_symlink', 'read_text', 'read_bytes', 'readlink', 'stat', 'glob', 'rglob', 'iterdir', 'get', 'items', 'keys', 'values', 'strip', 'split', 'splitlines', 'startswith', 'endswith', 'join', 'loads', 'dumps', 'hexdigest', 'sha256', 'DefaultSelector', 'register', 'select', 'close', 'TemporaryFile', 'readline', 'flush', 'terminate', 'kill', 'wait', 'getenv', 'getcwd'}
RPC_METHODS = {'initialize', 'initialized', 'hooks/list', 'skills/list'}


def inline_program(command):
    lines = command.splitlines()
    if not lines:
        return None
    match = re.search(r"\s+<<(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1\s*$", lines[0])
    if match:
        if len(lines) < 3 or lines[-1] != match[2]:
            return None
        words = shlex.split(lines[0][:match.start()])
        if len(words) != 2 or words[1] != '-':
            return None
        program = '\n'.join(lines[1:-1])
    else:
        words = shlex.split(command)
        if len(words) != 3 or words[1] != '-c':
            return None
        program = words[2]
    if not re.fullmatch(r'python(?:3(?:\.\d+)?)?', Path(words[0]).name):
        return None
    return program


def qualified(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return qualified(node.value) + '.' + node.attr
    return ''


def readonly(command):
    try:
        program = inline_program(command)
        if program is None or len(program) > 65536:
            return False
        tree = ast.parse(program)
        nodes = list(ast.walk(tree))
        functions = {node.name for node in nodes if isinstance(node, ast.FunctionDef)}
        parameters = {node.arg for node in nodes if isinstance(node, ast.arg)}
        reserved = BUILTINS | MODULES | {'open'}
        if parameters & (reserved | functions):
            return False
        bindings = {}
        for node in nodes:
            if isinstance(node, (ast.ClassDef, ast.AsyncFunctionDef, ast.Global, ast.Nonlocal, ast.Delete)):
                return False
            if isinstance(node, ast.Import):
                if any(alias.name not in MODULES or alias.asname for alias in node.names):
                    return False
            if isinstance(node, ast.ImportFrom):
                if node.module != 'pathlib' or node.level or any(alias.name != 'Path' or alias.asname for alias in node.names):
                    return False
            if isinstance(node, ast.Name) and node.id in {'eval', 'exec', 'compile', '__import__', 'getattr', 'setattr', 'delattr', 'globals', 'locals', 'vars'}:
                return False
            if isinstance(node, ast.Attribute) and (node.attr.startswith('_') or node.attr in {'write_text', 'write_bytes', 'unlink', 'rename', 'replace', 'mkdir', 'rmdir', 'chmod', 'touch'}):
                return False
            if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store) and node.id in reserved | functions | parameters:
                return False
            targets = node.targets if isinstance(node, ast.Assign) else [node.target] if isinstance(node, (ast.AnnAssign, ast.AugAssign, ast.NamedExpr)) else []
            for target in targets:
                if not isinstance(target, ast.Name) or target.id in reserved | functions | parameters or target.id in bindings:
                    return False
                bindings[target.id] = getattr(node, 'value', None)
        if functions & reserved:
            return False

        def literal_path(node, seen=None):
            seen = set() if seen is None else seen
            if isinstance(node, ast.Constant) and isinstance(node.value, str):
                return node.value
            if isinstance(node, ast.Name) and node.id in bindings and node.id not in seen:
                return literal_path(bindings[node.id], seen | {node.id})
            if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
                return str(Path(literal_path(node.left, seen)) / literal_path(node.right, seen))
            if isinstance(node, ast.Call) and qualified(node.func) in ('Path.home', 'pathlib.Path.home') and not node.args:
                return str(Path.home())
            if isinstance(node, ast.Call) and qualified(node.func) in ('str', 'Path') and len(node.args) == 1:
                return literal_path(node.args[0], seen)
            raise ValueError('opaque executable')

        processes = set()
        for name, value in bindings.items():
            if isinstance(value, ast.Call) and qualified(value.func) == 'subprocess.Popen':
                if not value.args or not isinstance(value.args[0], ast.List):
                    return False
                args = value.args[0].elts
                executable = literal_path(args[0])
                options = [arg.value if isinstance(arg, ast.Constant) else None for arg in args[1:]]
                trusted_cli = executable == 'codex' or '/node_modules/@openai/codex' in executable and '/vendor/' in executable and executable.endswith('/bin/codex') and '..' not in Path(executable).parts
                if not trusted_cli or options != ['--no-daemon', '--strict-config', 'app-server', '--stdio'] or any(item.arg not in {'stdin', 'stdout', 'stderr', 'text', 'bufsize'} for item in value.keywords):
                    return False
                processes.add(name)
        for node in nodes:
            if not isinstance(node, ast.Call):
                continue
            name = qualified(node.func)
            if name.startswith('os.') and name not in {'os.getenv', 'os.getcwd', 'os.environ.get', 'os.environ.items', 'os.environ.keys', 'os.environ.values'}:
                return False
            if name == 'request':
                if len(node.args) < 2 or not isinstance(node.args[1], ast.Constant) or node.args[1].value not in RPC_METHODS:
                    return False
            elif name == 'print':
                if any(item.arg is None or item.arg == 'file' and qualified(item.value) not in ('sys.stdout', 'sys.stderr') for item in node.keywords):
                    return False
            elif name == 'open':
                if len(node.args) > 2 or any(item.arg not in {'mode', 'encoding', 'errors', 'newline'} for item in node.keywords):
                    return False
                mode = node.args[1] if len(node.args) > 1 else next((item.value for item in node.keywords if item.arg == 'mode'), ast.Constant('r'))
                if not isinstance(mode, ast.Constant) or mode.value not in ('r', 'rb', 'rt'):
                    return False
            elif name == 'subprocess.Popen':
                if node not in [bindings[p] for p in processes]:
                    return False
            elif isinstance(node.func, ast.Name):
                if name not in BUILTINS | functions:
                    return False
            elif isinstance(node.func, ast.Attribute):
                if node.func.attr == 'write':
                    if qualified(node.func.value) not in {p + '.stdin' for p in processes} or len(node.args) != 1:
                        return False
                    payload = node.args[0]
                    if isinstance(payload, ast.BinOp) and isinstance(payload.op, ast.Add) and isinstance(payload.right, ast.Constant) and payload.right.value == '\n':
                        payload = payload.left
                    if isinstance(payload, ast.Constant) and isinstance(payload.value, str):
                        if json.loads(payload.value).get('method') not in RPC_METHODS:
                            return False
                    elif isinstance(payload, ast.Call) and qualified(payload.func) == 'json.dumps' and payload.args and isinstance(payload.args[0], ast.Dict):
                        if any(not isinstance(key, ast.Constant) or not isinstance(key.value, str) for key in payload.args[0].keys):
                            return False
                        fields = {key.value: val for key, val in zip(payload.args[0].keys, payload.args[0].values) if isinstance(key, ast.Constant)}
                        method = fields.get('method')
                        if not (isinstance(method, ast.Constant) and method.value in RPC_METHODS or isinstance(method, ast.Name) and method.id == 'method' and 'request' in functions):
                            return False
                    else:
                        return False
                elif node.func.attr not in METHODS:
                    return False
            else:
                return False
        return True
    except (ValueError, SyntaxError, TypeError, IndexError, AttributeError, OSError, RecursionError):
        return False
