import json,os,datetime
OUT=r'E:\MyGame\Game11\conquer\trunk\ballsprite\market-analysis-20261019\data'
d=json.load(open(os.path.join(OUT,'gama_Roguelike_Deckbuilder.json'),encoding='utf-8'))
names={g['name'].lower():g for g in d}
for n in ['balatro','slay the spire','slay the spire 2','monster train','backpack battles','the last flame','chrono ark','across the obelisk','yi xian: the cultivation card game','inscryption']:
    print(n, 'FOUND' if n in names else '-', names.get(n,{}).get('copiesSold'))
print('max copies', max(g.get('copiesSold',0) for g in d))
print('top10', [(g['name'],g.get('copiesSold')) for g in sorted(d,key=lambda x:x.get('copiesSold',0),reverse=True)[:10]])
print('first page 3', [(g['name'],g.get('copiesSold')) for g in d[:3]])
print('last page 3', [(g['name'],g.get('copiesSold')) for g in d[-3:]])
print('ids', len(set(g.get('steamId') for g in d)))
a=json.load(open(os.path.join(OUT,'gama_Auto_Battler.json'),encoding='utf-8'))
print('auto n',len(a),'max',max(g.get('copiesSold',0) for g in a))
print([(g['name'],g.get('copiesSold')) for g in sorted(a,key=lambda x:x.get('copiesSold',0),reverse=True)[:10]])
