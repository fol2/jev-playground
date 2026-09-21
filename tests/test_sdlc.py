from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from tools import sdlc


class Routing(unittest.TestCase):
    def test_document_only(self):
        self.assertEqual(sdlc.route([('M', 'README.md')])['checks'], ['integrity', 'governance'])
        self.assertNotIn('python-tests', sdlc.route([('M', 'docs/changes/note.md')])['checks'])

    def test_all_authority_and_code_paths(self):
        for path in sdlc.CODE | sdlc.POLICY:
            with self.subTest(path=path):
                self.assertIn('python-tests', sdlc.route([('M', path)])['checks'])

    def test_add_delete_and_mixed(self):
        for status in ('A', 'D', 'T'):
            self.assertIn('automation-tests', sdlc.route([(status, 'README.md')])['checks'])
        self.assertIn('python-tests', sdlc.route([('M', 'README.md'), ('M', 'tools/sdlc.py')])['checks'])

    def test_unknown_and_malformed_fail_closed(self):
        cases = [[], [('M', 'foo.py')], [('M', 'docs/anything.md')], [('R100', 'README.md')],
                 [('M', '../README.md')], [('M', '/README.md')], [('M', 'docs//changes/a.md')],
                 [('M', 'docs/changes/../a.md')], [('M', 'docs/changes/a\n.md')],
                 [('M', 'docs\\changes\\a.md')], [('M', '.env')], [('M', 'README.md'), ('M', 'surprise.sh')]]
        for case in cases:
            with self.subTest(case=case), self.assertRaises(sdlc.GateError):
                sdlc.route(case)

    def test_fishing_routes_real_offline_proof(self):
        for path in ['experiments/001_wow_fishing/live.swift',
                     'experiments/001_wow_fishing/evidence/run/events.jsonl',
                     'data/001_wow_fishing/angles_20260921/far-02-detail.mp4']:
            self.assertIn('fishing-offline', sdlc.route([('M', path)])['checks'])
        for path in ['experiments/001_wow_fishing/unregistered.swift',
                     'experiments/001_wow_fishing/evidence/payload.py',
                     'data/001_wow_fishing/payload.sh', 'experiments/002_unknown/main.py']:
            with self.assertRaises(sdlc.GateError):
                sdlc.route([('A', path)])

    def test_every_tracked_path_is_classified(self):
        # inspect() routes the whole tree, so one unregistered file holds the gate.
        for path in sdlc.git('ls-files', '-z').decode().split('\0'):
            if path and path not in sdlc.REQUIRED:
                with self.subTest(path=path):
                    sdlc.route([('M', path)])

    def test_runtime_never_inferred(self):
        result = sdlc.route([('M', 'tools/sdlc.py')])
        self.assertIn('F3', result['omitted'])
        self.assertIn('F4', result['omitted'])


class GitIntegrity(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.g('init', '-q')
        self.g('config', 'user.name', 'Fixture')
        self.g('config', 'user.email', 'fixture@example.invalid')
        (self.root / 'README.md').write_text('baseline\n')
        self.base = self.commit()
        (self.root / 'README.md').write_text('candidate\n')
        self.head = self.commit()

    def g(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, stderr=subprocess.DEVNULL).decode().strip()

    def commit(self):
        self.g('add', '.')
        self.g('commit', '-qm', 'fixture')
        return self.g('rev-parse', 'HEAD')

    def test_exact_identity(self):
        result = sdlc.inspect(self.base, self.head, self.root)
        self.assertEqual(result['head'], self.head)
        self.assertEqual(result['tree'], self.g('rev-parse', 'HEAD^{tree}'))

    def test_dirty_and_untracked(self):
        for path in ('README.md', 'untracked.txt'):
            (self.root / path).write_text('dirty')
            with self.assertRaises(sdlc.GateError):
                sdlc.inspect(self.base, self.head, self.root)

    def test_wrong_head_empty_and_invalid_base(self):
        for base, head in ((self.base, self.base), (self.head, self.head), ('missing-ref', self.head), ('--help', self.head)):
            with self.assertRaises(sdlc.GateError):
                sdlc.inspect(base, head, self.root)

    def test_symlink(self):
        (self.root / 'README.md').unlink()
        (self.root / 'README.md').symlink_to('/etc/passwd')
        head = self.commit()
        with self.assertRaises(sdlc.GateError):
            sdlc.inspect(self.base, head, self.root)

    def test_executable_document_is_not_documentation_only(self):
        (self.root / 'README.md').chmod(0o755)
        head = self.commit()
        with self.assertRaises(sdlc.GateError):
            sdlc.inspect(self.base, head, self.root)

    def test_rename_cannot_hide_unknown_destination(self):
        self.g('mv', 'README.md', 'payload.py')
        head = self.commit()
        with self.assertRaises(sdlc.GateError):
            sdlc.inspect(self.base, head, self.root)

    def test_removed_required_file_routes_full(self):
        self.g('rm', 'README.md')
        head = self.commit()
        self.assertIn('python-tests', sdlc.inspect(self.base, head, self.root)['checks'])


class Contract(unittest.TestCase):
    def test_current_contract(self):
        sdlc.contracts()

    def test_claude_startup_imports_only_the_kernel(self):
        entry = (sdlc.ROOT / 'CLAUDE.md').read_text()
        self.assertEqual(re.findall(r'@([A-Za-z0-9_./-]+)', entry), ['AGENTS.md'])
        self.assertLess(len(entry.encode()), 400)

    def test_security_and_instruction_mutations(self):
        mutations = [
            ('AGENTS.md', lambda s: s.replace('No compromise', 'Optional')),
            ('AGENTS.md', lambda s: s + ('x' * 6501)),
            ('CLAUDE.md', lambda s: s.replace('@AGENTS.md', 'other.md')),
            ('.github/workflows/ai-sdlc.yml', lambda s: s.replace('"contents": "read"', '"contents": "write"')),
            ('.github/workflows/ai-sdlc.yml', lambda s: s.replace('macos-14', 'self-hosted')),
            ('.github/workflows/ai-sdlc.yml', lambda s: s.replace('"persist-credentials": false', '"persist-credentials": true')),
            ('.github/workflows/ai-sdlc.yml', lambda s: s.replace('11d5960a326750d5838078e36cf38b85af677262', 'v4')),
            ('.github/workflows/ai-sdlc.yml', lambda s: s.replace('"Focus Gate"', '"Optional"')),
            ('.github/workflows/ai-sdlc.yml', lambda s: s.replace('"pull_request"', '"pull_request_target"')),
        ]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for path in sdlc.REQUIRED:
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(sdlc.ROOT / path, root / path)
            for path, mutate in mutations:
                original = (root / path).read_text()
                (root / path).write_text(mutate(original))
                with self.subTest(path=path), self.assertRaises(sdlc.GateError):
                    sdlc.contracts(root)
                (root / path).write_text(original)
            (root / 'REVIEW.md').unlink()
            with self.assertRaises(sdlc.GateError):
                sdlc.contracts(root)

    def test_workflow_topology(self):
        w = json.loads((sdlc.ROOT / '.github/workflows/ai-sdlc.yml').read_text())
        self.assertEqual(w['on']['push']['branches'], ['main'])
        self.assertTrue(w['concurrency']['cancel-in-progress'])
        steps = w['jobs']['focus']['steps']
        self.assertEqual(steps[0]['with']['fetch-depth'], 0)
        self.assertIn('pull_request.head.sha', steps[0]['with']['ref'])
        self.assertIn('python3 tools/sdlc.py "${args[@]}"', steps[1]['run'])
        self.assertIn('args+=(--full)', steps[1]['run'])
        self.assertNotIn('secrets.', json.dumps(w))


class Manifest(unittest.TestCase):
    """The manifest must anchor the decided content, or a reviewer cannot reproduce it."""

    def report(self, elapsed, **overrides):
        base = {'checks': ['integrity', 'governance'], 'reason': 'allowlisted documentation only',
                'base': 'a' * 40, 'head': 'b' * 40, 'tree': 'c' * 40,
                'changes': [['M', 'README.md']]} | overrides
        out = io.StringIO()
        with patch.object(sdlc, 'inspect', return_value=base), \
             patch.object(sdlc.time, 'monotonic', side_effect=[0.0, elapsed]), \
             patch.object(sdlc.sys, 'argv', ['sdlc', 'route', '--base', 'x']), \
             redirect_stdout(out):
            self.assertEqual(sdlc.main(), 0)
        return json.loads(out.getvalue())

    def test_wall_clock_does_not_change_the_manifest(self):
        slow, fast = self.report(59.5979), self.report(0.0042)
        self.assertNotEqual(slow['elapsed_seconds'], fast['elapsed_seconds'])
        self.assertEqual(slow['manifest_sha256'], fast['manifest_sha256'])

    def test_manifest_still_covers_every_decided_field(self):
        reference = self.report(1.0)
        for field, value in (('tree', 'd' * 40), ('head', 'e' * 40), ('base', 'f' * 40),
                             ('reason', 'other'), ('checks', ['integrity']),
                             ('changes', [['A', 'README.md']])):
            with self.subTest(field=field):
                self.assertNotEqual(self.report(1.0, **{field: value})['manifest_sha256'],
                                    reference['manifest_sha256'])

    def test_manifest_is_recomputable_from_the_published_report(self):
        published = self.report(1.0)
        recomputed = sdlc.hashlib.sha256(json.dumps(
            {k: v for k, v in published.items() if k not in {'manifest_sha256', 'elapsed_seconds'}},
            sort_keys=True).encode()).hexdigest()
        self.assertEqual(recomputed, published['manifest_sha256'])


if __name__ == '__main__':
    unittest.main()
