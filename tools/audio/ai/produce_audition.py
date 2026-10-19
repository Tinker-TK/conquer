"""Produce the 2026-10-19 listening batch from CC0 foley and original synthesis.

No network or account is needed. These are explicitly local sound designs, not
ElevenLabs/Suno results. Prompts and per-layer provenance accompany every file.
Run with the project's numpy/soundfile Python, then build_audio_library.py.
"""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path[:0] = [str(ROOT), str(ROOT / '.maintenance/audio-tools')]
import numpy as np
import soundfile as sf
from tools.audio.ai import classify, dsp, procedural, spec

SR = 44100
BATCH_FILE = Path(__file__).with_name('batch_audition_20261019.json')
OUT = ROOT / 'assets/audio/ai/local_design'
REVIEW = ROOT / 'outputs/audio-audition-20261019'
MANIFEST = ROOT / 'assets/audio/library/manifest.json'
SOURCE = 'res://tools/audio/ai/produce_audition.py'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def n(seconds):
    return round(seconds * SR)


def envelope(seconds, decay, attack=.001):
    t = np.arange(n(seconds)) / SR
    return np.minimum(t / attack, 1) * np.exp(-t / decay)


def band(x, low=0, high=18000):
    f = np.fft.rfftfreq(len(x), 1 / SR)
    gain = 1 / (1 + (f / high) ** 6)
    if low:
        gain *= 1 - 1 / (1 + (f / low) ** 6)
    return np.fft.irfft(np.fft.rfft(x) * gain, len(x)).astype(np.float32)


def noise(rng, seconds, low, high):
    return band(rng.normal(0, 1, n(seconds)), low, high)


def put(out, clip, at=0, gain=1, wrap=False):
    start = n(at)
    if wrap:
        indices = (np.arange(len(clip)) + start) % len(out)
        np.add.at(out, indices, clip * gain)
    elif start < len(out):
        count = min(len(clip), len(out) - start)
        out[start:start + count] += clip[:count] * gain


def tone(freq, seconds, decay=.16, attack=.002, harmonics=3):
    t = np.arange(n(seconds)) / SR
    wave = sum(np.sin(2 * np.pi * freq * h * t) / h ** 1.8 for h in range(1, harmonics + 1))
    return wave * envelope(seconds, decay, attack)


def thump(rng, seconds=.25, freq=100):
    t = np.arange(n(seconds)) / SR
    phase = 2 * np.pi * (freq * .46 * t + freq * .54 * .025 * (1 - np.exp(-t / .025)))
    return (np.sin(phase) + .22 * noise(rng, seconds, 90, 1500)) * envelope(seconds, .065)


def procedural_clip(name, speed=1):
    x = procedural.render(name)
    return dsp.resample(x, round(procedural.SR * speed), SR)


def foley(relative, sources, catalog, speed=1, seconds=None):
    path = 'res://assets/audio/' + relative
    meta = catalog[path]
    if meta['license'] != 'CC0-1.0':
        raise ValueError('This batch uses CC0 foley only: ' + path)
    file = ROOT / path[6:]
    if digest(file) != meta['sha256']:
        raise ValueError('Source changed: ' + path)
    sources[path] = {key: meta[key] for key in ('path', 'author', 'source', 'license', 'sha256')}
    x, rate = sf.read(file, dtype='float32', always_2d=True)
    mono = x.mean(axis=1)
    # Opposed stereo weapon recordings must not disappear in a mono preview.
    if np.mean(mono ** 2) < .25 * np.max(np.mean(x ** 2, axis=0)):
        mono = x[:, np.argmax(np.mean(x ** 2, axis=0))]
    mono = dsp.resample(mono, round(rate * speed), SR)
    mono = dsp.trim(mono, SR, threshold_db=-44, pre_ms=1, post_ms=18)
    mono /= max(float(np.max(np.abs(mono))), .001)
    if seconds:
        mono = mono[:n(seconds)]
    return dsp.fade(mono, SR, .5, 15)


def music(battle, rng):
    # Both arrangements share 96 BPM, 8 bars, D minor and an identical motif.
    beat, seconds = .625, 20
    out = np.zeros(n(seconds), np.float32)
    chords = [(50, 57, 62, 65), (46, 53, 58, 62), (48, 55, 60, 64), (45, 52, 57, 61)]
    motif = [74, 77, 81, 79, 77, 74, 72, 69, 74, 77, 79, 81, 84, 81, 77, 74]
    hz = lambda midi: 440 * 2 ** ((midi - 69) / 12)
    for step in range(64):
        chord = chords[(step // 16) % 4]
        note = chord[1 + (step % 3)]
        put(out, tone(hz(note), 1.8, .29, harmonics=6), step * beat / 2,
            .085 if battle else .07, True)
    for i, note in enumerate(motif):
        # Breath and gentle vibrato keep the tune distinct from UI chimes.
        t = np.arange(n(1.5)) / SR
        phase = 2 * np.pi * hz(note) * t + .035 * np.sin(2 * np.pi * 4.8 * t)
        flute = (np.sin(phase) + .09 * np.sin(phase * 2)) * envelope(1.5, .5, .045)
        put(out, flute, i * 2 * beat, .07 if battle else .12, True)
    for bar in range(8):
        chord = chords[(bar // 2) % 4]
        put(out, tone(hz(chord[0]), 2.8, .65, .012, 3), bar * 4 * beat, .14, True)
        if battle:
            for step in (0, 1.5, 2, 3.5):
                put(out, thump(rng, .3, 112), (bar * 4 + step) * beat, .32, True)
            for step in (1, 3):
                hit = noise(rng, .13, 450, 4300) * envelope(.13, .028)
                put(out, hit, (bar * 4 + step) * beat, .13, True)
    return out


def ambience(name, rng):
    seconds = 16
    t = np.arange(n(seconds)) / SR
    if name == 'forest':
        x = noise(rng, seconds, 180, 2900) * (.12 + .045 * np.sin(2 * np.pi * t / 8))
        for i in range(12):
            length = rng.uniform(.11, .2)
            tt = np.arange(n(length)) / SR
            f = rng.uniform(2300, 3500)
            chirp = np.sin(2 * np.pi * (f * tt + 650 * tt ** 2)) * np.sin(np.pi * tt / length) ** 2
            put(x, chirp, rng.uniform(0, seconds), .025, True)
    else:
        x = noise(rng, seconds, 55, 650) * .065 + noise(rng, seconds, 900, 4500) * .012
        x *= 1 + .18 * np.sin(2 * np.pi * t / 4)
        for i in range(105):
            length = rng.uniform(.012, .05)
            pop = noise(rng, length, 350, 6500) * envelope(length, .007)
            put(x, pop, rng.uniform(0, seconds), rng.uniform(.025, .11), True)
    return x


def render(item, variant, catalog):
    seed = int(hashlib.sha256((item['id'] + str(variant)).encode()).hexdigest()[:8], 16)
    rng = np.random.default_rng(seed)
    recipe = item['recipe']
    sources = {}
    speed = .94 if variant == 2 else 1.04
    if recipe.startswith('music_'):
        return music(recipe == 'music_battle', rng), sources, seed
    if recipe in ('forest', 'campfire'):
        return ambience(recipe, rng), sources, seed
    out = np.zeros(n(item['duration']), np.float32)
    get = lambda path, **kw: foley(path, sources, catalog, **kw)
    if recipe == 'sword':
        put(out, get('library/swishes/swish_3.ogg', speed=speed * 1.25), gain=.6)
        put(out, noise(rng, .18, 1400, 7500) * envelope(.18, .045), gain=.12)
    elif recipe == 'axe':
        put(out, get('library/medieval-textures/axe_swing_02.ogg', speed=speed * .88), gain=.65)
        put(out, get('combat/kenney-rpg/chop.ogg', speed=speed * .9), .09, .26)
        put(out, thump(rng, .4, 96), .09, .24)
    elif recipe == 'parry':
        put(out, get('library/medieval-impacts/axe_katana_blade_on_blade_02.ogg', speed=speed), gain=.75)
        put(out, thump(rng, .13, 180), gain=.08)
    elif recipe == 'bow':
        put(out, get('library/medieval-textures/scythian_recurve_shoot_02.ogg', speed=speed), gain=.8)
        put(out, procedural_clip('bow_release', speed), gain=.13)
    elif recipe == 'hit':
        put(out, get('library/body-hits/hit05_mp3.ogg', speed=speed * .96), gain=.72)
        put(out, get('combat/kenney-rpg/dropLeather.ogg', speed=speed * 1.2), gain=.17)
        put(out, thump(rng, .21, 117), gain=.12)
    elif recipe == 'fire_cast':
        put(out, get('library/swishes/swish_5.ogg', speed=speed * 1.2), gain=.37)
        put(out, procedural_clip('fire_cast', speed * 1.6), gain=.6)
    elif recipe == 'fire_hit':
        put(out, get('library/explosions/explosion2.ogg', speed=speed * 1.35), gain=.45)
        put(out, thump(rng, .45, 105), gain=.32)
        put(out, noise(rng, .55, 600, 4800) * envelope(.55, .13), gain=.28)
    elif recipe == 'ice':
        put(out, get('combat/kenney-impact/impactGlass_light_000.ogg', speed=speed * 1.15), gain=.54)
        for i in range(8):
            put(out, tone(rng.uniform(1900, 6200), .25, .04, harmonics=1), i * .036, .085)
        put(out, noise(rng, .3, 3000, 11000) * envelope(.3, .06), gain=.1)
    elif recipe == 'lightning':
        put(out, noise(rng, .1, 800, 9500) * envelope(.1, .011), gain=.55)
        put(out, noise(rng, .65, 75, 1400) * envelope(.65, .16), gain=.4)
        put(out, thump(rng, .4, 135), gain=.2)
        for at in (.045, .085, .14):
            put(out, noise(rng, .04, 1600, 10000) * envelope(.04, .005), at, .16)
    elif recipe == 'heal':
        for i, freq in enumerate((587.33, 739.99, 880, 1174.66)):
            put(out, tone(freq * (1.015 if variant == 2 else 1), .8, .22, .012, 2), i * .07, .16)
        put(out, noise(rng, .8, 3600, 9000) * envelope(.8, .18, .045), .03, .035)
    elif recipe in ('draw', 'play', 'click'):
        name = {'draw': 'card_draw', 'play': 'card_play', 'click': 'ui_click'}[recipe]
        put(out, procedural_clip(name, speed * (1.25 if recipe == 'draw' else 1)), gain=.5)
        if recipe != 'draw':
            put(out, get('combat/kenney-impact/impactWood_medium_000.ogg', speed=speed * 1.6, seconds=.07), gain=.14)
    else:
        raise ValueError(recipe)
    return out, sources, seed


def write_asset(item, variant, x, sources, seed, batch):
    loop = item.get('loop', item['category'] in ('music', 'ambience'))
    x = np.asarray(x, dtype=np.float32)
    x -= np.mean(x)
    if not loop:
        x = dsp.trim(x, SR, threshold_db=-50, pre_ms=1, post_ms=25)
        x = dsp.fade(x, SR, .8, 18)
    # Moderate crest reduction makes rapid repeats easier to compare.
    x /= max(float(np.max(np.abs(x))), .001)
    x = np.tanh(x * 1.15).astype(np.float32)
    x = dsp.normalize_peak(x, -3)
    if loop:
        target = -23 if item['category'] == 'ambience' else -21
        x *= min(10 ** ((target - dsp.rms_db(x)) / 20), 1)
        # A 2 ms bridge controls the seam without periodic gain dips.
        count = n(.002)
        delta = x[0] - x[-1]
        x[-count:] += np.linspace(0, delta, count, dtype=np.float32)
    asset = spec.asset_name(item, variant)
    path = OUT / item['category'] / (asset + '.ogg')
    dsp.write_ogg(path, x, SR)
    decoded, rate = sf.read(path, dtype='float32')
    metrics = dsp.features(decoded, rate)
    if not np.all(np.isfinite(decoded)) or metrics['peak_dbfs'] > -1 or metrics['rms_dbfs'] < -45:
        raise ValueError('Output QA failed: ' + asset)
    seam = abs(float(decoded[0] - decoded[-1])) if loop else None
    if loop and seam > .02:
        raise ValueError('Loop seam failed: ' + asset)
    relative = 'res://' + path.relative_to(ROOT).as_posix()
    title = item['title'] + ((' · A 清脆' if variant == 1 else ' · B 厚重') if item['variants'] == 2 else '')
    meta = dict(path=relative, asset=asset, title=title, category=item['category'], domain=item['domain'],
                batch=batch, provider='local_design', recipe=item['recipe'], variant=variant, seed=seed,
                prompt=item['prompt'], author='项目本地声音设计（CC0 分层素材＋原创程序合成）',
                source=SOURCE, license='CC0-1.0', source_layers=list(sources.values()),
                changes='分层混音、确定性变体、裁剪静音、44.1kHz 单声道、短淡入淡出、峰值控制、OGG；循环保留完整小节。',
                notes='本批试听 · 本地制作；' + item['domain'] + ('；可循环。' if loop else '；单次动作。'),
                duration_seconds=metrics['duration_seconds'], loop=loop, features=metrics, channels=1, sample_rate=SR,
                seam_jump=seam, sha256=digest(path), created_at=datetime.now(timezone.utc).isoformat(timespec='seconds'))
    problems, tags = classify.review(meta)
    if problems:
        raise ValueError(f'{asset}: {problems}')
    meta.update(tags=tags, problems=problems)
    path.with_suffix('.ogg.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return meta, decoded


def main():
    payload = json.loads(BATCH_FILE.read_text(encoding='utf-8'))
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    catalog = {e['path']: e for e in manifest['files']}
    old = json.loads((ROOT / 'assets/audio/combat/manifest.json').read_text(encoding='utf-8'))
    for e in old['files']:
        p = 'res://assets/audio/combat/' + e['path']
        catalog.setdefault(p, dict(e, path=p))
    entries, sounds = [], {}
    for item in payload['items']:
        for variant in range(1, item['variants'] + 1):
            x, sources, seed = render(item, variant, catalog)
            meta, decoded = write_asset(item, variant, x, sources, seed, payload['batch'])
            entries.append(meta)
            sounds[(item['recipe'], variant)] = decoded
            print(f'{meta["title"]}: {meta["duration_seconds"]:.2f}s / {meta["features"]["peak_dbfs"]:.1f} dBFS')
    # A continuous arrangement comparison illustrates the shared phrase and tempo.
    cross = n(2.5)
    camp, battle = sounds[('music_camp', 1)], sounds[('music_battle', 1)]
    ramp = np.linspace(0, 1, cross, dtype=np.float32)
    transition = np.concatenate([camp[:-cross], camp[-cross:] * (1-ramp) + battle[-cross:] * ramp, battle])
    item = dict(id='bgm_journey_transition', title='征途主题 · 营地转战斗试听', category='music', domain='BGM', loop=False,
                variants=1, recipe='transition', prompt='Locally arranged preview: camp theme crossfades to the same-tempo battle arrangement over one bar. Not a Suno output.')
    meta, _ = write_asset(item, 1, transition, {}, 0, payload['batch'])
    meta['notes'] = '本批试听 · 本地制作；营地→战斗同速转场示例；请关闭循环听转场。'
    sidecar = ROOT / meta['path'][6:]
    sidecar.with_suffix('.ogg.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    entries.append(meta)
    incoming = {e['path'] for e in entries}
    manifest['files'] = [e for e in manifest['files'] if e['path'] not in incoming] + entries
    manifest['audition_batch'] = payload['batch']
    manifest['audition_title'] = '本批试听 · 10月19日'
    manifest['audition_description'] = '本地声音设计 · 武器 / 法术 / 卡牌 / UI / 环境 / BGM；A 清脆，B 厚重。'
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    REVIEW.mkdir(parents=True, exist_ok=True)
    (REVIEW / '.gdignore').write_text('', encoding='utf-8')
    reel = []
    for item in payload['items']:
        x = sounds[(item['recipe'], 1)]
        if item['domain'] != 'SFX':
            continue
        reel += [x, np.zeros(n(.45), np.float32)]
    dsp.write_wav(REVIEW / 'sfx_audition_reel.wav', np.concatenate(reel), SR)
    (REVIEW / 'quality_report.json').write_text(json.dumps(entries, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (OUT / 'index.json').write_text(json.dumps(dict(provider='local_design', count=len(entries), entries=entries), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    lines = ['# 2026-10-19 首批声音试听', '',
             '本批由 Codex 在本地制作：CC0 录音分层、原创合成与编曲。没有使用 ElevenLabs 或 Suno 生成，不应标记为平台产物。', '',
             '在 Godot 打开 `res://examples/scenes/audio_library.tscn` 按 F6，默认“本批试听”。A 较清脆，B 较厚重。', '',
             f'共 {len(entries)} 条：26 条 SFX、2 条环境循环、2 条同主题 BGM、1 条转场试听。', '',
             '| 声音 | 时长 | 类别 |', '| --- | ---: | --- |']
    lines += [f'| {e["title"]} | {e["duration_seconds"]:.2f}s | {e["domain"]} |' for e in entries]
    lines += ['', '## 自编平台提示词', '', '以下提示词已写好，平台登录后可用于生成对照版本。当前本地音频由明确的制作配方产出，不是把文字交给音频模型推理。', '']
    for item in payload['items']:
        lines += [f'### {item["title"]}', '', item['prompt'], '']
    (REVIEW / 'README.md').write_text('\n'.join(lines)+'\n', encoding='utf-8')
    from tools.audio.build_audio_library import main as rebuild_scene
    rebuild_scene()
    print(f'Added {len(entries)} locally designed assets to the unified audition scene.')


if __name__ == '__main__':
    # Vorbis needs a larger thread stack on Windows.
    import threading
    from concurrent.futures import ThreadPoolExecutor
    threading.stack_size(16 * 1024 * 1024)
    with ThreadPoolExecutor(max_workers=1) as pool:
        pool.submit(main).result()
