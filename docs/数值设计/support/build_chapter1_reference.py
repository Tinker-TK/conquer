"""Build a reference design, without editing live game resources."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'docs' / '数值设计'
MAP = ROOT / 'data' / 'levels' / '第一章 ·  翠绿原野.json'
chapter = json.loads(MAP.read_text(encoding='utf-8-sig'))
nodes = {n['id']: n for n in chapter['locations']}

def unit_values(name):
    defaults = {'max_hp': 100, 'attack': 15, 'defence': 5,
                'card_cost': 1, 'hp_damage_value': 1, 'dodge_rate': 0}
    source = ROOT / 'data' / 'units' / (name + '.tres')
    text = source.read_text(encoding='utf-8-sig')
    for key in defaults:
        hit = re.search(r'^' + key + r'\s*=\s*([0-9.]+)\s*$', text, re.M)
        if hit:
            defaults[key] = float(hit[1]) if '.' in hit[1] else int(hit[1])
    return defaults

enemies = [
    {'code': 'S', 'name': '骷髅兵', 'source': 'skeleton', 'max_hp': 70, 'attack': 9, 'defence': 2, 'hp_damage_value': 1, 'dodge_rate': 0, 'role': '基础近战，早期主力'},
    {'code': 'R', 'name': '骷髅弓手', 'source': 'skeleton_archer', 'max_hp': 55, 'attack': 10, 'defence': 1, 'hp_damage_value': 2, 'dodge_rate': 0, 'role': '脆弱远程；资源显示名为弓箭手哥布林'},
    {'code': 'O', 'name': '哥布林', 'source': 'orc', 'max_hp': 100, 'attack': 11, 'defence': 3, 'hp_damage_value': 1, 'dodge_rate': 0, 'role': '中段近战，力量强化的受益目标'},
    {'code': 'T', 'name': '武装哥布林', 'source': 'armored_orc', 'max_hp': 145, 'attack': 10, 'defence': 4, 'hp_damage_value': 2, 'dodge_rate': 0, 'role': '高生命前排；首版关闭闪避，减少随机反击'},
    {'code': 'B', 'name': '原野督军', 'source': 'elite_orc', 'max_hp': 220, 'attack': 13, 'defence': 4, 'hp_damage_value': 3, 'dodge_rate': 0, 'role': '沿用精英哥布林技能，仅作为Boss波次单位'},
]
for u in enemies:
    u['current'] = unit_values(u['source'])
    u['source_path'] = 'res://data/units/' + u['source'] + '.tres'

def wave(s=0, r=0, o=0, t=0, b=0):
    return dict(zip(['S', 'R', 'O', 'T', 'B'], [s, r, o, t, b]))

# Reference settlement: result 1=win, 0=loss, 2=draw. It is a design example,
# never presented as a simulated or measured combat outcome.
encounters = [
    {'id': 'A', 'name': '原野初遇', 'floors': '第2层', 'enemy_max_hp': 22, 'round_target': '4–6', 'loss_target': '0–8',
     'waves': [wave(1), wave(2), wave(1,1), wave(), wave(2), wave(1)],
     'settlement': [(1,2,0),(1,3,0),(0,0,1),(1,3,0),(1,2,0)],
     'purpose': '先学征召，再接触近远程混编；第4轮给补伤害机会。'},
    {'id': 'B', 'name': '边境混编', 'floors': '第4层战斗', 'enemy_max_hp': 30, 'round_target': '5–7', 'loss_target': '6–14',
     'waves': [wave(2), wave(1,1), wave(2,1), wave(), wave(1,0,1), wave(1,1), wave(1)],
     'settlement': [(1,3,0),(1,3,0),(0,0,2),(1,3,0),(0,0,2),(1,3,0),(1,2,0)],
     'purpose': '第一场明显压力；第3、5轮检验强化和前后排配合。'},
    {'id': 'C', 'name': '补给线阻击', 'floors': '第5层战斗', 'enemy_max_hp': 34, 'round_target': '6–8', 'loss_target': '8–16',
     'waves': [wave(2), wave(1,0,1), wave(1,2), wave(), wave(1,1,1), wave(1,1), wave(1)],
     'settlement': [(1,3,0),(1,2,0),(0,0,2),(1,3,0),(0,0,2),(1,3,0),(1,3,0)],
     'purpose': '双远程与哥布林交替；仍只用当前起始牌组做基准。'},
    {'id': 'D', 'name': '原野守军', 'floors': '第7层战斗', 'enemy_max_hp': 38, 'round_target': '6–8', 'loss_target': '8–18',
     'waves': [wave(1,0,1), wave(0,1,1), wave(2,2), wave(), wave(1,1,1), wave(1,1), wave(1)],
     'settlement': [(1,3,0),(1,3,0),(0,0,2),(1,3,0),(0,0,2),(1,3,0),(1,3,0),(1,2,0)],
     'purpose': '第3轮四单位为本关峰值，随后缓和；第8轮起复用末波单骷髅。'},
    {'id': 'E', 'name': '督军前哨', 'floors': '第8层战斗', 'enemy_max_hp': 42, 'round_target': '7–9', 'loss_target': '10–22',
     'waves': [wave(1,0,1), wave(0,1,0,1), wave(1,2,1), wave(), wave(1,1,0,1), wave(0,1,1), wave(1)],
     'settlement': [(1,3,0),(0,0,2),(0,0,2),(1,3,0),(0,0,2),(1,3,0),(1,3,0),(1,3,0),(1,2,0)],
     'purpose': '引入高生命前排，鼓励力量强化；不要求高阶征召、药水或招募奖励。'},
    {'id': 'F', 'name': '原野督军', 'floors': '第10层Boss', 'enemy_max_hp': 52, 'round_target': '8–11', 'loss_target': '16–34',
     'waves': [wave(1,0,1), wave(0,2,1), wave(0,1,0,1), wave(), wave(1,0,0,0,1), wave(0,1,1), wave(1,1,0,1), wave(), wave(0,1,0,0,1), wave(1,1)],
     'settlement': [(1,3,0),(1,3,0),(0,0,2),(1,3,0),(0,0,3),(1,3,0),(0,0,2),(1,3,0),(1,2,0),(1,3,0)],
     'purpose': '第5、9轮督军压力，第4、8轮喘息；第11轮起循环6–10波，不附加成长。'},
]
by_enc = {e['id']: e for e in encounters}
damage_values = {u['code']: u['hp_damage_value'] for u in enemies}

def resolve_wave(e, round_no):
    if e['id'] != 'F':
        return min(round_no, len(e['waves'])) - 1, 0
    if round_no <= 10:
        return round_no - 1, 0
    elapsed = round_no - 11
    return 5 + elapsed % 5, 1 + elapsed // 5

for e in encounters:
    e.update(energy_per_round=3, energy_growth=1, base_energy_cap=10, cards_per_round=5,
             repeat_waves=e['id']=='F', repeat_start=6 if e['id']=='F' else 1,
             repeat_end=10 if e['id']=='F' else 0, cycle_growth={'attack':0,'max_hp':0,'defence':0})
    hp, loss = e['enemy_max_hp'], 0
    e['reference_rows'] = []
    for r, (result, allies, enemy) in enumerate(e['settlement'], 1):
        idx, cycle = resolve_wave(e, r)
        composition = e['waves'][idx]
        enemy_pool = sum(composition[k]*damage_values[k] for k in composition)
        assert enemy <= enemy_pool
        assert result in [0,1,2]
        assert result != 0 or sum(composition.values()) > 0
        assert hp > 0, 'Reference example must stop after victory'
        dealt = r + allies if result == 1 else 0
        lost = r + enemy if result == 0 else 0
        hp = max(0, hp-dealt)
        loss += lost
        e['reference_rows'].append({'round':r, 'wave':idx+1, 'cycle':cycle,
            'composition':composition, 'result':result, 'ally_survivor_damage':allies,
            'enemy_survivor_damage':enemy, 'enemy_damage':dealt, 'player_loss':lost,
            'enemy_remaining_hp':hp, 'cumulative_loss':loss, 'base_energy':min(3+r-1,10)})
    assert hp == 0
    e['reference_rounds'] = len(e['settlement'])
    e['reference_loss'] = loss
    e['reference_enemy_damage'] = sum(x['enemy_damage'] for x in e['reference_rows'])

floor_enc = {2:'A', 4:'B', 5:'C', 7:'D', 8:'E', 10:'F'}
for n in chapter['locations']:
    n['reference_encounter'] = floor_enc[n['floor']] if n['type'] in (0,3) else ''

paths = []
def walk(id_, prefix):
    node = nodes[id_]
    path = prefix + [id_]
    if not node['next']:
        paths.append(path)
    for nxt in node['next']:
        walk(nxt, path)
for id_ in chapter['starting_ids']:
    walk(id_, [])

def path_budget(path, factor=1):
    hp, total_loss, actual_heal = 100, 0, 0
    boss_entry = None
    points = []
    for id_ in path:
        n = nodes[id_]
        if n['type'] == 3:
            boss_entry = hp
        loss = by_enc[n['reference_encounter']]['reference_loss']*factor if n['reference_encounter'] else 0
        heal = max(c['heal'] for c in n['event']['choices']) if n['type'] in (1,2) else 0
        previous = hp
        hp = 0 if hp <= 0 or hp-loss <= 0 else min(100,hp-loss+heal)
        used = max(0,hp-(previous-loss)) if previous>loss else 0
        total_loss += loss
        actual_heal += used
        points.append({'node_id':id_, 'entry_hp':previous, 'loss':loss, 'nominal_heal':heal, 'actual_heal':used, 'exit_hp':hp})
    return {'boss_entry_hp':boss_entry, 'end_hp':hp, 'total_loss':total_loss,
            'actual_heal':actual_heal, 'points':points}

routes = []
for i, path in enumerate(paths, 1):
    types = [nodes[x]['type'] for x in path]
    assert len(path) == 10 and types[-1] == 3
    routes.append({'id':i, 'nodes':path, 'normal_battles':types.count(0),
        'rest_count':types.count(2), 'baseline':path_budget(path), 'stress':path_budget(path,1.5)})

facts = {'node_count':len(chapter['locations']), 'starting_hp':100, 'max_hp':100, 'gold':99, 'starting_deck':{'soldier':3,'archer':2,'defend':2,'power_enhance':3},
    'normal_battles_min':min(r['normal_battles'] for r in routes),
    'normal_battles_max':max(r['normal_battles'] for r in routes),
    'path_count':len(routes), 'rest_min':min(r['rest_count'] for r in routes), 'rest_max':max(r['rest_count'] for r in routes),
    'boss_entry_min':min(r['baseline']['boss_entry_hp'] for r in routes),
    'boss_entry_max':max(r['baseline']['boss_entry_hp'] for r in routes),
    'end_hp_min':min(r['baseline']['end_hp'] for r in routes), 'end_hp_max':max(r['baseline']['end_hp'] for r in routes),
    'stress_boss_min':min(r['stress']['boss_entry_hp'] for r in routes), 'stress_boss_max':max(r['stress']['boss_entry_hp'] for r in routes),
    'stress_end_min':min(r['stress']['end_hp'] for r in routes), 'stress_end_max':max(r['stress']['end_hp'] for r in routes)}

source_files = ['data/levels/第一章 ·  翠绿原野.json','data/units/unit_data.gd','data/run/run_start_data.tres','data/run/run_start_data.gd',
    'scripts/battle/level_wave.gd','scripts/battle/wave_sequence.gd','scripts/battle/battle_round_manager.gd','scripts/cards/card_instance.gd',
    'scripts/cards/hand_manager.gd','scripts/units/skill_manager.gd','scripts/map/fixed_map_config.gd','autoload/run_manager.gd',
    'data/cards/power_enhance.tres','data/cards/defend.tres','data/relics/base_heart.tres'] + ['data/units/'+u['source']+'.tres' for u in enemies] + ['data/units/soldier.tres','data/units/archer.tres']
data = {'version':'CH1-v0.1', 'date':'2026-10-09', 'status':'reference_only_not_game_import',
    'scope':'保留现有节点类型和连线；不计地形、天气、站位收益；不依赖新卡或药水；结算示例不代表实测。',
    'facts':facts, 'player_units':{name:unit_values(name) for name in ['soldier','archer']},
    'enemies':enemies, 'encounters':encounters,
    'chapter_nodes':sorted(chapter['locations'],key=lambda n:(n['floor'],n['id'])), 'routes':routes,
    'sources': [{'path':s,'sha256':hashlib.sha256((ROOT/s).read_bytes()).hexdigest()} for s in source_files]}
(OUT/'第一章·翠绿原野_数值草案.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')

def composition(w):
    return ' + '.join(f'{k}×{v}' for k,v in w.items() if v) or '空波'
def table(headers, rows):
    return '\n'.join(['| '+' | '.join(headers)+' |','| '+' | '.join(['---']*len(headers))+' |'] + ['| '+' | '.join(map(str,row))+' |' for row in rows])

doc = f'''# 第一章·翠绿原野：关卡数值参考 v0.1

版本：CH1-v0.1。日期：2026-10-09。用途：给现有项目提供一套可填入配置、再通过试玩调整的首版数值。

本版保持原地图的10层、{facts['node_count']}个节点、全部连线和实际节点类型，只给真实战斗节点分配6套不同强度的配置。不计地形、天气、移动路径或特殊站位带来的收益；保留现有技能。本文和同名工作簿是参考方案，尚未修改游戏中的 `.tres` 或地图 JSON。所有目标区间和参考结算顺序都是设计假设，没有虚构试玩结果。

## 1. 先固定试玩基准

先用当前起始牌组测这章：士兵×3、弓箭手×2、护甲加固×2、力量强化×3，共10张。士兵100生命/10攻击/5防御，弓手80生命/13攻击/3防御，均初始1费；攻击强化1费加5攻击，护甲1费加3防御。保留现有技能倍率和冷却，不同时调整牌组与关卡。

玩家有效开局生命为100/100：RunStartData基础80，加坚城之心20。初始金币99。保留现有遗物行为；十抽引擎产生的额外能量按真实抽牌计数处理，不把它假定成每个偶数回合必得1能量，因为计数可跨战斗。三瓶初始药水保留，但首轮校准先不用药水；随后单独记录药水能少掉多少生命。当前事件主要给金币，不假设玩家已获得更强征召牌。

全部6套关卡统一：`energy_per_round=3`、`energy_growth=1`、`base_energy_cap=10`、`cards_per_round=5`。基础能量依次3/4/5/6/7/8/9/10/10…；遗物附加能量另算。

## 2. 实际路线与绑定

当前文件中，`floor_03_01`、`floor_03_03`、`floor_04_01`、`floor_06_01` 虽然标题写“战斗”，但 `type=1`，实际为事件；`floor_09_02` 标成“战斗”，但 `type=2`，实际为回血休息。本方案按类型处理它们，不擅自增加战斗。使用数值草案时只需把标题改得与实际类型一致，避免体验判断出错。

{table(['楼层','真实战斗节点','草案编号','其他节点'],[
    ['1','无','—','开局事件，维持金币15'],
    ['2','02_01 / 02_02 / 02_03','A','三个分支同强度；忽略原场景地形差别'],
    ['3','无','—','全部为事件'],
    ['4','04_03','B','04_01事件；04_02回血20'],
    ['5','05_02','C','05_01 / 05_03事件'],
    ['6','无','—','06_01 / 06_03事件；06_02回血20'],
    ['7','07_02 / 07_03','D','07_01事件'],
    ['8','08_01 / 08_03','E','08_02事件'],
    ['9','无','—','09_01 / 09_02均回血20'],
    ['10','10_01','F','Boss终点']])}

以上节点简写省略了 `floor_` 前缀。路线穷举得到{facts['path_count']}条完整路径，每条有{facts['normal_battles_min']}–{facts['normal_battles_max']}场普通战斗、1场Boss、{facts['rest_min']}–{facts['rest_max']}次休息。因此第一章不能按“固定打8场小怪后再打Boss”来定生命预算。

## 3. 敌方单位属性

S/R/O/T/B只是本文的波次代号。以下属性只用于本章的敌方副本，不改玩家征召对应的全局资源。两类生命要分开：这一表的生命是场上单位生命；下一节的据点生命是胜利结算要扣完的 `enemy_max_hp`。

{table(['代号','敌人','单位生命','攻击','防御','获胜幸存扣血值','闪避'],[[u['code'],u['name'],u['max_hp'],u['attack'],u['defence'],u['hp_damage_value'],'0%'] for u in enemies])}

- S来自 `skeleton.tres`，保留普通攻击和强击，设计为可由一名士兵处理的基础敌人。
- R来自 `skeleton_archer.tres`，资源显示名目前是“弓箭手哥布林”。保留现有射击技能，生命较低但幸存扣血值2，促使玩家注意远程敌人。
- O来自 `orc.tres`，保留普通攻击和1.5倍率强击，比S更耐打。
- T来自 `armored_orc.tres`，保留主动技能，首版将闪避率从20%设为0；防守反击不会因闪避触发。先把基础强度调好，再尝试恢复10%闪避。
- B来自 `elite_orc.tres`，取名原野督军，保留现有技能。当前旋转攻击是普通攻击脚本、0.8倍率、4个命中帧、8秒冷却，不能按“一次范围攻击”估价；本章只提高生命到220，攻击降至13、防御降至4，避免原攻击17、防御7压制初始牌组。

本章敌人最高防御4，避免士兵10攻击长期卡在1点伤害。基础攻击公式仍是 `max(int(攻击×倍率)-目标防御,1)`，多段攻击每段分别减防御。

数值手感对照：士兵打S，普通攻击8伤害，+5攻击后13伤害；仅看普通攻击击杀需要9次或6次。士兵打T，普通攻击6伤害，强化后11伤害，需要25次或14次。S打士兵每次4伤害，+3防御后为1；督军普通攻击打士兵每次8伤害，加固后5。这些是属性检查，不是完整交锋耗时或真实DPS，技能和同时攻击会改变结果。

## 4. 六套关卡总参数

{table(['编号/名称','据点生命','目标交锋轮数','目标生命战损','参考脚本轮数','参考脚本战损'],[[e['id']+' '+e['name'],e['enemy_max_hp'],e['round_target'],e['loss_target'],e['reference_rounds'],e['reference_loss']] for e in encounters])}

交锋轮数指一次遭遇内的回合数。目标战损指玩家基地生命减少量，不是场上单位损失。目标区间用于试玩后判断偏差；右两列来自下文明确列出的假设胜负与幸存者结算，不是模拟胜率，也不是实测平均值。

## 5. 每轮敌人编成

所有单位按当前技能出场。不加波次固定强化，不加循环成长。空波是 `waves` 数组中的 `null`，不是删除这一轮；玩家仍须正常完成本轮出牌与结算。
'''

for e in encounters:
    doc += f'\n### {e["id"]}：{e["name"]}\n\n{e["purpose"]}\n\n'
    doc += table(['原始波次/回合','敌人编成','人数','本波幸存扣血上限'],[[i+1,composition(w),sum(w.values()),sum(w[k]*damage_values[k] for k in w)] for i,w in enumerate(e['waves'])])+'\n\n'
    if e['id']=='F':
        doc += '`repeat_waves=true`，`repeat_start=6`，`repeat_end=10`。第11–15轮依次使用O+R / T+S+R / 空波 / B+R / S+R，第16轮开始同样循环；单位属性不成长。这样长战仍有喘息，不因征召涨费进入无限加强。\n'
    else:
        doc += '`repeat_waves=false`。列表耗尽后，当前代码会持续复用最后一个非空波次，本版均为S×1；不会因打完列表自动胜利。据点生命仍必须打到0。\n'

doc += '''
## 6. 结算公式与一版参考结果

每轮单位全清：存活单位也不会自动带到下一轮。原征召牌绑定单位死亡或清场后，该卡实例费用+1并回弃牌堆，下一场遭遇重置费用。非RUN的单位强化不会自动继承给下一轮的新单位。因此本版在前几轮做压力峰值，再用空波和单S收尾，不把“每轮能量+1”当成每轮可以无条件多铺一名士兵。

我方赢本轮：`敌方据点扣血 = 当前回合数 + Σ我方幸存单位hp_damage_value`。

敌方赢本轮：`玩家基地扣血 = 当前回合数 + Σ敌方幸存单位hp_damage_value`。

双方全灭：本轮扣血0。幸存扣血值看谁活着，不看其剩余生命百分比；攻击力也不直接乘进据点扣血。

Boss F的一组参考结算如下。它用于核验52点据点生命和约22点战损能否在10轮脚本中同时成立，并不保证手牌随机、出牌选择和真实交锋一定产生该顺序。

'''
doc += table(['回合','假设胜负','获胜方幸存扣血值合计','打敌据点','玩家战损','敌方余生命'],[[r['round'],'胜' if r['result']==1 else '败',r['ally_survivor_damage'] if r['result']==1 else r['enemy_survivor_damage'],r['enemy_damage'],r['player_loss'],r['enemy_remaining_hp']] for r in by_enc['F']['reference_rows']])+'\n\n'
doc += f'''该脚本第3/5/7轮失败，分别损失5/8/9生命，共22；第10轮将52点据点生命扣完。全部6套脚本都在工作簿“波次与结算”中，可修改胜负和幸存扣血值，观察轮数、战损及路线生命变化。

## 7. 整章生命预算

维持原图事件金币15、休息回血20，回血不超过100；以不使用药水、取回血选项为基准。对所有{facts['path_count']}条路径按上述结算示例逐节点计算，考虑满血溢出与生命归零后无法继续：

- 基准脚本：Boss入场生命{facts['boss_entry_min']}–{facts['boss_entry_max']}，章末生命{facts['end_hp_min']}–{facts['end_hp_max']}。
- 压力情景：各战斗战损预算统一×1.5，Boss入场{facts['stress_boss_min']}–{facts['stress_boss_max']}，章末{facts['stress_end_min']}–{facts['stress_end_max']}。

×1.5仅检查生命预算的余量，使用连续数值预算，可能出现半点生命；真实游戏生命为整数，它不是另一组真实可复现的交锋脚本。较少战斗的路线会更轻松，这是现有事件密度造成的。本版先接受这一差异；如果试玩发现事件路始终占优，后续再给战斗路增加有用奖励或调整节点类型，不在首次定数时同时改变成长系统。

第9层两条路线都有20点回血，预期让玩家以较好的状态试Boss。开局遗物或药水如果之后删减，应重测这章，不直接套用本版生命预算。

## 8. 填入游戏配置的顺序

1. 在游戏配置中复制5份敌人资源，使用例如 `ch1_skeleton`、`ch1_archer`、`ch1_orc`、`ch1_armored_orc`、`ch1_commander` 标识；保留原单位类型、动画、技能路径，仅写入第3节属性。不要直接降低 `data/units/skeleton.tres` 等全局共享资源。
2. 在波次编辑器创建A–F的波次，给敌人的 `unit_data` 绑定本章副本。波次的单次强化、循环成长均留空。已有 `wave_spawn_effects` 只支持正向增益，不能靠负值把原攻击15减到9；必须用独立资源或等价的独立属性快照。
3. 复制关卡资源为 `level_ch1_a.tres` 至 `level_ch1_f.tres`，填入据点生命、能量、抽牌和循环规则。原地图的A节点目前用 `level_001` / `level_001_1`，B–E大多用 `level_001`，需要分别绑定新ID才能出现进度差异。
4. 在地图工坊按第2节真实战斗节点替换 `event_id`，保存为新路线文件；事件和休息节点仍维持原类型与奖励。本文JSON是分析草案，不是地图工坊可直接导入的路线文件。
5. 第一次验证用平坦、晴天、无水/雪/泥潭影响的战场，并使用一致的摆放规则。若绑定原战场，实际地形仍会影响交锋，本章数值不能单独解释差异。

## 9. 试玩后怎样改

先单独测A、E、F，再打完整章节。每档至少试10次，覆盖“只征召”“征召+力量强化”“征召+护甲”三种常见策略，记录进入/离开生命、交锋轮数、每轮剩余能量、征召牌当前费用、实际交锋秒数；药水使用另列。10次只用于发现大偏差，不足以稳定估计精确通关率。

{table(['观察到的偏差','优先调整','一轮建议幅度'],[
    ['大部分轮都能赢，但关卡拖长','据点生命','A–E减4；F减6'],
    ['通关过快，交锋本身合适','据点生命','A–E加4；F加6'],
    ['第1轮就普遍打不过','第1波编成 / 单位攻击','少1个S；或该档攻击减1，不先增加玩家回血'],
    ['前期能打，后期只因费用上涨崩盘','尾部波次 / 空波位置','提前1轮给空波，或把最后波改为S×1'],
    ['T需要过久才能杀死，但输得不突然','T生命','145减至130'],
    ['督军波突然全灭','B攻击或随从数','13减至12；先保留220生命'],
    ['进入Boss前生命常低于50','中段败轮 / 原图休息','先降低D/E关键波强度，后尝试单次回血+5'],
    ['进入Boss经常满血且Boss无需思考','Boss关键波 / 据点生命','先只把F据点52增至58，再决定是否增加敌人']])}

一次只动一个维度，保留版本编号。缩短据点生命只能减少需要赢的轮数，不会直接改善某一轮的交锋强度；提高攻击则会同时影响胜负和交锋时长。若后续启用更强单位或新增永久强化奖励，再单独更新敌兵与波次数量，别先用这版数值推断全局兵种平衡。

## 10. 文件与验证范围

- `第一章·翠绿原野_关卡参考.xlsx`：4张表，关卡总览、波次与结算、敌兵与开局、路线生命；黄色为可调输入，白色为公式，灰色为项目当前值。目标区间在文档中保留，脚本模型中明确使用假设结果。
- `第一章·翠绿原野_数值草案.json`：完整敌兵属性、6套配置、波次、参考结算、实际节点绑定与全部路径；带源文件SHA256用于后续追溯。它不会自动修改或导入游戏。
- 已做静态资源核对、连线穷举、参考脚本结算与表格公式校验。没有真实交锋胜率/耗时测量，也没有将草案运行在Godot战场中。当前Godot命令行导出尝试在引擎启动阶段崩溃，因此本次属性核对采用现有源码与资源默认值，不把旧快照当作新实测结果。

主要依据：`data/levels/第一章 ·  翠绿原野.json`、`data/units/*.tres`、`data/units/unit_data.gd`、`data/run/run_start_data.tres`、`data/run/run_start_data.gd`、`scripts/battle/battle_round_manager.gd`、`scripts/battle/level_wave.gd`、`scripts/battle/wave_sequence.gd`、`scripts/cards/card_instance.gd`、`scripts/cards/hand_manager.gd`、`scripts/units/skill_manager.gd`、`scripts/map/fixed_map_config.gd`、`autoload/run_manager.gd`。默认值与本章设计值在工作簿分列展示。
'''
(OUT/'第一章·翠绿原野_初版.md').write_text(doc,encoding='utf-8')
print(json.dumps({'facts':facts,'encounters':[{k:e[k] for k in ['id','enemy_max_hp','reference_rounds','reference_loss','reference_enemy_damage']} for e in encounters]},ensure_ascii=False))
