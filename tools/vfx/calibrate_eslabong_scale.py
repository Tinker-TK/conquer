"""Calibrate restored VFX against the host game's visible 18px character body.

Reads actual GPU render captures. Alpha/energy quantiles ignore sprite padding
and faint outlier particles; roles retain the difference between a personal
shield, a weapon, a contact burst and an intentional area spell.
"""
from pathlib import Path
import collections
import json
import re
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'assets/effect/eslabong_vfx'
WORK = ROOT / '.maintenance/eslabong/scale'
BODY = 18.0
SOURCE_BODY = 48.0


def role(item):
    name = item['original_name'].lower()
    source = item['source_path'].lower()
    category = item['category']
    if item['mode'] == 'postprocess':
        return 'screen', 0, 0
    if 'heattrail' in name:
        return 'refraction', 1.5, 4.5
    # A comic word needs readable letters; summon particles need enough pixel
    # area to survive the host game's small character scale.
    if name == 'boocastvfx':
        return 'comic_callout', 3.0, 5.5
    if name in ['naturecastvfx','polymorphcastvfx']:
        return 'summon_cast', 2.4, 4.0
    if 'bubble' in name or name in ['glacialprisonvfx', 'iceblock', 'freezevfx']:
        return 'enclosure', 1.25, 1.5
    if 'statuseffects/' in source:
        if any(x in name for x in ['ambient', 'shards', 'orbit', 'inner', 'mirror', 'thorns', 'shield']):
            return 'personal_aura', 1.0, 2.3
        if any(x in name for x in ['charm', 'confusion', 'fear', 'sleep', 'silence', 'stun', 'weaken', 'curse', 'greed', 'blockshieldicon']):
            return 'status_icon', .4, .75
        return 'body_status', .65, 1.6
    if name == 'hookprojectile':
        return 'rope', .06, .2
    if name == 'deadeyewindupvfx':
        return 'beam', .15, .6
    if name == 'vanishingsmokecloud':
        return 'area', 1.5, 4.5
    if item['mode'] == 'projectile':
        if 'tornado' in name:
            return 'vortex_projectile', 1.0, 2.2
        if 'net' in name or 'hook' in name or 'lasso' in name:
            return 'trap_projectile', .4, 1.4
        return 'projectile', .2, .85
    if 'flamethrower' in name:
        return 'stream', .35, .8
    if 'holywrath' in name or 'meteor' in name or 'apocalypse' in name or 'armageddon' in name:
        return 'large_area', 2.0, 6.0
    if item['mode'] == 'beam':
        return 'beam', .15, 1.1
    if 'wavespike' in name or name in ['earthspike', 'icespike']:
        return 'wave_piece', .65, 1.8
    if 'burningfire' in name or name in ['burnvfx', 'immolationvfx']:
        return 'body_status', .65, 1.6
    if 'boss_presence' in name:
        return 'personal_aura', 1.5, 3.5
    if 'orbit' in name or item['mode'] == 'continuous' or category == '持续光环':
        return 'personal_aura', 1.0, 3.0
    if category == '近战攻击' or category == '近战招式':
        return 'attack_arc', .7, 2.8
    if category == '施法传送':
        return 'cast', .6, 2.4 if 'portal' in name else 1.8
    if category == '治疗恢复':
        return 'heal', .65, 2.0
    if category == '范围地面' or any(x in name for x in ['nova', 'storm', 'well', 'barrier', 'ward', 'field', 'prayer', 'sanctuary', 'mass']):
        return 'area', 1.5, 4.5
    if 'sparks' in name:
        return 'sparks', .2, 1.3
    if any(x in name for x in ['explosion', 'slam', 'smash', 'shockwave', 'shatter']):
        return 'heavy_impact', .9, 3.5
    return 'impact', .7, 2.5


def frame_bounds(path, zoom):
    pixels = np.asarray(Image.open(path).convert('RGBA'), dtype=np.float32) / 255
    if pixels[0,0,3] > .99:
        # Uniform opaque background keeps additive particles visible as in the
        # actual demo. Transparent targets can have RGB with zero output alpha.
        corners = np.array([pixels[0,0,:3],pixels[0,-1,:3],pixels[-1,0,:3],pixels[-1,-1,:3]])
        energy = np.abs(pixels[:,:,:3] - np.median(corners,axis=0)).max(axis=2)
    else:
        energy = pixels[:, :, 3] * pixels[:, :, :3].max(axis=2)
    energy[energy < .025] = 0
    if np.count_nonzero(energy) < 2:
        return None
    def interval(weights):
        cdf = weights.cumsum()
        total = cdf[-1]
        return [int(np.searchsorted(cdf, total * .015)), int(np.searchsorted(cdf, total * .985)) + 1]
    x0, x1 = interval(energy.sum(axis=0))
    y0, y1 = interval(energy.sum(axis=1))
    height, width = energy.shape
    return {'width': (x1-x0)/zoom, 'height': (y1-y0)/zoom,
            'origin_diameter': max(abs(x0-width*.5),abs(x1-width*.5),abs(y0-height*.5),abs(y1-height*.5))*2/zoom,
            'offset': [((x0+x1)*.5-width*.5)/zoom,((y0+y1)*.5-height*.5)/zoom],
            'clipped': bool(np.any(energy[:2]) or np.any(energy[-2:]) or np.any(energy[:,:2]) or np.any(energy[:,-2:])),
            'clipped_x':bool(np.any(energy[:,:2]) or np.any(energy[:,-2:])),
            'clipped_y':bool(np.any(energy[:2]) or np.any(energy[-2:]))}


def measurements(phases):
    result = collections.defaultdict(list)
    baseline = WORK/'authored/frames.json'
    baseline_time = baseline.stat().st_mtime if baseline.exists() else 0
    for phase in phases:
        folder = WORK / phase
        index = folder / 'frames.json'
        if not index.exists():
            continue
        if phase in ['wide','detail'] and index.stat().st_mtime < baseline_time:
            continue
        if phase=='recheck' and (WORK/'fitted/frames.json').exists() and index.stat().st_mtime < (WORK/'fitted/frames.json').stat().st_mtime:
            continue
        for frame in json.loads(index.read_text(encoding='utf-8-sig')):
            bounds = frame_bounds(folder/frame['file'], frame['zoom'])
            if bounds:
                result[frame['id']].append(bounds | {'phase': phase})
    return result


def validate():
    data=json.loads((BASE/'scale_profiles.json').read_text(encoding='utf-8'))
    frames=measurements(['fitted','recheck'])
    rows=[]
    oversized=[]
    undersized=[]
    missing=[]
    for effect_id,profile in data['profiles'].items():
        if profile['role'] in ['screen','refraction']:
            rows.append({'id':effect_id,'role':profile['role'],'result':'screen effect; no body-size bound'})
            continue
        samples=frames.get(effect_id,[])
        if any(x['phase']=='recheck' for x in samples):
            samples=[x for x in samples if x['phase']=='recheck']
        if not samples:
            missing.append(effect_id)
            continue
        kind=profile['role']
        measured=max(x['height'] if kind in ['beam','stream','rope'] else max(x['width'],x['height'],x['origin_diameter'] if kind=='personal_aura' else 0) for x in samples)
        ratio=measured/BODY
        result='ok'
        if ratio>profile['max_units']*1.22:
            oversized.append(effect_id)
            result='large'
        elif ratio<profile['min_units']*.68:
            undersized.append(effect_id)
            result='small'
        rows.append({'id':effect_id,'role':kind,'body_ratio':round(ratio,3),'min_units':profile['min_units'],'max_units':profile['max_units'],'result':result})
    report={'reference_body_height':BODY,'items':len(data['profiles']),'rows':rows,'oversized':oversized,'undersized':undersized,'unmeasured':missing}
    (WORK/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (WORK/'selection.json').write_text(json.dumps(oversized+undersized+missing),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='rows'},ensure_ascii=False))


def main():
    if '--validate' in sys.argv:
        validate()
        return
    catalog = json.loads((BASE/'catalog.json').read_text(encoding='utf-8'))
    measured = measurements(['authored', 'wide', 'detail'])
    profiles = {}
    wide, detail = [], []
    for item in catalog['items']:
        kind, low, high = role(item)
        frames = measured.get(item['id'], [])
        if any(x['phase']=='wide' for x in frames):
            frames = [x for x in frames if x['phase']=='wide']
        elif any(x['phase']=='detail' for x in frames):
            frames = [x for x in frames if x['phase']=='detail']
        width = max((x['width'] for x in frames), default=0)
        height = max((x['height'] for x in frames), default=0)
        diameter = max((x['origin_diameter'] for x in frames), default=0)
        metric = height if kind in ['beam','stream','rope'] else max(width,height,diameter if kind=='personal_aura' else 0)
        clipped = any(x['clipped_y'] if kind in ['beam','stream','rope'] else x['clipped'] for x in frames)
        if clipped and kind not in ['screen','refraction'] and not any(x['phase']=='wide' for x in frames):
            wide.append(item['id'])
        if (not frames or metric<7) and kind not in ['screen','refraction'] and not any(x['phase']=='detail' for x in frames):
            detail.append(item['id'])
        if kind=='refraction': metric=200.0
        if kind=='enclosure' and 'bubble' in item['original_name'].lower(): metric=max(metric,68.0)
        factor = BODY / SOURCE_BODY
        if metric>0 and kind!='screen':
            factor=min(high*BODY/metric,max(low*BODY/metric,factor))
        if kind=='screen': factor=1.0
        profiles[item['id']]={'role':kind,'native_width':round(width,3),'native_height':round(height,3),'metric':round(metric,3),'min_units':low,'max_units':high,'scale_at_18px':round(factor,6),'measured':bool(frames),'clipped':clipped,'native_offset':max(frames,key=lambda x:x['width']*x['height'])['offset'] if frames else [0,0]}
        if kind=='comic_callout':
            profiles[item['id']]['anchor_offset_units']=[0,-1.4]
    data={'reference_body_height':BODY,'source_body_height':SOURCE_BODY,'profiles':profiles}
    output=BASE/'runtime/scale_profiles_data.gd'
    output.write_text('extends RefCounted\n\nconst DATA = '+json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (BASE/'scale_profiles.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    report={'profiles':profiles,'wide':wide,'detail':detail,'unmeasured':[key for key,value in profiles.items() if not value['measured']],'reductions':sum(p['scale_at_18px']<.356 for p in profiles.values()),'small_effect_boosts':sum(p['scale_at_18px']>.394 and p['role']!='screen' for p in profiles.values())}
    (WORK/'calibration.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if '--select-wide' in sys.argv:
        (WORK/'selection.json').write_text(json.dumps(wide),encoding='utf-8')
    if '--select-detail' in sys.argv:
        (WORK/'selection.json').write_text(json.dumps(detail),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='profiles'},ensure_ascii=False))


if __name__=='__main__': main()
