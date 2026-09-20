"""Run a bounded, provider-free fishing test with exactly one pre-go."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
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
    args = parser.parse_args()
    mode = ['--background'] if args.background else []
    run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '_' + uuid.uuid4().hex[:6]
    folder = ROOT / 'runs' / '001_wow_fishing' / ('test_a_' + run_id)
    folder.mkdir(parents=True)
    record = {'status': 'running', 'mode': 'background' if args.background else 'foreground',
              'target_seconds': 300, 'pre_go_runs': 1, 'provider_calls': 0,
              'started_at_utc': datetime.now(timezone.utc).isoformat(), 'cycles': []}
    source = ROOT / 'experiments' / '001_wow_fishing'
    record['source_hashes'] = {
        str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in [source/'live.swift', source/'page-two.png', source/'run_test_a.py',
                  source/'probes/background-click/Adapter.swift',
                  source/'probes/background-click/NativeWindowServerPreparation.swift',
                  source/'probes/background-click/NativeBackgroundClickTransport.swift']}
    print(f'Test A {record["mode"]}; results: {folder}', flush=True)
    started = None
    try:
        prego, events = invoke(['--check', *mode], 60)
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
            result, events = invoke(['--execute', '--prepared', *mode], 45)
            (folder/f'cycle-{number:02d}.log').write_text(result.stdout + result.stderr)
            collected = any(e['event'] == 'loot_collected' for e in events)
            outcome = 'loot_collected' if collected else (events[-1]['event'] if events else 'process_failed')
            cycle = {'number': number, 'outcome': outcome, 'exit_code': result.returncode,
                     'elapsed_seconds': round(time.monotonic()-started, 2),
                     'run_path': next((e['output'] for e in events if e['event'] == 'ready'), None),
                     'item': next((e['item'] for e in events if e['event'] == 'loot_collected'), None)}
            record['cycles'].append(cycle)
            print(json.dumps(cycle), flush=True)
            consecutive_failures = 0 if collected else consecutive_failures+1
            if consecutive_failures >= 3:
                record['status'] = 'stopped_after_three_consecutive_failures'
                break
            if result.returncode or any(e['event'] in ['stopped_focus_or_geometry', 'stopped_before_click',
                                                       'loot_item_unconfirmed', 'loot_not_cleared', 'retrieval_unverified'] for e in events):
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
        record['autonomous_seconds'] = round(time.monotonic()-started, 2) if started is not None else 0
        record['verified_loot_cycles'] = sum(c['outcome'] == 'loot_collected' for c in record['cycles'])
        record['perfect_run'] = (record.get('status') == 'completed' and record['autonomous_seconds'] >= 300
                                 and bool(record['cycles']) and record['verified_loot_cycles'] == len(record['cycles']))
        record['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        (folder/'summary.json').write_text(json.dumps(record, indent=2)+'\n')
        print(json.dumps({k: record[k] for k in ['status','mode','pre_go_runs','autonomous_seconds','verified_loot_cycles','provider_calls','perfect_run']}), flush=True)


if __name__ == '__main__':
    main()
