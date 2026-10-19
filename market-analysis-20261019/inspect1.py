import json,datetime,statistics,os
OUT=r'E:\MyGame\Game11\conquer\trunk\ballsprite\market-analysis-20261019\data'
d=json.load(open(os.path.join(OUT,'gama_Roguelike_Deckbuilder.json'),encoding='utf-8'))
def yr(g): return datetime.datetime.utcfromtimestamp(g['releaseDate']/1000).year if g.get('releaseDate') else None
print('n',len(d))
from collections import Counter
print('years',sorted(Counter(yr(g) for g in d).items()))
prem=[g for g in d if (g.get('price') or 0)>=4.99 and not g.get('unreleased')]
print('premium',len(prem))
print('\nTOP 45 by copies:')
for g in sorted(prem,key=lambda x:x.get('copiesSold',0),reverse=True)[:45]:
    print(f"{g.get('copiesSold',0):>9} {yr(g)} ${g.get('price'):>5} {g.get('reviewScore','?'):>3} {g['name'][:55]}")
vals=sorted([g.get('copiesSold',0) for g in prem if yr(g) and 2019<=yr(g)<=2026])
import numpy as np
print('\npercentiles copies (premium 2019-2026):')
for p in [10,25,50,75,90,95,99]:
    print(p, int(np.percentile(vals,p)))
print('n',len(vals))
