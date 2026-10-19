import json,os
OUT=r'E:\MyGame\Game11\conquer\trunk\ballsprite\market-analysis-20261019\data'
pool=json.load(open(os.path.join(OUT,'gama2_Roguelike_Deckbuilder.json'),encoding='utf-8'))+json.load(open(os.path.join(OUT,'gama2_Auto_Battler.json'),encoding='utf-8'))
byname={}
for g in pool: byname.setdefault(g['name'].strip().lower(),g)
wanted=['Slay the Spire','Slay the Spire 2','Balatro','Monster Train','Monster Train 2','Backpack Battles','The Bazaar','9 Kings','The King is Watching','The Last Flame','Hadean Tactics','Chrono Ark','Across the Obelisk','Gordian Quest','Wildfrost','StarVaders','Alina of the Arena','Fights in Tight Spaces','Cobalt Core','Super Fantasy Kingdom','He is Coming','Tales & Tactics','Symphony of War: The Nephilim Saga',"Hero's Hour","Despot's Game: Dystopian Battle Simulator",'The Dungeon Beneath','Vivid Knight','Knightica','Luck be a Landlord','Ballionaire','Backpack Hero','Dungeon Clawler','Shogun Showdown','Emberward','Trials of Fire','Roguebook','Griftlands','Inscryption','Darkest Dungeon II','Loop Hero','Star Renegades','The Last Spell','Yi Xian: The Cultivation Card Game',"Indies' Lies",'Yao-Guai Hunter','Touhou: Lost Branch of Legend','Night of Full Moon','Demonic Mahjong','Cat God Ranch','Decktamer','Oaken Tower','Overlooting','Commander Quest','ShapeHero Factory']
found=[];miss=[]
for w in wanted:
    g=byname.get(w.lower())
    if g: found.append(g)
    else: miss.append(w)
print('found',len(found),'miss',len(miss))
print('MISS:',miss)
for g in found:
    print(g['steamId'],'|',g['name'],'|',g.get('copiesSold'),'|',g.get('price'),'|',g.get('releaseDate'))
json.dump(found,open(os.path.join(OUT,'curated_raw.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=1)
