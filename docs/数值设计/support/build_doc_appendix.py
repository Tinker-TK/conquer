# -*- coding: utf-8 -*-
"""Append appendices E/F/G: ally skills, chapter-1 nodes, current shop."""
import json, pathlib
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / 'docs' / '数值设计'
DATA = json.loads((OUT / 'support' / 'design_data.json').read_text(encoding='utf-8'))
DOC = OUT / '数值框架与全量数值.md'


def esc(x):
    return str(x).replace('|', '/').replace('\n', '<br>')


def table(headers, rows):
    out = ['| ' + ' | '.join(headers) + ' |',
           '| ' + ' | '.join(['---'] * len(headers)) + ' |']
    for r in rows:
        out.append('| ' + ' | '.join(esc(x) for x in r) + ' |')
    return '\n'.join(out)


def s14():
    allies = [u for u in DATA['units'] if u['team'] == 'ally']
    skill_rows = []
    for u in allies:
        for s in u['skills']:
            skill_rows.append([u['name'], s['name'], s['kind'], f"{s['rate']:g}", f"{s['cooldown']:g}",
                               s.get('hits', 1), f"{s['range']:g}", ','.join(str(x) for x in s.get('unlock', []))])
    nodes = json.loads((ROOT / 'data/levels/第一章 ·  翠绿原野.json').read_text(encoding='utf-8-sig'))
    type_name = {0: '战斗', 1: '事件', 2: '篝火', 3: 'Boss', 4: '商店', 5: '宝箱'}
    node_rows = []
    for l in sorted(nodes['locations'], key=lambda x: (x['floor'], x['id'])):
        node_rows.append([l['floor'], l['id'], l['title'], type_name.get(l['type'], l['type']),
                          len(l.get('next', [])), l.get('event_id', '') or '—'])
    shop = json.loads((ROOT / 'data/shops/caravan.json').read_text(encoding='utf-8-sig'))
    shop_rows = []
    for key, label in [('recruits', '征召'), ('cards', '卡牌'), ('relics', '遗物'), ('potions', '药水')]:
        prices = [x['price'] for x in shop.get(key, [])]
        shop_rows.append([label, len(prices), f"{min(prices)}–{max(prices)}" if prices else '—'])
    return f"""## 附录 E：己方单位技能参数

> 技能按当前资源读取；`生效等级` 中 0 = 未训练，1 = 训练一次。敌方单位多用普通攻击，参数在同一套 `data/skills/*.tres` 中。

{table(['单位', '技能', '类型', '倍率', '冷却', '段数', '射程', '生效等级'], skill_rows)}

## 附录 F：第一章节点表

{table(['层', 'ID', '标题', '类型', '后继数', '事件 ID'], node_rows)}

> 类型按地图 JSON 的 `type` 统计：0 战斗、1 事件、2 篝火、3 Boss、4 商店、5 宝箱。部分节点标题写“战斗”但类型是事件/篝火，实装前应统一标题。

## 附录 G：当前商店价格

{table(['类别', '商品数', '价格区间'], shop_rows)}

- 商店还有 3 个征召位、4 个卡牌位、3 个遗物位、3 个药水位。
- 删牌建议 75 金起，之后每次 +25。
- 价格与第 10.2 节的目标价不完全一致；当前价格保留，目标价用于后续调参。

---
"""


if __name__ == '__main__':
    text = DOC.read_text(encoding='utf-8')
    DOC.write_text(text.rstrip() + '\n\n' + s14(), encoding='utf-8')
    print('appended appendices', len(s14()))
