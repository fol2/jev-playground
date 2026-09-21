"""Compare bite policies with identical preparation, observations and input checks."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
BINARY = Path('/tmp/jev-fishing-live')


def invoke(arguments, timeout):
    result = subprocess.run([str(BINARY), *arguments], cwd=ROOT, capture_output=True,
                            text=True, timeout=timeout)
    events = []
    for line in result.stdout.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and 'event' in value:
            events.append(value)
    return result, events


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--background', action='store_true')
    parser.add_argument('--jev', action='store_true', help='Test B: provider-backed bite decisions; shared deterministic preparation')
    args = parser.parse_args()
    label = 'B' if args.jev else 'A'
    if args.jev:
        if not os.environ.get('TYPESAFE_API_KEY') and (ROOT / '.env').is_file():
            for line in (ROOT / '.env').read_text().splitlines():
                name, sep, value = line.removeprefix('export ').partition('=')
                if sep and name.strip() == 'TYPESAFE_API_KEY':
                    os.environ['TYPESAFE_API_KEY'] = value.strip().strip('\"\'')
        if not os.environ.get('TYPESAFE_API_KEY'):
            raise SystemExit('Set TYPESAFE_API_KEY locally before Test B')
        os.environ['JEV_CALL_LIMIT'] = '120'
    mode = ['--background'] if args.background else []
    policy_mode = mode + (['--jev'] if args.jev else [])
    run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '_' + uuid.uuid4().hex[:6]
    folder = ROOT / 'runs' / '001_wow_fishing' / ('test_' + label.lower() + '_' + run_id)
    folder.mkdir(parents=True)
    record = {'protocol': 'anchored-pixel-bite-only-v1', 'comparison_scope': 'bite_policy_only',
              'policy': 'jev' if args.jev else 'rules', 'call_budget': 120 if args.jev else 0, 'status': 'running', 'mode': 'targeted' if args.background else 'foreground',
              'input_mode': 'targeted_without_activation' if args.background else 'foreground_without_activation',
              'game_foreground_observed': False, 'focus_observations': 0,
              'target_seconds': 300, 'pre_go_runs': 1, 'provider_calls': 0,
              'started_at_utc': datetime.now(timezone.utc).isoformat(), 'cycles': []}
    source = ROOT / 'experiments' / '001_wow_fishing'
    record['source_hashes'] = {
        str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in [source/'live.swift', source/'decision.swift', source/'self_tests.swift', source/'motion.swift', source/'motion-fixtures.png', source/'jev.swift', source/'loot.swift', source/'loot-close.png', source/'loot-layout.png', source/'build.sh', source/'page-two.png', source/'rod-icon.png', source/'split-bobber.png', source/'split-bobber-before.png', source/'bobber-no-red.png', source/'bobber-no-red-before.png', source/'run_test_a.py',
                  source/'probes/background-click/Adapter.swift',
                  source/'probes/background-click/NativeWindowServerPreparation.swift',
                  source/'probes/background-click/NativeBackgroundClickTransport.swift']}
    print(f'Test {label} {record["mode"]}; results: {folder}', flush=True)
    def account(events):
        record['provider_calls'] += sum(e['event'] == 'jev_request' for e in events)
        for event in events:
            if event['event'] == 'focus_observed':
                record['focus_observations'] += 1
                record['game_foreground_observed'] |= event['game_foreground']
            if event['event'] == 'jev_response':
                record.setdefault('request_seconds', []).append(event['request_seconds'])
                for name, count in event.get('response', {}).get('usage', {}).items():
                    record[name] = record.get(name, 0) + count
        if args.jev:
            os.environ['JEV_CALL_LIMIT'] = str(max(0, 120-record['provider_calls']))
    started = None
    try:
        prego, events = invoke(['--check', *mode], 120)
        account(events)
        (folder/'pre-go.log').write_text(prego.stdout + prego.stderr)
        if prego.returncode or not any(e['event'] == 'pre_go_pass' for e in events):
            record['status'] = 'pre_go_failed'
            return
        started = time.monotonic()
        print('Pre-go passed once; autonomous 300-second test started.', flush=True)
        consecutive_failures = 0
        # Finish an in-flight cast rather than kill it with a mouse button held.
        # This bounds normal completion to 300 seconds plus at most one 45-second cycle.
        while time.monotonic()-started < 300:
            number = len(record['cycles']) + 1
            result, events = invoke(['--execute', '--prepared', *policy_mode], 45)
            account(events)
            (folder/f'cycle-{number:02d}.log').write_text(result.stdout + result.stderr)
            collected = any(e['event'] == 'loot_collected' for e in events)
            outcome = 'loot_collected' if collected else (events[-1]['event'] if events else 'process_failed')
            cycle = {'number': number, 'outcome': outcome, 'exit_code': result.returncode,
                     'elapsed_seconds': round(time.monotonic()-started, 2),
                     'run_path': next((e['output'] for e in events if e['event'] == 'ready'), None),
                     'item': next((e['item'] for e in events if e['event'] == 'loot_collected'), None),
                     'labels_observed': next((e.get('labels_observed', []) for e in events if e['event'] == 'loot_collected'), []),
                     'loot_clicks': next((e.get('loot_clicks', 1) for e in events if e['event'] == 'loot_collected'), 0)}
            record['cycles'].append(cycle)
            print(json.dumps(cycle), flush=True)
            consecutive_failures = 0 if collected else consecutive_failures+1
            if consecutive_failures >= 3:
                record['status'] = 'stopped_after_three_consecutive_failures'
                break
            # A native safety stop is terminal. Never repair a changed view by recasting.
            if result.returncode or any(e['event'].startswith('stopped_') or e['event'] in [
                    'loot_item_unconfirmed', 'loot_not_cleared', 'loot_layout_unconfirmed',
                    'loot_batch_limit', 'retrieval_unverified'] for e in events):
                record['status'] = 'stopped_for_review'
                break
            time.sleep(0.5)
        else:
            record['status'] = 'completed' if any(c['outcome'] == 'loot_collected' for c in record['cycles']) else 'no_verified_catches'
    except KeyboardInterrupt:
        record['status'] = 'interrupted'
    except subprocess.TimeoutExpired:
        record['status'] = 'process_timeout'
    finally:
        if args.background:
            record['mode'] = ('targeted_mixed_focus' if record['game_foreground_observed'] else
                              'background' if record['focus_observations'] else 'targeted_focus_unobserved')
        record['autonomous_seconds'] = round(time.monotonic()-started, 2) if started is not None else 0
        record['verified_loot_cycles'] = sum(c['outcome'] == 'loot_collected' for c in record['cycles'])
        record['unverified_retrievals'] = sum(c['outcome'] == 'retrieval_unverified' for c in record['cycles'])
        record['perfect_run'] = (record.get('status') == 'completed' and record['autonomous_seconds'] >= 300
                                 and bool(record['cycles']) and record['verified_loot_cycles'] == len(record['cycles']))
        record['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        (folder/'summary.json').write_text(json.dumps(record, indent=2)+'\n')
        print(json.dumps({k: record[k] for k in ['status','mode','pre_go_runs','autonomous_seconds','verified_loot_cycles','unverified_retrievals','provider_calls','perfect_run']}), flush=True)


if __name__ == '__main__':
    main()
