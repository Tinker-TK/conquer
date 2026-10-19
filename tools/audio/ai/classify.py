"""质检与自动标注：按规范检查时长、响度、单声道与循环接缝，并补充音色标签。

    python tools/audio/ai/classify.py --provider procedural [--strict]
"""
from pathlib import Path
import argparse
import json
import sys

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.audio.ai import spec  # noqa: E402


def brightness(centroid: float) -> str:
    if centroid < 1200:
        return 'dark'
    if centroid < 3000:
        return 'balanced'
    return 'bright'


def review(entry: dict) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    tags: list[str] = []
    metrics = entry['features']
    target = spec.TARGETS[entry['category']]
    duration = metrics['duration_seconds']
    peak = metrics['peak_dbfs']

    if entry['channels'] != 1:
        problems.append('不是单声道')
    if duration < 0.05:
        problems.append('短于 50ms')
    if not entry['loop'] and duration > target['max_seconds'] + 0.05:
        problems.append(f'超出 {target["max_seconds"]:.1f}s 上限')
    if peak > 0.1:
        problems.append('峰值越界，可能削波')
    if peak < -12:
        problems.append('峰值过低，可能过轻')
    if entry['loop']:
        if duration < 4:
            problems.append('循环短于 4s')
        seam = entry.get('seam_jump') or 0.0
        if seam > 0.02:
            problems.append(f'循环接缝跳变 {seam:.3f}')
        tags.append('loop')
    else:
        tags.append('one-shot')
        if metrics['attack_ms'] <= 15:
            tags.append('percussive')
        else:
            tags.append('soft-attack')
    tags.append(brightness(metrics['spectral_centroid_hz']))
    if metrics['crest_db'] > 18:
        tags.append('spiky')
    elif metrics['crest_db'] < 9:
        tags.append('compressed')
    return problems, tags


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--provider', required=True)
    parser.add_argument('--strict', action='store_true', help='有问题时返回非零退出码')
    args = parser.parse_args()

    folder = spec.AI_ROOT / args.provider
    files = sorted(folder.glob('*/*.ogg.json'))
    if not files:
        print(f'没有可分类的成品: {folder}')
        return 0

    entries = []
    failures = 0
    print(f'{"asset":38} {"cat":10} {"sec":>6} {"peak":>6} {"centroid":>9}  tags')
    for sidecar in files:
        entry = json.loads(sidecar.read_text(encoding='utf-8'))
        problems, auto_tags = review(entry)
        entry['tags'] = sorted(set(entry.get('tags', []) + auto_tags))
        entry['problems'] = problems
        entries.append(entry)
        failures += 1 if problems else 0
        flag = '!' if problems else ' '
        print(f'{entry["asset"]:38} {entry["category"]:10} '
              f'{entry["features"]["duration_seconds"]:6.2f} {entry["features"]["peak_dbfs"]:6.1f} '
              f'{entry["features"]["spectral_centroid_hz"]:9.0f}  {flag}{",".join(entry["tags"])}')
        for problem in problems:
            print(f'    - {problem}')

    index = {'provider': args.provider, 'count': len(entries), 'entries': entries}
    (folder / 'index.json').write_text(json.dumps(index, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'共 {len(entries)} 条；{failures} 条有告警。索引: {folder / "index.json"}')
    return 1 if (args.strict and failures) else 0


if __name__ == '__main__':
    raise SystemExit(main())
