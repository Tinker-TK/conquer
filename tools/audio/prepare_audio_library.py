"""Prepare licensed audition candidates from locally downloaded audio archives.

Requires numpy and soundfile (the latter may be installed in .maintenance/audio-tools).
No network requests. Raw archives/recordings remain in .maintenance/audio-sources.
Only selected, short samples enter the project. Run build_audio_library.py afterwards.
"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.maintenance/audio-tools'))
import numpy as np
import soundfile as sf

SOURCES = ROOT / '.maintenance/audio-sources'
EXTRACTED = SOURCES / 'extracted'
OUT = ROOT / 'assets/audio/library'
PACKS = {
    'medieval-textures': ('Medieval Weapon Textures', 'https://opengameart.org/content/medieval-sound-effects-weapon-textures', 'Ben Jaszczak & Brian Nelson / Still North Media', 'CC0-1.0'),
    'medieval-impacts': ('Medieval Weapon Impacts', 'https://opengameart.org/content/medieval-sound-effects-weapon-impacts', 'Ben Jaszczak & Brian Nelson / Still North Media', 'CC0-1.0'),
    'swishes': ('Swishes Sound Pack', 'https://opengameart.org/content/swishes-sound-pack', 'artisticdude', 'CC0-1.0'),
    'body-hits': ('37 hits/punches', 'https://opengameart.org/content/37-hitspunches', 'Independent.nu (submitted by qubodup)', 'CC0-1.0'),
    'wet-impacts': ('8 wet squish, slurp impacts', 'https://opengameart.org/content/8-wet-squish-slurp-impacts', 'Independent.nu (submitted by qubodup)', 'CC0-1.0'),
    'magic-spell': ('Magic Spell SFX', 'https://opengameart.org/content/magic-spell-sfx', 'JaggedStone', 'CC0-1.0'),
    'qubodup-spells': ('Ice & Electricity Magic', 'https://opengameart.org/content/ice-electricity-magic', "Iwan 'qubodup' Gabovitch", 'CC-BY-3.0'),
    'human-voices': ('11 male human pain/death sounds', 'https://opengameart.org/content/11-male-human-paindeath-sounds', 'Michel Baradari', 'CC-BY-3.0'),
    'badre-death': ('Hurt / Death sound effect for character', 'https://opengameart.org/content/hurt-death-sound-effect-for-character', 'Badre-Eddine', 'CC0-1.0'),
    'fire-spell': ('Spell 4 (fire)', 'https://opengameart.org/content/spell-4-fire', 'Bart K.', 'CC-BY-3.0'),
    'explosions': ('Explosions', 'https://opengameart.org/content/explosions-4', 'EZduzziteh', 'CC0-1.0'),
    'rubberduck-sfx2': ('100 CC0 SFX #2', 'https://opengameart.org/content/100-cc0-sfx-2', 'rubberduck', 'CC0-1.0'),
}
FILES = []


def record(pack, source, target, title, category, notes, changes, **extra):
    name, url, author, license_id = PACKS[pack]
    FILES.append(dict(path='res://' + target.relative_to(ROOT).as_posix(), title=title,
                      category=category, notes=notes, pack=pack, pack_title=name,
                      source=url, author=author, license=license_id,
                      license_url='https://creativecommons.org/' + ('publicdomain/zero/1.0/' if license_id == 'CC0-1.0' else 'licenses/by/3.0/'),
                      source_path=source.relative_to(SOURCES).as_posix(),
                      source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                      sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
                      changes=changes, **extra))


def export_clip(pack, source, title, category, notes, start=0.0, end=None, suffix=''):
    audio, rate = sf.read(source, always_2d=True, dtype='float32')
    end = len(audio) / rate if end is None else end
    clip = audio[round(start * rate):round(end * rate)].copy()
    # Preserve stereo phase. Some weapon recordings have strongly opposed channels.
    # Retain the original channels instead of cancelling them through a mono mix.
    target_rate = 44100
    if rate != target_rate:
        old = np.arange(len(clip)) / rate
        new = np.arange(round(len(clip) * target_rate / rate)) / target_rate
        clip = np.stack([np.interp(new, old, clip[:, ch]) for ch in range(clip.shape[1])], axis=1)
    peak = float(np.abs(clip).max())
    if peak < .001:
        raise ValueError(f'Silent candidate: {source} {start} {end}')
    # Match audition peaks without clipping; output volume remains user adjustable.
    gain = min(.8 / peak, 10.0)
    clip *= gain
    fade = min(round(.003 * target_rate), len(clip) // 2)
    clip[:fade] *= np.linspace(0, 1, fade)[:, None]
    clip[-fade:] *= np.linspace(1, 0, fade)[:, None]
    stem = re.sub(r'[^a-z0-9]+', '_', source.stem.lower()).strip('_') + suffix
    target = OUT / pack / (stem + '.ogg')
    target.parent.mkdir(parents=True, exist_ok=True)
    sf.write(target, clip, target_rate, format='OGG', subtype='VORBIS')
    record(pack, source, target, title, category, notes,
           '裁切单次动作（如适用）；保留原声道；重采样至44.1kHz；峰值调整；3ms淡入淡出；转OGG。',
           source_start_seconds=round(start, 4), source_end_seconds=round(end, 4),
           duration_seconds=round(len(clip) / target_rate, 4), gain=round(gain, 4))


def single(pack, filename, title, category, notes, trim=True):
    source = next((EXTRACTED / pack).rglob(filename), None) or SOURCES / filename
    audio, rate = sf.read(source, always_2d=True)
    envelope = np.max(np.abs(audio), axis=1)
    active = np.flatnonzero(envelope > max(.0008, float(envelope.max()) * .008))
    start = max(0, active[0] / rate - .025) if trim else 0
    end = min(len(audio) / rate, active[-1] / rate + .15) if trim else len(audio) / rate
    export_clip(pack, source, title, category, notes, start, end)


def split_recording(archive, filename, title, category, count=4, notes='真实武器录音，已裁切为单次动作。'):
    source = EXTRACTED / archive / filename
    audio, rate = sf.read(source, always_2d=True)
    step = round(rate * .01)
    blocks = audio[:len(audio) // step * step].reshape(-1, step, audio.shape[1])
    energy = np.sqrt(np.mean(blocks ** 2, axis=(1, 2)))
    active = np.flatnonzero(energy > max(.0008, float(energy.max()) * .035))
    groups = np.split(active, np.where(np.diff(active) > 24)[0] + 1)
    tail = .50 if category in ('blade_clash', 'block') else .22
    events = [(max(0, g[0] * .01 - .035), min(len(audio) / rate, (g[-1] + 1) * .01 + tail))
              for g in groups if len(g) >= 2]
    if not events:
        raise ValueError('No single actions detected: ' + str(source))
    for i in range(len(events) - 1):
        events[i] = (events[i][0], min(events[i][1], events[i + 1][0]))
    indices = np.linspace(0, len(events) - 1, min(count, len(events)), dtype=int)
    pack = 'medieval-textures' if 'textures' in archive else 'medieval-impacts'
    for number, index in enumerate(indices, 1):
        start, end = events[index]
        export_clip(pack, source, f'{title} {number:02}', category, notes, start, end, f'_{number:02}')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for filename, title in [('Norse Sword Katana Blade on Blade.wav', '北欧剑与武士刀碰撞'),
                            ('Sabre Katana Blade on Blade.wav', '军刀与武士刀碰撞'),
                            ('Dagger Katana Blade on Blade.wav', '短刀与武士刀碰撞'),
                            ('Axe Katana Blade on Blade.wav', '斧刃与刀刃碰撞')]:
        split_recording('medieval-impacts-1', filename, title, 'blade_clash')
    for filename, title in [('Axe Sabre Haft on Blade.wav', '斧柄挡刀'),
                            ('Sabre Katana Hilt on Blade.wav', '剑柄格挡'),
                            ('Mace Norse Sword Blade.wav', '钉锤与剑格挡')]:
        split_recording('medieval-impacts-1', filename, title, 'block')
    for number in range(1, 14):
        heavy = number >= 5
        single('swishes', f'swish-{number}.wav',
               f'大锤挥摆候选 · 重破风 {number - 4:02}' if heavy else f'轻武器破风 {number:02}',
               'hammer_swing' if heavy else 'weapon_swing',
               '重武器挥摆破风素材，可调低音调匹配大锤；原素材并非实录锤头。' if heavy else '轻型武器挥摆破风录音。')
    split_recording('medieval-textures-2', 'Axe Swing.wav', '重斧挥摆', 'hammer_swing', 4,
                    '真实重斧挥摆录音，也可试听作为大锤破风候选。')
    split_recording('medieval-textures-1', 'Katana Swing.wav', '武士刀挥斩', 'weapon_swing')
    for filename, title in [('English Longbow Shoot.wav', '英式长弓射击'),
                            ('Scythian Recurve Shoot.wav', '反曲弓射击'),
                            ('Crossbow Shoot.wav', '弩箭射击')]:
        split_recording('medieval-textures-1', filename, title, 'bow_shot')
    for filename, title in [('Scythian Recurve Arrow Passby.wav', '箭矢掠过'),
                            ('English Longbow Draw.wav', '长弓拉弦')]:
        split_recording('medieval-textures-1', filename, title, 'bow_shot', 2)
    for number in range(1, 8):
        single('magic-spell', f'magical_{number}.ogg', f'魔法释放 {number:02}', 'spell_cast', '七种不同质感的施法候选。')
    for number in range(1, 3):
        single('qubodup-spells', f'qubodupElectricityDamage{number:02}.flac', f'电击爆裂 {number:02}', 'lightning_hit', '电流与雷电魔法受击；需保留作者署名。')
    for number in ['01', '02', '03', '03b']:
        single('qubodup-spells', f'qubodupIceDamage{number}.flac', f'冰魔法爆裂 {number}', 'magic_hit', '冰系魔法冲击／爆裂；需保留作者署名。')
    for number in range(1, 5):
        single('explosions', f'explosion{number}.ogg', f'火焰爆炸 {number:02}', 'fire_hit', '爆炸短音候选。')
    single('fire-spell', 'foom.wav', '火焰冲击爆燃', 'fire_hit', '火焰法术冲击；需保留作者署名。')
    single('rubberduck-sfx2', 'sfx100v2_thunder_01.ogg', '雷击轰鸣', 'lightning_hit', '短雷声候选，可与电流爆裂对照。')
    for number in range(1, 13):
        single('body-hits', f'hit{number:02}.mp3.flac', f'身体受击 {number:02}', 'physical_hit', '身体、拳击与钝击录音。')
    for number in range(1, 5):
        single('wet-impacts', f'impactsplat{number:02}.mp3.flac', f'血肉受击 {number:02}', 'physical_hit', '湿润血肉撞击候选。')
    for number in range(1, 7):
        single('human-voices', f'pain{number}.wav', f'男性受伤呼声 {number:02}', 'physical_hit', '人物受伤呼声；需保留作者署名。')
    for filename, title in [('deathh.wav', '男性死亡低吼'), ('die1.wav', '男性死亡呼声 01'), ('die2.wav', '男性死亡呼声 02')]:
        single('human-voices', filename, title, 'death', '人物死亡录音；需保留作者署名。')
    for number in range(1, 20):
        source = EXTRACTED / 'badre-death' / f'{number}.mp3'
        target = OUT / 'badre-death' / f'character_{number:02}.mp3'
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        record('badre-death', source, target, f'角色受伤／死亡呼声 {number:02}', 'death',
               '原包没有区分受伤与死亡，请试听选择适合的用途。', '原文件保持不变。')
    # Rebuilding the original curated batch must preserve later imported collections.
    previous_manifest = json.loads((OUT / 'manifest.json').read_text(encoding='utf-8')) if (OUT / 'manifest.json').exists() else {}
    retained = [entry for entry in previous_manifest.get('files', []) if entry['pack'] not in PACKS]
    manifest = dict(previous_manifest, collected_on='2026-10-10', files=FILES + retained)
    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    lines = ['# 音效试听库素材来源与署名', '',
             '免费候选采用 CC0-1.0 或 CC-BY-3.0。CC-BY 素材使用、修改及发布时需保留作者、来源、许可与修改说明。',
             'CC0: https://creativecommons.org/publicdomain/zero/1.0/',
             'CC-BY-3.0: https://creativecommons.org/licenses/by/3.0/', '',
             '本次修改：部分长录音裁切为单次动作，保留原声道，重采样、调整峰值、边界淡入淡出，转为 OGG。MP3 呼声保持原文件。', '',
             '| 目录 | 作品 | 作者 | 许可 |', '| --- | --- | --- | --- |']
    for pack, (name, url, author, license_id) in PACKS.items():
        lines.append(f'| {pack} | [{name}]({url}) | {author} | {license_id} |')
    retained_packs = {entry['pack']: entry for entry in retained}
    for pack, entry in retained_packs.items():
        lines.append(f'| {pack} | [{entry.get("pack_title", pack)}]({entry["source"]}) | {entry["author"]} | {entry["license"]} |')
    lines += ['', "Ice and Electricity Magic by Iwan 'qubodup' Gabovitch https://opengameart.org/users/qubodup", '',
              '完整逐条原文件、裁切时间、修改、SHA256 见 manifest.json。上一批素材署名见 ../combat/CREDITS.md。', '']
    credit_path = OUT / 'CREDITS.md'
    existing_credits = credit_path.read_text(encoding='utf-8') if credit_path.exists() else ''
    marker = '\n本地 Kenney 全集导入：'
    if marker in existing_credits:
        lines.append(marker + existing_credits.split(marker, 1)[1])
    credit_path.write_text('\n'.join(lines), encoding='utf-8')
    print(f'Prepared {len(FILES)} new candidates; {sum(p.stat().st_size for p in OUT.rglob("*") if p.suffix in (".ogg", ".mp3")):,} audio bytes.')


if __name__ == '__main__':
    # libvorbis uses stack buffers larger than the default Windows main thread stack.
    import threading
    from concurrent.futures import ThreadPoolExecutor
    threading.stack_size(16 * 1024 * 1024)
    with ThreadPoolExecutor(max_workers=1) as executor:
        executor.submit(main).result()
