import io
from contextlib import redirect_stdout, redirect_stderr
import unittest
from unittest.mock import patch
from tools import merge_pr as m

HEAD, BASE = 'a' * 40, 'b' * 40


def fixture():
    repo = {'full_name': m.REPO}
    return {
        'pr': {'number': 1, 'state': 'open', 'draft': False, 'merged': False,
               'head': {'sha': HEAD, 'ref': 'task', 'repo': repo},
               'base': {'sha': BASE, 'ref': 'main', 'repo': repo},
               'mergeable': True, 'mergeable_state': 'clean', 'user': {'login': 'owner'}},
        'integration': BASE, 'compare': {'status': 'ahead'}, 'main_compare': {'status': 'ahead'},
        'runs': [{'id': 10, 'run_number': 1, 'run_attempt': 1, 'workflow_id': m.WORKFLOW_ID, 'path': m.PATH, 'head_sha': HEAD,
                  'event': 'pull_request', 'head_repository': repo, 'pull_requests': [{'number': 1}],
                  'status': 'completed', 'conclusion': 'success'}],
        'jobs': [{'name': 'Focus Gate', 'status': 'completed', 'conclusion': 'success', 'run_id': 10}],
        'checks': [], 'statuses': [], 'threads': [],
        'reviews': [{'id': 1, 'user': {'login': 'owner'}, 'state': 'COMMENTED', 'commit_id': HEAD,
                     'submitted_at': '2026-09-21T12:00:00Z', 'author_association': 'OWNER', 'body': f'AI-SDLC review: PASS\nIndependence: author-review\nHead: {HEAD}'}]}


class Decision(unittest.TestCase):
    def test_eligible(self):
        self.assertEqual(m.evaluate(fixture(), 1, HEAD)['decision'], 'ELIGIBLE')

    def test_blockers(self):
        changes = [
            ('pr.state', 'closed'), ('pr.draft', True), ('pr.merged', True),
            ('pr.head.sha', BASE), ('pr.head.repo', {'full_name': 'other/repo'}),
            ('pr.base.ref', 'release'), ('pr.head.ref', 'main'), ('integration', 'c' * 40),
            ('compare.status', 'diverged'), ('main_compare.status', 'behind'),
            ('main_compare.status', 'diverged'), ('pr.mergeable', None), ('pr.mergeable_state', 'blocked'),
            ('runs', []), ('jobs', []), ('reviews', []),
            ('checks', [{'status': 'queued', 'conclusion': None}]),
            ('checks', [{'status': 'completed', 'conclusion': 'failure'}]),
            ('statuses', [{'state': 'pending'}]), ('threads', [{'isResolved': False}]),
        ]
        for path, value in changes:
            s = fixture()
            target = s
            parts = path.split('.')
            for part in parts[:-1]:
                target = target[part]
            target[parts[-1]] = value
            with self.subTest(path=path), self.assertRaises(m.Hold):
                m.evaluate(s, 1, HEAD)

    def test_run_identity_and_latest_attempt(self):
        for field, value in [('workflow_id', 6), ('path', '.github/workflows/fake.yml'), ('head_sha', BASE), ('event', 'push'),
                             ('pull_requests', []), ('head_repository', {'full_name': 'other/repo'}),
                             ('status', 'in_progress'), ('conclusion', 'failure')]:
            s = fixture()
            s['runs'][0][field] = value
            with self.subTest(field=field), self.assertRaises(m.Hold):
                m.evaluate(s, 1, HEAD)
        s = fixture()
        rerun = dict(s['runs'][0], run_attempt=2, status='queued', conclusion=None)
        s['runs'].append(rerun)
        with self.assertRaises(m.Hold):
            m.evaluate(s, 1, HEAD)

    def test_review_truth_and_newer_verdicts(self):
        for field, value in [('commit_id', BASE), ('author_association', 'NONE'), ('state', 'DISMISSED'),
                             ('state', 'APPROVED'), ('body', f'AI-SDLC review: PASS\nHead: {HEAD}'),
                             ('body', 'AI-SDLC review: INCONCLUSIVE'), ('body', 'AI-SDLC review: REQUEST_CHANGES')]:
            s = fixture()
            s['reviews'][0][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(m.Hold):
                m.evaluate(s, 1, HEAD)
        s = fixture()
        s['reviews'].append(dict(s['reviews'][0], id=2, body='AI-SDLC review: INCONCLUSIVE'))
        with self.assertRaises(m.Hold):
            m.evaluate(s, 1, HEAD)

    def test_comments_do_not_clear_native_requested_changes(self):
        s = fixture()
        s['reviews'].insert(0, dict(s['reviews'][0], id=0, state='CHANGES_REQUESTED', body='Fix it'))
        with self.assertRaises(m.Hold):
            m.evaluate(s, 1, HEAD)
        s['reviews'][0]['state'] = 'DISMISSED'  # GitHub mutates the dismissed review itself
        self.assertEqual(m.evaluate(s, 1, HEAD)['decision'], 'ELIGIBLE')

    def test_other_reviewer_cannot_overrule_open_findings(self):
        s = fixture()
        s['reviews'].append(dict(s['reviews'][0], id=2, user={'login': 'reviewer'}, body='AI-SDLC review: REQUEST_CHANGES'))
        s['reviews'].append(dict(s['reviews'][0], id=3))
        with self.assertRaises(m.Hold):
            m.evaluate(s, 1, HEAD)

    def test_gate_cannot_be_skipped_or_forged(self):
        for field, value in [('name', 'Optional'), ('conclusion', 'skipped'), ('run_id', 11)]:
            s = fixture()
            s['jobs'][0][field] = value
            with self.assertRaises(m.Hold):
                m.evaluate(s, 1, HEAD)

    def test_sha_and_pr_validation(self):
        for number, head in [(2, HEAD), (1, HEAD[:7]), (1, '--help')]:
            with self.assertRaises(m.Hold):
                m.evaluate(fixture(), number, head)

    def test_full_pagination_and_bounded_failure(self):
        with patch.object(m, 'api', side_effect=[list(range(100)), [100]]) as call:
            self.assertEqual(len(m.pages('test')), 101)
            self.assertIn('page=2', call.call_args.args[0])
        with patch.object(m, 'api', return_value=[0] * 100), self.assertRaises(m.Hold):
            m.pages('test')

    def test_read_only_default(self):
        with patch('sys.argv', ['merge_pr.py', '1', HEAD]), patch.object(m, 'collect', return_value=fixture()), \
             patch.object(m, 'api') as api, patch.object(m.subprocess, 'run') as run:
            with redirect_stdout(io.StringIO()):
                self.assertEqual(m.main(), 0)
            api.assert_not_called()
            run.assert_not_called()

    def test_execute_guards_head_and_verifies_readback(self):
        s = fixture()
        reads = [s['pr'], {'commit': {'sha': BASE}}, {'merged': True, 'merge_commit_sha': 'c' * 40}]
        result = type('Result', (), {'returncode': 0, 'stdout': '{"merged":true,"sha":"' + 'c' * 40 + '"}'})()
        with patch('sys.argv', ['merge_pr.py', '1', HEAD, '--execute']), \
             patch.object(m, 'collect', return_value=s), patch.object(m, 'api', side_effect=reads), \
             patch.object(m.subprocess, 'run', return_value=result) as run, redirect_stdout(io.StringIO()):
            self.assertEqual(m.main(), 0)
            self.assertIn('PUT', run.call_args.args[0])
            self.assertIn(HEAD, run.call_args.kwargs['input'])

    def test_execute_stops_if_base_moves_before_write(self):
        s = fixture()
        with patch('sys.argv', ['merge_pr.py', '1', HEAD, '--execute']), \
             patch.object(m, 'collect', return_value=s), \
             patch.object(m, 'api', side_effect=[s['pr'], {'commit': {'sha': 'd' * 40}}]), \
             patch.object(m.subprocess, 'run') as run, redirect_stderr(io.StringIO()):
            self.assertEqual(m.main(), 1)
            run.assert_not_called()

    def test_thread_pagination_checks_every_page(self):
        def page(resolved, more, cursor):
            return {'data': {'repository': {'pullRequest': {'reviewThreads': {
                'nodes': [{'isResolved': resolved}],
                'pageInfo': {'hasNextPage': more, 'endCursor': cursor}}}}}}
        with patch.object(m, 'api', side_effect=[page(True, True, 'next'), page(False, False, None)]):
            self.assertEqual(m.threads(1), [{'isResolved': True}, {'isResolved': False}])
        with patch.object(m, 'api', return_value=page(True, True, 'repeat')), self.assertRaises(m.Hold):
            m.threads(1)


class ReviewRegression(unittest.TestCase):
    def test_delayed_draft_verdict_is_ordered_by_submission_not_id(self):
        s = fixture()
        s['reviews'].append(dict(s['reviews'][0], id=0,
            submitted_at='2026-09-21T12:01:00Z', body='AI-SDLC review: REQUEST_CHANGES'))
        with self.assertRaises(m.Hold):
            m.evaluate(s, 1, HEAD)

    def test_delayed_native_veto_is_not_cleared_by_older_approval(self):
        s = fixture()
        s['reviews'] += [dict(s['reviews'][0], id=3, user={'login': 'reviewer'},
            state='APPROVED', body='Reviewed'), dict(s['reviews'][0], id=2,
            user={'login': 'reviewer'}, state='CHANGES_REQUESTED', body='Blocking defect',
            submitted_at='2026-09-21T12:01:00Z')]
        with self.assertRaises(m.Hold):
            m.evaluate(s, 1, HEAD)

    def test_dismissing_another_review_does_not_clear_an_active_veto(self):
        s = fixture()
        s['reviews'] += [dict(s['reviews'][0], id=2, user={'login': 'reviewer'},
            state='CHANGES_REQUESTED', body='Unresolved defect'), dict(s['reviews'][0],
            id=3, user={'login': 'reviewer'}, state='DISMISSED', body='Other review',
            submitted_at='2026-09-21T12:01:00Z')]
        with self.assertRaises(m.Hold):
            m.evaluate(s, 1, HEAD)

    def test_unsubmitted_draft_is_not_a_verdict(self):
        s = fixture()
        s['reviews'].append(dict(s['reviews'][0], id=9, state='PENDING', submitted_at=None))
        self.assertEqual(m.evaluate(s, 1, HEAD)['decision'], 'ELIGIBLE')

    def test_unverifiable_submission_time_blocks(self):
        for value in (None, '', 'bad-time', '2026-99-21T12:00:00Z'):
            s = fixture()
            s['reviews'][0]['submitted_at'] = value
            with self.subTest(value=value), self.assertRaises(m.Hold):
                m.evaluate(s, 1, HEAD)

    def test_conflicting_verdict_lines_block(self):
        s = fixture()
        s['reviews'][0]['body'] += '\nAI-SDLC review: REQUEST_CHANGES'
        with self.assertRaises(m.Hold):
            m.evaluate(s, 1, HEAD)

    def test_same_second_negative_verdict_cannot_be_overruled_by_id(self):
        s = fixture()
        s['reviews'].append(dict(s['reviews'][0], id=0, body='AI-SDLC review: INCONCLUSIVE'))
        with self.assertRaises(m.Hold):
            m.evaluate(s, 1, HEAD)


class IntegrationBranch(unittest.TestCase):
    """A non-main target must be named; it can never be reached by default."""

    def test_main_is_the_default_and_other_targets_are_held(self):
        s = fixture()
        s['pr']['base']['ref'] = 'experiment/test-b-parity'
        with self.assertRaises(m.Hold):
            m.evaluate(s, 1, HEAD)
        self.assertEqual(m.evaluate(s, 1, HEAD, 'experiment/test-b-parity')['decision'], 'ELIGIBLE')

    def test_named_target_still_requires_current_main(self):
        s = fixture()
        s['pr']['base']['ref'] = 'experiment/test-b-parity'
        s['main_compare'] = {'status': 'behind'}
        with self.assertRaises(m.Hold):
            m.evaluate(s, 1, HEAD, 'experiment/test-b-parity')

    def test_named_target_is_recorded_in_the_decision(self):
        s = fixture()
        s['pr']['base']['ref'] = 'topic'
        self.assertEqual(m.evaluate(s, 1, HEAD, 'topic')['integration_ref'], 'topic')

    def test_malformed_integration_branch_is_held(self):
        for bad in ('', 'a b', 'x' * 101, 'refs/heads/../main', '/main', 'main/', 'a//b', '..'):
            with self.subTest(bad=bad), patch('sys.argv', ['merge_pr.py', '1', HEAD, '--into', bad]), \
                 patch.object(m, 'collect') as collect, redirect_stderr(io.StringIO()):
                self.assertEqual(m.main(), 1)
                collect.assert_not_called()


if __name__ == '__main__':
    unittest.main()
