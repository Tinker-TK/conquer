"""一条命令跑完整条流水线：生成 → 处理 → 质检分类 → 入清单 → 重建试听场景。

    python tools/audio/ai/pipeline.py --provider procedural
    python tools/audio/ai/pipeline.py --provider elevenlabs --dry-run
    python tools/audio/ai/pipeline.py --provider suno --skip-generate

Suno 没有公开 API，先生成提示词，去网页端出稿后放进 assets/audio/ai/inbox/suno/，
再跑 ingest_suno.py 把这些文件接进同一条流水线。
"""
from pathlib import Path
import argparse
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def run(script: Path, *args: str) -> None:
    command = [sys.executable, str(script), *args]
    print('\n$ ' + ' '.join(Path(part).name if part == str(script) else part for part in command[1:]))
    result = subprocess.run(command, cwd=ROOT)
    if result.returncode != 0:
        raise SystemExit(f'步骤失败: {script.name}')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--provider', choices=['procedural', 'elevenlabs', 'suno'], default='procedural')
    parser.add_argument('--batch', default='sfx,music')
    parser.add_argument('--only', nargs='*')
    parser.add_argument('--variants', type=int)
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--skip-generate', action='store_true')
    parser.add_argument('--skip-scene', action='store_true')
    args = parser.parse_args()

    only = list(args.only or [])
    if not args.skip_generate and not args.dry_run and args.provider != 'suno':
        extra = ['--provider', args.provider, '--batch', args.batch]
        extra += ['--only', *only] if only else []
        extra += ['--variants', str(args.variants)] if args.variants else []
        extra += ['--force'] if args.force else []
        run(HERE / 'generate.py', *extra)

    if args.dry_run:
        run(HERE / 'generate.py', '--provider', 'elevenlabs', '--batch', args.batch, '--dry-run',
            *(['--only', *only] if only else []))

    if not args.dry_run:
        process_args = ['--provider', args.provider]
        process_args += ['--only', *only] if only else []
        process_args += ['--force'] if args.force else []
        run(HERE / 'process.py', *process_args)
        run(HERE / 'classify.py', '--provider', args.provider)
        run(HERE / 'library.py', '--provider', args.provider)
        if not args.skip_scene:
            run(ROOT / 'tools/audio/build_audio_library.py')

    print('\n下一步：用 Godot 打开 res://examples/scenes/audio_library.tscn，按 F6 试听。')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
