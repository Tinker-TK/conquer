import json, re, pathlib, math

ROOT = pathlib.Path('.')

def read(p):
    return pathlib.Path(p).read_text(encoding='utf-8-sig').replace('\r\n', '\n')

def ext_resources(text):
    out = {}
    for attrs in re.findall(r'^\[ext_resource\s+(.*?)\]$', text, re.M):
        f = dict(re.findall(r'(\w+)="([^"]*)"', attrs))
        if 'id' in f and 'path' in f:
            out[f['id']] = f['path']
    return out

def scalar(text, key, default=None):
    m = re.search(r'^' + re.escape(key) + r'\s*=\s*(.*?)\s*$', text, re.M)
    if not m:
        return default
    v = m.group(1)
    if v == 'null':
        return None
    if v in ('true', 'false'):
        return v == 'true'
    if v.startswith('&"'):
        return json.loads(v[1:])
    if v.startswith('"'):
        return json.loads(v)
    if re.fullmatch(r'-?\d+', v):
        return int(v)
    if re.fullmatch(r'-?\d+\.\d+', v):
        return float(v)
    return v

def parse_levels(text):
    m = re.search(r'^unlock_upgrade_levels\s*=\s*(.*)$', text, re.M)
    if not m:
        return [0, 1]
    raw = m.group(1)
    if 'Array' in raw:
        inner = re.search(r'\(\[(.*?)\]\)', raw) or re.search(r'\[(.*?)\]\s*$', raw)
        if not inner:
            return []
        return [int(x) for x in re.findall(r'\d+', inner.group(1))]
    if raw.startswith('['):
        return [int(x) for x in re.findall(r'\d+', raw)]
    return [int(raw)]

KIND = {
    'normal_attack.gd': 'normal', 'soldier_slash.gd': 'normal',
    'soldier_missile.gd': 'projectile', 'seventh_strike.gd': 'normal',
    'sword_wind_combo.gd': 'normal', 'blood_shadow_slash.gd': 'normal',
    'shield_chop.gd': 'normal', 'taunt_attack.gd': 'normal',
    'arrow_attack.gd': 'projectile', 'area_attack.gd': 'area',
    'bear_earth_shake.gd': 'area', 'dash_attack.gd': 'dash',
    'wolf_pounce_combo.gd': 'normal', 'bear_chain_claw.gd': 'normal',
    'frost_storm.gd': 'area', 'ally_heal.gd': 'heal',
    'summon_unit.gd': 'summon', 'bloodthirst_attack.gd': 'lifesteal',
}

def skill_data(path):
    st = read(path.removeprefix('res://'))
    se = ext_resources(st)
    sr = re.search(r'^script = ExtResource\("([^"]+)"\)', st, re.M)
    script = pathlib.Path(se.get(sr.group(1), '?')).name if sr else '?'
    hm = re.search(r'^hit_frame = (?:Array\[int\]\()?\[([^\]]*)\]', st, re.M)
    hits = len(re.findall(r'\d+', hm.group(1))) if hm else 1
    return {
        'id': pathlib.Path(path).stem,
        'name': scalar(st, 'skill_name', '普通攻击'),
        'script': script,
        'kind': KIND.get(script, 'normal'),
        'rate': float(scalar(st, 'attack_rate', 1.0)),
        'cooldown': float(scalar(st, 'cooldown', 1.0)),
        'priority': int(scalar(st, 'priority', 0)),
        'range': float(scalar(st, 'cast_range', 80.0)),
        'hits': max(1, hits),
        'branch': scalar(st, 'soldier_branch', ''),
        'unlock': parse_levels(st),
    }

def unit_data(p):
    text = read(p); exts = ext_resources(text)
    name = scalar(text, 'unit_name', p.stem)
    team = scalar(text, 'unit_team', 'team_a')
    hp = int(scalar(text, 'max_hp', 100))
    attack = int(scalar(text, 'attack', 15))
    defence = int(scalar(text, 'defence', 5))
    dodge = float(scalar(text, 'dodge_rate', 0.0))
    cost = int(scalar(text, 'card_cost', 1))
    eng = scalar(text, 'unit_english_name', '')
    if not eng:
        eng = p.stem
    m = re.search(r'^skills = (.*)$', text, re.M)
    skills = []
    if m:
        for sid in re.findall(r'ExtResource\("([^"]+)"\)', m.group(1)):
            if sid in exts:
                skills.append(skill_data(exts[sid]))
    # remove engine default normal_attack when a real normal exists
    unique = []
    seen = set()
    for s in skills:
        key = (s['name'], s['rate'], s['cooldown'], s['hits'])
        if key in seen:
            continue
        seen.add(key)
        unique.append(s)
    return {'id': p.stem, 'name': name, 'team': team, 'hp': hp, 'attack': attack,
            'defence': defence, 'dodge': dodge, 'cost': cost,
            'english': eng, 'skills': unique,
            'card_name': scalar(text, 'card_name', ''),
            'upgrade_points': int(scalar(text, 'upgrade_ability_points', 2)),
            'max_upgrade': int(scalar(text, 'max_upgrade_count', 1))}

def load_units():
    return [unit_data(p) for p in sorted((ROOT / 'data/units').glob('*.tres'))]

def simulate(u, level=0, model=None):
    model = model or {}
    window = model.get('window', 12.0)
    cast = model.get('cast', 0.55)
    target_def = model.get('target_def', 5)
    area_targets = model.get('area_targets', 1.4)
    uptime_melee = model.get('melee_uptime', 0.8)
    uptime_ranged = model.get('ranged_uptime', 1.0)
    heal_weight = model.get('heal_weight', 0.5)
    # A summon skill is priced as a flat battlefield contribution; the child
    # unit's own DPS is not folded into the caster's body.
    summon_power = 50.0 if any(s['kind'] == 'summon' and level in s['unlock'] for s in u['skills']) else 0.0
    # active skills
    skills = []
    for s in u['skills']:
        if level > 0 and s.get('branch') and s['branch'] != 'missile':
            continue
        if level not in s['unlock']:
            continue
        if s['kind'] in ('normal', 'projectile', 'area', 'dash', 'lifesteal') and s['rate'] <= 0:
            continue
        if s['kind'] == 'summon':
            continue
        skills.append(dict(s))
    if not skills:
        return {'dps': 0, 'hps': 0, 'output': 0, 'ehp': 0, 'summon_power': summon_power}
    ranged = any(s['range'] >= 250 for s in skills if s['kind'] not in ('heal',))
    uptime = uptime_ranged if ranged else uptime_melee
    ready = {s['id']: 0 for s in skills}
    t = 0.0
    dmg = 0.0
    heal = 0.0
    casts = 0
    while t < window - 1e-9 and casts < 100:
        avail = [s for s in skills if ready[s['id']] <= t + 1e-9]
        if not avail:
            t = min(ready.values())
            continue
        avail.sort(key=lambda s: (-s['priority'], s['id']))
        s = avail[0]
        start = t
        end = start + cast
        ready[s['id']] = start + max(s['cooldown'], cast)
        casts += 1
        if end <= window:
            if s['kind'] == 'heal':
                heal += u['attack'] * s['rate']
            else:
                per_hit = max(math.floor(u['attack'] * s['rate']) - math.ceil(target_def / max(1, s['hits'])), 1)
                targets = area_targets if s['kind'] in ('area', 'dash') else 1.0
                dmg += per_hit * s['hits'] * targets
        t = end
    dps = dmg / window * uptime
    hps = heal / window * uptime
    ehp = u['hp'] * 15.0 / max(15 - u['defence'], 1) / (1 - u['dodge'] * 0.7)
    return {'dps': dps, 'hps': hps, 'output': dps + heal_weight * hps, 'ehp': ehp, 'summon_power': summon_power}

def main():
    units = load_units()
    ref = next(u for u in units if u['id'] == 'soldier')
    base = simulate(ref, 0)
    print('BASE', base)
    rows = []
    for u in units:
        b = simulate(u, 0)
        p = 100 * math.sqrt(b['ehp'] / base['ehp'] * b['output'] / base['output']) if b['output'] > 0 else 0
        up = simulate(u, 1) if u['max_upgrade'] > 0 else b
        pu = 100 * math.sqrt(up['ehp'] / base['ehp'] * up['output'] / base['output']) if up['output'] > 0 else 0
        rows.append((u['team'], u['name'], u['hp'], u['attack'], u['defence'], u['cost'], round(b['ehp'], 1), round(b['dps'], 2), round(p, 1), round(pu, 1)))
    rows.sort(key=lambda r: (r[0], -r[8]))
    print(f"{'team':6} {'name':10} {'hp':>4} {'atk':>3} {'def':>3} {'cost':>4} {'ehp':>6} {'dps':>5} {'P0':>6} {'P1':>6}")
    for r in rows:
        print(f'{r[0]:6} {r[1]:10} {r[2]:>4} {r[3]:>3} {r[4]:>3} {r[5]:>4} {r[6]:>6} {r[7]:>5} {r[8]:>6} {r[9]:>6}')

if __name__ == '__main__':
    main()
