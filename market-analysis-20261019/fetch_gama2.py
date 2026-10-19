import json,urllib.request,urllib.parse,time,os
OUT=r'E:\MyGame\Game11\conquer\trunk\ballsprite\market-analysis-20261019\data'
UA={'User-Agent':'Mozilla/5.0'}
def get(q):
    u='https://api.gamalytic.com/steam-games/list?'+urllib.parse.urlencode(q)
    return json.load(urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=60))
def pull(tag):
    out={}
    for page in range(0,12):
        q={'limit':100,'tags':tag,'page':page,'sort':'copiesSold','order':'desc'}
        r=get(q); res=r.get('result',[])
        print(tag,'page',page,len(res),'total',r.get('total'))
        if not res: break
        for g in res: out[g['steamId']]=g
        time.sleep(0.3)
    return list(out.values())
for tag,fn in [('Roguelike Deckbuilder','gama2_Roguelike_Deckbuilder.json'),('Auto Battler','gama2_Auto_Battler.json')]:
    data=pull(tag)
    json.dump(data,open(os.path.join(OUT,fn),'w',encoding='utf-8'),ensure_ascii=False)
    print('saved',tag,len(data))
    print([(g['name'],g.get('copiesSold')) for g in data[:5]])
