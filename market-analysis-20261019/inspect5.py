import json,os,datetime
OUT=r'E:\MyGame\Game11\conquer\trunk\ballsprite\market-analysis-20261019\data'
a=json.load(open(os.path.join(OUT,'gama2_Auto_Battler.json'),encoding='utf-8'))
a=[g for g in a if (g.get('price') or 0)>=4.99 and not g.get('unreleased')]
def has(g,*ts): return any(t.lower() in [x.lower() for x in g.get('tags',[])] for t in ts)
sel=[g for g in a if has(g,'Roguelike','Roguelike Deckbuilder','Deckbuilding','Turn-Based Tactics','Party-Based RPG')]
print('auto+rogue/deck',len(sel))
for g in sel[:45]:
    y=datetime.datetime.fromtimestamp(g['releaseDate']/1000,datetime.UTC).year
    print(f"{g.get('copiesSold',0):>9} {y} ${g.get('price'):>6} {g['name'][:55]} | {','.join([t for t in g['tags'] if t in ('Roguelike','Deckbuilding','Auto Battler','Turn-Based Tactics','Party-Based RPG','Strategy RPG')])}")
print('\nNAME SEARCH:')
allg=json.load(open(os.path.join(OUT,'gama2_Roguelike_Deckbuilder.json'),encoding='utf-8'))+a
seen=set()
for g in allg:
    n=g['name'].lower()
    if any(k in n for k in ['last flame','yi xian','super auto','bazaar','mechabellum','songs of silence','hero\'s hour','star renegades','trials of fire','last spell','darkest dungeon','legion td','auto chess','underlords','just king','nine kings','9 kings']):
        if g['steamId'] in seen: continue
        seen.add(g['steamId'])
        print(g['steamId'],g['name'],g.get('copiesSold'),g.get('price'),g.get('tags',[])[:8])
