# -*- coding: utf-8 -*-
"""Single source of truth for the numerical design document and calculator.

Reads live Godot resources, merges the proposed content from the design docs,
and computes design-power estimates. It never writes gameplay resources.
"""
import json, math, re, pathlib, sys
from collections import Counter, OrderedDict

ROOT = pathlib.Path(__file__).resolve().parents[3]
SUPPORT = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(SUPPORT))

import _extract as ex
import _unit_model as um
import _card_model as cm
from _parse_items import relics as parse_new_relics, potions as parse_new_potions
from _parse_tables import tables

OUT = ROOT / 'docs' / '数值设计'
DATA_PATH = OUT / 'support' / 'design_data.json'

# ---------------------------------------------------------------------------
# Tunable design constants
# ---------------------------------------------------------------------------
MODEL = {
    'version': 'NUM-DESIGN-v1.0-IMPLEMENTED',
    'date': '2026-10-19',
    'window': 12.0,
    'cast': 0.55,
    'target_def': 5,
    'area_targets': 1.4,
    'melee_uptime': 0.8,
    'ranged_uptime': 1.0,
    'heal_weight': 0.5,
    'reference_hp': 150.0,
    'reference_output': 4.0,
    'reference_power': 100.0,
    'energy_value': 100.0,
    'draw_value': 40.0,
    'hp_value': 2.5,
    'gold_value': 1.0,
}

# Current player units -> proposed target (hp, atk, def, cost).  Target power is
# recalculated from the same model, it is not copied from the old 100-point table.
TARGET_UNITS = {
    'soldier': (100, 10, 5, 1),
    'archer': (75, 9, 2, 1),
    'armored_axeman': (160, 8, 7, 1),
    'priest': (100, 10, 4, 1),
    'knight': (150, 15, 5, 2),
    'knight_templar': (160, 14, 6, 2),
    'were_bear': (100, 15, 5, 2),
    'were_wolf': (100, 15, 5, 2),
    'lancer': (160, 17, 6, 3),
    'swords_man': (180, 18, 5, 3),
    'wizard': (115, 23, 3, 3),
}

# Cost curve used for every design budget (sub-linear: 3-cost is ~2.4x a 1-cost).
def card_budget(cost):
    if cost <= 0:
        return 100.0
    return 100.0 * (cost ** 0.8)

# Suggested cost changes for currently over-priced / under-powered cards.
CARD_TARGET_COST = {
    'vulnerability': 1,
    'death_explosion': 1,
    'slumber': 1,
    'last_stand': 1,
    'stratagem': 1,
    'overflow_prayer': 1,
    'sacrifice': 2,
    'diverse_army': 2,
    'return_dead': 2,
    'comrade': 2,
    'judger': 2,
    'keep_distance': 2,
    'transcription': 2,
    'fortify': 2,
    'war_cry': 2,
    'battle_standard': 2,
    'reformation': 2,
    'undying_army': 4,
}

CARD_ROLE = {
    # core = 主要兑现伤害/场面；support = 增益/控制/功能；resource = 资源循环；finisher = 规则级
    'power_enhance': 'support', 'defend': 'support', 'heal': 'support',
    'poison_on_hit': 'support', 'death_explosion': 'support', 'copy_ally': 'core',
    'frenzy': 'core', 'judger': 'core', 'vulnerability': 'support',
    'weakness': 'support', 'intimidation': 'support', 'paralysis': 'support',
    'convert_enemy': 'core', 'draw_four': 'resource', 'draw_hp': 'resource',
    'master_strategy': 'resource', 'random_play': 'resource', 'recall_ally': 'support',
    'retreat_draw': 'resource', 'fire_zone': 'core', 'mud_zone': 'support',
    'death_attack': 'support', 'undying_army': 'finisher', 'diverse_army': 'support',
    'keep_distance': 'support', 'comrade': 'support', 'evolution': 'resource',
    'armor_shred': 'support', 'battle_standard': 'support', 'fortify': 'support',
    'haste': 'support', 'healing_ban': 'support', 'hold_ground': 'support',
    'holy_bulwark': 'support', 'last_stand': 'support', 'letting_go': 'resource',
    'martyrdom': 'support', 'mobilization': 'resource', 'overdraft': 'resource',
    'overflow_prayer': 'support', 'reformation': 'resource', 'rend': 'core',
    'return_dead': 'finisher', 'sacrifice': 'resource', 'slumber': 'support',
    'spike_trap': 'support', 'stratagem': 'resource', 'thrift': 'resource',
    'transcription': 'resource', 'war_cry': 'support',
}

# Effect kind -> display name / value coefficient.  Coeffs are intentionally
# editable in the calculator; they encode "one point of this is worth how many P".
CARD_COEF = {
    'ATTACK_UP': 25.0, 'DEFENCE_UP': 30.0, 'HEAL_PERCENT': 1.5,
    'POISON_ON_HIT': 20.0, 'DEATH_EXPLOSION': 1.5, 'COPY_ALLY': 100.0,
    'DAMAGE_ZONE': 16.9, 'MUD_ZONE': 65.0, 'DRAW': 40.0, 'LOCK_DRAW': -30.0,
    'PAY_HP': -2.5, 'ENERGY_EACH_ROUND': 50.0, 'DEATH_ATTACK_AURA': 50.0,
    'RANDOM_PLAY': 50.0, 'RECALL_ALLY': 55.0, 'GAIN_ENERGY': 65.0,
    'MAX_HP_UP': 3.0, 'RETAIN_ALLIES': 130.0, 'WEAKNESS': 25.0,
    'VULNERABILITY': 3.0, 'DEFENCE_DOWN': 25.0, 'PARALYSIS': 60.0,
    'CONVERT_ENEMY': 120.0, 'FRENZY': 100.0, 'RETREAT_DRAW': 60.0,
    'DIVERSE_ARMY': 70.0, 'KEEP_DISTANCE': 60.0, 'JUDGER': 80.0,
    'COMRADE': 100.0, 'TEMPORARY_UPGRADE': 85.0, 'BLEED': 1.0,
    'HEALING_BAN': 50.0, 'ARMOR_SHRED': 55.0, 'SLEEP': 50.0,
    'SHIELD': 1.2, 'OVERFLOW_SHIELD': 55.0, 'MISSING_HEALTH_SHIELD': 0.8,
    'KNOCKBACK_IMMUNITY': 40.0, 'TUTOR_UNIT': 65.0, 'DISCARD_DRAW': 40.0,
    'SACRIFICE': 80.0, 'RESURRECT': 120.0, 'DEATH_DRAW': 60.0,
    'ARMY_ATTACK': 50.0, 'ARMY_DEFENCE': 50.0, 'ARMY_SPEED': 1.2,
    'BATTLE_STANDARD': 80.0, 'SPIKE_TRAP': 1.4, 'TRANSCRIBE': 90.0,
    'REFORMATION': 75.0, 'HAND_DISCOUNT': 35.0, 'OVERDRAFT': 75.0,
    'THRIFT': 100.0,
}

# Manual power overrides for relics / potions (per battle / per use, in P).
RELIC_POWER = {
    # current 6
    'draw_engine': 170, 'draw_ring': 150, 'base_heart': 70,
    'traveler_amulet': 50, 'reserve_crystal': 200, 'opening_armour': 65,
    # wide
    'war_banner': 78, 'muster_roll': 82, 'diverse_codex': 170,
    'fallen_roster': 72, 'beacon': 180, 'earth_altar': 340,
    # tall
    'anvil': 88, 'lone_wolf': 180, 'bloodstone': 76, 'legacy_seal': 175,
    'duel_pact': 185, 'kings_blade': 380,
    # death
    'urn': 70, 'mourner': 76, 'sacrificial_dagger': 72, 'death_echo': 175,
    'martyr_crown': 180, 'undying_throne': 400,
    # dot
    'corrosive_vial': 86, 'ember': 80, 'plague_mask': 185,
    'slow_death': 180, 'sulfur_heart': 175, 'burning_city': 360,
    # control
    'chains': 76, 'fear_totem': 70, 'sunder': 165, 'inquisitor': 180,
    'executioner': 75, 'stasis_field': 350,
    # cycle
    'gloves': 80, 'fate_coin': 75, 'steady_hands': 64, 'borrowed_time': 170,
    'echo_crystal': 180, 'perpetual_gear': 380,
    # guard
    'iron_wall': 175, 'thorn_mail': 75, 'last_stand': 70,
    'counter_stance': 170, 'holy_symbol': 165, 'guardian_oath': 180,
    'blood_bank': 175, 'unfallen_fortress': 360,
    # ranged
    'longbow_string': 75, 'kite_boots': 70, 'spell_focus': 180,
    'hunter_mark': 175, 'volley_horn': 350,
    # economy
    'coin_purse': 60, 'field_kit': 65, 'alchemy_pack': 80,
    'merchant_seal': 160, 'greedy_cup': 165, 'relic_hunter': 330,
    # neutral
    'tactical_map': 80, 'scout_horn': 70, 'veteran_medal': 70,
    'hourglass': 165, 'spare_quiver': 75,
}

POTION_POWER = {
    # common
    'fire': 110, 'blast': 100, 'frost_flask': 95, 'poison_flask': 105,
    'mud_flask': 90, 'weaken_gas': 95, 'sunder_acid': 95, 'strength_brew': 110,
    'iron_brew': 105, 'cleanse_water': 95, 'healing_potion': 100,
    'gambler_brew': 90, 'decoy_totem': 115,
    # rare
    'lightning': 190, 'tornado': 210, 'chain_lightning': 220,
    'corrosive_flask': 210, 'frost_nova': 200, 'sleep_dust': 190,
    'confusion_gas': 195, 'gravity_well': 185, 'aegis_brew': 210,
    'envenom_brew': 215, 'deathrattle_brew': 210, 'energy_potion': 190,
    'tactics_brew': 220, 'insight_brew': 185, 'reinforcement_horn': 210,
    'forge_oil': 200, 'smoke_bomb': 180,
    # legendary
    'thunder_cloud': 360, 'meteor': 450, 'time_stop': 380,
    'revive_potion': 360, 'fairy_tear': 420, 'undead_legion': 400,
    'duplication_potion': 380, 'convert_potion': 370, 'life_fruit': 400,
    'blood_offering': 360,
}

RELIC_PRICE = {'common': 150, 'rare': 200, 'boss': 0}
POTION_PRICE = {}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def read(p):
    return pathlib.Path(p).read_text(encoding='utf-8-sig').replace('\r\n', '\n')


def md_table(headers, rows, align=None):
    align = align or ['---'] * len(headers)
    out = ['| ' + ' | '.join(headers) + ' |', '| ' + ' | '.join(align) + ' |']
    for r in rows:
        out.append('| ' + ' | '.join('' if v is None else str(v) for v in r) + ' |')
    return '\n'.join(out)


def fmt(x, d=1):
    if x is None:
        return '—'
    if isinstance(x, float) and abs(x - round(x)) < 1e-9:
        return str(int(round(x)))
    return f'{x:.{d}f}'


def pct(x):
    return f'{x * 100:.0f}%'


# ---------------------------------------------------------------------------
# Units
# ---------------------------------------------------------------------------
def build_units():
    units = um.load_units()
    # Two enemy resources share the display name "骷髅剑士"; disambiguate them
    # so tables and the calculator can address them independently.
    for u in units:
        if u['id'] == 'skull':
            u['name'] = '骷髅剑士（骨刃）'
        elif u['id'] == 'greatsword_skeleton':
            u['name'] = '骷髅剑士（巨剑）'
    base_model = {'window': MODEL['window'], 'cast': MODEL['cast'],
                  'target_def': MODEL['target_def'], 'area_targets': MODEL['area_targets'],
                  'melee_uptime': MODEL['melee_uptime'], 'ranged_uptime': MODEL['ranged_uptime'],
                  'heal_weight': MODEL['heal_weight']}
    ref = next(u for u in units if u['id'] == 'soldier')
    base = um.simulate(ref, 0, base_model)
    ref_hp = base['ehp']
    ref_out = base['output']

    out = []
    for u in units:
        cur = um.simulate(u, 0, base_model)
        cur_power = MODEL['reference_power'] * math.sqrt((cur['ehp'] / ref_hp) * (cur['output'] / ref_out)) + cur.get('summon_power', 0) if cur['output'] > 0 else cur.get('summon_power', 0)
        # training / card upgrade level 1: current default is all points into attack
        trained = dict(u)
        trained['attack'] = u['attack'] + u['upgrade_points']
        up = um.simulate(trained, 1, base_model) if u.get('max_upgrade', 1) > 0 else cur
        up_power = MODEL['reference_power'] * math.sqrt((up['ehp'] / ref_hp) * (up['output'] / ref_out)) + up.get('summon_power', 0) if up['output'] > 0 else up.get('summon_power', 0)
        trained_note = ''
        if up_power < cur_power:
            # Some upgraded skills replace a base skill with a special effect
            # (chain lightning, frost slow, ...) that this model does not price.
            # Use "current skills + training points" as a conservative floor.
            floor = dict(u)
            floor['attack'] = u['attack'] + u['upgrade_points']
            fs = um.simulate(floor, 0, base_model)
            up_power = MODEL['reference_power'] * math.sqrt((fs['ehp'] / ref_hp) * (fs['output'] / ref_out)) + fs.get('summon_power', 0) if fs['output'] > 0 else fs.get('summon_power', 0)
            trained_note = '模型下限：只计训练点，未计强化技能的特殊效果'
        target = None
        if u['id'] in TARGET_UNITS:
            hp, atk, df, cost = TARGET_UNITS[u['id']]
            tu = dict(u)
            tu.update(hp=hp, attack=atk, defence=df, cost=cost)
            ts = um.simulate(tu, 0, base_model)
            tp = MODEL['reference_power'] * math.sqrt((ts['ehp'] / ref_hp) * (ts['output'] / ref_out)) + ts.get('summon_power', 0) if ts['output'] > 0 else ts.get('summon_power', 0)
            target = {'hp': hp, 'attack': atk, 'defence': df, 'cost': cost,
                      'ehp': round(ts['ehp'], 1), 'dps': round(ts['dps'], 2),
                      'power': round(tp, 1), 'per_cost': round(tp / cost, 1) if cost else None}
        role = unit_role(u)
        out.append({
            'id': u['id'], 'name': u['name'], 'team': 'ally' if u['team'] == 'team_a' else 'enemy',
            'english': u['english'], 'role': role, 'tier': enemy_tier(u) if u['team'] == 'team_b' else None,
            'hp': u['hp'], 'attack': u['attack'], 'defence': u['defence'], 'dodge': u['dodge'],
            'cost': u['cost'], 'upgrade_points': u['upgrade_points'], 'max_upgrade': u['max_upgrade'],
            'card_name': u.get('card_name', ''),
            'skills': u['skills'],
            'current': {'ehp': round(cur['ehp'], 1), 'dps': round(cur['dps'], 2),
                        'hps': round(cur['hps'], 2), 'output': round(cur['output'], 2),
                        'power': round(cur_power, 1), 'per_cost': round(cur_power / u['cost'], 1) if u['cost'] else None,
                        'trained_power': round(up_power, 1),
                        'trained_gain': round(up_power - cur_power, 1),
                        'trained_gain_pct': round((up_power / cur_power - 1) * 100, 1) if cur_power else 0,
                        'trained_note': trained_note},
            'target': target,
        })
    return out, {'soldier_ehp': round(ref_hp, 1), 'soldier_output': round(ref_out, 2)}


def unit_role(u):
    if u['team'] == 'team_b':
        return 'enemy'
    if u['id'] in ('knight', 'knight_templar', 'armored_axeman', 'were_bear'):
        return '前排/守护'
    if u['id'] in ('priest',):
        return '治疗/辅助'
    if u['id'] in ('archer', 'wizard'):
        return '远程输出'
    if u['id'] in ('lancer', 'were_wolf', 'swords_man'):
        return '突进/刺客'
    return '通用前排'


def enemy_tier(u):
    # T1 杂兵, T2 标准, T3 精英, T4 重型, T5 首领
    p = u.get('_power', None)
    if u['id'] in ('minotaur', 'troll'):
        return 'T5'
    if u['id'] in ('bear', 'panda', 'orc_rider', 'turtle'):
        return 'T4'
    if u['id'] in ('pig_rider', 'slime', 'harpoon_shark', 'paddle_shark', 'elite_orc'):
        return 'T3'
    if u['id'] in ('skeleton', 'skeleton_archer', 'gnome', 'bat', 'bumblebee', 'snake', 'imp'):
        return 'T1'
    return 'T2'


# ---------------------------------------------------------------------------
# Cards
# ---------------------------------------------------------------------------
def load_card_texts():
    texts = {}
    path = ROOT / 'docs' / '卡牌效果说明.md'
    if path.exists():
        for header, rows in tables(str(path)):
            if '卡牌' not in header or '基础说明' not in header:
                continue
            for r in rows:
                name = r['卡牌'].strip()
                texts[name] = {
                    'base': r['基础说明'].replace('<br>', '\n'),
                    'upgrade': r.get('强化一次后的说明', '').replace('<br>', '\n'),
                }
    return texts


NEW_CARD_UPGRADE = {
    'armor_shred': '每次受击防御力-2，可叠加，持续本场战斗。',
    'battle_standard': '半径200内友军攻击力+3。',
    'fortify': '全体己方防御力+2。',
    'haste': '全体己方移动速度+30%。',
    'healing_ban': '12秒内无法回复生命。',
    'hold_ground': '费用降为0。',
    'holy_bulwark': '获得40点护盾。',
    'last_stand': '获得相当于已损失生命45%的护盾。',
    'letting_go': '弃1张手牌，抽3张。',
    'martyrdom': '每有1名己方单位阵亡，抽2张。',
    'mobilization': '费用降为0。',
    'overdraft': '本回合能量上限+4，下回合-3。',
    'overflow_prayer': '费用降为1。',
    'reformation': '费用降为1。',
    'rend': '流血9点/秒，持续8秒，无视防御。',
    'return_dead': '以75%最大生命复活。',
    'sacrifice': '每有2名敌方单位阵亡，获得1能量。',
    'slumber': '睡眠8秒，受击立即醒来。',
    'spike_trap': '造成25点伤害并眩晕1秒。',
    'stratagem': '当前其它手牌本回合费用-2，最低0费。',
    'thrift': '费用降为0。',
    'transcription': '抽到的牌临时强化，下次成功使用后还原。',
    'war_cry': '全体己方攻击力+2。',
}


def effect_name(kind):
    names = cm.NAMES
    return names[kind] if 0 <= kind < len(names) else f'KIND_{kind}'


def card_effect_value(e, upgraded=False):
    """Return the design value of one effect in P.

    The coefficient table is the editable part of the model.  Special cases
    read the effect's own duration / radius / status fields instead of forcing
    every kind into a single "amount x coefficient" shape.
    """
    k = effect_name(e.get('kind', 0))
    a = float(e.get('amount', 0)) + (float(e.get('upgrade_amount', 0)) if upgraded else 0)
    seconds = float(e.get('status_seconds', 0)) + (float(e.get('upgrade_status_seconds', 0)) if upgraded else 0)
    rounds = float(e.get('lasting_rounds', 2)) + (float(e.get('upgrade_lasting_rounds', 0)) if upgraded else 0)
    radius = float(e.get('radius', 0))
    if k == 'ATTACK_UP':
        return a * CARD_COEF[k]
    if k == 'DEFENCE_UP':
        return a * CARD_COEF[k]
    if k == 'HEAL_PERCENT':
        return a * CARD_COEF[k]
    if k == 'POISON_ON_HIT':
        return a * CARD_COEF[k]
    if k == 'DEATH_EXPLOSION':
        return a * CARD_COEF[k] * (1 + max(0, radius - 120) / 400)
    if k == 'COPY_ALLY':
        return CARD_COEF[k]
    if k == 'DAMAGE_ZONE':
        return a * CARD_COEF[k]
    if k == 'MUD_ZONE':
        return CARD_COEF[k] + 15 * max(0, rounds - 2)
    if k == 'DRAW':
        return a * CARD_COEF[k]
    if k == 'LOCK_DRAW':
        return CARD_COEF[k]
    if k == 'PAY_HP':
        return a * CARD_COEF[k]
    if k == 'ENERGY_EACH_ROUND':
        return a * CARD_COEF[k]
    if k == 'DEATH_ATTACK_AURA':
        return a * CARD_COEF[k]
    if k == 'RANDOM_PLAY':
        return a * CARD_COEF[k]
    if k == 'RECALL_ALLY':
        return CARD_COEF[k]
    if k == 'GAIN_ENERGY':
        return a * CARD_COEF[k]
    if k == 'MAX_HP_UP':
        return a * CARD_COEF[k]
    if k == 'RETAIN_ALLIES':
        return CARD_COEF[k] - 15 * a
    if k == 'WEAKNESS':
        return a * CARD_COEF[k]
    if k == 'VULNERABILITY':
        return a * CARD_COEF[k]
    if k == 'DEFENCE_DOWN':
        return a * CARD_COEF[k]
    if k == 'PARALYSIS':
        return a * CARD_COEF[k]
    if k == 'CONVERT_ENEMY':
        return CARD_COEF[k]
    if k == 'FRENZY':
        return CARD_COEF[k]
    if k == 'RETREAT_DRAW':
        return CARD_COEF[k] + 15 * a
    if k == 'DIVERSE_ARMY':
        return CARD_COEF[k] + 20 * a
    if k == 'KEEP_DISTANCE':
        return CARD_COEF[k] + 1.5 * (a - 100)
    if k == 'JUDGER':
        return CARD_COEF[k] + 10 * a
    if k == 'COMRADE':
        return CARD_COEF[k]
    if k == 'TEMPORARY_UPGRADE':
        return CARD_COEF[k]
    if k == 'BLEED':
        return a * max(1, seconds) * CARD_COEF[k]
    if k == 'HEALING_BAN':
        return CARD_COEF[k] + 2.5 * max(1, seconds)
    if k == 'ARMOR_SHRED':
        return CARD_COEF[k] + 15 * max(0, a - 1)
    if k == 'SLEEP':
        return CARD_COEF[k] + 4 * max(1, seconds)
    if k == 'SHIELD':
        return a * CARD_COEF[k]
    if k == 'OVERFLOW_SHIELD':
        return CARD_COEF[k]
    if k == 'MISSING_HEALTH_SHIELD':
        return a * CARD_COEF[k]
    if k == 'KNOCKBACK_IMMUNITY':
        return CARD_COEF[k]
    if k == 'TUTOR_UNIT':
        return CARD_COEF[k]
    if k == 'DISCARD_DRAW':
        return a * CARD_COEF[k]
    if k == 'SACRIFICE':
        # amount = enemy deaths required per 1 energy; lower is better.
        return CARD_COEF[k] + 45 * (4.0 / max(1.0, a))
    if k == 'RESURRECT':
        return CARD_COEF[k]
    if k == 'DEATH_DRAW':
        return CARD_COEF[k]
    if k == 'ARMY_ATTACK':
        return a * CARD_COEF[k]
    if k == 'ARMY_DEFENCE':
        return a * CARD_COEF[k]
    if k == 'ARMY_SPEED':
        return a * CARD_COEF[k]
    if k == 'BATTLE_STANDARD':
        return 40 * a
    if k == 'SPIKE_TRAP':
        return 30 + a * CARD_COEF[k]
    if k == 'TRANSCRIBE':
        return CARD_COEF[k] + (20 if upgraded and e.get('upgrade_upgrades_drawn_cards') else 0)
    if k == 'REFORMATION':
        return CARD_COEF[k]
    if k == 'HAND_DISCOUNT':
        return a * CARD_COEF[k]
    if k == 'OVERDRAFT':
        return a * CARD_COEF[k] - 15 * float(e.get('next_round_penalty', 3))
    if k == 'THRIFT':
        return CARD_COEF[k]
    return 0.0


KIND_CN = {
    'ATTACK_UP': '攻击', 'DEFENCE_UP': '防御', 'HEAL_PERCENT': '治疗',
    'POISON_ON_HIT': '附毒', 'DEATH_EXPLOSION': '死亡爆炸', 'COPY_ALLY': '复制',
    'DAMAGE_ZONE': '区域伤害', 'MUD_ZONE': '泥潭', 'DRAW': '抽牌',
    'LOCK_DRAW': '禁抽', 'PAY_HP': '支付生命', 'ENERGY_EACH_ROUND': '每回合能量',
    'DEATH_ATTACK_AURA': '阵亡加攻', 'RANDOM_PLAY': '随机出牌', 'RECALL_ALLY': '回撤',
    'GAIN_ENERGY': '获得能量', 'MAX_HP_UP': '最大生命', 'RETAIN_ALLIES': '留存友军',
    'WEAKNESS': '虚弱', 'VULNERABILITY': '易伤', 'DEFENCE_DOWN': '减防',
    'PARALYSIS': '麻痹', 'CONVERT_ENEMY': '策反', 'FRENZY': '狂化',
    'RETREAT_DRAW': '鸣金', 'DIVERSE_ARMY': '合理搭配', 'KEEP_DISTANCE': '保持距离',
    'JUDGER': '审判者', 'COMRADE': '战友', 'TEMPORARY_UPGRADE': '临时强化',
    'BLEED': '流血', 'HEALING_BAN': '禁疗', 'ARMOR_SHRED': '破甲',
    'SLEEP': '睡眠', 'SHIELD': '护盾', 'OVERFLOW_SHIELD': '溢出转盾',
    'MISSING_HEALTH_SHIELD': '损失生命转盾', 'KNOCKBACK_IMMUNITY': '免击退',
    'TUTOR_UNIT': '检索单位', 'DISCARD_DRAW': '弃牌抽牌', 'SACRIFICE': '献祭',
    'RESURRECT': '复活', 'DEATH_DRAW': '阵亡抽牌', 'ARMY_ATTACK': '全体攻击',
    'ARMY_DEFENCE': '全体防御', 'ARMY_SPEED': '全体移速', 'BATTLE_STANDARD': '战旗',
    'SPIKE_TRAP': '地刺', 'TRANSCRIBE': '誊抄', 'REFORMATION': '变阵',
    'HAND_DISCOUNT': '手牌减费', 'OVERDRAFT': '透支', 'THRIFT': '节流',
}


def upgrade_note(c):
    notes = []
    if c.get('upgrade_cost'):
        notes.append(f"费用 {c['cost']}→{max(0, c['cost'] + c['upgrade_cost'])}")
    for e in c['effects']:
        k = effect_name(e.get('kind', 0))
        kcn = KIND_CN.get(k, k)
        if e.get('upgrade_amount'):
            if k == 'SACRIFICE':
                notes.append(f"每 {fmt(e.get('amount', 0))}→{fmt(e.get('amount', 0) + e['upgrade_amount'])} 名敌方阵亡得1能量")
            else:
                notes.append(f"{kcn} {fmt(e.get('amount', 0))}→{fmt(e.get('amount', 0) + e['upgrade_amount'])}")
        if e.get('upgrade_status_seconds'):
            notes.append(f"持续 {fmt(e.get('status_seconds', 8))}→{fmt(e.get('status_seconds', 8) + e['upgrade_status_seconds'])} 秒")
        if e.get('upgrade_lasting_rounds'):
            r0 = e.get('lasting_rounds', 2)
            notes.append(f"持续 {fmt(r0)}→{fmt(r0 + e['upgrade_lasting_rounds'])} 回合")
        if e.get('upgrade_can_convert_elite'):
            notes.append('可策反精英')
        if e.get('upgrade_upgrades_drawn_cards'):
            notes.append('抽到的牌临时强化')
    return '；'.join(notes) or '机制升级'


def build_cards(units):
    cards = ex.cards()
    texts = load_card_texts()
    unit_by_name = {u['name']: u for u in units}
    out = []
    for c in cards:
        base = sum(card_effect_value(e) for e in c['effects'])
        up = sum(card_effect_value(e, upgraded=True) for e in c['effects'])
        text = texts.get(c['name'])
        if text:
            base_text = text['base']
            upgrade_text = text['upgrade']
        else:
            base_text = c['desc'] or '（待补文案）'
            upgrade_text = NEW_CARD_UPGRADE.get(c['id'], '')
        if not base_text.strip():
            base_text = '（待补文案）'
        target_cost = CARD_TARGET_COST.get(c['id'], c['cost'])
        cur_budget = card_budget(c['cost'])
        target_budget = card_budget(target_cost)
        upgraded_cost = max(0, c['cost'] + c['upgrade_cost'])
        upgraded_budget = card_budget(upgraded_cost)
        out.append({
            'id': c['id'], 'name': c['name'], 'cost': c['cost'], 'target_cost': target_cost,
            'rarity': 'rare' if c['rarity'] == 1 else 'common',
            'category': 'effect', 'role': CARD_ROLE.get(c['id'], 'support'),
            'target': c['target'], 'after': c['after'], 'retain': c['retain'], 'starts': c['starts'],
            'max_upgrade': c['max_upgrade'], 'upgrade_cost': c['upgrade_cost'],
            'upgraded_cost': upgraded_cost,
            'effects': c['effects'], 'desc': base_text, 'upgrade_desc': upgrade_text,
            'power': round(base, 1), 'upgrade_power': round(up, 1),
            'upgrade_delta': round(up - base, 1),
            'upgrade_delta_pct': round((up / base - 1) * 100, 1) if base else 0,
            'upgraded_budget': round(upgraded_budget, 1),
            'upgraded_ratio': round(up / upgraded_budget, 2) if upgraded_budget else None,
            'upgrade_note': upgrade_note(c),
            'budget': round(target_budget, 1),
            'current_budget': round(cur_budget, 1),
            'ratio': round(base / cur_budget, 2) if cur_budget else None,
            'target_ratio': round(base / target_budget, 2) if target_budget else None,
            'tags': card_tags(c),
        })
    # recruit cards (UnitData resources)
    for u in units:
        if u['team'] != 'ally':
            continue
        out.append({
            'id': 'unit_' + u['id'], 'name': u.get('card_name') or (u['name'] + '征召'),
            'cost': u['cost'], 'target_cost': u['cost'], 'rarity': 'common', 'category': 'recruit',
            'role': 'recruit', 'target': 1, 'after': 0, 'retain': False, 'starts': False,
            'max_upgrade': u['max_upgrade'], 'upgrade_cost': 0,
            'upgraded_cost': u['cost'],
            'effects': [], 'desc': f'征召1名{u["name"]}。',
            'upgrade_desc': '训练后提升攻击/防御，并解锁强化技能。',
            'power': u['current']['power'], 'upgrade_power': u['current']['trained_power'],
            'upgrade_delta': u['current']['trained_gain'],
            'upgrade_delta_pct': u['current']['trained_gain_pct'],
            'upgraded_budget': round(card_budget(u['cost']), 1),
            'upgraded_ratio': round(u['current']['trained_power'] / card_budget(u['cost']), 2),
            'upgrade_note': f"训练 +{u['upgrade_points']} 点（默认全加攻击）" + (f"；{u['current']['trained_note']}" if u['current'].get('trained_note') else ''),
            'budget': round(card_budget(u['cost']), 1),
            'current_budget': round(card_budget(u['cost']), 1),
            'ratio': round(u['current']['power'] / card_budget(u['cost']), 2),
            'target_ratio': round(u['current']['power'] / card_budget(u['cost']), 2),
            'tags': ['征召'], 'unit_id': u['id'],
        })
    return out


def card_tags(c):
    tags = []
    for e in c['effects']:
        k = effect_name(e.get('kind', 0))
        if k in ('ATTACK_UP', 'DEFENCE_UP', 'HEAL_PERCENT', 'SHIELD', 'MISSING_HEALTH_SHIELD', 'OVERFLOW_SHIELD'):
            tags.append('增益')
        elif k in ('DAMAGE_ZONE', 'BLEED', 'POISON_ON_HIT', 'DEATH_EXPLOSION', 'SPIKE_TRAP', 'ARMOR_SHRED'):
            tags.append('输出')
        elif k in ('DRAW', 'GAIN_ENERGY', 'ENERGY_EACH_ROUND', 'RANDOM_PLAY', 'RETRIEVE', 'TUTOR_UNIT',
                   'DISCARD_DRAW', 'HAND_DISCOUNT', 'OVERDRAFT', 'THRIFT', 'TRANSCRIBE', 'REFORMATION', 'TEMPORARY_UPGRADE'):
            tags.append('资源')
        elif k in ('WEAKNESS', 'VULNERABILITY', 'DEFENCE_DOWN', 'PARALYSIS', 'SLEEP', 'HEALING_BAN', 'MUD_ZONE',
                   'CONVERT_ENEMY', 'KNOCKBACK_IMMUNITY'):
            tags.append('控制')
        elif k in ('DEATH_ATTACK_AURA', 'DIVERSE_ARMY', 'KEEP_DISTANCE', 'JUDGER', 'COMRADE', 'FRENZY',
                   'ARMY_ATTACK', 'ARMY_DEFENCE', 'ARMY_SPEED', 'BATTLE_STANDARD', 'FORTIFY', 'RETAIN_ALLIES',
                   'DEATH_DRAW', 'MARTYRDOM', 'SACRIFICE', 'RESURRECT'):
            tags.append('成长')
    return sorted(set(tags)) or ['功能']


# ---------------------------------------------------------------------------
# Relics
# ---------------------------------------------------------------------------
NEW_RELIC_SECTIONS = {
    'war_banner': 'wide', 'muster_roll': 'wide', 'diverse_codex': 'wide', 'fallen_roster': 'wide',
    'beacon': 'wide', 'earth_altar': 'wide',
    'anvil': 'tall', 'lone_wolf': 'tall', 'bloodstone': 'tall', 'legacy_seal': 'tall',
    'duel_pact': 'tall', 'kings_blade': 'tall',
    'urn': 'death', 'mourner': 'death', 'sacrificial_dagger': 'death', 'death_echo': 'death',
    'martyr_crown': 'death', 'undying_throne': 'death',
    'corrosive_vial': 'dot', 'ember': 'dot', 'plague_mask': 'dot', 'slow_death': 'dot',
    'sulfur_heart': 'dot', 'burning_city': 'dot',
    'chains': 'control', 'fear_totem': 'control', 'sunder': 'control', 'inquisitor': 'control',
    'executioner': 'control', 'stasis_field': 'control',
    'gloves': 'cycle', 'fate_coin': 'cycle', 'steady_hands': 'cycle', 'borrowed_time': 'cycle',
    'echo_crystal': 'cycle', 'perpetual_gear': 'cycle',
    'iron_wall': 'guard', 'thorn_mail': 'guard', 'last_stand': 'guard', 'counter_stance': 'guard',
    'holy_symbol': 'guard', 'guardian_oath': 'guard', 'blood_bank': 'guard', 'unfallen_fortress': 'guard',
    'longbow_string': 'ranged', 'kite_boots': 'ranged', 'spell_focus': 'ranged',
    'hunter_mark': 'ranged', 'volley_horn': 'ranged',
    'coin_purse': 'economy', 'field_kit': 'economy', 'alchemy_pack': 'economy',
    'merchant_seal': 'economy', 'greedy_cup': 'economy', 'relic_hunter': 'economy',
    'tactical_map': 'neutral', 'scout_horn': 'neutral', 'veteran_medal': 'neutral',
    'hourglass': 'neutral', 'spare_quiver': 'neutral',
}
SECTION_NAME = {
    'wide': '军团铺场', 'tall': '单核养成', 'death': '亡语献祭', 'dot': '毒火持续',
    'control': '控制压制', 'cycle': '循环连招', 'guard': '防守续航', 'ranged': '远程风筝',
    'economy': '经济补给', 'neutral': '中立通用',
}
RARITY_CN = {'common': '普通', 'rare': '稀有', 'boss': '首领'}


def relic_price(rarity, power):
    if rarity == 'boss':
        return 0
    if rarity == 'common':
        return 160 if power >= 80 else 150 if power >= 70 else 140
    return 220 if power >= 180 else 200 if power >= 160 else 180


def build_relics():
    new = parse_new_relics()
    out = []
    for r in new:
        rid = r['id']
        rarity = r['rarity']
        power = RELIC_POWER.get(rid, 70 if rarity == 'common' else 170 if rarity == 'rare' else 350)
        out.append({
            'id': rid, 'name': r['name'], 'rarity': rarity, 'rarity_cn': RARITY_CN[rarity],
            'trigger': r['trigger'], 'effect': r['effect'], 'link': r['link'],
            'tags': [NEW_RELIC_SECTIONS.get(rid, 'neutral')],
            'section': SECTION_NAME.get(NEW_RELIC_SECTIONS.get(rid, 'neutral'), '中立通用'),
            'power': power, 'price': relic_price(rarity, power), 'source': 'current' if (ROOT / 'data/relics' / (rid + '.tres')).exists() else 'new',
        })
    old = ex.resources('relics', {'display_name': '', 'description': '', 'kind': 0, 'amount': 1,
                                  'draw_threshold': 10, 'rounds': 3})
    old_map = {
        'draw_engine': ('十抽引擎', 'rare', 'cycle'),
        'draw_ring': ('行军戒指', 'rare', 'cycle'),
        'base_heart': ('坚城之心', 'common', 'neutral'),
        'traveler_amulet': ('旅人护符', 'common', 'neutral'),
        'reserve_crystal': ('储能水晶', 'rare', 'neutral'),
        'opening_armour': ('出征护甲', 'common', 'wide'),
        'base_armour': ('旧城防', 'common', 'neutral'),
    }
    for r in old:
        rid = r['id']
        if rid == 'base_armour' or rid not in old_map:
            continue
        name, rarity, section = old_map[rid]
        out.append({
            'id': rid, 'name': name, 'rarity': rarity, 'rarity_cn': RARITY_CN[rarity],
            'trigger': 'DRAW_ENERGY' if rid in ('draw_engine', 'draw_ring') else
                       'BATTLE_START' if rid == 'opening_armour' else 'PASSIVE',
            'effect': r['description'], 'link': '', 'tags': [section],
            'section': SECTION_NAME[section],
            'power': RELIC_POWER[rid], 'price': relic_price(rarity, RELIC_POWER[rid]), 'source': 'current',
        })
    out.sort(key=lambda x: ({'common': 0, 'rare': 1, 'boss': 2}[x['rarity']], x['section'], x['name']))
    return out


# ---------------------------------------------------------------------------
# Potions
# ---------------------------------------------------------------------------
ACT_RARE_1 = {'lightning', 'tornado', 'chain_lightning', 'frost_nova', 'aegis_brew',
              'energy_potion', 'tactics_brew', 'insight_brew', 'smoke_bomb'}
ACT_LEG_1 = {'life_fruit'}
ACT_LEG_3 = {'revive_potion', 'undead_legion', 'duplication_potion'}
POTION_RARITY = {'普通': 'common', '稀有': 'rare', '传说': 'legendary'}
RARITY_POTION_CN = {'common': '普通', 'rare': '稀有', 'legendary': '传说'}


def build_potions():
    new = parse_new_potions()
    meta = {}
    for header, rows in tables(str(ROOT / 'docs' / '药水能力设计与投放方案.md')):
        if 'ID' in header and '稀有度' in header:
            for r in rows:
                rid = r['ID'].strip('`')
                meta[rid] = {'rarity': POTION_RARITY.get(r['稀有度'], 'common'),
                             'price': int(r['价格']), 'act': r['层级']}
    out = []
    for p in new:
        rid = p['id']
        m = meta.get(rid, {'rarity': 'common', 'price': 45, 'act': 'A'})
        rarity = m['rarity']
        if rarity == 'common':
            min_act = 1
        elif rarity == 'rare':
            min_act = 1 if rid in ACT_RARE_1 else 2
        else:
            min_act = 3 if rid in ACT_LEG_3 else 1 if rid in ACT_LEG_1 else 2
        out.append({
            'id': rid, 'name': p['name'], 'rarity': rarity, 'rarity_cn': RARITY_POTION_CN[rarity],
            'target': p['target'], 'effect': p['effect'], 'role': p['role'], 'note': p['note'],
            'power': POTION_POWER.get(rid, 100), 'price': m['price'],
            'min_act': min_act, 'tier': m['act'], 'source': 'current' if (ROOT / 'data/potions' / (rid + '.tres')).exists() else 'new',
        })
    return out


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------
def build_events():
    text = read(ROOT / 'docs' / '路线事件设计.md')
    sections = re.split(r'^####\s+(\d+)\s+·\s+(.+?)$', text, flags=re.M)
    events = []
    for i in range(1, len(sections), 3):
        num = int(sections[i])
        title = sections[i + 1].strip()
        body = sections[i + 2]
        # Stop at the horizontal rule that closes this event; otherwise the
        # parser would absorb options from later sections (event 20).
        body = re.split(r'\n---\s*\n', body, maxsplit=1)[0]
        loc = re.search(r'\*\*定位：\*\*\s*(T\d)\s*/\s*(\S+?)\s*/\s*第\s*([\d–\-]+)\s*层', body)
        if not loc:
            continue
        options = []
        for line in body.splitlines():
            if not line.startswith('- **'):
                continue
            parts = [x.strip() for x in line[2:].split('｜')]
            if len(parts) < 2:
                continue
            opt = re.sub(r'\*\*', '', parts[0]).strip()
            options.append({'option': opt, 'cost': parts[1] if len(parts) > 1 else '',
                            'reward': parts[2] if len(parts) > 2 else ''})
        events.append({
            'num': num, 'title': title, 'tier': loc.group(1), 'rarity': loc.group(2),
            'floors': loc.group(3), 'options': options,
        })
    return events


# ---------------------------------------------------------------------------
# Map / routes / waves
# ---------------------------------------------------------------------------
def build_routes():
    d = json.loads(read(ROOT / 'data/run/game_map.json'))
    locs = {l['id']: l for l in d['locations']}
    ends = {l['id'] for l in d['locations'] if l['floor'] == d['floors']}
    paths = []
    def walk(i, p):
        p = p + [i]
        if i in ends:
            paths.append(p)
            return
        for n in locs[i].get('next', []):
            walk(n, p)
    for l in d['locations']:
        if l['floor'] == 1:
            walk(l['id'], [])
    type_name = {0: '战斗', 1: '事件', 2: '篝火', 3: 'Boss', 4: '商店', 5: '宝箱'}
    routes = []
    for p in paths:
        c = Counter(locs[x]['type'] for x in p)
        routes.append({
            'nodes': [locs[x]['title'] for x in p],
            'battles': c.get(0, 0), 'events': c.get(1, 0), 'campfires': c.get(2, 0),
            'shop': c.get(4, 0), 'treasure': c.get(5, 0), 'boss': c.get(3, 0),
        })
    counts = Counter(l['type'] for l in d['locations'])
    return {
        'floors': d['floors'], 'nodes': len(d['locations']),
        'battle': counts.get(0, 0), 'event': counts.get(1, 0), 'campfire': counts.get(2, 0),
        'boss': counts.get(3, 0), 'shop': counts.get(4, 0), 'treasure': counts.get(5, 0),
        'routes': len(routes), 'route_stats': routes,
        'min_battles': min(r['battles'] for r in routes), 'max_battles': max(r['battles'] for r in routes),
        'min_events': min(r['events'] for r in routes), 'max_events': max(r['events'] for r in routes),
    }


ENEMY_SETS = {
    'A': [
        ['skeleton', 'skeleton'], ['skeleton', 'skeleton'], ['skeleton', 'skeleton_archer'],
        [], ['skeleton', 'skeleton'], ['skeleton'],
    ],
    'B': [
        ['skeleton', 'skeleton'], ['skeleton', 'skeleton_archer'],
        ['skeleton', 'skeleton', 'skeleton_archer'], [], ['skeleton', 'orc'],
        ['skeleton', 'skeleton_archer'], ['skeleton'],
    ],
    'C': [
        ['skeleton', 'skeleton'], ['skeleton', 'orc'],
        ['skeleton', 'skeleton_archer', 'skeleton_archer'], [],
        ['skeleton', 'skeleton_archer', 'orc'], ['skeleton', 'skeleton_archer'], ['skeleton'],
    ],
    'D': [
        ['skeleton', 'orc'], ['skeleton_archer', 'orc'],
        ['skeleton', 'skeleton', 'skeleton_archer', 'skeleton_archer'], [],
        ['skeleton', 'skeleton_archer', 'orc'], ['skeleton', 'skeleton_archer'], ['skeleton'],
    ],
    'E': [
        ['skeleton', 'orc'], ['skeleton_archer', 'armored_orc'],
        ['skeleton', 'skeleton_archer', 'skeleton_archer', 'orc'], [],
        ['skeleton', 'skeleton_archer', 'armored_orc'], ['skeleton_archer', 'orc'], ['skeleton'],
    ],
    'F': [
        ['skeleton', 'orc'], ['skeleton_archer', 'skeleton_archer', 'orc'],
        ['skeleton_archer', 'armored_orc'], [], ['skeleton', 'elite_orc'],
        ['skeleton_archer', 'orc'], ['skeleton', 'skeleton_archer', 'armored_orc'],
        [], ['elite_orc', 'armored_orc'], ['skeleton', 'skeleton_archer'],
    ],
}
WAVE_META = {
    'A': {'name': '原野初遇', 'hp': 22, 'rounds': '4–6', 'loss': '0–8'},
    'B': {'name': '边境混编', 'hp': 30, 'rounds': '5–7', 'loss': '6–14'},
    'C': {'name': '补给线阻击', 'hp': 34, 'rounds': '6–8', 'loss': '8–16'},
    'D': {'name': '原野守军', 'hp': 38, 'rounds': '6–8', 'loss': '8–18'},
    'E': {'name': '督军前哨', 'hp': 42, 'rounds': '7–9', 'loss': '10–22'},
    'F': {'name': '原野督军', 'hp': 52, 'rounds': '8–11', 'loss': '16–34'},
}


def player_budget(round_no):
    # 5 draws, 5/12 recruit share, 160 P average unit; round-1 energy is the
    # binding constraint, later rounds are draw-bound.
    return 267.0 if round_no == 1 else 333.0


def build_waves(units):
    up = {u['id']: u for u in units}
    out = []
    for key, waves in ENEMY_SETS.items():
        wave_rows = []
        for i, ids in enumerate(waves, 1):
            p = sum(up[x]['current']['power'] for x in ids if x in up)
            wave_rows.append({'round': i, 'enemies': ids,
                              'names': [up[x]['name'] for x in ids if x in up],
                              'power': round(p, 1), 'count': len(ids),
                              'pressure': round(p / player_budget(i), 2)})
        peak = max((w['power'] for w in wave_rows), default=0)
        peak_pressure = max((w['pressure'] for w in wave_rows), default=0)
        avg = sum(w['power'] for w in wave_rows) / max(1, len(wave_rows))
        out.append({'id': key, 'name': WAVE_META[key]['name'], 'hp': WAVE_META[key]['hp'],
                    'target_rounds': WAVE_META[key]['rounds'], 'target_loss': WAVE_META[key]['loss'],
                    'waves': wave_rows, 'peak_power': round(peak, 1),
                    'peak_pressure': peak_pressure,
                    'avg_power': round(avg, 1)})
    return out


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    units, baseline = build_units()
    # fill enemy tier after power is known
    for u in units:
        if u['team'] == 'enemy':
            u['tier'] = enemy_tier(u)
    cards = build_cards(units)
    relics = build_relics()
    potions = build_potions()
    events = build_events()
    routes = build_routes()
    waves = build_waves(units)
    data = {
        'meta': {
            'title': 'ballsprite 商业级数值框架与全量数值',
            'version': 'NUM-DESIGN-v1.0',
            'date': '2026-10-19',
            'scope': '第一章翠绿原野 / 三幕结构 / 单位、卡牌、遗物、药水、路线、经济',
            'soldier_power': 100,
            'note': '已接入NUM-DESIGN-v1.0；每段扣ceil(防御/段数)。P为估价，胜率与时长仍需试玩校准。',
        },
        'model': {**MODEL, 'cardCoef': CARD_COEF, 'kindNames': cm.NAMES, 'kindCn': KIND_CN},
        'baseline': {
            **baseline,
            'start_hp': 80, 'start_gold': 99, 'start_cards': 12,
            'start_deck': {'运筹帷幄': 2, '士兵': 3, '弓箭手': 2, '护甲加固': 2, '力量强化': 3},
            'start_deck_ids': [['master_strategy', 2], ['unit_soldier', 3], ['unit_archer', 2],
                               ['defend', 2], ['power_enhance', 3]],
            'energy_round_1': 3, 'energy_growth': 1, 'energy_cap': 10,
            'draw_per_round': 5, 'enemy_max_hp': 45,
            'battle_reward_gold': 35, 'boss_reward_gold': 120,
            'normal_potion_chance': 35, 'normal_relic_chance': 12,
            'boss_potion_chance': 100, 'boss_relic_chance': 100,
        },
        'prices': {
            'card': {'common': '55–80', 'rare': '90–120'},
            'relic': {'common': '140–160', 'rare': '180–220', 'boss': '不出售'},
            'potion': {'common': '40–55', 'rare': '65–90', 'legendary': '110–150'},
            'recruit': '60–170', 'remove': '75 + 25×已删次数',
        },
        'drops': {
            'normal': {'gold': 35, 'potion': 35, 'relic': 12},
            'elite': {'gold': 60, 'potion': 60, 'relic': 35},
            'boss': {'gold': 120, 'potion': 100, 'relic': 100, 'relic_choice': 3},
            'treasure': {'gold': 0, 'relic_choice': 3},
        },
        'units': units, 'cards': cards, 'relics': relics, 'potions': potions,
        'events': events, 'routes': routes, 'waves': waves,
    }
    DATA_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding='utf-8')
    print('wrote', DATA_PATH, len(json.dumps(data, ensure_ascii=False)), 'chars')
    print('units', len(units), 'cards', len(cards), 'relics', len(relics), 'potions', len(potions),
          'events', len(events), 'waves', len(waves))
    print('ally', [(u['name'], u['current']['power'], u['target']['power'] if u['target'] else None) for u in units if u['team'] == 'ally'])
    print('relic rarity', Counter(r['rarity'] for r in relics))
    print('potion rarity', Counter(p['rarity'] for p in potions))


if __name__ == '__main__':
    main()
