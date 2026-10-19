"""Build visual skill sequences from recovered AbilityResource/AbilityEffect links.

This does not execute the original combat code. Each association retains its source
file/property, so a sequence can be reviewed independently of the recovery folder.
"""
from pathlib import Path
import collections
import importlib.util
import json
import re

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / '.maintenance/eslabong/recovered'
DEST = ROOT / 'assets/effect/eslabong_vfx'
CATALOG = json.loads((DEST / 'catalog.json').read_text(encoding='utf-8'))
BY_PATH = {x['source_path']: x for x in CATALOG['items'] if not x.get('recipe')}
BY_NAME = {x['original_name'].lower(): x for x in CATALOG['items']}
spec = importlib.util.spec_from_file_location('port', Path(__file__).with_name('import_eslabong.py'))
port = importlib.util.module_from_spec(spec)
spec.loader.exec_module(port)


def parse(path):
    text = path.read_text(encoding='utf-8')
    ext = {key: source for source, key in re.findall(r'^\[ext_resource[^\n]*path="([^"]+)"[^\n]*id="([^"]+)"[^\n]*\]', text, re.M)}
    sections = {}
    for header, body in re.findall(r'^\[([^\n]+)\]\n(.*?)(?=^\[|\Z)', text, re.M | re.S):
        if header == 'resource' or header.startswith('sub_resource'):
            key = 'resource' if header == 'resource' else re.search(r'id="([^"]+)"', header)[1]
            sections[key] = {k: v.strip() for k, v in re.findall(r'^(\w+) = (.*?)(?=^\w+ =|\Z)', body, re.M | re.S)}
    return ext, sections


def ref(raw, ext):
    match = re.fullmatch(r'ExtResource\("([^"]+)"\)', raw or '')
    if match:
        return ext.get(match[1], '')
    match = re.fullmatch(r'(?:preload|load)\("(res://[^"]+)"\)', raw or '')
    return match[1] if match else ''


def scalar(raw, default=0.0):
    try:
        return float(raw)
    except (TypeError, ValueError):
        return default


def string(raw):
    return (raw or '').removeprefix('&').strip('"')


def color(raw):
    match = re.fullmatch(r'Color\(([^)]+)\)', raw or '')
    return [float(x) for x in match[1].split(',')] if match else [1, 1, 1, 1]


def defaults(script):
    path = SOURCE / script.removeprefix('res://')
    if not path.is_file():
        return {}
    return {key: value.strip() for key, value in re.findall(r'^@export[^\n]*?\bvar\s+(\w+)[^=\n]*=\s*([^\n]+)', path.read_text(encoding='utf-8'), re.M)}


def visual(path, evidence, **options):
    item = BY_PATH.get(path)
    if not item:
        return None
    return {'effect': item['id'], 'source': evidence, **options}


def statuses(props, ext, origin):
    result = []
    # Only base status_effects: milestone/evolution statuses are deliberately separate.
    for key in re.findall(r'ExtResource\("([^"]+)"\)', props.get('status_effects', '')):
        source = ext.get(key, '')
        path = SOURCE / source.removeprefix('res://')
        if not path.is_file():
            continue
        se, ss = parse(path)
        own = ss.get('resource', {})
        data = defaults(ref(own.get('script'), se)) | own
        for slot in ['vfx_scene', 'bubble_scene', 'ambient_vfx_scene']:
            item = visual(ref(data.get(slot), se), source + ':' + slot, duration=min(4.0, max(0.35, scalar(data.get('duration'), 2.0))), stage='持续效果', status_id=string(data.get('id')))
            if item and item['effect'] not in [x['effect'] for x in result]:
                result.append(item)
    if scalar(props.get('slow_duration')) > 0 and scalar(props.get('slow_multiplier'), 1) < 1:
        item = BY_NAME.get('slowvfx')
        if item and not any(x.get('status_id') == 'slow' for x in result):
            result.append({'effect': item['id'], 'duration': min(4, scalar(props['slow_duration'])), 'stage': '持续效果', 'source': origin + ':slow_duration', 'status_id': 'slow'})
    return result


def build(path):
    ext, sections = parse(path)
    root = sections.get('resource', {})
    if not root.get('ability_id'):
        return None, '非技能资源'
    ability_id = string(root['ability_id'])
    origin = 'res://' + path.relative_to(SOURCE).as_posix()
    cast = max(0, scalar(root.get('cast_time_sec')))
    if root.get('requires_charge') == 'true':
        cast = max(cast, min(1.5, scalar(root.get('max_charge_time'), .6)))
    actions, windup, release, unsupported = [], [], [], []
    for key, output in [('cast_windup_vfx_scene', windup), ('cast_vfx_scene', release), ('muzzle_vfx_scene', release)]:
        item = visual(ref(root.get(key), ext), origin + ':' + key, at='muzzle' if key=='muzzle_vfx_scene' else 'caster', duration=max(0.2, cast) if 'windup' in key else 1.1)
        if item:
            output.append(item)
    root_impact = visual(ref(root.get('impact_vfx_scene'), ext), origin + ':impact_vfx_scene', scale=scalar(root.get('impact_vfx_scale'), .75), tint=color(root.get('impact_vfx_modulate')), stage='命中')
    effect_keys = re.findall(r'SubResource\("([^"]+)"\)', root.get('effects', ''))
    for effect_key in effect_keys:
        own = sections.get(effect_key, {})
        script = ref(own.get('script'), ext)
        family = Path(script).stem
        props = defaults(script) | own
        # Evolution-only effects should not fire in the base skill demonstration.
        if string(props.get('required_evolution_id')):
            continue
        evidence = origin + ':' + effect_key
        on_hit = []
        impact_path = ref(props.get('impact_vfx'), ext) or ref(props.get('impact_vfx_scene'), ext)
        hit = visual(impact_path, evidence + ':impact_vfx', stage='命中') or root_impact
        if hit:
            hit = hit | {'properties': {'ability_vfx_id': ability_id}}
            on_hit.append(hit.copy())
        sparks = visual(ref(props.get('impact_sparks_scene'), ext), evidence + ':impact_sparks_scene', stage='命中')
        if sparks:
            on_hit.append(sparks)
        decal = visual(ref(props.get('impact_decal_scene'), ext), evidence + ':impact_decal_scene', duration=2.2, stage='地面余效')
        if decal:
            on_hit.append(decal)
        on_hit += statuses(props, ext, evidence)
        if family == 'EffectFireWave':
            # FireWaveSpike supplies these via its visual/status scripts rather
            # than the root AbilityResource's impact_vfx_scene slot.
            fire_hit = visual('res://Scenes/VFX/FireWaveImpactVFX.tscn', 'res://Scenes/fire_wave_spike.gd:hit_impact_vfx_scene', scale=.48, stage='命中')
            if fire_hit:
                on_hit.insert(0, fire_hit)
            burn = visual('res://Scenes/BurningFire.tscn', 'res://Scripts/StatusEffects/StatusEffectBurningFire.gd:BURNING_FIRE_SCENE', duration=4.0, stage='持续效果', status_id='burning_arrow_dot')
            if burn:
                on_hit.append(burn)
        delayed_bolt = visual(ref(props.get('delayed_lightning_vfx_scene'), ext), evidence + ':delayed_lightning_vfx_scene', delay=max(0, scalar(props.get('delayed_lightning_delay'))), offset_y=-min(240, max(80, scalar(props.get('delayed_lightning_sky_height'), 240))), stage='延迟落雷', duration=.7)
        if delayed_bolt:
            on_hit.append(delayed_bolt)
            delayed_impact = visual(ref(props.get('delayed_lightning_impact_vfx'), ext), evidence + ':delayed_lightning_impact_vfx', delay=delayed_bolt['delay'], stage='二段命中')
            if delayed_impact:
                on_hit.append(delayed_impact)
        if family in ['EffectDash', 'EffectCharge', 'EffectBlazingDash', 'EffectBullRushDash', 'EffectHornRush', 'EffectShadowDash', 'EffectGenericLeap', 'EffectLeap', 'EffectLeapSmash', 'EffectMovementStep']:
            actions.append({'kind': 'dash', 'start': scalar(props.get('start_time')), 'duration': max(.12, min(1.5, scalar(props.get('dash_duration'), scalar(props.get('duration'), .32)))), 'leap': 'Leap' in family, 'ghost_tint': color(props.get('ghost_trail_color_override') or props.get('dash_modulate')), 'react': bool(on_hit) and family != 'EffectDash', 'on_hit': on_hit, 'source': evidence + ':movement'})
            # Explicit endpoint/departure scenes are appended below as well.
            if family in ['EffectDash', 'EffectMovementStep']:
                continue
        proj_path = ref(props.get('projectile_scene'), ext) or ref(props.get('projectile_override_scene'), ext)
        projectile = visual(proj_path, evidence + ':projectile_scene')
        if projectile:
            scene_text = (SOURCE / proj_path.removeprefix('res://')).read_text(encoding='utf-8')
            if not hit:
                scene_ext = {m[1]: m[0] for m in re.findall(r'\[ext_resource[^\n]*path="([^"]+)"[^\n]*id="([^"]+)"', scene_text)}
                scene_hit = re.search(r'^impact_vfx = (.+)$', scene_text, re.M)
                hit = visual(ref(scene_hit[1], scene_ext), proj_path + ':impact_vfx', stage='命中') if scene_hit else None
                if hit:
                    on_hit.insert(0, hit)
            count = max(1, int(scalar(props.get('projectile_count'), 1)))
            burst_count = max(1, int(scalar(props.get('burst_count'), 1)))
            rain = family in ['EffectRainOfArrows', 'EffectArcticStorm', 'EffectIceStorm', 'EffectMeteorRain']
            interval = max(0, scalar(props.get('spawn_delay_increment')))
            if rain:
                interval = max(.015, scalar(props.get('duration'), 1.0) / count)
            burst_interval = scalar(props.get('burst_duration'), 2.0) / burst_count if family == 'EffectBurstProjectiles' else scalar(props.get('burst_interval'), .12)
            projectile.update(kind='projectile', start=scalar(props.get('spawn_delay')), speed=max(50, scalar(props.get('speed'), 600)), scale=scalar(props.get('projectile_scale'), 1), tint=color(props.get('projectile_modulate')), arc=props.get('use_arc_physics') == 'true' or 'use_arc_physics = true' in scene_text, visual_height=scalar(props.get('visual_height')), shadow=props.get('use_shadow') == 'true', count=count, burst_count=burst_count, interval=interval, burst_interval=burst_interval, spread=scalar(props.get('spread_degrees')), pattern='rain' if rain else 'forward', fall_seconds=max(.2, scalar(props.get('fall_time'), .6)), on_hit=on_hit, properties={'ability_vfx_id': ability_id})
            actions.append(projectile)
            storm = visual(ref(props.get('storm_vfx_scene'), ext), evidence + ':storm_vfx_scene', kind='effect', at='target', start=0, duration=min(4, max(.5, scalar(props.get('duration'), 2))))
            if storm:
                actions.append(storm)
            continue
        beam_key = next((key for key in ['beam_scene', 'lightning_vfx_scene', 'bolt_vfx_scene', 'flamethrower_vfx'] if ref(props.get(key), ext)), '')
        if beam_key:
            beam_path = ref(props[beam_key], ext)
            beam = visual(beam_path, evidence + ':' + beam_key)
            if beam:
                beam.update(kind='beam', start=scalar(props.get('start_time')), duration=min(4, max(.2, scalar(props.get('duration'), scalar(props.get('max_duration'), .25)))), on_hit=on_hit, tint=color(props.get('beam_modulate') or props.get('vfx_color') or props.get('bolt_color_tint')), stream='flamethrower' in family.lower(), width=scalar(props.get('beam_width'), 24))
                actions.append(beam)
                continue
        # Explicit scene slots in effect data cover zones, healing, defenses and
        # melee/charge endpoints. Avoid evolution dictionaries and unused ext refs.
        direct = []
        for key, raw in props.items():
            # This export belongs to an unused helper, not cast_spell_no_wait.
            # Enumerating it as a wave spawned nine giant refraction fields.
            if family == 'EffectFireWave' and key == 'heat_trail_vfx':
                continue
            source = ref(raw, ext)
            if not source.endswith('.tscn') or source == proj_path or 'projectile' in key or 'evolution' in key or key in ['impact_vfx', 'impact_vfx_scene', 'impact_decal_scene']:
                continue
            v = visual(source, evidence + ':' + key)
            if not v or v['effect'] in [x['effect'] for x in direct]:
                continue
            at = 'caster' if any(w in key for w in ['buff', 'cast', 'aura', 'dash', 'departure', 'start', 'muzzle', 'orbit']) else 'target'
            v.update(kind='effect', at=at, start=scalar(props.get('start_time')), duration=min(4, max(.4, scalar(props.get('duration'), scalar(props.get('beam_duration_sec'), 1.2)))))
            if family in ['EffectEarthSpike', 'EffectIceSpike', 'EffectFireWave', 'EffectIceWave']:
                v.update(kind='wave', count=min(12, max(2, int(scalar(props.get('spike_quantity'), 7)))), interval=max(.03, scalar(props.get('delay_between_spikes'), .1)), on_hit=on_hit)
            direct.append(v)
        if direct:
            actions += direct
            if on_hit and not any(x['kind'] == 'wave' for x in direct):
                actions.append({'kind': 'contact', 'start': .12, 'on_hit': on_hit})
            continue
        # Enumerated recovered implementations, whose style is selected by skill ID.
        style_item = next((x for x in CATALOG['items'] if x.get('recipe', {}).get('shadow_priest') and x.get('recipe', {}).get('style') == int(scalar(props.get('spell')))), None) if family == 'EffectShadowPriest' else None
        if not style_item and ability_id == 'umbral_scripture':
            style_item = BY_NAME.get('umbral_bolt')
        if family == 'EffectShadowPriest' and style_item:
            style = style_item['recipe']['style']
            zone = style in [3, 4, 5, 7, 11]
            duration = min(4, max(.7, scalar(props.get('duration'), 1.4)))
            actions.append({'effect': style_item['id'], 'kind': 'effect' if zone else 'beam', 'at': 'target', 'start': 0, 'duration': duration if zone else .8, 'points': 'target' if zone else 'reverse' if style == 2 else 'both', 'on_hit': on_hit, 'source': script + ':Spell=' + str(style)})
            if zone:
                actions.append({'kind': 'contact', 'start': .15, 'react': style not in [4, 5], 'on_hit': on_hit})
            if style in [2, 5, 11]:
                pulse = BY_NAME['rite_pulse'] if style != 2 else style_item
                interval = max(.15, scalar(props.get('tick_interval'), .5))
                for i in range(1, min(12, max(2, int(duration / interval)))):
                    actions.append({'effect': pulse['id'], 'kind': 'effect' if zone else 'beam', 'at': 'target', 'start': i * interval, 'duration': min(.6, interval + .08), 'points': 'target' if zone else 'reverse', 'source': script + ':tick_interval'})
        elif family in ['EffectMeleeAttack', 'EffectVoidMarkMelee']:
            arc = visual(ref(root.get('arc_vfx_scene'), ext), origin + ':arc_vfx_scene')
            if arc:
                actions.append(arc | {'kind': 'melee', 'start': scalar(props.get('start_time')), 'at': 'caster', 'on_hit': on_hit})
            elif on_hit:
                actions.append({'kind': 'melee', 'start': scalar(props.get('start_time')), 'on_hit': on_hit})
            else:
                unsupported.append(family)
        elif family in ['EffectApplyStatus', 'EffectStatusArea', 'EffectSelfBuff', 'EffectDirectHeal', 'EffectDirectHealPercentMaxHP'] and on_hit:
            self_target = props.get('apply_to_self') == 'true' or family == 'EffectSelfBuff'
            actions.append({'kind': 'contact', 'start': 0, 'at': 'caster' if self_target else 'target', 'react': not self_target, 'on_hit': on_hit})
        elif family not in ['EffectMovementStep']:
            unsupported.append(family)
    # A resource-level visual remains useful for skills driven by combat-specific
    # scripts, but those entries explicitly retain a partial-coverage marker.
    if not actions and root_impact:
        actions.append({'kind': 'contact', 'start': 0, 'on_hit': [root_impact]})
    if not actions and not release and not windup:
        return None, '无独立可恢复的视觉阶段: ' + ', '.join(sorted(set(unsupported)))
    kinds = {x['kind'] for x in actions}
    category = '投射技能' if 'projectile' in kinds else '光束连接' if 'beam' in kinds else '突进与跳跃' if 'dash' in kinds else '近战技能' if 'melee' in kinds else '地面范围' if 'wave' in kinds else '状态与法术'
    english = string(root.get('ability_name')) or ability_id.replace('_', ' ').title()
    chinese = {'rock_throw': '投石', 'fireball': '火球术', 'ice_bolt': '冰霜飞弹', 'chain_lightning': '连锁闪电', 'flamethrower': '火焰喷射', 'burning_arrow': '燃烧箭', 'net_throw': '投网', 'grenade': '手榴弹', 'earth_spike': '大地尖刺', 'holy_light': '神圣之光', 'mini_shield': '小型护盾', 'magic_missile': '魔法飞弹', 'shaman_bolt': '萨满飞弹'}
    name = chinese.get(ability_id) or port.label(english.replace(' ', '_'))
    return {'id': ability_id, 'name': name, 'original_name': english, 'category': category, 'mode': 'sequence', 'path': 'res://assets/effect/eslabong_vfx/skills/skill_player.tscn', 'source_path': origin, 'fidelity': 'skill_sequence', 'cast_seconds': cast, 'animation': string(root.get('animation_name')), 'windup': windup, 'release': release, 'actions': actions, 'unsupported_effects': sorted(set(unsupported)), 'coverage': 'partial' if unsupported else 'linked', 'friendly': root.get('target_allies') == 'true', 'description': string(root.get('description'))}, ''


def main():
    items, omitted = [], []
    for path in sorted((SOURCE / 'Data/Abilities').rglob('*.tres')):
        item, reason = build(path)
        if item:
            items.append(item)
        else:
            omitted.append({'source': 'res://' + path.relative_to(SOURCE).as_posix(), 'reason': reason})
    # Some source files intentionally share an ability ID. Keep their source path
    # visible while making API IDs deterministic and unique.
    used = set()
    for item in items:
        if item['id'] in used:
            item['id'] += '__' + Path(item['source_path']).parent.name.lower() + '_' + Path(item['source_path']).stem.lower()
        used.add(item['id'])
    items.sort(key=lambda x: (x['id'] not in ['rock_throw', 'fireball', 'ice_bolt', 'chain_lightning', 'flamethrower'], x['category'], x['id']))
    data = {'source_game': 'Eslabong Demo', 'source_resources': 590, 'items': items, 'categories': dict(collections.Counter(x['category'] for x in items)), 'omitted': omitted, 'notes': ['按原技能资源的引用恢复基础技能视觉流程。', '未启用进化专属分支；多目标弹幕收束到展示目标，飞行路径与舞台比例适配。', '单次展示的长持续状态最多保留4秒；缺少独立视觉实现的效果在清单中保留。']}
    target = DEST / 'skills'
    target.mkdir(exist_ok=True)
    text = json.dumps(data, ensure_ascii=False, indent=2)
    (target / 'skill_catalog.json').write_text(text + '\n', encoding='utf-8')
    (target / 'skill_catalog_data.gd').write_text('extends RefCounted\n\nconst DATA = ' + text + '\n', encoding='utf-8')
    lines = ['# Eslabong 技能视觉组合', '', f'从590份技能资源整理出 **{len(items)} 套可播放组合**。每套保留原始资源路径和属性依据。', '', '界面中的“完整关联”表示已串起当前已支持效果类型的全部基础视觉阶段；“部分阶段”表示还包含原游戏专用逻辑，见下表。', '', '| 技能 ID | 名称 | 类型 | 阶段来源 | 未覆盖的专用逻辑 |', '| --- | --- | --- | --- | --- |']
    for item in items:
        kinds = {x['kind'] for x in item['actions']}
        action_stages = ['发射 / 飞行 / 命中'] if 'projectile' in kinds else ['突进 / 落点 / 作用'] if 'dash' in kinds else ['接近 / 挥击 / 命中'] if 'melee' in kinds else ['释放 / 连接 / 目标作用'] if 'beam' in kinds else ['地面逐段推进 / 落点'] if 'wave' in kinds else ['释放 / 作用']
        sustained = any(hit.get('stage') == '持续效果' for action in item['actions'] for hit in action.get('on_hit', []))
        stages = ' → '.join((['蓄力'] if item['cast_seconds'] > 0 else []) + (['施法'] if item['release'] else []) + action_stages + (['持续状态'] if sustained else []) + ['结束'])
        lines.append('| ' + ' | '.join([item['id'], item['name'], item['category'], stages, ', '.join(item['unsupported_effects']) or '—']) + ' |')
    lines += ['', '## 未作为完整技能展示的资源', '', '这些资源可能是被动、召唤单位、切换形态或专用战斗逻辑；仍可在原始特效目录查看其独立素材。', '']
    lines += [f'- `{x["source"]}`：{x["reason"]}' for x in omitted]
    (target / 'SKILL_COMBINATIONS.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(json.dumps({'sequences': len(items), 'omitted': len(omitted), 'partial': sum(bool(x['unsupported_effects']) for x in items), 'categories': data['categories']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
