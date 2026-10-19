"""Reference power model; reads live resources, never changes gameplay data."""
import ast
import copy
import hashlib
import json
import math
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT/'docs'/'数值设计'
SUPPORT = OUT/'support'
MODEL_PATH = OUT/'单位战力_计算标准.json'
DEFAULT_MODEL = {
    'version':'UNIT-POWER-v0.2', 'date':'2026-10-10',
    'window_seconds':12, 'reference_incoming_raw_hit':15, 'reference_target_defence':5,
    'incoming_dodge_eligible_share':0.7, 'reference_target_dodge':0,
    'melee_output_uptime':0.8, 'ranged_output_uptime':1.0, 'ranged_threshold':250,
    'area_mean_targets':1.5, 'pierce_mean_targets':1.5,
    'heal_realization':0.5, 'lifesteal_realization':0.5, 'heal_output_weight':0.5,
    'summon_realization':0.75, 'counter_net_dps_by_unit':{},
    'formation_coefficient':1.0, 'reference_power':100,
    'cost_bonus_per_extra_energy':0.08, 'budget_tolerance':0.15,
    'scope':'基础单位：未训练，无卡牌/遗物/战术/波次增益，无地形收益；反击净DPS待实测。'
}
if not MODEL_PATH.exists():
    MODEL_PATH.write_text(json.dumps(DEFAULT_MODEL,ensure_ascii=False,indent=2),encoding='utf-8')
model=json.loads(MODEL_PATH.read_text(encoding='utf-8-sig'))
assert model['window_seconds']>0 and model['reference_incoming_raw_hit']>0
assert 0<=model['incoming_dodge_eligible_share']<=1
for key in ['reference_target_dodge','heal_realization','lifesteal_realization','summon_realization']:
    assert 0<=model[key]<=1,key

sources={}
def read(relative):
    relative=relative.removeprefix('res://')
    path=ROOT/relative
    data=path.read_bytes()
    sources[relative]=hashlib.sha256(data).hexdigest()
    return data.decode('utf-8-sig').replace('\r\n','\n').replace('\r','\n')

def ext_resources(text):
    result={}
    for attrs in re.findall(r'^\[ext_resource\s+(.*?)\]$',text,re.M):
        fields=dict(re.findall(r'(\w+)="([^"]*)"',attrs))
        if 'path' in fields:
            result[fields['id']]=fields['path']
    return result

def scalar(text, key, default):
    match=re.search(r'^'+re.escape(key)+r'\s*=\s*(.*?)\s*$',text,re.M)
    if not match:
        return default
    v=match[1]
    if v=='null': return None
    if v in ('true','false'): return v=='true'
    if v.startswith('&"'): return json.loads(v[1:])
    if v.startswith('"'): return json.loads(v)
    if v.startswith("'"): return ast.literal_eval(v)
    if re.fullmatch(r'-?\d+(?:\.\d+)?',v): return float(v) if '.' in v else int(v)
    raise ValueError(f'Unsupported scalar {key}={v}')

def gd_default(text,key,fallback):
    match=re.search(r'@export[^\n]*\bvar\s+'+key+r'\s*:[^=\n]+?=\s*([^\n#]+)',text)
    if not match: raise ValueError('Missing default '+key)
    return scalar(key+' = '+match[1].strip(),key,fallback)

def balanced(text,start):
    opening=text[start]
    closing={'[':']','{':'}','(':')'}[opening]
    depth=0; quoted=False; escape=False
    for i in range(start,len(text)):
        c=text[i]
        if quoted:
            if escape: escape=False
            elif c=='\\': escape=True
            elif c=='"': quoted=False
            continue
        if c=='"': quoted=True
        elif c==opening: depth+=1
        elif c==closing:
            depth-=1
            if depth==0: return i+1
    raise ValueError('Unclosed bracket')

def animations(scene_path):
    text=read(scene_path)
    frame_ref=re.search(r'^sprite_frames = SubResource\("([^"]+)"\)',text,re.M)
    if not frame_ref: raise ValueError('No local SpriteFrames '+scene_path)
    resource_id=frame_ref[1]
    begin=text.index('[sub_resource type="SpriteFrames" id="'+resource_id+'"]')
    end=text.find('\n[',begin+1)
    part=text[begin:] if end<0 else text[begin:end]
    start=part.index('[',part.index('animations ='))
    array=part[start+1:balanced(part,start)-1]
    result={}; i=0
    speed_scale=scalar(text,'speed_scale',1.0)
    assert speed_scale>0
    while i<len(array):
        if array[i]!='{': i+=1;continue
        end=balanced(array,i); block=array[i:end]; i=end
        fstart=block.index('[',block.index('"frames"'))
        fend=balanced(block,fstart)
        durations=[float(x) for x in re.findall(r'"duration":\s*([\d.]+)',block[fstart:fend])]
        tail=block[fend:]
        name=re.search(r'"name":\s*&?"([^"]+)"',tail)[1]
        speed=float(re.search(r'"speed":\s*([\d.]+)',tail)[1])*speed_scale
        loop=re.search(r'"loop":\s*(true|false)',tail)[1]=='true'
        assert speed>0 and durations
        secs=[x/speed for x in durations]
        result[name]={'duration':sum(secs),'frame_seconds':secs,'frames':len(secs),'loop':loop}
    return result

unit_base=read('data/units/unit_data.gd')
skill_base=read('data/skills/skill_base.gd')
unit_defaults={k:gd_default(unit_base,k,v) for k,v in {'max_hp':100,'attack':15,'defence':5,'card_cost':1,'hp_damage_value':1,'dodge_rate':0,'unit_name':'名字','unit_english_name':'soldier','unit_team':'team_a'}.items()}
skill_defaults={k:gd_default(skill_base,k,v) for k,v in {'attack_rate':1.0,'cooldown':1.0,'priority':0,'cast_range':80.0,'manual_finish':False,'cast_animation':'attack_01','target_type':0}.items() if k!='target_type'}
default_levels=ast.literal_eval(re.search(r'var unlock_upgrade_levels: Array\[int\] = (\[[^\n]+?\])',skill_base)[1])
def skill_levels(text):
    match=re.search(r'^unlock_upgrade_levels\s*=\s*Array\[int\]\((\[[^\n]*\])\)',text,re.M)
    if match:return ast.literal_eval(match[1])
    legacy=re.search(r'^unlock_upgrade_level\s*=\s*(\d+)',text,re.M)
    return list(range(int(legacy[1]),100)) if legacy else copy.deepcopy(default_levels)
skills={}
def skill(path):
    if path in skills:return skills[path]
    text=read(path); exts=ext_resources(text)
    script_ref=re.search(r'^script = ExtResource\("([^"]+)"\)',text,re.M)[1]
    assert script_ref in exts,(path,script_ref,exts)
    script_path=exts[script_ref]; script_text=read(script_path)
    out={k:scalar(text,k,v) for k,v in skill_defaults.items()}
    out.update(path=path,script_path=script_path,name=scalar(text,'skill_name','普通攻击'),unlock=skill_levels(text))
    m=re.search(r'^hit_frame = .*?\(\[([^\]]*)\]\)',text,re.M)
    out['hit_frame']=[int(x) for x in re.findall(r'\d+',m[1])] if m else [3]
    file=Path(script_path).name
    out['kind']={'ally_heal.gd':'heal','summon_unit.gd':'summon','bloodthirst_attack.gd':'lifesteal','arrow_attack.gd':'projectile','area_attack.gd':'area','dash_attack.gd':'dash','normal_attack.gd':'normal','dodge_attack.gd':'counter','teleport_combo_attack.gd':'teleport','consecutive_attack.gd':'combo_passive','protection_aura.gd':'aura_passive','low_health_stealth.gd':'stealth_passive'}[file]
    parameters={'combo_passive':{'attack_bonus_per_hit':1},'aura_passive':{'aura_radius':200.0,'aura_attack_bonus':2,'aura_include_caster':True},'stealth_passive':{'stealth_health_percent':50.0,'stealth_duration':5.0}}
    for key,fallback in parameters.get(out['kind'],{}).items():
        out[key]=scalar(text,key,gd_default(script_text,key,fallback))
    for runtime in {'combo_passive':['scripts/units/consecutive_attack_runtime.gd'],'aura_passive':['scripts/units/protection_aura_runtime.gd'],'stealth_passive':['scripts/units/low_health_stealth_runtime.gd'],'teleport':['scripts/skills/normal_attack.gd']}.get(out['kind'],[]):read(runtime)
    out['targets']=model['area_mean_targets'] if out['kind'] in ['area','dash'] else 1
    if out['kind']=='projectile':
        out['pierce_count']=scalar(text,'pierce_count',gd_default(script_text,'pierce_count',1))
        out['trajectory']=scalar(text,'projectile_trajectory',gd_default(script_text,'projectile_trajectory',1))
        if out['trajectory']==0 and out['pierce_count']>1:
            out['targets']=min(out['pierce_count'],model['pierce_mean_targets'])
    if out['kind']=='dash':
        out['dash_distance']=scalar(text,'dash_distance',gd_default(script_text,'dash_distance',600))
        out['dash_speed']=scalar(text,'dash_speed',gd_default(script_text,'dash_speed',300))
    if out['kind']=='summon':
        for key in ['summon_scene','on_hit_effect']:
            ref=re.search(r'^'+key+r' = ExtResource\("([^"]+)"\)',text,re.M)
            if not ref:raise ValueError('Missing summon resource '+key)
            out[key]=exts[ref[1]]
        effect_name=scalar(text,'effect_animation',gd_default(script_text,'effect_animation','green_magic_circle'))
        out['effect_duration']=animations(out['on_hit_effect'])[effect_name]['duration']
    skills[path]=out
    return out

units=[]
for path in sorted((ROOT/'data'/'units').glob('*.tres')):
    resource_path='res://data/units/'+path.name
    text=read(resource_path); exts=ext_resources(text)
    u={k:scalar(text,k,v) for k,v in unit_defaults.items()}
    u.update(id=path.stem,path=resource_path)
    match=re.search(r'^skills = (.*)$',text,re.M)
    paths=[exts[x] for x in re.findall(r'ExtResource\("([^"]+)"\)',match[1]) if exts[x].endswith('.tres')] if match else ['res://data/skills/normal_attack.tres']
    u['skills']=[copy.deepcopy(skill(x)) for x in paths]
    counter_ref=re.search(r'^dodge_skill = ExtResource\("([^"]+)"\)',text,re.M)
    u['counter_skill']=copy.deepcopy(skill(exts[counter_ref[1]])) if counter_ref else None
    u['scene_path']='res://scenes/units/'+u['unit_english_name']+'.tscn'
    scene_text=read(u['scene_path']); scene_exts=ext_resources(scene_text)
    bound_data=re.search(r'^unit_data = ExtResource\("([^"]+)"\)',scene_text,re.M)
    assert bound_data and scene_exts[bound_data[1]]==resource_path,'Scene unit data mismatch: '+u['id']
    u['animations']=animations(u['scene_path'])
    assert u['max_hp']>0 and u['attack']>=0 and u['defence']>=0 and 0<=u['dodge_rate']<=1
    for k in u['skills']:
        if k['kind'].endswith('_passive'):
            k['duration']=0;k['hit_offsets']=[]
            continue
        anim=u['animations'][k['cast_animation']]
        assert (not anim['loop'] or k['manual_finish']) and k['cooldown']>0,(u['id'],k['name'],k['cast_animation'],anim['loop'],k['cooldown'])
        assert all(0<=f<anim['frames'] for f in k['hit_frame']),(u['id'],k['name'])
        k['hit_offsets']=[sum(anim['frame_seconds'][:f]) for f in k['hit_frame']]
        if k['kind']=='dash':
            # Manual finish happens after dash; animation and dash overlap.
            k['duration']=k['hit_offsets'][0]+k['dash_distance']/k['dash_speed']
        else:k['duration']=anim['duration']
    u['output_uptime']=model['ranged_output_uptime'] if any(k['cast_range']>=model['ranged_threshold'] for k in u['skills'] if k['kind'] not in ['heal','summon','dash']) else model['melee_output_uptime']
    units.append(u)


# Marker used by the calculator builder to load the resource reader only.
by_id = {u['id']: u for u in units}

if __name__ == '__main__':
    import os
    import shutil
    import subprocess
    subprocess.run([sys.executable, str(SUPPORT/'build_unit_power_calculator.py')], check=True)
    bundled = Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe'
    node = str(bundled) if bundled.exists() else shutil.which('node')
    if not node:
        raise SystemExit('需要 Node.js 生成与计算器使用同一模型的战力报告')
    subprocess.run([node, str(SUPPORT/'export_current_unit_power.cjs')], check=True)
