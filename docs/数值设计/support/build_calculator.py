# -*- coding: utf-8 -*-
"""Inject design_data.json + calculator_app.js into the HTML template."""
import json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / 'docs' / '数值设计'
SUPPORT = OUT / 'support'
DATA = json.loads((SUPPORT / 'design_data.json').read_text(encoding='utf-8'))
TEMPLATE = (SUPPORT / 'calculator_template.html').read_text(encoding='utf-8')
APP = (SUPPORT / 'calculator_app.js').read_text(encoding='utf-8')

data_js = json.dumps(DATA, ensure_ascii=False, separators=(',', ':'))
data_js = data_js.replace('</', '<\\/')
html = TEMPLATE.replace('/*__DATA__*/', data_js).replace('/*__APP__*/', APP)
out = OUT / '战力计算器.html'
out.write_text(html, encoding='utf-8')
print('wrote', out, len(html), 'chars')
print('data', len(data_js), 'app', len(APP))
