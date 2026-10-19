"""批量生成原始音频：ElevenLabs 在线生成，或离线程序合成占位音。

    python tools/audio/ai/generate.py --provider procedural
    python tools/audio/ai/generate.py --provider elevenlabs --dry-run
    python tools/audio/ai/generate.py --provider elevenlabs --only ui_click_primary
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.audio.ai import dsp, elevenlabs, procedural, spec  # noqa: E402


def load_batches(names: list[str]) -> list[dict]:
    items: list[dict] = []
    for name in names:
        path = Path(__file__).resolve().parent / f'batch_{name}.json'
        if not path.is_file():
            raise SystemExit(f'找不到批次清单: {path}')
        payload = json.loads(path.read_text(encoding='utf-8'))
        items.extend(payload['items'])
    return items


def raw_path(provider: str, asset: str, extension: str) -> Path:
    return spec.RAW_ROOT / provider / f'{asset}.{extension}'


def write_sidecar(path: Path, payload: dict) -> None:
    path.with_suffix(path.suffix + '.json').write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def detect_extension(data: bytes, output_format: str) -> str:
    if data[:4] == b'RIFF':
        return 'wav'
    if data[:3] == b'ID3' or data[:2] in (b'\xff\xfb', b'\xff\xf3', b'\xff\xf2'):
        return 'mp3'
    return 'wav' if 'wav' in (output_format or '') else 'mp3'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--provider', choices=['elevenlabs', 'procedural'], default='procedural')
    parser.add_argument('--batch', default='sfx,music', help='逗号分隔: sfx,music')
    parser.add_argument('--only', nargs='*', help='只生成这些 id')
    parser.add_argument('--variants', type=int, help='覆盖批次里的变体数')
    parser.add_argument('--force', action='store_true', help='已有原文件也重新生成')
    parser.add_argument('--dry-run', action='store_true', help='只打印计划，不调用接口')
    parser.add_argument('--check', action='store_true', help='查询 ElevenLabs 订阅额度')
    args = parser.parse_args()
    spec.ensure_ignored_dirs()

    if args.check:
        info = elevenlabs.subscription()
        used = info.get('character_count')
        limit = info.get('character_limit')
        print(json.dumps({'tier': info.get('tier'), 'used': used, 'limit': limit,
                          'remaining': (limit - used) if isinstance(used, int) and isinstance(limit, int) else None},
                         ensure_ascii=False, indent=2))
        return 0

    items = load_batches([part.strip() for part in args.batch.split(',') if part.strip()])
    if args.only:
        wanted = set(args.only)
        items = [item for item in items if item['id'] in wanted]
        missing = wanted - {item['id'] for item in items}
        if missing:
            raise SystemExit('未知 id: ' + ', '.join(sorted(missing)))

    defaults = {'variants': 1, 'prompt_influence': 0.55}
    total_credits = 0
    planned = 0
    for item in items:
        if args.provider == 'procedural' and not item.get('procedural'):
            continue
        if args.provider == 'elevenlabs' and item['category'] in ('music', 'ambience'):
            print(f'[skip] {item["id"]}: 音效接口不产 BGM/环境音，走 Suno 或 Eleven Music API')
            continue
        variants = args.variants or item.get('variants') or defaults['variants']
        for variant in range(1, variants + 1):
            asset = spec.asset_name(item, variant)
            existing = list((spec.RAW_ROOT / args.provider).glob(f'{asset}.*'))
            existing = [path for path in existing if not path.name.endswith('.json')]
            complete = [path for path in existing if path.with_suffix(path.suffix + '.json').is_file()]
            if complete and not args.force:
                continue
            planned += 1
            seconds = float(item.get('duration') or item.get('loop_seconds') or 30.0)
            if args.provider == 'elevenlabs':
                total_credits += elevenlabs.estimate_credits(seconds)
                if args.dry_run:
                    print(f'[plan] {asset}  {seconds:.2f}s  ~{elevenlabs.estimate_credits(seconds)} credits')
                    continue
                prompt = spec.build_prompt(item)
                audio, output_format = elevenlabs.generate(
                    prompt, seconds, item.get('prompt_influence', defaults['prompt_influence']))
                extension = detect_extension(audio, output_format)
                path = raw_path(args.provider, asset, extension)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(audio)
                print(f'[ok] {path.relative_to(ROOT)}  {len(audio) / 1024:.1f} KB')
            else:
                samples = procedural.render(item['procedural'])
                path = raw_path(args.provider, asset, 'wav')
                dsp.write_wav(path, samples, procedural.SR)
                extension = 'wav'
                output_format = 'wav_48000'
                print(f'[ok] {path.relative_to(ROOT)}  {samples.size / procedural.SR:.2f}s')
            write_sidecar(path, {
                'id': item['id'],
                'variant': variant,
                'asset': asset,
                'provider': args.provider,
                'category': item['category'],
                'title': item['title'],
                'prompt': spec.build_prompt(item) if args.provider == 'elevenlabs' else item['prompt'],
                'source_prompt': item['prompt'],
                'duration_seconds': seconds,
                'output_format': output_format,
                'tags': item.get('tags', []),
                'license': spec.LICENSES[args.provider],
                'author': spec.AUTHOR[args.provider],
                'source': spec.SOURCE[args.provider],
                'recipe': item.get('procedural'),
                'created_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            })

    if args.provider == 'elevenlabs' and not args.dry_run:
        print(f'完成 {planned} 条，预计消耗 {total_credits} credits。')
    else:
        print(f'完成 {planned} 条。')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
