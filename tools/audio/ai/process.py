"""把原始音频处理成游戏可用的 OGG：裁剪、单声道、44.1kHz、峰值归一、循环接缝。

    python tools/audio/ai/process.py --provider procedural
    python tools/audio/ai/process.py --provider elevenlabs --only ui_click_primary
"""
from pathlib import Path
import argparse
import hashlib
import json
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.audio.ai import dsp, spec  # noqa: E402


def sidecars(folder: Path) -> list[Path]:
    if not folder.is_dir():
        return []
    return sorted(path for path in folder.glob('*.json') if not path.name.startswith('_'))


def process_one(raw: Path, meta: dict, force: bool) -> dict | None:
    category = meta['category']
    target = spec.TARGETS[category]
    asset = meta['asset']
    out_path = spec.output_dir(meta['provider'], category) / f'{asset}.ogg'
    out_sidecar = out_path.with_suffix('.ogg.json')
    if out_sidecar.is_file() and not force:
        return json.loads(out_sidecar.read_text(encoding='utf-8'))

    samples, rate = dsp.read(raw)
    if 'source_start_seconds' in meta or 'source_end_seconds' in meta:
        start = float(meta.get('source_start_seconds', 0))
        end = float(meta.get('source_end_seconds', len(samples) / rate))
        if not np.isfinite(start) or not np.isfinite(end) or not 0 <= start < end <= len(samples) / rate:
            raise ValueError(f'Invalid selected source interval: {asset}')
        samples = samples[round(start * rate):round(end * rate)]
    samples = dsp.to_mono(samples)
    samples = dsp.resample(samples, rate, spec.SAMPLE_RATE)

    if target['loop']:
        samples = dsp.trim(samples, spec.SAMPLE_RATE, threshold_db=-55.0, pre_ms=0.0, post_ms=0.0)
        samples = dsp.loop_blend(samples, spec.SAMPLE_RATE, spec.LOOP_BLEND_SECONDS[category])
        loop = True
    else:
        samples = dsp.trim(samples, spec.SAMPLE_RATE)
        limit = int(target['max_seconds'] * spec.SAMPLE_RATE)
        if samples.size > limit:
            samples = dsp.fade(samples[:limit], spec.SAMPLE_RATE, 2.5, 25.0)
        samples = dsp.fade(samples, spec.SAMPLE_RATE)
        loop = False

    samples = dsp.normalize_peak(samples, target['peak_dbfs'])
    if loop:
        # 循环类按 RMS 对齐，避免“峰值一样但听感一响一轻”。
        target_rms = -20.0 if category == 'music' else -22.0
        current = dsp.rms_db(samples)
        if current > -60:
            samples = (samples * (10 ** ((target_rms - current) / 20))).astype(np.float32)
        if dsp.peak_db(samples) > -1.0:
            samples = dsp.normalize_peak(samples, -1.0)
    samples = dsp.soft_limit(samples)
    dsp.write_ogg(out_path, samples, spec.SAMPLE_RATE)

    metrics = dsp.features(samples, spec.SAMPLE_RATE)
    seam = None
    if loop and samples.size > 8:
        seam = float(abs(float(samples[0]) - float(samples[-1])))
    payload = dict(meta)
    payload.update({
        'path': 'res://' + out_path.relative_to(spec.ROOT).as_posix(),
        'loop': loop,
        'sample_rate': spec.SAMPLE_RATE,
        'channels': 1,
        'features': metrics,
        'seam_jump': round(seam, 6) if seam is not None else None,
        'sha256': hashlib.sha256(out_path.read_bytes()).hexdigest(),
        'bytes': out_path.stat().st_size,
    })
    out_sidecar.parent.mkdir(parents=True, exist_ok=True)
    out_sidecar.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--provider', required=True)
    parser.add_argument('--only', nargs='*')
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()

    folder = spec.RAW_ROOT / args.provider
    files = sidecars(folder)
    if args.only:
        wanted = set(args.only)
        files = [path for path in files if json.loads(path.read_text(encoding='utf-8')).get('id') in wanted]
    if not files:
        print(f'没有可处理的原始文件: {folder}')
        return 0

    rows = []
    for sidecar in files:
        meta = json.loads(sidecar.read_text(encoding='utf-8'))
        raw = sidecar.with_suffix('')
        if not raw.is_file():
            print(f'[skip] 缺少音频: {raw.name}')
            continue
        payload = process_one(raw, meta, args.force)
        if payload:
            rows.append(payload)

    print(f'{"asset":38} {"cat":10} {"sec":>6} {"peak":>6} {"rms":>6} {"centroid":>9}  loop')
    for row in rows:
        metrics = row['features']
        print(f'{row["asset"]:38} {row["category"]:10} {metrics["duration_seconds"]:6.2f} '
              f'{metrics["peak_dbfs"]:6.1f} {metrics["rms_dbfs"]:6.1f} '
              f'{metrics["spectral_centroid_hz"]:9.0f}  {row["loop"]}')
    print(f'共 {len(rows)} 条。')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
