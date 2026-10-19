import json,os
OUT=r'E:\MyGame\Game11\conquer\trunk\ballsprite\market-analysis-20261019\data'
r=json.load(open(os.path.join(OUT,'details','646570.json'),encoding='utf-8'))
print(list(r.keys()))
print(json.dumps(r.get('store',{}),ensure_ascii=False)[:1200])
print(json.dumps(r.get('reviews',{}).get('query_summary'),ensure_ascii=False))
print(json.dumps(r.get('spy',{}),ensure_ascii=False)[:400])
