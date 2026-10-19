"""Render denser local battle arrangements; retain blocked Suno outputs as links.

The Suno free account showed zero downloads on 2026-10-19. Never obtain its
stream through an alternate route. Local audio is clearly marked local_design.
"""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path[:0] = [str(ROOT), str(ROOT / '.maintenance/audio-tools')]
import numpy as np
from tools.audio.ai.produce_audition import SR, n, band, noise, put, tone, thump, envelope, write_asset
from tools.audio.ai import dsp
from tools.audio.build_audio_library import main as rebuild_scene

BATCH = 'battle_tight_20261019'
PROMPTS = Path(__file__).with_name('batch_battle_tight_20261019.json')
REVIEW = ROOT / 'outputs/audio-audition-20261019'


def render(bpm, seed):
    rng = np.random.default_rng(seed)
    beat = 60 / bpm
    out = np.zeros(n(beat * 64), np.float32)
    hz = lambda midi: 440 * 2 ** ((midi - 69) / 12)
    # Sixteenth-note bowed/plucked figures replace the earlier long flute line.
    chords = [(50, 53, 57, 62), (46, 50, 53, 58), (43, 50, 55, 58), (45, 52, 57, 61)]
    for step in range(256):
        chord = chords[(step // 32) % 4]
        pattern = (0, 2, 1, 2, 0, 3, 1, 2)
        note = chord[pattern[step % 8]]
        length = beat * .45
        t = np.arange(n(length)) / SR
        # Several slightly detuned harmonic strings share one short bow envelope.
        string = np.zeros(len(t), np.float32)
        for detune in (.997, 1, 1.003):
            f = hz(note) * detune
            for harmonic in range(1, 7):
                string += np.sin(2 * np.pi * f * harmonic * t + .12 * harmonic) / harmonic ** 1.2
        string = band(string, 130, 4200) * envelope(length, beat * .10, .002)
        gain = .064 if step % 4 == 0 else .037 if step % 2 == 0 else .025
        put(out, string, step * beat / 4, gain, True)
    for bar in range(16):
        base = bar * 4 * beat
        root = chords[(bar // 2) % 4][0] - 12
        for step in (0, 1.5, 2, 2.75, 3.5):
            put(out, thump(rng, .22, 120 if step in (0, 2) else 157), base + step * beat,
                .32 if step in (0, 2) else .18, True)
        for step in (1, 3):
            slap = noise(rng, .12, 450, 5800) * envelope(.12, .022, .0007)
            put(out, slap, base + step * beat, .12, True)
            put(out, tone(185, .14, .027, .001, 3), base + step * beat, .07, True)
        for step in range(8):
            tick = noise(rng, .037, 2500, 8500) * envelope(.037, .006, .0006)
            put(out, tick, base + (step + .5) * beat / 2, .035 if step % 2 else .045, True)
        for step in (0, 2):
            put(out, tone(hz(root), beat * .7, beat * .16, .003, 5), base + step * beat, .11, True)
        # Brief low brass accents answer the rhythm without a sustained melody.
        if bar % 2 == 0:
            brass = sum(tone(hz(note - 12), beat * .6, beat * .17, .007, 7)
                        for note in chords[(bar // 2) % 4][:3])
            put(out, brass, base + 3 * beat, .035, True)
        if bar % 4 == 3:
            for i in range(4):
                put(out, thump(rng, .12, 160 + i * 25), base + (3 + i / 4) * beat, .12, True)
    return out


def main():
    config = json.loads(PROMPTS.read_text(encoding='utf-8'))
    prompt = config['items'][0]['prompt']
    manifest_path = ROOT / 'assets/audio/library/manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    entries, previews = [], []
    for bpm, seed, suffix, title in [(144, 14419, 'advance', '战斗 · 紧凑推进 144 BPM'),
                                     (156, 15619, 'assault', '战斗 · 急袭压迫 156 BPM')]:
        item = dict(id=f'bgm_battle_tight_{suffix}', category='music', domain='BGM', variants=1,
                    title=title, recipe=f'local_battle_{bpm}', prompt=prompt.replace('144 BPM', f'{bpm} BPM'))
        meta, decoded = write_asset(item, 1, render(bpm, seed), {}, seed, BATCH)
        meta.update(target_bpm=bpm, bpm=bpm, bars=16,
                    source='res://tools/audio/ai/revise_battle_music.py', author='项目原创程序合成编曲',
                    notes=f'紧凑战斗新候选 · 本地原创编曲 · {bpm} BPM；密集短弦乐、战鼓与切分重音；非 Suno 导出。')
        path = ROOT / meta['path'][6:]
        path.with_suffix('.ogg.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
        entries.append(meta)
        preview = REVIEW / f'battle_tight_{bpm}_preview.wav'
        dsp.write_wav(preview, dsp.fade(decoded[:n(12)], SR, 8, 350), SR)
        previews.append(preview.name)
    incoming = {e['path'] for e in entries}
    manifest['files'] = [e for e in manifest['files'] if e['path'] not in incoming] + entries
    manifest['audition_batch'] = BATCH
    manifest['audition_title'] = '战斗 BGM · 紧凑新版'
    manifest['audition_description'] = '144 / 156 BPM 本地编曲；密集短弦乐、战鼓、切分重音。Suno 生成曲可点上方按钮在线听。'
    manifest['online_previews'] = [
        dict(title='Suno 战斗 A · 在线听',url='https://suno.com/song/8c8f32eb-1055-438b-bde9-a6311cca6e89',
             provider='suno',license='AI-SUNO',download_status='free plan: 0 downloads',prompt=prompt),
        dict(title='Suno 战斗 B · 在线听',url='https://suno.com/song/a937f1a7-cc32-4e59-947a-34b188a4a77c',
             provider='suno',license='AI-SUNO',download_status='free plan: 0 downloads',prompt=prompt)
    ]
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
    (REVIEW / 'battle_tight_report.json').write_text(json.dumps(dict(local_assets=entries,online_previews=manifest['online_previews']),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    rebuild_scene()
    print(json.dumps(dict(local_files=[e['path'] for e in entries],previews=previews),ensure_ascii=False))


if __name__ == '__main__':
    import threading
    from concurrent.futures import ThreadPoolExecutor
    threading.stack_size(16 * 1024 * 1024)
    with ThreadPoolExecutor(max_workers=1) as pool:
        pool.submit(main).result()
