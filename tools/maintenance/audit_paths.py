"""Audit explicit Godot references, sidecars and dynamically named unit scenes."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[2]
SKIP = {'.godot', '.maintenance', '.git', '.svn', 'tools', 'docs'}
# These exact paths test rejection or are created and removed by the test itself.
TEST_FIXTURES = {
    'tests/battle_rewards_test.gd': {'res://missing.tres'},
    'tests/comic_ui_test.gd': {'res://missing_scene.tscn'},
    'tests/game_config_editor_test.gd': {
        'res://data/cards/round_add.tres', 'res://data/cards/round_reduce.tres',
        'res://data/units/skill_unlock_shared_test.tres',
    },
    'tests/shop_test.gd': {'res://data/shops/missing.json'},
    'tests/sword_arrow_test.gd': {'res://data/cards/sword_arrow.tres'},
    'tests/wave_editor_test.gd': {'res://unrelated.tscn', 'res://tests/wave_editor_fixture_tmp.tres'},
}
# These files are optional inputs; their callers already handle absence explicitly.
OPTIONAL_REFERENCES = {
    'tests/mecha_asset_check.gd': {'res://assets/MechaGirl/MechaGirl.tscn'},
    'scripts/map/fixed_map_config.gd': {
        'res://data/run/game_map.json', 'res://data/run/game_map_act_2.json',
        'res://data/run/game_map_act_3.json',
    },
}
# The importer creates this directory on demand; it is not a resource dependency.
GENERATED_REFERENCES = {
    'addons/batch_effect_importer/ui/batch_effect_dock.gd': {'res://assets/animations/generated'},
}
paths = [p for p in ROOT.rglob('*') if p.is_file()
         and not any(part in SKIP for part in p.relative_to(ROOT).parts)
         and not any((parent / '.gdignore').exists() for parent in p.parents if parent != ROOT.parent)]
missing, dynamic, orphans, optional_missing = [], [], [], []
checked = 0
for p in paths:
    rel = p.relative_to(ROOT).as_posix()
    if p.suffix in {'.uid', '.import'} and not p.with_suffix('').exists():
        orphans.append(rel)
    if p.suffix not in {'.gd', '.tscn', '.tres', '.godot', '.cfg', '.gdshader'}:
        continue
    text = p.read_text(encoding='utf-8-sig')
    for line_number, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith(('#', ';')):
            continue
        for match in re.finditer(r'''["']\*?(res://[^"'\n]*)["']''', line):
            value = match.group(1)
            # Embedded resources have a real file before the :: subresource suffix.
            target = value.removeprefix('res://').split('::', 1)[0]
            if target.startswith(('.godot/', '.maintenance/')) or target == '.maintenance':
                continue
            if value in TEST_FIXTURES.get(rel, set()):
                continue
            if value in GENERATED_REFERENCES.get(rel, set()):
                continue
            if '%' in target or '{' in target:
                dynamic.append(dict(file=rel, line=line_number, path=value))
            elif 'FileAccess.WRITE' in line:
                continue
            elif not (ROOT / target).exists():
                record = dict(file=rel, line=line_number, path=value)
                if value in OPTIONAL_REFERENCES.get(rel, set()):
                    optional_missing.append(record)
                else:
                    missing.append(record)
            checked += 1

# UnitData names are used by the card runtime to construct scene filenames.
unit_scenes = []
for p in (ROOT/'data/units').glob('*.tres'):
    m = re.search(r'^unit_english_name = "([^"]+)"', p.read_text(encoding='utf-8'), re.M)
    target = 'scenes/units/' + (m.group(1) if m else 'soldier') + '.tscn'
    unit_scenes.append(target)
    if not (ROOT/target).exists():
        missing.append(dict(file=p.relative_to(ROOT).as_posix(), path=target))
report = dict(explicit_references=checked, dynamic_references=dynamic,
              unit_scene_checks=len(unit_scenes), missing=missing, orphan_sidecars=orphans,
              optional_missing=optional_missing)
out = ROOT/'.maintenance/path_audit.json'
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
raise SystemExit(bool(missing or orphans))
