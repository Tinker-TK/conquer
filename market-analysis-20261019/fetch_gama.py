import json,urllib.request,urllib.parse,time,os,sys
OUT=r'E:\MyGame\Game11\conquer\trunk\ballsprite\market-analysis-20261019\data'
UA={'User-Agent':'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36'}
def get(url):
    req=urllib.request.Request(url,headers=UA)
    return json.load(urllib.request.urlopen(req,timeout=60))
def pull(tag, maxpages=40):
    out=[]; page=1
    while page<=maxpages:
        q={'limit':100,'tags':tag,'page':page}
        u='https://api.gamalytic.com/steam-games/list?'+urllib.parse.urlencode(q)
        r=get(u)
        res=r.get('result',[])
        out.extend(res)
        print(tag,'page',page,'+',len(res),'total',len(out),'of',r.get('total'))
        if not res or page>=r.get('pages',1): break
        page+=1; time.sleep(0.4)
    return out
alltags={}
for tag in ['Roguelike Deckbuilder','Auto Battler']:
    fn=os.path.join(OUT,'gama_'+tag.replace(' ','_')+'.json')
    if os.path.exists(fn):
        alltags[tag]=json.load(open(fn,encoding='utf-8'))
        print('cached',tag,len(alltags[tag])); continue
    data=pull(tag)
    json.dump(data,open(fn,'w',encoding='utf-8'),ensure_ascii=False)
    alltags[tag]=data
    print('saved',tag,len(data))
print('done')
