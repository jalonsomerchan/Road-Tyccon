"""Run Godot checks sequentially in isolated projects; never use the player's save.

The historical suite expects 400 cities, so its fixture uses a 2048-cell region.
The gameplay suite also runs against the workspace's actual configuration.
"""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
GODOT = sys.argv[1] if len(sys.argv) > 1 else '/Applications/Godot.app/Contents/MacOS/Godot'
CASES = ['smoke', 'starting_cities', 'road_connections', 'presentation', 'visual_refresh',
         'expanding_world', 'cheats', 'urban_roads', 'city_layout', 'incidents',
         'condition_assets', 'navigation_toolbar', 'title_screen', 'gameplay', 'event_notices', 'curves', 'steam_deck']

def run(project, case, extra=()):
    args = [GODOT, '--headless', '--path', str(project), '--log-file',
            str(project / f'{case}.log'), '--script', f'tests/{case}.gd', '--', '--test-mode', *extra]
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=55)
        output = result.stdout + result.stderr
        ok = result.returncode == 0 and 'PASS:' in output and 'SCRIPT ERROR' not in output
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or b'').decode() + (error.stderr or b'').decode()
        ok = False
    print(('PASS' if ok else 'FAIL') + ': ' + case, flush=True)
    if not ok:
        print(output, flush=True)
    return ok

with tempfile.TemporaryDirectory(prefix='entre-ciudades-checks-') as directory:
    target = Path(directory)
    for folder in ['scripts', 'scenes', 'tests']:
        shutil.copytree(ROOT / folder, target / folder, ignore=shutil.ignore_patterns('*.png', '*.bin'))
    for folder in ['assets', '.godot']:
        (target / folder).symlink_to(ROOT / folder, target_is_directory=True)
    shutil.copy2(ROOT / 'project.godot', target / 'project.godot')
    failures = 0
    failures += not run(target, 'gameplay')
    settings = target / 'scripts/world_settings.gd'
    settings.write_text(re.sub(r'(?m)^const INITIAL_SIDE = [^\n]+', 'const INITIAL_SIDE = 2048', settings.read_text()))
    for case in CASES:
        failures += not run(target, case, ['--title-screen'] if case == 'title_screen' else [])
    print(f'{len(CASES)+1-failures}/{len(CASES)+1} checks passed', flush=True)
    sys.exit(1 if failures else 0)
