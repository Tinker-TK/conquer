import json,urllib.request,urllib.parse
UA={'User-Agent':'Mozilla/5.0'}
def get(q):
    u='https://api.gamalytic.com/steam-games/list?'+urllib.parse.urlencode(q)
    r=json.load(urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=60))
    return r
for q in [
 {'limit':5,'tags':'Roguelike Deckbuilder','sort':'copiesSold','order':'desc'},
 {'limit':5,'tags':'Roguelike Deckbuilder','sort':'copiesSold','order':'asc'},
 {'limit':5,'tags':'Roguelike Deckbuilder','sort':'revenue','order':'desc'},
 {'limit':5,'tags':'Roguelike Deckbuilder','page':10},
 {'limit':5,'tags':'Roguelike Deckbuilder','page':11},
 {'limit':5,'tags':'Roguelike Deckbuilder','minCopiesSold':200000},
]:
    try:
        r=get(q)
        print(q,'=>',[(x['name'],x.get('copiesSold')) for x in r['result'][:3]],'total',r.get('total'))
    except Exception as e:
        print(q,'ERR',repr(e)[:200])
