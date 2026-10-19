"""Import both complete local Kenney packs into the existing F6 audio library.

Copies original audio byte for byte; reuses the identical previously imported samples.
Preserves other library entries. No network or third-party Python modules required.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil

from build_audio_library import ROOT, main as build_scene

LIBRARY = ROOT / 'assets/audio/library'
MANIFEST = LIBRARY / 'manifest.json'
PACKS = {
    'kenney-impact-full': ('kenney-impact', 'kenney_impact', 'Impact Sounds', 'https://kenney.nl/assets/impact-sounds'),
    'kenney-rpg-full': ('kenney-rpg', 'kenney_rpg', 'RPG Audio', 'https://kenney.nl/assets/rpg-audio'),
}
MATERIALS = {'Bell': '钟声', 'Generic': '普通碰撞', 'Glass': '玻璃碰撞', 'Metal': '金属碰撞',
             'Mining': '采矿敲击', 'Plank': '木板碰撞', 'Plate': '板材碰撞', 'Punch': '拳击',
             'Soft': '柔软撞击', 'Tin': '锡罐碰撞', 'Wood': '木材碰撞',
             'carpet': '地毯脚步', 'concrete': '水泥脚步', 'grass': '草地脚步',
             'snow': '雪地脚步', 'wood': '木地板脚步'}
STRENGTHS = {'light': '轻击', 'medium': '中击', 'heavy': '重击'}
RPG_NAMES = {'beltHandle': '整理腰带', 'bookClose': '合上书本', 'bookFlip': '翻书',
             'bookOpen': '打开书本', 'bookPlace': '放下书本', 'chop': '劈砍',
             'cloth': '衣物摩擦', 'clothBelt': '布腰带', 'creak': '吱嘎声',
             'doorClose': '关门', 'doorOpen': '开门', 'drawKnife': '拔刀',
             'dropLeather': '皮革落地', 'footstep': '脚步', 'handleCoins': '摆弄金币',
             'handleSmallLeather': '整理小皮具', 'knifeSlice': '刀刃挥切',
             'metalClick': '金属轻响', 'metalLatch': '金属门闩', 'metalPot': '金属容器',
             'Preview': 'RPG 音效合集预览'}


def title_for(pack, filename):
    stem = Path(filename).stem
    if pack == 'kenney-impact-full':
        tokens = stem.split('_')
        material = tokens[1] if tokens[0] == 'footstep' else tokens[0].removeprefix('impact')
        label = MATERIALS.get(material, material)
        strength = STRENGTHS.get(tokens[1], '')
        return ' · '.join(part for part in (label, strength, tokens[-1]) if part)
    name = re.sub(r'[_\d]+$', '', stem)
    number = re.search(r'(\d+)$', stem)
    return RPG_NAMES.get(name, name) + (' ' + number.group(1) if number else '')


def import_pack(pack, directory, date, old, existing):
    directory = directory.resolve()
    license_file = directory / 'License.txt'
    if 'CC0' not in license_file.read_text(encoding='utf-8-sig'):
        raise ValueError('Expected Kenney CC0 license: ' + str(license_file))
    old_pack, category, pack_title, source = PACKS[pack]
    audio = sorted((p for p in directory.rglob('*') if p.is_file()
                    and p.suffix.lower() in ('.ogg', '.wav', '.mp3')), key=lambda p: p.relative_to(directory).as_posix())
    if not audio:
        raise ValueError('No audio found: ' + str(directory))
    entries = []
    reused = 0
    copied_bytes = 0
    for origin in audio:
        relative = origin.relative_to(directory)
        payload = origin.read_bytes()
        digest = hashlib.sha256(payload).hexdigest()
        old_relative = old_pack + '/' + origin.name
        candidate = old.get(old_relative)
        if candidate and candidate['sha256'] == digest:
            path = 'res://assets/audio/combat/' + old_relative
            target = ROOT / path.removeprefix('res://')
            if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
                raise ValueError('Previously imported audio changed: ' + str(target))
            reused += 1
        else:
            target = LIBRARY / pack / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != digest:
                target.write_bytes(payload)
            path = 'res://' + target.relative_to(ROOT).as_posix()
            copied_bytes += len(payload)
        prior = existing.get(path)
        if prior and prior['pack'] != pack:
            raise ValueError('Another collection owns the audio path: ' + path)
        entries.append(dict(path=path, title=title_for(pack, origin.name), category=category,
                            notes='素材包全部音效的串联预览。' if origin.stem == 'Preview' else f'{pack_title} 原版音效；可搜索原文件名和中文名称。',
                            pack=pack, pack_title=pack_title, source=source, author='Kenney',
                            license='CC0-1.0', license_url='https://creativecommons.org/publicdomain/zero/1.0/',
                            source_directory=str(directory), source_path=relative.as_posix(),
                            source_sha256=digest, sha256=digest, imported_on=date,
                            changes='原文件保持不变。'))
    licenses = LIBRARY / 'licenses'
    licenses.mkdir(exist_ok=True)
    shutil.copyfile(license_file, licenses / (pack + '.txt'))
    print(f'{pack_title}: {len(entries)} audio files; reused {reused}; copied {copied_bytes:,} bytes.')
    return entries


def update_credits():
    path = LIBRARY / 'CREDITS.md'
    text = path.read_text(encoding='utf-8')
    lines = []
    for pack, (_, _, title, url) in PACKS.items():
        if f'| {pack} |' not in text:
            lines.append(f'| {pack} | [{title}]({url}) | Kenney | CC0-1.0 |')
    if lines:
        text = text.replace("\n\nIce and Electricity Magic", '\n' + '\n'.join(lines) + "\n\nIce and Electricity Magic")
    marker = '\n本地 Kenney 全集导入：'
    if marker not in text:
        text += marker + '两个目录内全部音频（含 RPG Preview.ogg），原文件保持不变。与上一批相同的 13 条复用已有文件。原包许可保存在 licenses/kenney-*-full.txt。\n'
    path.write_text(text, encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--impact-dir', required=True, type=Path)
    parser.add_argument('--rpg-dir', required=True, type=Path)
    parser.add_argument('--collected-on', required=True, help='YYYY-MM-DD')
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    old = {entry['path']: entry for entry in json.loads((ROOT / 'assets/audio/combat/manifest.json').read_text(encoding='utf-8'))['files']}
    existing = {entry['path']: entry for entry in manifest['files']}
    keep = [entry for entry in manifest['files'] if entry['pack'] not in PACKS]
    for pack, directory in [('kenney-impact-full', args.impact_dir), ('kenney-rpg-full', args.rpg_dir)]:
        keep.extend(import_pack(pack, directory, args.collected_on, old, existing))
    manifest['files'] = keep
    manifest['updated_on'] = args.collected_on
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    update_credits()
    build_scene()


if __name__ == '__main__':
    main()
