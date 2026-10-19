"""Build a self-contained offline asset catalog and validate all output layers."""
from pathlib import Path
import json
import hashlib
import numpy as np
from PIL import Image, ImageOps

ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8'))
layouts=json.loads((ROOT/'card_layouts.json').read_text(encoding='utf-8'))
ui_layouts=json.loads((ROOT/'ui_layouts.json').read_text(encoding='utf-8'))
sources=json.loads((ROOT.parent/'ui_extracted/manifest.json').read_text(encoding='utf-8'))

fixed={
 'hud/top_status_bar.png':['panels/top_bar.png'],
 'hud/crown_badge.png':['components/crown_backplate.png','icons/crown.png'],
 'hud/health_panel.png':['panels/stat_panel.png','icons/heart.png'],
 'hud/gold_panel.png':['panels/stat_panel.png','icons/gold_coin.png'],
 'hud/equipment_panel.png':['panels/stat_panel.png','icons/equipment_sword.png','icons/equipment_armor.png','icons/equipment_potion.png'],
 'hud/chapter_banner.png':['components/chapter_banner.png'],
 'hud/map_button.png':['panels/navigation_button.png','icons/map.png'],
 'hud/deck_button.png':['panels/navigation_button.png','icons/deck_book.png'],
 'hud/settings_button.png':['panels/navigation_button.png','icons/gear.png'],
 'hud/preparation_badge.png':['panels/phase_panel.png','icons/crossed_swords.png'],
 'controls/battle_control_panel.png':['panels/battle_control_panel.png','panels/speed_button_blank.png','controls/selected_border.png','controls/pause_symbol.png','controls/toggle_track.png','controls/toggle_knob.png'],
 'controls/pause_button.png':['panels/speed_button_blank.png','controls/pause_symbol.png'],
 'controls/speed_1x_selected.png':['panels/speed_button_blank.png','controls/selected_border.png'],
 'controls/speed_2x_button.png':['panels/speed_button_blank.png'],
 'controls/auto_battle_row.png':['panels/auto_row_blank.png','controls/toggle_track.png','controls/toggle_knob.png'],
 'controls/auto_battle_toggle.png':['controls/toggle_track.png','controls/toggle_knob.png'],
 'controls/start_battle_button.png':['components/gold_button.png','icons/crossed_swords.png'],
 'unit_hud/attack_icon.png':['icons/equipment_sword.png'],
 'unit_hud/shield_icon.png':['status/shield.png'],
 'unit_hud/tree_status_icon.png':['status/tree.png'],
 'unit_hud/healing_status_icon.png':['status/healing.png'],
 'unit_hud/skull_status_icon.png':['status/skull.png'],
 'unit_hud/knight_stats_row.png':['icons/equipment_sword.png','status/shield.png'],
 'unit_hud/enemy_stats_row.png':['icons/equipment_sword.png','status/shield.png'],
 'energy/energy_orb_3_of_3.png':['energy/00_core.png','energy/10_rim.png'],
 'piles/draw_pile_with_count.png':['panels/pile_backplate.png','components/draw_book.png','badges/counter_red.png'],
 'piles/discard_pile_with_count.png':['panels/pile_backplate.png','components/discard_book.png','badges/counter_red.png']
}
mapping=[]
for s in sources:
    f=s['file']; name=Path(f).stem
    if f in fixed: outputs=fixed[f]
    elif f.startswith('icons/'): outputs=[f]
    elif f.startswith('units/'): outputs=['units/goblin.png' if name.startswith('goblin') else f]
    elif name.endswith('_health_bar'): outputs=['health/00_empty_bar.png','health/10_fill.png','health/20_border.png']
    elif f.startswith('cards/'):
        cname=name.removeprefix('card_'); outputs=next(x['layers'] for x in layouts if x['name']==cname)
    elif f.startswith('card_art/'):
        cname=name.removeprefix('art_');outputs=[f'card_art/{cname}_subject.png',f'card_art/{cname}_background.png']
    else: raise ValueError(f'Unmapped source {f}')
    for out in outputs: assert (ROOT/out).is_file(),out
    mapping.append(dict(source=f,outputs=outputs,note='无文字数值；重复造型复用。补画是风格推断，不是原始图层恢复。'))
(ROOT/'source_mapping.json').write_text(json.dumps(mapping,ensure_ascii=False,indent=2),encoding='utf-8')

checks=[]
for row in manifest:
    p=ROOT/row['file']; im=Image.open(p)
    assert im.mode=='RGBA',(p,im.mode)
    a=np.array(im); alpha=a[:,:,3]
    assert (alpha>0).any(),p
    if not row.get('intentional_opaque'):
        assert (alpha==0).any(),f'No transparency: {p}'
        assert not (alpha[0]>0).any() and not (alpha[-1]>0).any(),f'Clipped vertically: {p}'
        assert not (alpha[:,0]>0).any() and not (alpha[:,-1]>0).any(),f'Clipped horizontally: {p}'
    magenta=(a[:,:,0].astype(int)-a[:,:,1]>70)&(a[:,:,2].astype(int)-a[:,:,1]>70)&(alpha>128)
    # The foreground palette explicitly excluded chroma-key magenta.
    count=int(magenta.sum())
    checks.append(dict(file=row['file'],rgba=True,transparent_pixels=int((alpha==0).sum()),
                       visible_magenta_pixels=count,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
for group in ui_layouts:
    combined=Image.new('RGBA',tuple(group['canvas']))
    for layer in group['layers']:
        combined.alpha_composite(Image.open(ROOT/layer['file']).convert('RGBA'))
    preview=Image.open(ROOT/f"ui_layers/{group['name']}/preview.png").convert('RGBA')
    assert np.array_equal(np.array(combined),np.array(preview)),group['name']
report=dict(output_png_count=len(manifest),mapped_original_slices=len(mapping),card_count=len(layouts),
            ui_group_count=len(ui_layouts),ui_reassemblies_verified=True,
            layers_per_card=8,card_canvas=[768,1024],all_reassemblies_verified=all(x['verified_reassembly'] for x in layouts),
            checks=checks)
(ROOT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')

# Review contact sheets contain no baked labels or numbers, just the artwork.
preview=ROOT/'_preview';preview.mkdir(exist_ok=True)
def contact(rows,name,cols,cell):
    h=((len(rows)+cols-1)//cols)*cell[1]
    sheet=Image.new('RGBA',(cols*cell[0],h),(39,50,61,255))
    for k,row in enumerate(rows):
        im=Image.open(ROOT/row['file']).convert('RGBA')
        im=ImageOps.contain(im,(cell[0]-24,cell[1]-24),Image.Resampling.NEAREST)
        x=(k%cols)*cell[0]+(cell[0]-im.width)//2;y=(k//cols)*cell[1]+(cell[1]-im.height)//2
        sheet.alpha_composite(im,(x,y))
    sheet.save(preview/name)
contact([r for r in manifest if r.get('preview') and r['file'].startswith('cards/')],'cards.png',5,(240,328))
contact([r for r in manifest if r.get('preview') and r['file'].startswith('ui_layers/')],'ui_groups.png',4,(320,240))
contact([r for r in manifest if r['file'].split('/')[0] in ['icons','status','units']],'icons_units.png',6,(200,200))
contact([r for r in manifest if r['file'].split('/')[0] in ['components','controls','health','energy','badges']],'components.png',5,(250,220))

html='''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>重绘 UI · 分层素材库</title><style>
:root{color-scheme:dark;font:15px/1.55 system-ui,sans-serif;background:#101920;color:#e8eff2}
*{box-sizing:border-box}body{margin:0 auto;max-width:1500px;padding:28px}a{color:#7edbd5}header{border-bottom:1px solid #34424b;padding-bottom:20px}h1{margin:0 0 8px;font-size:28px}h2{font-size:21px;margin:30px 0 14px}p{color:#b6c7cf}button,select,input{font:inherit;border:1px solid #526572;border-radius:6px;padding:8px 12px;background:#22333f;color:#eef5f5}button{cursor:pointer}button:hover{border-color:#7edbd5}.stats{display:flex;gap:10px;flex-wrap:wrap}.stats span{background:#243a45;padding:6px 12px;border-radius:30px}.inspector{display:grid;grid-template-columns:390px 1fr;gap:26px;background:#182731;border:1px solid #354651;border-radius:12px;padding:20px}.stage{position:relative;aspect-ratio:3/4;width:100%;max-width:384px;overflow:hidden}.checker{background-color:#243640;background-image:conic-gradient(#30444e 25%,transparent 0 50%,#30444e 0 75%,transparent 0);background-size:24px 24px}.stage img{position:absolute;inset:0;width:100%;height:100%;image-rendering:pixelated}.layer-list{display:grid;gap:8px;margin:18px 0}.layer-row{display:flex;align-items:center;gap:10px;padding:7px;background:#22343e;border-radius:6px}.layer-row label{flex:1;cursor:pointer}.layer-row a{font-size:12px}.layer-row button{font-size:12px;padding:3px 9px}.toolbar{display:flex;gap:10px;flex-wrap:wrap;align-items:center}.gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:14px}.asset{border:1px solid #334651;border-radius:8px;overflow:hidden;background:#172731}.thumb{height:190px;display:flex;align-items:center;justify-content:center;padding:12px}.thumb img{max-width:100%;max-height:100%;image-rendering:pixelated}.caption{padding:10px;font-size:12px;overflow-wrap:anywhere}.caption small{color:#97b7c3}.card-strip{display:flex;gap:12px;overflow:auto;margin:16px 0}.card-choice{width:120px;flex:none;background:#1e303a}.card-choice img{display:block;width:100%}.muted{color:#94b0bf}.hide{display:none!important}footer{border-top:1px solid #334651;margin-top:30px;padding-top:20px;color:#a0bac5}@media(max-width:760px){body{padding:14px}.inspector{grid-template-columns:1fr}.stage{margin:auto}.gallery{grid-template-columns:repeat(2,minmax(0,1fr))}}
</style></head><body><header><h1>重绘 UI · 分层素材库</h1><p>高清像素风重绘 / 去字去数值 / 真正 RGBA / 完整独立图层。旧切片不变。</p><div class="stats"><span id="count"></span><span>5 张卡牌 × 8 层</span><span>统一画布 768 × 1024</span><span>原始 59 切片均有对应记录</span></div><p><a href="README.md">使用说明</a> · <a href="source_mapping.json">旧图对应表</a> · <a href="manifest.json">素材清单</a> · <a href="verification.json">校验报告</a></p></header>
<h2>卡牌图层检查</h2><p>点击卡牌切换；关闭任意图层检查它后面的补画。页面文字只用于说明，不在 PNG 里。</p><div id="card-strip" class="card-strip"></div><div class="inspector"><div id="stage" class="stage checker"></div><div><div class="toolbar"><select id="card"></select><button id="all">显示全部</button><button id="none">隐藏全部</button><button id="bg">切换检查底色</button></div><div id="layers" class="layer-list"></div><p class="muted">从底向上叠放；所有层左上角均为 (0,0)，不要自动裁切透明边缘。插画背景是一张完整画面；主体和 UI 外部为透明。标题、描述、费用徽章保持空白。</p><a id="composite" href="#">查看整卡合成 PNG</a></div></div>
<h2>全部素材</h2><div class="toolbar"><select id="category"><option value="all">所有分类</option></select><input id="search" placeholder="按文件名筛选"><label><input type="checkbox" id="showlayers"> 显示卡牌单层重复文件</label></div><p id="shown" class="muted"></p><div id="gallery" class="gallery"></div><footer>AI 重绘与局部推断补画，并非找回原始 PSD 图层。蓝/绿/金卡框由同一红框调色，保证尺寸一致。raw/ 与 drafts/ 为过程文件，正式素材请按 manifest.json 使用。</footer>
<script>const assets=__ASSETS__;const cards=__CARDS__;
const names={summon_guard:'召唤卫兵',hold_position:'坚守阵地',fireball:'火球术',battlefield_heal:'战场治疗',battle_inspiration:'战意鼓舞'};
const layerNames=['完整卡底','完整插画背景','插画主体与特效','插画边框','外卡框','空白标题面板','空白描述面板','空白费用徽章'];
const categoryNames={icons:'图标',status:'状态图标',units:'单位',components:'共用组件',panels:'无字面板',controls:'战斗控件',health:'血条分层',energy:'能量分层',badges:'空白徽章',card_art:'完整插画图层',cards:'卡牌'};
document.querySelector('#count').textContent=assets.length+' 个正式 PNG';let current=0;let bg=0;
cards.forEach((c,i)=>{const o=document.createElement('option');o.value=i;o.textContent=names[c.name];document.querySelector('#card').append(o);const b=document.createElement('button');b.className='card-choice';b.innerHTML='<img src="cards/'+c.name+'/preview.png" alt="'+names[c.name]+'">'+names[c.name];b.onclick=()=>{document.querySelector('#card').value=i;showCard(i)};document.querySelector('#card-strip').append(b)});
function showCard(i){current=Number(i);const c=cards[current],stage=document.querySelector('#stage'),list=document.querySelector('#layers');stage.replaceChildren();list.replaceChildren();c.layers.forEach((f,k)=>{const im=new Image();im.src=f;im.alt=layerNames[k];im.id='layer-'+k;stage.append(im);const row=document.createElement('div');row.className='layer-row';row.innerHTML='<input type="checkbox" checked id="check-'+k+'"><label for="check-'+k+'">'+layerNames[k]+'</label><button>单独查看</button><a href="'+f+'" download>PNG</a>';row.querySelector('input').onchange=e=>im.style.display=e.target.checked?'':'none';row.querySelector('button').onclick=()=>{document.querySelectorAll('.layer-row input').forEach((x,n)=>{x.checked=n===k;document.querySelector('#layer-'+n).style.display=n===k?'':'none'})};list.append(row)});document.querySelector('#composite').href='cards/'+c.name+'/preview.png'}
document.querySelector('#card').onchange=e=>showCard(e.target.value);document.querySelector('#all').onclick=()=>showCard(current);document.querySelector('#none').onclick=()=>{document.querySelectorAll('.layer-row input').forEach(x=>x.checked=false);document.querySelectorAll('#stage img').forEach(x=>x.style.display='none')};document.querySelector('#bg').onclick=()=>{bg=(bg+1)%3;const s=document.querySelector('#stage');s.style.backgroundImage=bg===0?'':'none';s.style.backgroundColor=bg===1?'#f4f0e8':bg===2?'#13191e':''};showCard(0);
Object.entries(categoryNames).forEach(([k,v])=>{const o=document.createElement('option');o.value=k;o.textContent=v;document.querySelector('#category').append(o)});
function gallery(){const cat=document.querySelector('#category').value,q=document.querySelector('#search').value.toLowerCase(),show=document.querySelector('#showlayers').checked,g=document.querySelector('#gallery');g.replaceChildren();const rows=assets.filter(a=>(cat==='all'||a.file.startsWith(cat+'/'))&&a.file.includes(q)&&(show||!a.file.startsWith('cards/')||a.preview));document.querySelector('#shown').textContent='当前显示 '+rows.length+' 项';rows.forEach(a=>{const box=document.createElement('article');box.className='asset';box.innerHTML='<a class="thumb checker" href="'+a.file+'"><img loading="lazy" src="'+a.file+'" alt="'+a.file+'"></a><div class="caption">'+a.file+'<br><small>'+a.width+' × '+a.height+' · '+(a.intentional_opaque?'完整插画背景':'RGBA 透明')+'</small> · <a href="'+a.file+'" download>保存</a></div>';g.append(box)})}
document.querySelector('#category').onchange=gallery;document.querySelector('#search').oninput=gallery;document.querySelector('#showlayers').onchange=gallery;gallery();</script></body></html>'''
html=html.replace("cards:'卡牌'", "cards:'卡牌',ui_layers:'UI 对齐分层'")
html=html.replace("!a.file.startsWith('cards/')||a.preview", "(!a.file.startsWith('cards/')&&!a.file.startsWith('ui_layers/'))||a.preview")
html=html.replace('显示卡牌单层重复文件','显示卡牌 / UI 的单层文件')
html=html.replace('<a href="manifest.json">素材清单</a>', '<a href="manifest.json">素材清单</a> · <a href="ui_layouts.json">14 组 UI 定位表</a>')
html=html.replace('__ASSETS__',json.dumps(manifest,ensure_ascii=False)).replace('__CARDS__',json.dumps(layouts,ensure_ascii=False))
(ROOT/'index.html').write_text(html,encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='checks'},ensure_ascii=False))
print('Visible magenta checks:',sum(c['visible_magenta_pixels'] for c in checks))
