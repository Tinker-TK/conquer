import hashlib
import json
from pathlib import Path
from zipfile import ZipFile
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'docs'/'数值设计'
d=json.loads((OUT/'第一章·翠绿原野_数值草案.json').read_text(encoding='utf-8'))
assert len(d['chapter_nodes'])==26
assert len(d['routes'])==14
for source in d['sources']:
    assert hashlib.sha256((ROOT/source['path']).read_bytes()).hexdigest()==source['sha256'],source['path']
ns={'m':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
expected={1:{'D9':22,'I9':5,'J9':4,'D14':52,'I14':10,'J14':22,'C20':76,'C21':100,'C22':54,'C23':78},
          2:{'F18':76,'G18':54,'F22':88,'G22':66},
          3:{'O11':4,'P60':0,'Q60':22,'Q65':22,'D61':1,'E61':1,'G64':1},
          4:{'C9':70,'C12':145,'C13':220,'J12':25,'K12':14,'D23':5,'D24':3,'M13':5}}
errors=[]
formulas=0
with ZipFile(OUT/'第一章·翠绿原野_关卡参考.xlsx') as z:
    book=ET.fromstring(z.read('xl/workbook.xml'))
    sheet_names=[x.attrib['name'] for x in book.find('m:sheets',ns)]
    assert sheet_names==['关卡总览','路线生命','波次与结算','敌兵与开局']
    for i in range(1,5):
        xml=ET.fromstring(z.read(f'xl/worksheets/sheet{i}.xml'))
        cells={c.attrib['r']:c for c in xml.findall('.//m:c',ns)}
        for cell in cells.values():
            formulas+=cell.find('m:f',ns) is not None
            if cell.attrib.get('t')=='e':
                errors.append([i,cell.attrib['r'],cell.findtext('m:v',namespaces=ns)])
        for address,number in expected[i].items():
            assert float(cells[address].findtext('m:v',namespaces=ns))==number,(i,address)
        assert xml.find('.//m:pane',ns) is not None
    charts=[n for n in z.namelist() if n.endswith('.xml') and '/charts/chart' in n]
    assert len(charts)==1
    chart=z.read(charts[0]).decode('utf-8')
    assert '397761' in chart and 'D19C43' in chart
assert not errors,errors
result={'date':'2026-10-09','nodes':len(d['chapter_nodes']),'paths':14,'source_hashes_verified':len(d['sources']),
        'sheets':sheet_names,'saved_formula_count':formulas,'saved_formula_errors':errors,
        'key_cached_values_verified':sum(map(len,expected.values())),
        'visuals_reviewed':True,'game_resources_modified':False,'combat_results_measured':False}
(OUT/'support'/'chapter1_saved_validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
