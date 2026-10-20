#!/usr/bin/env python3
"""Explicit, short UI-only CPU observation. Never changes notes, timer or network settings."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
STATE = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state')))
CONTROL = STATE / 'noctalia/plugins/data/pang/tide-sidebar/private/frontend/control.json'
TICKS = os.sysconf('SC_CLK_TCK')
PAGE = os.sysconf('SC_PAGE_SIZE')

def ipc(action, page=None):
    argv = ['noctalia', 'msg', 'plugin', 'pang/tide-sidebar:backend', 'all', action]
    if page: argv.append(page)
    subprocess.run(argv, check=True, stdout=subprocess.DEVNULL, timeout=5)

def pids(pattern, exact=False):
    result = subprocess.run(['pgrep', '-x' if exact else '-f', pattern], capture_output=True, text=True, check=False)
    if result.returncode: raise RuntimeError('Required process is not running')
    return [int(item) for item in result.stdout.split()]

def usage(pid):
    # Kernel counters only; no command line, note content, passwords or application titles.
    tail = Path('/proc/' + str(pid) + '/stat').read_text().rsplit(')', 1)[1].split()
    return int(tail[11]) + int(tail[12]), int(tail[21]) * PAGE / (1024 * 1024)

def sample(targets, seconds):
    before = {name: [usage(pid)[0] for pid in values] for name, values in targets.items()}
    started = time.monotonic()
    time.sleep(seconds)
    elapsed = time.monotonic() - started
    result = {'seconds': round(elapsed, 3)}
    total = 0
    for name, values in targets.items():
        after = [usage(pid) for pid in values]
        cpu = sum(item[0] - old for item, old in zip(after, before[name])) / TICKS / elapsed * 100
        result[name] = {'one_core_cpu_percent': round(cpu, 2), 'rss_mib': round(sum(item[1] for item in after), 1)}
        total += cpu
    result['combined_one_core_cpu_percent'] = round(total, 2)
    return result

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--allow-ui-toggle', action='store_true')
parser.add_argument('--seconds', type=float, default=6)
args = parser.parse_args()
if not args.allow_ui_toggle: parser.error('explicit --allow-ui-toggle required')
if not 3 <= args.seconds <= 20: parser.error('seconds must be between 3 and 20')
original = json.loads(CONTROL.read_text())['data']
if original.get('visible') and original.get('page') == 'notes':
    raise SystemExit('Please close the notes page before this optional UI observation.')
try:
    ipc('show', 'tools')
    time.sleep(1.1)  # exclude cold presentation/stylesheet setup from the short sample
    targets = {'noctalia': pids('noctalia', True),
               'native_ui': pids('^gjs -m ' + re.escape(str(ROOT / 'native/main.js')))}
    opened = sample(targets, args.seconds)
    ipc('hide')
    time.sleep(0.3)
    closed = sample(targets, args.seconds)
    print(json.dumps({'open_tools': opened, 'closed': closed,
        'scope': 'Short whole-process CPU/RSS observation, including unrelated shell activity; not FPS or input latency.'}, ensure_ascii=False, indent=2))
finally:
    ipc('show' if original.get('visible') else 'hide', original.get('page', 'notes'))
