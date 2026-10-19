"""把处理好的成品并入统一试听清单 assets/audio/library/manifest.json。

清单是试听场景的唯一事实来源：先入清单，再由 build_audio_library.py 生成场景。

    python tools/audio/ai/library.py --provider procedural
"""
from pathlib import Path
import argparse
import json
import sys

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.audio.ai import spec  # noqa: E402

MANIFEST = spec.SAMPLES_ROOT / 'manifest.json'
AI_PREFIX = 'res://assets/audio/ai/'


def to_entry(meta: dict) -> dict:
    title = meta['title']
    if meta['provider'] == 'procedural':
        title += '（占位）'
    notes = []
    if meta['provider'] == 'procedural':
        notes.append('离线程序合成占位音，用于打通流水线，待 AI 生成后替换。')
    if meta.get('selection_note'):
        notes.append(meta['selection_note'])
    if meta.get('source_prompt'):
        notes.append('提示词：' + meta['source_prompt'])
    if meta.get('tags'):
        notes.append('标签：' + '/'.join(meta['tags']))
    notes.append('循环 ' + ('是' if meta['loop'] else '否') + f'；{meta["features"]["duration_seconds"]:.2f}s')
    changes = '自动处理：裁剪首尾静音、单声道、44.1kHz、峰值归一、淡入淡出、转 OGG Vorbis。'
    if meta['loop']:
        changes = '自动处理：单声道、44.1kHz、峰值归一、等功率首尾交叉淡化做循环接缝、转 OGG Vorbis。'
    return {
        'path': meta['path'],
        'title': title,
        'category': meta['category'],
        'notes': '；'.join(notes),
        'author': meta['author'],
        'source': meta['source'],
        'license': meta['license'],
        'changes': changes,
        'sha256': meta['sha256'],
        'provider': meta['provider'],
        'tags': meta.get('tags', []),
        'prompt': meta.get('source_prompt', ''),
        'duration_seconds': meta['features']['duration_seconds'],
        'loop': meta['loop'],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--provider', required=True)
    args = parser.parse_args()

    folder = spec.AI_ROOT / args.provider
    files = sorted(folder.glob('*/*.ogg.json'))
    if not files:
        print(f'没有可入库的成品: {folder}')
        return 0

    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    entries = [to_entry(json.loads(path.read_text(encoding='utf-8'))) for path in files]
    incoming = {entry['path']: entry for entry in entries}

    kept = []
    removed = 0
    for entry in manifest['files']:
        path = entry['path']
        if path in incoming:
            removed += 1
            continue
        if path.startswith(AI_PREFIX) and not (ROOT / path.removeprefix('res://')).is_file():
            removed += 1
            continue
        kept.append(entry)
    kept.extend(entries)

    manifest['files'] = kept
    manifest['ai_updated_on'] = max(
        (json.loads(path.read_text(encoding='utf-8')).get('created_at', '') for path in files), default='')
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'清单更新：新增/替换 {len(entries)} 条，清理 {removed} 条旧条目，总计 {len(kept)} 条。')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
