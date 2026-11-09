import json
import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(sys.argv.pop(1))


class InstallerCases(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / 'repo with spaces'
        self.repo.mkdir()
        for name in ['install.sh', 'scripts', 'shared', 'adapters', 'codex', 'claude', '.generated-files']:
            source = SOURCE / name
            if source.is_dir():
                shutil.copytree(source, self.repo / name, ignore=shutil.ignore_patterns('__pycache__'))
            else:
                shutil.copy2(source, self.repo / name)
        self.home = self.base / 'home'
        self.codex = self.home / '.codex'
        self.skills = self.home / '.agents/skills'
        self.env = dict(os.environ, HOME=str(self.home), CODEX_HOME=str(self.codex), AGENTS_SKILLS_HOME=str(self.skills), PYTHONDONTWRITEBYTECODE='1')

    def run_install(self, *args, success=True, extra=None):
        result = subprocess.run(['bash', str(self.repo / 'install.sh'), '--target', 'codex', *args], env=dict(self.env, **(extra or {})), capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def manifest(self):
        return json.loads((self.codex / 'harness/manifest.json').read_text())


    def test_native_trust_tables_inside_managed_block_survive_update(self):
        self.codex.mkdir(parents=True)
        brainstorming = self.skills / 'brainstorming'
        brainstorming.mkdir(parents=True)
        (brainstorming / 'SKILL.md').write_text('foreign workflow')
        self.run_install()
        config = self.codex / 'config.toml'
        trust = '\n[hooks.state.synthetic]\ntrusted_hash = "synthetic-original-hash"\n'
        config.write_text(config.read_text().replace('# <<< ai-harness-config', trust + '# <<< ai-harness-config'))
        self.run_install()
        text = config.read_text()
        self.assertIn(trust.strip(), text)
        self.assertNotIn('hooks.state', self.manifest()['config_block'])
        self.run_install()
        self.assertEqual(config.read_text(), text)
        self.run_install('--uninstall')
        self.assertIn(trust.strip(), config.read_text())

    def test_native_trust_does_not_hide_owned_config_edits(self):
        brainstorming = self.skills / 'brainstorming'
        brainstorming.mkdir(parents=True)
        (brainstorming / 'SKILL.md').write_text('foreign workflow')
        self.run_install()
        config = self.codex / 'config.toml'
        original = config.read_text()
        trust = '\n[hooks.state.synthetic]\ntrusted_hash = "original"\n'
        cases = [
            original.replace('enabled = false', 'enabled = true') + trust,
            original.replace('# <<< ai-harness-config', 'extra = true\n' + trust + '# <<< ai-harness-config'),
            original.replace('# <<< ai-harness-config', '\n[[skills.config]]\npath = "foreign"\n' + trust + '# <<< ai-harness-config'),
        ]
        for changed in cases:
            with self.subTest(config=changed):
                config.write_text(changed)
                for args in [(), ('--uninstall',)]:
                    self.run_install(*args, success=False)
                    self.assertEqual(config.read_text(), changed)

    def test_dry_run_and_foreign_collision(self):
        self.run_install('--dry-run')
        self.assertFalse(self.home.exists())
        foreign = self.skills / 'spec'
        foreign.mkdir(parents=True)
        (foreign / 'SKILL.md').write_text('foreign')
        self.run_install(success=False)
        self.assertEqual((foreign / 'SKILL.md').read_text(), 'foreign')
        self.assertFalse(self.codex.exists())

    def test_install_repeat_uninstall_preserves_foreign(self):
        self.codex.mkdir(parents=True)
        self.skills.mkdir(parents=True)
        (self.skills / 'brainstorming').mkdir()
        (self.skills / 'brainstorming/SKILL.md').write_text('foreign workflow')
        config = '[tui]\nstatus_line = ["weekly-limit"]\n'
        (self.codex / 'config.toml').write_text(config)
        (self.codex / 'AGENTS.md').write_text('user rules\n')
        foreign_hook = {'hooks': [{'type': 'command', 'command': 'echo foreign'}]}
        (self.codex / 'hooks.json').write_text(json.dumps({'hooks': {'Stop': [foreign_hook]}}))
        claude = self.home / '.claude'
        claude.mkdir()
        (claude / 'settings.json').write_text('unchanged')
        self.run_install()
        self.assertEqual((claude / 'settings.json').read_text(), 'unchanged')
        manifest = self.manifest()
        self.assertEqual(len(manifest['links']), 28)
        for item in manifest['links']:
            self.assertNotIn(str(self.repo), item['target'])
            self.assertTrue(Path(item['target']).exists())
        before = {n: (self.codex / n).read_bytes() for n in ['config.toml', 'hooks.json', 'AGENTS.md', 'harness/manifest.json']}
        self.run_install()
        for n, data in before.items():
            self.assertEqual((self.codex / n).read_bytes(), data, n)
        with (self.codex / 'config.toml').open('a') as f:
            f.write('\n[foreign]\nvalue = 3\n')
        self.run_install('--uninstall')
        self.assertFalse((self.skills / 'spec').exists())
        self.assertEqual((self.skills / 'brainstorming/SKILL.md').read_text(), 'foreign workflow')
        self.assertEqual((self.codex / 'AGENTS.md').read_text(), 'user rules\n')
        self.assertEqual(json.loads((self.codex / 'hooks.json').read_text()), {'hooks': {'Stop': [foreign_hook]}})
        self.assertIn('[foreign]', (self.codex / 'config.toml').read_text())
        self.assertNotIn('enabled = false', (self.codex / 'config.toml').read_text())

    def test_rollback_failure_and_explicit_restore(self):
        self.codex.mkdir(parents=True)
        original = '[tui]\nstatus_line = ["weekly-limit"]\n'
        (self.codex / 'config.toml').write_text(original)
        self.run_install(success=False, extra={'HARNESS_TEST_FAIL_AFTER': '2'})
        self.assertEqual((self.codex / 'config.toml').read_text(), original)
        self.assertFalse((self.codex / 'harness/manifest.json').exists())
        self.assertFalse((self.codex / 'AGENTS.md').exists())
        result = self.run_install()
        backup = next(line.split('backup: ', 1)[1] for line in result.stdout.splitlines() if line.startswith('backup: '))
        self.run_install('--restore', backup)
        self.assertEqual((self.codex / 'config.toml').read_text(), original)
        self.assertFalse((self.codex / 'harness/manifest.json').exists())
        self.assertFalse((self.skills / 'sdd').exists())

    def test_bad_config_manifest_and_edited_owned_block(self):
        self.codex.mkdir(parents=True)
        config = self.codex / 'config.toml'
        config.write_text('[broken')
        self.run_install(success=False)
        self.assertFalse((self.codex / 'harness').exists())
        config.write_text('')
        self.run_install()
        rules = self.codex / 'AGENTS.md'
        rules.write_text(rules.read_text().replace('execution contract', 'edited by user'))
        self.run_install(success=False)
        self.assertIn('edited by user', rules.read_text())
        (self.codex / 'harness/manifest.json').write_text('{broken')
        self.run_install(success=False)

    def test_update_release_rollback_and_changed_link(self):
        self.run_install()
        first = self.manifest()['release']
        source = self.repo / 'adapters/codex/instructions.md'
        source.write_text(source.read_text() + '\nNew synthetic rule.\n')
        subprocess.run(['sh', str(self.repo / 'scripts/render.sh')], check=True, capture_output=True)
        self.run_install()
        self.assertNotEqual(first, self.manifest()['release'])
        self.run_install('--release', first)
        self.assertEqual(first, self.manifest()['release'])
        link = self.skills / 'spec'
        link.unlink()
        link.symlink_to(self.base / 'foreign-target')
        self.run_install(success=False)
        self.assertEqual(link.readlink(), self.base / 'foreign-target')

    def test_equal_foreign_hook_survives_update_and_uninstall(self):
        self.run_install()
        p = self.codex / 'hooks.json'
        hooks = json.loads(p.read_text())
        entry = hooks['hooks']['PreToolUse'][0]
        hooks['hooks']['PreToolUse'].append(entry)
        p.write_text(json.dumps(hooks))
        self.run_install()
        self.run_install('--uninstall')
        self.assertEqual(json.loads(p.read_text())['hooks']['PreToolUse'], [entry])

    def test_restore_works_with_corrupt_current_config_and_manifest(self):
        self.codex.mkdir(parents=True)
        (self.codex / 'config.toml').write_text('[tui]\n')
        (self.skills / 'brainstorming').mkdir(parents=True)
        (self.skills / 'brainstorming/SKILL.md').write_text('foreign')
        result = self.run_install()
        backup = next(line.removeprefix('backup: ') for line in result.stdout.splitlines() if line.startswith('backup: '))
        (self.codex / 'config.toml').write_text('[broken')
        (self.codex / 'harness/manifest.json').write_text('[]')
        self.run_install('--restore', backup)
        self.assertEqual((self.codex / 'config.toml').read_text(), '[tui]\n')
        self.assertFalse((self.codex / 'harness/manifest.json').exists())
        self.assertFalse((self.skills / 'spec').exists())

    def test_restore_rejects_bad_journal_before_any_mutation(self):
        result = self.run_install()
        backup = Path(next(line.removeprefix('backup: ') for line in result.stdout.splitlines() if line.startswith('backup: ')))
        rules = self.codex / 'AGENTS.md'
        before = rules.read_bytes()
        entries = [{'path': str(rules), 'kind': 'absent'}, {'path': str(self.codex / 'config.toml'), 'kind': 'file', 'copy': '../outside'}]
        (backup / 'journal.json').write_text(json.dumps(entries))
        self.run_install('--restore', str(backup), success=False)
        self.assertEqual(rules.read_bytes(), before)

    def test_symlinked_parent_rejected_without_writing_through_it(self):
        self.codex.mkdir(parents=True)
        foreign = self.base / 'foreign'
        foreign.mkdir()
        (self.codex / 'agents').symlink_to(foreign, target_is_directory=True)
        self.run_install(success=False)
        self.assertEqual(list(foreign.iterdir()), [])
        self.assertFalse((self.codex / 'harness').exists())

    def test_lock_precedes_manifest_read_and_covers_shared_skills(self):
        name = hashlib.sha256(str(self.skills).encode()).hexdigest()
        lock = Path('/tmp').resolve() / ('ai-harness-install-' + str(os.getuid()) + '-' + name + '.lock')
        with lock.open('a') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            different_tmp = self.base / 'different tmp'
            different_tmp.mkdir()
            result = self.run_install(success=False, extra={'TMPDIR': str(different_tmp), 'CODEX_HOME': str(self.home / 'other-codex')})
            self.assertIn('Another install', result.stderr)
            self.assertFalse(self.codex.exists())

    def test_unsupported_skill_discovery_root_rejected_before_writes(self):
        result = self.run_install(success=False, extra={'AGENTS_SKILLS_HOME': str(self.base / 'unseen-skills')})
        self.assertIn('native discovery root', result.stderr)
        self.assertFalse(self.home.exists())

    def test_source_change_during_snapshot_is_not_published(self):
        script = '''
import importlib.util, pathlib, sys
source = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('installer', source / 'scripts/install-codex.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original = module.shutil.copytree
def changed(src, dst, *args, **kwargs):
    if pathlib.Path(src) == source / 'codex':
        rules = pathlib.Path(src) / 'AGENTS.md'
        rules.write_text(rules.read_text() + '\\nSynthetic concurrent change.\\n')
    return original(src, dst, *args, **kwargs)
module.shutil.copytree = changed
sys.argv = ['install-codex.py']
module.main()
'''
        result = subprocess.run([sys.executable, '-c', script, str(self.repo)], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('changed while taking its snapshot', result.stderr)
        self.assertFalse(self.codex.exists())

    def test_snapshot_survives_checkout_removal_and_ignores_bytecode(self):
        ignored = self.repo / 'codex/cache.pyc'
        ignored.mkdir()
        (ignored / 'not-bytecode.txt').write_text('ignored')
        self.run_install()
        release = self.codex / 'harness/releases' / self.manifest()['release']
        self.assertFalse((release / 'cache.pyc').exists())
        moved = self.base / 'new checkout'
        self.repo.rename(moved)
        self.repo = moved
        self.run_install()
        shutil.rmtree(self.repo)
        self.assertTrue((self.skills / 'spec/SKILL.md').is_file())
        self.assertTrue((self.codex / 'agents/planner.toml').is_file())

    def test_targets_isolate_clients_and_all_rejects_codex_only_options(self):
        env = dict(self.env, CLAUDE_HOME=str(self.home / '.claude'))
        for option, success in [('--uninstall', False), ('--dry-run', True)]:
            result = subprocess.run(['bash', str(self.repo / 'install.sh'), '--target', 'all', option], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
            self.assertFalse(self.home.exists())
        self.run_install()
        before = {p: p.read_bytes() for p in [self.codex / 'hooks.json', self.codex / 'AGENTS.md', self.codex / 'harness/manifest.json']}
        subprocess.run(['bash', str(self.repo / 'install.sh'), '--target', 'claude'], env=env, capture_output=True, text=True, check=True)
        for path, content in before.items():
            self.assertEqual(path.read_bytes(), content)
        subprocess.run(['bash', str(self.repo / 'install.sh'), '--target', 'all'], env=env, capture_output=True, text=True, check=True)
        self.assertTrue((self.home / '.claude/CLAUDE.md').is_file())
        self.assertTrue((self.codex / 'harness/manifest.json').is_file())


unittest.main()
