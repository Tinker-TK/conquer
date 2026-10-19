"""Extract the selected CC0 samples from downloaded archives and write the Godot bank.

Archives live in .maintenance/audio-sources; no downloads or executable archive content.
Existing audio is preserved byte for byte. Run with the bundled Python runtime.
"""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/audio/combat'
PACKS = {
    'kenney-rpg': ('https://kenney.nl/assets/rpg-audio', 'Kenney', 'Audio/',
                   ['knifeSlice', 'knifeSlice2', 'chop', 'dropLeather']),
    'kenney-impact': ('https://kenney.nl/assets/impact-sounds', 'Kenney', 'Audio/',
                      ['impactPunch_medium_000', 'impactPunch_medium_001', 'impactPunch_heavy_000',
                       'impactMetal_light_000', 'impactMetal_light_001',
                       'impactGlass_light_000', 'impactGlass_light_001',
                       'impactWood_medium_000', 'impactWood_medium_001']),
    'rubberduck-rpg': ('https://opengameart.org/content/80-cc0-rpg-sfx', 'rubberduck', '',
                      ['blade_01', 'wood_01', 'wood_02', 'creature_die_01',
                       'creature_hurt_01', 'creature_hurt_02', 'creature_monster_01',
                       'creature_monster_02', 'creature_slime_01', 'creature_slime_02',
                       'creature_slime_03', 'spell_01', 'spell_02',
                       'spell_fire_01', 'spell_fire_02', 'spell_fire_03']),
    'artisticdude-battle': ('https://opengameart.org/content/battle-sound-effects',
                          'artisticdude (submitted by Ogrebane)', 'battle_sound_effects/', ['Bow']),
}
GROUPS = {
    'melee': ['kenney-rpg/knifeSlice.ogg', 'kenney-rpg/knifeSlice2.ogg', 'rubberduck-rpg/blade_01.ogg'],
    'bow': ['artisticdude-battle/Bow.wav'],
    'fire': ['rubberduck-rpg/spell_fire_01.ogg', 'rubberduck-rpg/spell_fire_02.ogg'],
    'ice': ['rubberduck-rpg/spell_02.ogg'],
    'magic': ['rubberduck-rpg/spell_01.ogg', 'rubberduck-rpg/spell_02.ogg'],
    'beast': ['rubberduck-rpg/creature_hurt_01.ogg', 'rubberduck-rpg/creature_hurt_02.ogg'],
    'slime': ['rubberduck-rpg/creature_slime_01.ogg', 'rubberduck-rpg/creature_slime_02.ogg'],
    'heal': ['rubberduck-rpg/spell_02.ogg'],
    'summon': ['rubberduck-rpg/spell_01.ogg'],
    'hit': ['kenney-impact/impactPunch_medium_000.ogg', 'kenney-impact/impactPunch_medium_001.ogg', 'kenney-rpg/chop.ogg'],
    'hit_bow': ['kenney-impact/impactWood_medium_000.ogg', 'kenney-impact/impactWood_medium_001.ogg'],
    'hit_fire': ['rubberduck-rpg/spell_fire_03.ogg'],
    'hit_ice': ['kenney-impact/impactGlass_light_000.ogg', 'kenney-impact/impactGlass_light_001.ogg'],
    'hit_magic': ['kenney-impact/impactPunch_heavy_000.ogg'],
    'hit_undead': ['kenney-impact/impactWood_medium_000.ogg', 'kenney-impact/impactWood_medium_001.ogg'],
    'hit_slime': ['rubberduck-rpg/creature_slime_02.ogg', 'rubberduck-rpg/creature_slime_03.ogg'],
    'block': ['kenney-impact/impactMetal_light_000.ogg', 'kenney-impact/impactMetal_light_001.ogg'],
    'death_human': ['kenney-rpg/dropLeather.ogg'],
    'death_monster': ['rubberduck-rpg/creature_die_01.ogg', 'rubberduck-rpg/creature_monster_01.ogg', 'rubberduck-rpg/creature_monster_02.ogg'],
    'death_undead': ['rubberduck-rpg/wood_01.ogg', 'rubberduck-rpg/wood_02.ogg'],
    'death_slime': ['rubberduck-rpg/creature_slime_03.ogg'],
}


def main():
    (OUT / 'licenses').mkdir(parents=True, exist_ok=True)
    files = []
    for pack, (source, author, prefix, names) in PACKS.items():
        (OUT / pack).mkdir(exist_ok=True)
        archive_path = ROOT / '.maintenance/audio-sources' / (pack + '.zip')
        with zipfile.ZipFile(archive_path) as archive:
            for name in names:
                filename = name + ('.wav' if pack == 'artisticdude-battle' else '.ogg')
                payload = archive.read(prefix + filename)
                (OUT / pack / filename).write_bytes(payload)
                files.append(dict(path=pack + '/' + filename, source_path=prefix + filename,
                                  pack=pack, source=source, author=author, license='CC0-1.0',
                                  sha256=hashlib.sha256(payload).hexdigest(),
                                  categories=[key for key, paths in GROUPS.items() if pack + '/' + filename in paths]))
            if 'License.txt' in archive.namelist():
                (OUT / 'licenses' / (pack + '.txt')).write_bytes(archive.read('License.txt'))
    (OUT / 'manifest.json').write_text(json.dumps(dict(collected_on='2026-10-10', files=files),
                                                 ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    ids = {file['path']: str(index + 2) for index, file in enumerate(files)}
    lines = ['[gd_resource type="Resource" script_class="CombatSoundBank" format=3]', '',
             '[ext_resource type="Script" path="res://data/audio/combat_sound_bank.gd" id="1"]']
    for path, identifier in ids.items():
        lines.append(f'[ext_resource type="AudioStream" path="res://assets/audio/combat/{path}" id="{identifier}"]')
    lines += ['', '[resource]', 'script = ExtResource("1")']
    for key, paths in GROUPS.items():
        refs = ', '.join(f'ExtResource("{ids[path]}")' for path in paths)
        lines.append(f'{key} = Array[AudioStream]([{refs}])')
    bank = ROOT / 'data/audio/combat_sounds.tres'
    bank.parent.mkdir(parents=True, exist_ok=True)
    bank.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'Prepared {len(files)} original CC0 samples and {len(GROUPS)} sound categories.')


if __name__ == '__main__':
    main()
