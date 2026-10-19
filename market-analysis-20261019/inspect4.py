import json,datetime,os,numpy as np
OUT=r'E:\MyGame\Game11\conquer\trunk\ballsprite\market-analysis-20261019\data'
d=json.load(open(os.path.join(OUT,'gama2_Roguelike_Deckbuilder.json'),encoding='utf-8'))
def yr(g): return datetime.datetime.fromtimestamp(g['releaseDate']/1000,datetime.UTC).year if g.get('releaseDate') else None
print('n',len(d),'unreleased',sum(1 for g in d if g.get('unreleased')))
print('years',sorted(__import__('collections').Counter(yr(g) for g in d).items()))
print('\nTOP 60:')
for g in d[:60]:
    print(f"{g.get('copiesSold',0):>9} {yr(g)} ${g.get('price'):>6} score{g.get('reviewScore','?'):>3} {g['name'][:50]}")
prem=[g for g in d if (g.get('price') or 0)>=4.99 and not g.get('unreleased') and yr(g) and 2019<=yr(g)<=2026]
vals=sorted(g.get('copiesSold',0) for g in prem)
print('\npremium n',len(prem))
for p in [10,25,50,60,70,75,80,90,95,99]: print('p'+str(p), int(np.percentile(vals,p)))
# count by year for premium
from collections import Counter
print('premium by year',sorted(Counter(yr(g) for g in prem).items()))
