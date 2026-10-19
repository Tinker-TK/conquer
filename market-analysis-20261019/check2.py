import json,os
OUT=r'E:\MyGame\Game11\conquer\trunk\ballsprite\market-analysis-20261019\data'
r=json.load(open(os.path.join(OUT,'details','646570.json'),encoding='utf-8'))
d=r['store']
print([k for k in d.keys()])
print('release',d.get('release_date'),'free',d.get('is_free'),'price',d.get('price_overview'))
print('platforms',d.get('platforms'))
