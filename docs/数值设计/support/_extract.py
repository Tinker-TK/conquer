import json, re, pathlib, sys

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
    if v.startswith("'"):
        return v.strip("'")
    if re.fullmatch(r'-?\d+', v):
        return int(v)
    if re.fullmatch(r'-?\d+\.\d+', v):
        return float(v)
    return v

def blocks(text, header):
    out = {}
    for m in re.finditer(r'^\[' + header + r'\s+([^\]]*)\]$', text, re.M):
        attrs = m.group(1)
        start = m.end()
        end = text.find('\n[', start)
        body = text[start:] if end < 0 else text[start:end]
        ident = re.search(r'id="([^"]+)"', attrs)
        if ident:
            out[ident.group(1)] = body
    return out

def effect_from(body):
    keys = ['kind', 'amount', 'upgrade_amount', 'lifetime', 'lasting_rounds',
            'upgrade_lasting_rounds', 'radius', 'interval', 'status_seconds',
            'upgrade_status_seconds', 'affected_team', 'can_convert_elite',
            'upgrade_can_convert_elite', 'required_unit_types',
            'minimum_attack_percent', 'distance_for_max_bonus',
            'crowded_unit_count', 'crowded_stat_percent',
            'solo_attack_bonus_percent', 'solo_defence_bonus_percent',
            'cooldown_reduction_percent', 'next_round_penalty',
            'upgrades_drawn_cards', 'upgrade_upgrades_drawn_cards']
    out = {}
    for k in keys:
        v = scalar(body, k, None)
        if v is not None:
            out[k] = v
    return out

def cards():
    out = []
    for p in sorted((ROOT / 'data/cards').glob('*.tres')):
        text = read(p)
        exts = ext_resources(text)
        subs = blocks(text, 'sub_resource')
        name = scalar(text, 'card_name', p.stem)
        cost = scalar(text, 'card_cost', 1)
        rarity = scalar(text, 'rarity', 0)
        category = scalar(text, 'category', 1)
        target = scalar(text, 'target', 1)
        after = scalar(text, 'after_use', 0)
        retain = scalar(text, 'retain_in_hand', False)
        starts = scalar(text, 'starts_in_hand', False)
        maxup = scalar(text, 'max_upgrade_count', 1)
        upcost = scalar(text, 'upgrade_cost_change', 0)
        desc = scalar(text, 'card_discription', '')
        sm = re.search(r'^effects = (.*)$', text, re.M)
        effs = []
        if sm:
            for sid in re.findall(r'SubResource\("([^"]+)"\)', sm.group(1)):
                if sid in subs:
                    e = effect_from(subs[sid])
                    if e:
                        effs.append(e)
        summon = None
        sm2 = re.search(r'^summon_unit = ExtResource\("([^"]+)"\)', text, re.M)
        if sm2 and sm2.group(1) in exts:
            summon = pathlib.Path(exts[sm2.group(1)]).stem
        out.append({'id': p.stem, 'name': name, 'cost': cost, 'rarity': rarity,
                    'category': category, 'target': target, 'after': after,
                    'retain': retain, 'starts': starts, 'max_upgrade': maxup,
                    'upgrade_cost': upcost, 'summon': summon, 'desc': desc,
                    'effects': effs})
    return out

def resources(dirname, fields):
    out = []
    for p in sorted((ROOT / 'data' / dirname).glob('*.tres')):
        text = read(p)
        item = {'id': p.stem}
        for k, default in fields.items():
            item[k] = scalar(text, k, default)
        out.append(item)
    return out

def units():
    out = []
    for p in sorted((ROOT / 'data/units').glob('*.tres')):
        text = read(p); exts = ext_resources(text)
        m = re.search(r'^skills = (.*)$', text, re.M)
        skill_paths = [exts[x] for x in re.findall(r'ExtResource\("([^"]+)"\)', m.group(1)) if x in exts] if m else []
        item = {'id': p.stem}
        for k, d in {'unit_name': '', 'unit_english_name': '', 'unit_team': 'team_a',
                     'monster_rank': 0, 'max_hp': 100, 'attack': 15, 'defence': 5,
                     'hp_damage_value': 1, 'speed': 150.0, 'dodge_rate': 0.0,
                     'card_cost': 1, 'is_flying': False, 'upgrade_ability_points': 3,
                     'max_upgrade_count': 1, 'card_name': ''}.items():
            item[k] = scalar(text, k, d)
        skills = []
        for sp in skill_paths:
            st = read(sp.removeprefix('res://')); se = ext_resources(st)
            sr = re.search(r'^script = ExtResource\("([^"]+)"\)', st, re.M)
            script = pathlib.Path(se.get(sr.group(1), '?')).name if sr else '?'
            sk = {'resource': pathlib.Path(sp).stem, 'script': script,
                  'name': scalar(st, 'skill_name', '普通攻击'),
                  'rate': scalar(st, 'attack_rate', 1.0),
                  'cooldown': scalar(st, 'cooldown', 1.0),
                  'priority': scalar(st, 'priority', 0),
                  'range': scalar(st, 'cast_range', 80.0),
                  'unlock': scalar(st, 'unlock_upgrade_levels', '[0, 1]')}
            skills.append(sk)
        item['skills'] = skills
        out.append(item)
    return out

def levels():
    out = []
    for p in sorted((ROOT / 'data/levels').glob('*.tres')):
        text = read(p)
        if 'BattleLevelConfig' not in text:
            continue
        item = {'id': p.stem}
        for k, d in {'level_name': '', 'enemy_max_hp': 45, 'energy_per_round': 3,
                     'energy_growth': 1, 'base_energy_cap': 10, 'cards_per_round': 5,
                     'repeat_waves': False, 'repeat_start': 1, 'repeat_end': 0,
                     'battle_duration': 10.0}.items():
            item[k] = scalar(text, k, d)
        item['wave_count'] = len(re.findall(r'^waves = Array\[ExtResource', text, re.M) and re.findall(r'ExtResource\("([^"]+)"\)', re.search(r'^waves = (.*)$', text, re.M).group(1)) or [])
        out.append(item)
    return out

def json_file(path):
    return json.loads(read(path))

if __name__ == '__main__':
    section = sys.argv[1] if len(sys.argv) > 1 else 'units'
    if section == 'units':
        data = units()
    elif section == 'cards':
        data = cards()
    elif section == 'relics':
        data = resources('relics', {'display_name': '', 'description': '', 'kind': 0, 'amount': 1, 'draw_threshold': 10, 'rounds': 3})
    elif section == 'potions':
        data = resources('potions', {'display_name': '', 'description': '', 'kind': 0, 'targets': 0, 'damage': 8, 'radius': 70.0, 'interval': 0.5, 'speed': 90.0, 'duration': 6.0, 'rounds': 3, 'casts': 4, 'cast_delay': 0.4})
    elif section == 'levels':
        data = levels()
    elif section == 'run':
        data = {'tres': read('data/run/run_start_data.tres')}
    elif section == 'map':
        data = json_file('data/levels/第一章 ·  翠绿原野.json')
    elif section == 'shops':
        data = json_file('data/shops/caravan.json')
    else:
        data = json_file(section)
    print(json.dumps(data, ensure_ascii=False, indent=1))
