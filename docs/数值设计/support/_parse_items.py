import sys, json, re, pathlib
sys.path.insert(0, 'docs/数值设计/support')
from _parse_tables import tables

def clean(s):
    return re.sub(r'\*\*|`', '', s).strip()

def rid(s):
    m = re.search(r'`([^`]+)`', s)
    return m.group(1) if m else clean(s)

def relics():
    out = []
    for header, rows in tables('docs/遗物流派设计.md'):
        if '遗物' not in header or '稀有度' not in header:
            continue
        for r in rows:
            out.append({
                'id': rid(r['遗物']), 'name': clean(re.sub(r'`[^`]+`', '', r['遗物'])).strip(),
                'rarity': {'普': 'common', '稀': 'rare', '首': 'boss'}.get(r['稀有度'], 'common'),
                'trigger': clean(r['触发']), 'effect': clean(r['效果']),
                'link': clean(r.get('联动', '')),
            })
    return out

def potions():
    out = []
    for header, rows in tables('docs/药水能力设计与投放方案.md'):
        if '药水' not in header or '效果（首版）' not in header or '目标' not in header:
            continue
        for r in rows:
            out.append({
                'id': rid(r['药水']), 'name': clean(re.sub(r'`[^`]+`', '', r['药水'])).strip(),
                'target': clean(r['目标']), 'effect': clean(r['效果（首版）']),
                'role': clean(r.get('定位', '')), 'note': clean(r.get('联动 / 备注', '')),
            })
    return out

if __name__ == '__main__':
    r = relics(); p = potions()
    print('relics', len(r)); print('potions', len(p))
    print(json.dumps(r[:2], ensure_ascii=False, indent=1))
    print(json.dumps(p[:2], ensure_ascii=False, indent=1))
    print([x['id'] for x in r])
    print([x['id'] for x in p])
