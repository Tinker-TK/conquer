"""接收 Suno 网页端手动下载的成品，归档成与其它 provider 相同的原始文件结构。

用法：
    1. python tools/audio/ai/ingest_suno.py --list         # 看还缺哪些条目
    2. 在 Suno 按提示词出稿，下载 mp3，按 bgm_xxx_v01.mp3 命名放进 assets/audio/ai/inbox/suno/
    3. python tools/audio/ai/ingest_suno.py                # 归档到 _raw/suno/
    4. python tools/audio/ai/pipeline.py --provider suno --skip-generate
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.audio.ai import spec  # noqa: E402

SUPPORTED = {'.mp3', '.wav', '.ogg', '.flac'}
VARIANT = re.compile(r'^(?P<base>.+?)_v(?P<variant>\d{2})$')


def load_music() -> list[dict]:
    path = Path(__file__).resolve().parent / 'batch_music.json'
    return json.loads(path.read_text(encoding='utf-8'))['items']


def guess(filename: str, items: list[dict]) -> tuple[dict, int]:
    stem = Path(filename).stem
    match = VARIANT.match(stem)
    base = match.group('base') if match else stem
    variant = int(match.group('variant')) if match else 1
    for item in items:
        if item['id'] == base:
            return item, variant
    category = 'music' if base.startswith('bgm_') else 'ambience' if base.startswith('amb_') else 'music'
    return {'id': base, 'category': category, 'title': base, 'prompt': '', 'tags': ['manual']}, variant


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list', action='store_true', help='列出批次条目和已归档状态')
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    spec.ensure_ignored_dirs()

    items = load_music()
    done = {json.loads(path.read_text(encoding='utf-8'))['id']
            for path in (spec.RAW_ROOT / 'suno').glob('*.json')} if (spec.RAW_ROOT / 'suno').is_dir() else set()

    if args.list:
        for item in items:
            mark = 'x' if item['id'] in done else ' '
            print(f'[{mark}] {item["id"]:24} {item["title"]:16} {item.get("suno_prompt", item["prompt"])}')
        return 0

    inbox = spec.INBOX_ROOT / 'suno'
    inbox.mkdir(parents=True, exist_ok=True)
    files = sorted(path for path in inbox.iterdir()
                   if path.is_file() and path.suffix.lower() in SUPPORTED and not path.name.startswith('_'))
    if not files:
        print(f'收件箱是空的: {inbox}')
        print('先运行 --list 看提示词，把 Suno 下载的文件按 bgm_xxx_v01.mp3 命名放进去。')
        return 0

    archived = 0
    for path in files:
        item, variant = guess(path.name, items)
        asset = spec.asset_name(item, variant)
        target = spec.RAW_ROOT / 'suno' / f'{asset}{path.suffix.lower()}'
        if target.exists() and not args.force:
            print(f'[skip] 已存在: {target.name}')
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        target.with_suffix(target.suffix + '.json').write_text(json.dumps({
            'id': item['id'],
            'variant': variant,
            'asset': asset,
            'provider': 'suno',
            'category': item['category'],
            'title': item['title'],
            'prompt': item.get('suno_prompt', item.get('prompt', '')),
            'source_prompt': item.get('suno_prompt', item.get('prompt', '')),
            'duration_seconds': item.get('loop_seconds', 30),
            'output_format': path.suffix.lower().lstrip('.'),
            'tags': item.get('tags', []),
            'license': spec.LICENSES['suno'],
            'author': spec.AUTHOR['suno'],
            'source': spec.SOURCE['suno'],
            'recipe': None,
            'created_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
            'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
            'note': 'Suno 免费档输出仅用于内部试听；商用前必须复核授权。',
        }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        archived += 1
        print(f'[ok] {path.name} -> {target.relative_to(ROOT)}')

    print(f'归档 {archived} 条。下一步: python tools/audio/ai/pipeline.py --provider suno --skip-generate')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
