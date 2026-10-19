"""Launch a development game session with error, log-size and duration limits."""
from pathlib import Path
import argparse
import json
import math
import os
from datetime import datetime

from godot_process import run_guarded


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_EXE', 'D:/Godot4/Godot_v4.6.2-stable_win64_console.exe'))
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--out', type=Path, help='Session output directory, preferably outside the working copy.')
    parser.add_argument('--timeout', type=float, default=1800, help='Session duration limit in real seconds.')
    parser.add_argument('--max-log-mb', type=float, default=16)
    parser.add_argument('engine_args', nargs=argparse.REMAINDER, help='Godot arguments after --.')
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0 or not math.isfinite(args.max_log_mb) or args.max_log_mb < 1 / 1024:
        parser.error('Use a positive finite timeout and a log limit of at least 1 KiB.')
    root = args.project.resolve()
    if not (root / 'project.godot').is_file():
        parser.error('Project must contain project.godot.')
    extra = args.engine_args[1:] if args.engine_args[:1] == ['--'] else args.engine_args
    if any(arg.split('=')[0] in ['--path', '--log-file', '--editor', '-e', '--project-manager'] for arg in extra):
        parser.error('The supervised game session owns its project and log paths; editor mode is unsupported.')
    # A unique default path prevents concurrently launched previews from sharing a log.
    out = (args.out or root / '.maintenance' / 'sessions' /
           (datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '-%d' % os.getpid())).resolve()
    out.mkdir(parents=True, exist_ok=True)
    userdata = out / 'userdata'
    userdata.mkdir(exist_ok=True)
    env = dict(os.environ, APPDATA=str(userdata), LOCALAPPDATA=str(userdata),
               TEMP=str(userdata), TMP=str(userdata))
    engine_log = out / 'engine.log'
    command = [args.godot, '--path', str(root), '--log-file', str(engine_log), *extra]
    result = run_guarded(command, cwd=root, env=env, log_path=out / 'console.log',
                         engine_log=engine_log, timeout=args.timeout,
                         max_log_bytes=int(args.max_log_mb * 1024 * 1024))
    report = dict(exit_code=result.exit_code, seconds=result.seconds, stopped=result.stopped,
                  errors=result.errors, output=str(out))
    (out / 'session.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=True))
    return 0 if result.exit_code == 0 and not result.stopped and not result.errors else 1


if __name__ == '__main__':
    raise SystemExit(main())
