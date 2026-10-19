from pathlib import Path
import json, zipfile, xml.etree.ElementTree as ET, math
base=Path(__file__).resolve().parent
file=base.parent/'数值调参工作簿.xlsx'
ns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
with zipfile.ZipFile(file) as z:
    w=ET.fromstring(z.read('xl/workbook.xml'))
    names=[s.attrib['name'] for s in w.findall('s:sheets/s:sheet',ns)]
    assert len(names)==7,names
    errors=[]; count=0
    for name in z.namelist():
        if name.startswith('xl/worksheets/sheet') and name.endswith('.xml'):
            r=ET.fromstring(z.read(name))
            count+=len(r.findall('.//s:f',ns))
            errors.extend((name,c.attrib.get('r')) for c in r.findall('.//s:c',ns) if c.attrib.get('t')=='e')
    assert not errors,errors
    units=ET.fromstring(z.read('xl/worksheets/sheet2.xml'))
    cells={c.attrib['r']:c for c in units.findall('.//s:c',ns)}
    snapshot=json.loads((base/'runtime_snapshot.json').read_text(encoding='utf8'))
    for i,u in enumerate(snapshot['units'],7):
        for col,key in [('W','card_cost'),('X','max_hp'),('Y','attack'),('Z','defence'),('AA','dodge_rate'),('AB','hp_damage_value')]:
            assert float(cells[col+str(i)].find('s:v',ns).text)==u[key],(i,key)
    t=ET.fromstring(z.read('xl/worksheets/sheet7.xml'))
    for c in t.findall('.//s:c',ns):
        if c.attrib['r'].startswith('O') and int(c.attrib['r'][1:])>=23:
            assert c.find('s:v',ns) is None or c.find('s:v',ns).text in (None,''),'Synthetic trial left'
    charts=[n for n in z.namelist() if 'chart' in n.lower() and n.endswith('.xml') and '/_rels/' not in n]
    print('CHART_FILES',charts)
    assert len(charts)==1
    assert '476FA5' in z.read(charts[0]).decode('utf8').upper()
report={'sheet_count':len(names),'formula_count':count,'cached_errors':errors,'source_units_reconciled':len(snapshot['units']),'trial_inputs_empty':True,'chart_count':len(charts),'no_unit_probability':math.comb(5,5)/math.comb(10,5),'no_front_probability':math.comb(7,5)/math.comb(10,5),'native_excel_recalculation_tested':False}
(base/'saved_validation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print(json.dumps(report))
