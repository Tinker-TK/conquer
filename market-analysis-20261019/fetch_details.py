import json,os,time,urllib.request
OUT=r'E:\MyGame\Game11\conquer\trunk\ballsprite\market-analysis-20261019\data'
D=os.path.join(OUT,'details')
UA={'User-Agent':'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36','Accept-Language':'zh-CN,zh;q=0.9,en;q=0.8'}
def get(url,tries=3):
    for i in range(tries):
        try:
            return json.load(urllib.request.urlopen(urllib.request.Request(url,headers=UA),timeout=45))
        except Exception:
            if i==tries-1: raise
            time.sleep(2*(i+1))
cur=json.load(open(os.path.join(OUT,'curated_raw.json'),encoding='utf-8'))
for g in cur:
    aid=str(g['steamId']); fn=os.path.join(D,aid+'.json')
    if os.path.exists(fn):
        print('cached',aid); continue
    rec={'appid':int(aid),'gama':g}
    try: rec['store']=get(f'https://store.steampowered.com/api/appdetails?appids={aid}&cc=cn&l=schinese').get(aid,{}).get('data')
    except Exception as e: rec['store_err']=repr(e)
    try: rec['reviews']=get(f'https://store.steampowered.com/appreviews/{aid}?json=1&language=all&purchase_type=all&num_per_page=0')
    except Exception as e: rec['reviews_err']=repr(e)
    try: rec['spy']=get(f'https://steamspy.com/api.php?request=appdetails&appid={aid}')
    except Exception as e: rec['spy_err']=repr(e)
    json.dump(rec,open(fn,'w',encoding='utf-8'),ensure_ascii=False)
    rv=(rec.get('reviews') or {}).get('query_summary',{})
    print(aid,'reviews',rv.get('total_reviews'),'ok')
    time.sleep(0.7)
print('done',len(os.listdir(D)))
