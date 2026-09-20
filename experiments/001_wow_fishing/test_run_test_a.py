"""Provider-free checks of Test B budgeting and stop behaviour."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import run_test_a as runner


class RunnerTests(unittest.TestCase):
    def run_case(self, prego, cycle=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root/'experiments/001_wow_fishing'
            for name in ['live.swift', 'jev.swift', 'build.sh', 'page-two.png', 'run_test_a.py',
                         'probes/background-click/Adapter.swift',
                         'probes/background-click/NativeWindowServerPreparation.swift',
                         'probes/background-click/NativeBackgroundClickTransport.swift']:
                path = source/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('fixture')
            results = [(SimpleNamespace(returncode=0, stdout='', stderr=''), prego)]
            if cycle is not None:
                results.append((SimpleNamespace(returncode=0, stdout='', stderr=''), cycle))
            with patch.object(runner, 'ROOT', root), patch.object(runner, 'invoke', side_effect=results) as invoke, \
                 patch('sys.argv', ['test', '--background', '--jev']), \
                 patch.dict('os.environ', {'TYPESAFE_API_KEY': 'offline-fixture'}), \
                 patch.object(runner.time, 'monotonic', side_effect=[0, 0, 10, 301, 301]), \
                 patch.object(runner.time, 'sleep'), patch('builtins.print'):
                runner.main()
                record = json.loads(next(root.glob('runs/*/*/summary.json')).read_text())
                return record, invoke.call_args_list

    def test_counts_actual_requests_and_usage(self):
        record, calls = self.run_case(
            [{'event': 'jev_request'}, {'event': 'pre_go_pass'}],
            [{'event': 'jev_request'}, {'event': 'jev_response', 'request_seconds': 0.3,
              'response': {'usage': {'input_tokens': 100, 'output_tokens': 20}}},
             {'event': 'loot_collected', 'item': 'Fresh fish'}])
        self.assertEqual(record['provider_calls'], 2)
        self.assertEqual(record['input_tokens'], 100)
        self.assertTrue(record['perfect_run'])
        self.assertIn('--prepared', calls[1].args[0])
        self.assertTrue(all('--jev' in call.args[0] for call in calls))

    def test_provider_failure_stops_without_rules_fallback(self):
        record, calls = self.run_case([{'event': 'pre_go_pass'}], [{'event': 'stopped_jev_error'}])
        self.assertEqual(record['status'], 'stopped_for_review')
        self.assertFalse(record['perfect_run'])
        self.assertEqual(len(calls), 2)

    def test_failed_preparation_never_casts(self):
        record, calls = self.run_case([{'event': 'pre_go_jev_not_ready'}])
        self.assertEqual(record['status'], 'pre_go_failed')
        self.assertEqual(len(calls), 1)


if __name__ == '__main__':
    unittest.main()
