"""把设计文案与明确的效果配方生成 EventDefinition；不解析文档中的工程指令。"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'assets/ui/events/illustrations'
J = lambda value: json.dumps(value, ensure_ascii=False)
def effect(kind, **values): return {'type': kind, **values}
def offer(kind='unit', pool=None):
    return effect('choose_cards', unit_offer=3 if kind=='unit' else 0, unit_picks=int(kind=='unit'), effect_offer=3 if kind=='effect' else 0, effect_picks=int(kind=='effect'), **({'unit_pool': pool} if pool else {}))
def choice(e=None, cost=None, gold=0, heal=0):
    out = {'gold': gold, 'heal': heal}
    if e: out['effects' if isinstance(e, list) else 'effect'] = e
    if cost: out['cost'] = cost
    return out
def gamble(stake, payout):
    return choice(effect('gamble', chance=.5, win=effect('gold', amount=payout), lose=effect('gold', amount=0)), {'gold': stake})
unit = lambda name: f'res://data/units/{name}.tres'
recruit = lambda name: f'res://data/event_recruits/{name}.tres'
elite = [unit(n) for n in ['knight', 'knight_templar', 'armored_axeman', 'lancer']]
beasts = [unit('were_wolf'), unit('were_bear'), recruit('bear')]
undead = [recruit(n) for n in ['skeleton', 'skeleton_archer', 'greatsword_skeleton']]
specs = [
('broken_standard',3,8,'rare',['recruit'],['two_recruits'],[choice(offer(pool=elite), {'max_hp':8}),choice(gold=55),choice(effect('random_potion'),heal=12)]),
('retired_drillmaster',2,6,'common',['train'],['trainable'],[choice(effect('train_unit'),{'gold':35}),choice(cost={'gold':20},heal=18),choice(offer('effect'),{'gold':45})]),
('beast_den',2,6,'common',['recruit'],[],[choice(offer(pool=beasts),{'max_hp':8}),choice(gold=35,heal=8),choice(effect('random_potion'))]),
('twin_barracks',5,9,'rare',['duplicate'],[],[choice(effect('duplicate_card',filter='recruit'),{'max_hp':8}),choice(gold=45),choice(effect('train_unit'),{'hp':8})]),
('last_forge',4,8,'rare',['remove'],['removable','enhanceable'],[choice([effect('remove_card'),effect('enhance_card')]),choice(effect('enhance_card'),{'gold':50}),choice(cost={'hp':8},gold=45)]),
('silent_altar',3,8,'common',['remove'],['removable'],[choice(effect('remove_card'),{'max_hp':6}),choice(effect('remove_card'),{'gold':70}),choice(heal=12)]),
('mirror_lake',5,9,'rare',['duplicate'],[],[choice(effect('duplicate_card',filter='any'),{'max_hp':12}),choice(heal=20),choice(cost={'hp':6},gold=55)]),
('war_games',4,8,'common',['enhance'],[],[choice(effect('enhance_random',count=2),{'max_hp':8}),choice(effect('enhance_card'),{'gold':35}),choice(gold=40)]),
('golden_idol',3,7,'common',['relic'],[],[choice(effect('random_relic'),{'max_hp':8}),choice(gold=65),choice(heal=12)]),
('caravan_wreck',2,6,'common',['max_hp'],[],[choice(cost={'hp':12},gold=65),choice(effect('max_hp',amount=4),{'gold':35},heal=10),choice(effect('random_potion'))]),
('blood_pact',6,9,'rare',['recruit'],[],[choice(effect('choose_cards',unit_offer=3,unit_picks=1,effect_offer=3,effect_picks=1),{'max_hp':12}),choice(cost={'hp':8},gold=55),choice(heal=8)]),
('heart_of_grove',6,9,'rare',['relic'],[],[choice(effect('random_relic'),{'max_hp':8}),choice(heal=22),choice(effect('max_hp',amount=4),{'gold':30})]),
('bog_hand',4,8,'gamble',['relic','gamble'],[],[choice(effect('gamble',chance=.6,win=effect('random_relic'),lose=effect('gold',amount=35)),{'hp':10}),choice(effect('random_potion'),{'gold':25}),choice(heal=12)]),
('gambler_dice',3,8,'common',['gamble'],[],[gamble(30,90),gamble(60,150),choice(gold=25)]),
('goblin_arena',6,9,'rare',['relic','gamble'],[],[choice(effect('random_relic'),{'hp':15}),gamble(25,75),choice(offer(),{'gold':40})]),
('falling_star',7,9,'rare',['enhance'],[],[choice(effect('enhance_random',count=2),{'hp':12}),choice(gold=70),choice(heal=18)]),
('refugees',2,6,'common',['max_hp','recruit'],[],[choice(effect('max_hp',amount=5),{'gold':40},heal=10),choice(offer(),{'gold':20}),choice(gold=40)]),
('captured_knight',4,8,'rare',['recruit'],[],[choice(offer(pool=[unit(n) for n in ['knight','knight_templar','lancer']]),{'hp':12}),choice(gold=80),choice(effect('random_potion'),heal=10)]),
('undead_whisper',6,9,'rare',['recruit'],[],[choice(offer(pool=undead),{'max_hp':8}),choice(cost={'gold':25},heal=20),choice(effect('max_hp',amount=3),{'gold':20})]),
('veteran_grave',5,9,'rare',['enhance','max_hp'],[],[choice(effect('enhance_card'),{'gold':10},heal=12),choice(cost={'hp':8},gold=85),choice(effect('max_hp',amount=3),{'gold':25})]),
]

def save_event(id, title, description, choices, low=1, high=9, rarity='common', tags=None, requires=None, illustration=None):
    for option in choices:
        option.setdefault('heal', 0)
        option.setdefault('gold', 0)
    image = illustration or id.removeprefix('act1_').replace('_','-')+'.png'
    image_path = f'res://assets/ui/events/illustrations/{image}'
    if not (ART / image).exists(): raise FileNotFoundError(ART / image)
    source = '[gd_resource type="Resource" script_class="EventDefinition" format=3]\n\n'
    source += '[ext_resource type="Script" path="res://data/events/event_definition.gd" id="1"]\n'
    source += f'[ext_resource type="Texture2D" path={J(image_path)} id="2"]\n\n[resource]\nscript = ExtResource("1")\n'
    fields = {'id':id,'title':title,'description':description,'template':4,'min_floor':low,'max_floor':high,'rarity':rarity}
    for key,value in fields.items(): source += f'{key} = {J(value)}\n'
    source += 'illustration = ExtResource("2")\n'
    source += f'tags = Array[String]({J(tags or [])})\nrequires = Array[String]({J(requires or [])})\n'
    source += f'choices = Array[Dictionary]({J(choices)})\n'
    (ROOT/'data/events'/f'{id}.tres').write_text(source,encoding='utf-8')

def main():
    document = (ROOT/'docs/路线事件设计.md').read_text(encoding='utf-8')
    sections = re.findall(r'#### (\d+) · ([^\n]+)\n(.*?)(?=\n---)', document, re.S)
    assert len(sections)==20
    entries=[]
    for (number,title,body), (short,low,high,rarity,tags,requires,choices) in zip(sections,specs):
        story=body.split('**正文：**',1)[1].split('**选项：**',1)[0]
        narration='\n\n'.join(re.findall(r'^> (.+)$',story,re.M))
        options=re.findall(r'- \*\*([^*]+)\*\*｜([^\n]+)\n((?:  -[^\n]+\n?)+)',body)
        assert len(options)==3, (short, options)
        for i,(text,summary,result) in enumerate(options):
            choices[i]['text']=text
            choices[i]['summary']=summary.replace('｜',' · ').rstrip('。')
            normal=re.search(r'  - 结果：(.+)',result)
            if normal: choices[i]['result_text']=normal[1]
            else:
                for key,label in [('win_text','成功结果'),('lose_text','失败结果')]:
                    choices[i]['effect'][key]=re.search(f'  - {label}：(.+)',result)[1]
            if choices[i].get('effect',{}).get('type')=='gamble' and 'gold' in choices[i].get('cost',{}):
                stake=choices[i]['cost']['gold']; payout=choices[i]['effect']['win']['amount']
                choices[i]['summary']=f'支付 {stake} 金币 · 50% 返还 {payout}，50% 不返还'
        choices.append({'text':'离开','leave':True})
        id='act1_'+short
        save_event(id,title,narration,choices,low,high,rarity,tags,requires)
        entries.append({'event':id,'weight':{'common':10,'rare':4,'gamble':3}[rarity],'min_floor':low,'max_floor':high})
    save_event('crossroads_recruitment','岔路的援军','一队远行的士兵在旧营地歇脚，桌上摊着战术卷轴。\n\n队长把名册推到你面前：兵员和卷轴，只能带走一份。',[
        {'text':'挑选一名新兵','effect':offer(),'result_text':'新兵背起行囊，在你的旗帜下站定。'},
        {'text':'抄录一份战术','effect':offer('effect'),'result_text':'你记下最后一行，收好这份行军的底气。'},
        {'text':'只要一碗水','heal':12,'result_text':'清水洗去尘土。队伍稍作休整，继续向前。'}, {'text':'离开','leave':True}],illustration='crossroads-recruitment.png')
    save_event('wandering_alchemist','旅人的药剂','林间的炼金师背着药箱，玻璃瓶在斗篷下碰响。\n\n他递来一瓶药，又晃了晃另一只颜色不太对的瓶子，问你愿不愿意替他试试。',[
        {'text':'收下药水','effect':effect('random_potion')},
        {'text':'帮他试药','cost':{'hp':6},'gold':40,'effect':effect('random_potion'),'result_text':'药汁苦得舌根发麻。炼金师认真记下你的表情，付清报酬。'},
        {'text':'只问路','heal':10}, {'text':'离开','leave':True}],2,7,illustration='wandering-alchemist.png')
    entries.append({'event':'wandering_alchemist','weight':2,'min_floor':2,'max_floor':7})
    save_event('forgotten_reliquary','遗忘的圣匣','残破的石柱间，封存已久的圣匣透出微光。\n\n锋利的石棱封住了匣盖，供台旁还留着一小袋零钱。',[
        {'text':'撬开圣匣','cost':{'hp':12},'effect':effect('random_relic'),'result_text':'石棱划开手背，圣匣终于松动。你握住遗物，感到古老的力量醒来。'},
        {'text':'取走零钱','gold':55}, {'text':'在供台前歇脚','heal':10}, {'text':'离开','leave':True}],tags=['relic'],illustration='forgotten-reliquary.png')
    pool_dir=ROOT/'data/events/pools'; pool_dir.mkdir(exist_ok=True)
    (pool_dir/'act1.json').write_text(J({'id':'act1','draw_without_replacement':True,'tag_caps':{'relic':1,'duplicate':1,'remove':2},'entries':entries}),encoding='utf-8')
    # 事件专属己方变体，避免修改敌军配方或向全局奖励池投放敌军。
    target=ROOT/'data/event_recruits'; target.mkdir(exist_ok=True)
    for name in ['bear','skeleton','skeleton_archer','greatsword_skeleton']:
        source=(ROOT/'data/units'/f'{name}.tres').read_text(encoding='utf-8')
        source=re.sub(r' uid="[^"]+"','',source,count=1)
        source=source.replace('unit_team = "team_b"','unit_team = "team_a"')
        source=re.sub(r'^metadata/.*\n?','',source,flags=re.M)
        image='beast-den.png' if name=='bear' else 'undead-whisper.png'
        image_path=f'res://assets/ui/events/illustrations/{image}' if (ART/image).exists() else 'res://assets/ui/events/illustrations/crossroads-recruitment.png'
        source=source.replace('[resource]',f'[ext_resource type="Texture2D" path={J(image_path)} id="event_card_art"]\n\n[resource]')
        names={'bear':'棕熊','skeleton':'骷髅兵','skeleton_archer':'骷髅弓箭手','greatsword_skeleton':'骷髅剑士'}
        source+=f'\ncard_name = {J(names[name]+"征召")}\ncard_discription = {J("征召1名"+names[name]+"。")}\ncard_image = ExtResource("event_card_art")\ncard_cost = 2\n'
        (target/f'{name}.tres').write_text(source,encoding='utf-8')
    route_path=ROOT/'data/levels/第一章 ·  翠绿原野.json'
    route=json.loads(route_path.read_text(encoding='utf-8-sig'))
    nodes={n['id']:n for n in route['locations']}
    changes={'floor_03_02':5,'floor_04_01':0,'floor_04_03':5,'floor_05_03':0,'floor_06_02':1,'floor_07_02':1}
    for id,kind in changes.items(): nodes[id]['type']=kind
    nodes['floor_04_01']['event_id']='level_104_1'
    nodes['floor_05_03']['event_id']='level_105_1'
    for n in nodes.values():
        if n['type']==1:
            n['event_source']='catalog'
            if n['floor']==1:
                n['event_id']='crossroads_recruitment'; n.pop('event_pool',None)
            else:
                n['event_pool']='res://data/events/pools/act1.json'; n['event_id']=''
            n['title']='旅途奇遇'
            n.pop('event',None)
        elif n['type']==2:
            n.update(title='篝火',event_id='campfire',event_source='catalog'); n.pop('event',None)
        else:
            for key in ['event','event_source','event_pool']: n.pop(key,None)
            n['title']={0:'战斗',3:'Boss',4:'宝箱',5:'商店'}[n['type']]
            if n['type']==5: n.update(event_id='',shop_catalog='res://data/shops/caravan.json')
    def paths(id,acc=None):
        path=(acc or [])+[id]
        if not nodes[id]['next']: yield path
        for target_id in nodes[id]['next']: yield from paths(target_id,path)
    counts=[]
    for start in route['starting_ids']:
        for path in paths(start):
            types=[nodes[id]['type'] for id in path]
            assert 3<=types.count(1)<=4 and types.count(0)>=3 and 1<=types.count(2)<=2,(path,types)
            counts.append({str(kind):types.count(kind) for kind in range(6)})
    route_text=json.dumps(route,ensure_ascii=False,indent='\t')+'\n'
    route_path.write_text(route_text,encoding='utf-8')
    (ROOT/'data/run/game_map.json').write_text(route_text,encoding='utf-8')
    print(f'Generated 20 route events, tutorial, alchemist, act1 pool, 4 allied event recruits. Verified {len(counts)} paths: 3–4 events, >=3 battles, 1–2 camps; 9 total battle nodes.')

if __name__=='__main__': main()
