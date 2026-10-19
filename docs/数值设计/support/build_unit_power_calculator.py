"""Build one offline calculator from current project resources, preserving prior reports."""
import ast
import copy
import datetime
import hashlib
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')
HERE = Path(__file__).resolve().parent
OUT = HERE.parent
# Reuse only the established reader/functions before `by_id`; the historical
# report-writing section is deliberately never executed.
reader = HERE / 'calculate_unit_power.py'
tree = ast.parse(reader.read_text(encoding='utf-8'))
prefix = []
for node in tree.body:
    if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'by_id' for t in node.targets):
        break
    prefix.append(node)
assert (OUT / '单位战力_计算标准.json').exists(), 'Existing comparison standard required'
scope = {'__file__': str(reader), '__name__': 'calculator_resource_reader'}
exec(compile(ast.Module(body=prefix, type_ignores=[]), str(reader), 'exec'), scope)
model = scope['model']
skill_defaults = scope['read']('data/skills/skill_base.gd')
default_levels = ast.literal_eval(re.search(r'var unlock_upgrade_levels: Array\[int\] = (\[[^\n]+?\])', skill_defaults)[1])


def skill_levels(text):
    match = re.search(r'^unlock_upgrade_levels\s*=\s*Array\[int\]\((\[[^\n]*\])\)', text, re.M)
    return ast.literal_eval(match[1]) if match else copy.deepcopy(default_levels)


units = []
for raw in scope['units']:
    text = scope['read'](raw['path'])
    scalar = scope['scalar']
    plan = dict(mode='training' if raw['unit_team'] == 'team_a' else 'custom', levels=1 if raw['unit_team']=='team_a' else 0,
                attackAllocation=scalar(text, 'upgrade_ability_points', 3), defenceAllocation=0,
                hpStep=0, attackStep=scalar(text, 'upgrade_ability_points', 3), defenceStep=0,
                hpGrowth=0, attackGrowth=0, defenceGrowth=0, dodgeStep=0, costStep=0,
                hpBuff=0, attackBuff=0, defenceBuff=0, dodgeBuff=0, costBuff=0,
                buffEnergy=0, cooldownFactor=1, animationFactor=1, outputFactor=1)
    u = dict(id=raw['id'], name=raw['unit_name'], team=raw['unit_team'], hp=raw['max_hp'],
             attack=raw['attack'], defence=raw['defence'], cost=raw['card_cost'], dodge=raw['dodge_rate'],
             hasCounter=bool(raw['counter_skill']), counterUnlock=[], counterNetDps=0, uptime=None,
             baseLevel=0, gameMax=scalar(text, 'max_upgrade_count', 1),
             upgradePoints=scalar(text, 'upgrade_ability_points', 3), departures=0,
             hpDamage=raw['hp_damage_value'], plan=plan, skills=[])
    if raw['counter_skill']:
        u['counterUnlock'] = skill_levels(scope['read'](raw['counter_skill']['path']))
    for k in raw['skills']:
        skill_text = scope['read'](k['path'])
        s = dict(id=k['path'], name=k['name'], kind=k['kind'], rate=k['attack_rate'],
                 cooldown=k['cooldown'], duration=k['duration'], offsets=k['hit_offsets'],
                 priority=k['priority'], range=k['cast_range'], unlock=skill_levels(skill_text),
                 targets=None, straight=k.get('trajectory') == 0, pierce=k.get('pierce_count', 1),
                 basic=scalar(skill_text, 'is_basic_attack', False) or
                    (k['script_path'].endswith('/normal_attack.gd') and k['cast_animation'] == 'attack_01' and k['priority'] == 0))
        if k['kind'] == 'summon':
            s.update(child=Path(k['summon_scene']).stem, summonDelay=k['effect_duration'])
        for key in ['attack_bonus_per_hit','aura_radius','aura_attack_bonus','aura_include_caster','stealth_health_percent','stealth_duration']:
            if key in k:s[key]=k[key]
        u['skills'].append(s)
    if u['id'] == 'soldier':
        anim = raw['animations']['attack_03']
        assert len(anim['frame_seconds']) > 7
        u['sword'] = dict(range=300, duration=anim['duration'], offset=sum(anim['frame_seconds'][:7]))
    units.append(u)

state = dict(schema='unit-power-calculator/v1', curveMax=max(1,max(u['gameMax'] for u in units if u['team']=='team_a')), units=units, model=dict(
    window=model['window_seconds'], incoming=model['reference_incoming_raw_hit'], targetDefence=model['reference_target_defence'],
    eligible=model['incoming_dodge_eligible_share'], targetDodge=model['reference_target_dodge'],
    meleeUptime=model['melee_output_uptime'], rangedUptime=model['ranged_output_uptime'], areaTargets=model['area_mean_targets'],
    pierceTargets=model['pierce_mean_targets'], healRealization=model['heal_realization'],
    lifestealRealization=model['lifesteal_realization'], healWeight=model['heal_output_weight'],
    summonRealization=model['summon_realization'], swordFarShare=model.get('sword_far_window_share',.5), costBonus=model['cost_bonus_per_extra_energy'], comboTargetHp=model.get('combo_reference_target_hp',100)))
assert len(units) == 21
reference = dict(soldier=copy.deepcopy(next(u for u in units if u['id'] == 'soldier')),
                 unitIds=[u['id'] for u in units])
reference['soldier']['baseLevel'] = 0
reference['soldier']['plan']['levels'] = 0
for p in ['scripts/cards/card_instance.gd','scripts/units/skill_manager.gd','scripts/units/unit_base.gd','docs/数值设计/单位战力_计算标准.json']:scope['read'](p)
sources = [{'path': p, 'sha256': h} for p, h in scope['sources'].items()]
for entry in sources:
    assert hashlib.sha256((scope['ROOT'] / entry['path']).read_bytes()).hexdigest() == entry['sha256'], 'Source changed while reading'
revision=hashlib.sha256(json.dumps(sorted((s['path'],s['sha256']) for s in sources)).encode()).hexdigest()[:12]
seed = dict(version='UNIT-POWER-CALC-v2', date='2026-10-11', sourceCount=len(sources), sourceRevision=revision,
            defaults=state, reference=reference, initialState=None, storageId='unit-power-calc-v2-'+revision, sources=sources)
seed_text = json.dumps(seed, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c')
template = (HERE / 'unit_power_calculator_template.html').read_text(encoding='utf-8')
html = template.replace('__SEED__', seed_text).replace('__MODEL__', (HERE / 'unit_power_calculator_model.js').read_text(encoding='utf-8')).replace('__APP__', (HERE / 'unit_power_calculator_app.js').read_text(encoding='utf-8'))
output = OUT / '单位战力计算器.html'
output.write_text(html, encoding='utf-8')
(HERE / 'unit_power_calculator_seed.json').write_text(json.dumps(seed, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'output': str(output), 'units': len(units), 'sources_checked': len(sources), 'bytes': output.stat().st_size}, ensure_ascii=False))
