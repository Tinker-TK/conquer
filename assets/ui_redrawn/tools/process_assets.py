"""User-authorized deterministic matte removal, alignment and layer export.

No network/API calls. Source art stays in raw/. Generated outputs are reproducible.
Requires Pillow and NumPy; edits only files beneath this asset directory.
"""
from pathlib import Path
import argparse
import json
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageOps, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
NEAREST = Image.Resampling.NEAREST
RECORDS = []

def flood(mask, seeds):
    """Scan-line connected component fill; protects enclosed white highlights."""
    h, w = mask.shape
    work = mask.copy()
    found = np.zeros_like(mask)
    q = deque(seeds)
    while q:
        x, y = q.pop()
        if not (0 <= x < w and 0 <= y < h) or not work[y, x]:
            continue
        left, right = x, x
        while left > 0 and work[y, left - 1]: left -= 1
        while right + 1 < w and work[y, right + 1]: right += 1
        work[y, left:right + 1] = False
        found[y, left:right + 1] = True
        for yy in (y - 1, y + 1):
            if 0 <= yy < h:
                row = work[yy, left:right + 1]
                starts = np.flatnonzero(row & np.r_[True, ~row[:-1]])
                q.extend((left + int(xx), yy) for xx in starts)
    return found

def clean(path, hole=False):
    im = Image.open(path).convert('RGBA')
    a = np.array(im)
    rgb = a[:, :, :3].astype(np.int16)
    # Preserve genuine alpha. Otherwise key the observed matte, never the art.
    if np.mean(a[:, :, 3] == 0) > .005:
        method = 'preserved_alpha'
    else:
        r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
        magenta = (r > 140) & (b > 130) & (g < 125) & (r - g > 65) & (b - g > 60)
        neutral = (rgb.min(2) > 170) & (rgb.max(2) - rgb.min(2) < 42)
        black = (rgb.max(2) < 12)
        candidates = magenta | neutral | black
        # This map rendition has a navy halo instead of the requested matte.
        # All map content is parchment, green terrain, brown paths and red mark.
        if Path(path).stem == 'map':
            candidates |= (r < 50) & (g < 90) & (b >= r)
        h, w = candidates.shape
        seeds = [(x, 0) for x in range(w)] + [(x, h-1) for x in range(w)]
        seeds += [(0,y) for y in range(h)] + [(w-1,y) for y in range(h)]
        if hole: seeds.append((w//2, h//2))
        removed = flood(candidates, seeds)
        # Magenta is reserved as the matte color, including enclosed holes.
        removed |= magenta
        a[removed, 3] = 0
        method = 'border_flood_and_chroma_key' + ('_center_hole' if hole else '')
    # Remove darker magenta edge contamination left by anti-aliased RGB mattes.
    spill=(rgb[:,:,0]-rgb[:,:,1]>55)&(rgb[:,:,2]-rgb[:,:,1]>55)
    a[spill,3]=0
    if Path(path).stem == 'map':
        # Discard the renderer's extraneous blue glow, not map symbols.
        halo = (rgb[:,:,0] < 50) & (rgb[:,:,1] < 90) & (rgb[:,:,2] >= rgb[:,:,0])
        a[halo, 3] = 0
        a[a[:,:,3] > 128, 3] = 255
    a[a[:,:,3] == 0, :3] = 0
    result = Image.fromarray(a)
    box = result.getbbox()
    if box is None: raise ValueError(f'Empty extraction: {path}')
    return result.crop(box), method

def fit(im, size, margin=0, stretch=False):
    out = Image.new('RGBA', size)
    inside = (size[0]-2*margin, size[1]-2*margin)
    fg = im.resize(inside, NEAREST) if stretch else ImageOps.contain(im, inside, NEAREST)
    out.alpha_composite(fg, ((size[0]-fg.width)//2, (size[1]-fg.height)//2))
    return out

def write(im, relative, sources, method, **extra):
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    im.convert('RGBA').save(path)
    aa = np.array(im.convert('RGBA'))[:,:,3]
    RECORDS.append(dict(file=relative, width=im.width, height=im.height,
                        transparent_pixels=int((aa==0).sum()),
                        opaque_pixels=int((aa==255).sum()), sources=sources,
                        method=method, **extra))
    return im

def simple_assets():
    for category, size in [('icons',(256,256)), ('status',(256,256)), ('units',(512,512))]:
        for p in sorted((ROOT/'raw'/category).glob('*.png')):
            im, method = clean(p, hole=p.stem in ('relic_ring','gear'))
            if p.stem == 'gold_coin':
                # The reference's embossed stroke can read as a numeral. Replace
                # its whole inner disk with blank golden material, not a glyph.
                a=np.array(im); h,w=a.shape[:2]; yy,xx=np.indices((h,w))
                mask=((xx-w*.5)/(w*.29))**2+((yy-h*.5)/(h*.34))**2<1
                ramp=np.clip((yy/(h-1)),0,1)
                for c,(top,bottom) in enumerate([(255,223),(214,146),(70,19)]):
                    val=(top*(1-ramp)+bottom*ramp).astype(np.uint8)
                    a[:,:,c][mask]=val[mask]
                im=Image.fromarray(a);method+='_blank_coin_face'
            write(fit(im,size,16), f'{category}/{p.name}', [str(p.relative_to(ROOT))], method)
    sizes = dict(gold_button=(1024,360),chapter_banner=(1280,280),dark_panel=(1000,440),
                 energy_orb=(512,512),parchment_card=(768,1024),cost_badge=(256,256),
                 draw_book=(512,512),discard_book=(512,512),health_bar=(768,128),toggle=(512,256),
                 crown_backplate=(384,512))
    for name, size in sizes.items():
        p = ROOT/'raw'/'surfaces'/f'{name}.png'
        if not p.exists(): continue
        im, method = clean(p)
        write(fit(im,size,16), f'components/{name}.png', [str(p.relative_to(ROOT))], method)
    old = ROOT/'drafts/card_frame_red_not_transparent.png'
    im, method = clean(old, hole=True)
    write(fit(im,(768,1024),16,stretch=True), 'components/card_frame_red.png',
          ['drafts/card_frame_red_not_transparent.png'], method)

def component(name):
    return Image.open(ROOT/'components'/f'{name}.png').convert('RGBA')

def color_frame(im, color):
    a = np.array(im)
    rgb = a[:,:,:3].astype(np.float32)
    red = (rgb[:,:,0] > rgb[:,:,1]*1.4) & (rgb[:,:,0] > rgb[:,:,2]*1.3)
    intensity = rgb[:,:,0] / 255
    palettes = dict(blue=(38,151,249),green=(25,207,103),gold=(255,205,70))
    if color != 'red':
        tinted = intensity[:,:,None] * np.array(palettes[color])[None,None,:]
        a[:,:,:3][red] = np.clip(tinted[red],0,255).astype(np.uint8)
    return Image.fromarray(a)

def positioned(im, rect, canvas=(768,1024), stretch=False):
    x,y,w,h = rect
    layer = Image.new('RGBA',canvas)
    layer.alpha_composite(fit(im,(w,h),0,stretch), (x,y))
    return layer

def cards():
    card_names = ['summon_guard','hold_position','fireball','battlefield_heal','battle_inspiration']
    colors = ['blue','blue','red','green','blue']
    base = component('parchment_card')
    frame = component('card_frame_red')
    badge = component('cost_badge')
    layouts = []
    for name,color in zip(card_names,colors):
        directory = ROOT/'raw/card_art'
        p = directory/f'{name}_subject.png'
        b = directory/f'{name}_background.png'
        if not p.exists() or not b.exists(): continue
        subject, method = clean(p)
        # Artwork backgrounds intentionally cover the whole illustration window.
        # Do not leak stochastic generated alpha into the parchment beneath.
        background = Image.open(b).convert('RGB').convert('RGBA')
        write(fit(subject,(768,768),24),f'card_art/{name}_subject.png',[str(p.relative_to(ROOT))],method)
        write(background.resize((768,768),NEAREST),f'card_art/{name}_background.png',
              [str(b.relative_to(ROOT))],'complete_background_redraw',intentional_opaque=True)
        # Every layer has the SAME canvas and origin; no trim is allowed here.
        layers = [
            ('00_backplate',positioned(base,(42,36,684,948),stretch=True)),
            ('10_art_background',positioned(background,(100,208,568,448),stretch=True)),
            ('20_art_subject',positioned(subject,(112,216,544,432))),
            ('30_art_border',positioned(color_frame(frame,'gold'),(84,192,600,480),stretch=True)),
            ('40_outer_frame',color_frame(frame,color)),
            ('50_title_plate',positioned(base,(118,86,532,114),stretch=True)),
            ('60_description_plate',positioned(base,(90,694,588,232),stretch=True)),
            ('70_cost_badge',positioned(badge,(0,0,168,168)))
        ]
        composed = Image.new('RGBA',(768,1024))
        layer_paths = []
        for order,(lname,im) in enumerate(layers):
            rel = f'cards/{name}/{lname}.png'
            write(im,rel,[str(p.relative_to(ROOT)),str(b.relative_to(ROOT)),
                  'components/parchment_card.png','components/card_frame_red.png','components/cost_badge.png'],
                  'aligned_full_layer',order=order,anchor=[0,0],card=name)
            composed.alpha_composite(im)
            layer_paths.append(rel)
        write(composed,f'cards/{name}/preview.png',layer_paths,'composited_preview',preview=True)
        # Reopen files and verify reassembly equals preview, not just same size.
        check = Image.new('RGBA',(768,1024))
        for rel in layer_paths: check.alpha_composite(Image.open(ROOT/rel).convert('RGBA'))
        assert np.array_equal(np.array(check),np.array(composed)), name
        layouts.append(dict(name=name,canvas=[768,1024],origin=[0,0],layers=layer_paths,
                            art_rect=[100,208,568,448],title_rect=[160,110,460,65],
                            description_rect=[125,728,518,150],cost_center=[84,84],verified_reassembly=True))
    return layouts

def ui_layers():
    panel = component('dark_panel')
    # Shared blanks replace all repeated panels; text stays in runtime Labels.
    for name,size in [('top_bar',(2048,128)),('stat_panel',(768,224)),
                      ('navigation_button',(512,224)),('phase_panel',(768,224)),
                      ('speed_button_blank',(320,224)),('auto_row_blank',(640,160)),
                      ('battle_control_panel',(1000,440)),('pile_backplate',(512,320))]:
        write(fit(panel,size,8,True),f'panels/{name}.png',['components/dark_panel.png'],'resized_complete_panel')
    for color in ['blue','green','gold']:
        write(color_frame(component('card_frame_red'),color),f'components/card_frame_{color}.png',
              ['components/card_frame_red.png'],'palette_variant')
    # Health border and FULL fill share an identical canvas; empty underlay is
    # reconstructed from the frame color, so decreasing fill never reveals holes.
    health = component('health_bar')
    a = np.array(health)
    rgb = a[:,:,:3].astype(np.int16)
    red = (rgb[:,:,0] > 110) & (rgb[:,:,0] > rgb[:,:,1]*1.15) & (rgb[:,:,0] > rgb[:,:,2]*1.2)
    fill = a.copy(); fill[~red,3]=0
    border = a.copy(); border[red,3]=0
    under = a.copy(); under[red,:3]=(26,47,64)
    for lname,arr in [('10_fill',fill),('20_border',border),('00_empty_bar',under)]:
        write(Image.fromarray(arr),f'health/{lname}.png',['components/health_bar.png'],'color_mask_full_layer',anchor=[0,0])
    # Energy core gets a complete round blue base behind the four rim points.
    orb = component('energy_orb')
    a = np.array(orb); rgb=a[:,:,:3].astype(np.int16)
    blue = (rgb[:,:,2] > rgb[:,:,0]+25) & (rgb[:,:,2] > 100)
    yy,xx=np.indices(a.shape[:2]); inner=(xx-256)**2+(yy-256)**2 < 174**2
    core_mask = blue | (inner & (rgb.min(2)>150))
    rim=a.copy(); rim[core_mask,3]=0
    # Low-frequency blue patch extends behind the gold rim to complete the core.
    core=Image.new('RGBA',orb.size)
    d=ImageDraw.Draw(core); d.ellipse((68,68,444,444),fill=(9,145,244,255))
    patch=a.copy(); patch[~core_mask,3]=0
    core.alpha_composite(Image.fromarray(patch))
    write(core,'energy/00_core.png',['components/energy_orb.png'],'extended_blue_core',anchor=[0,0])
    write(Image.fromarray(rim),'energy/10_rim.png',['components/energy_orb.png'],'isolated_gold_rim',anchor=[0,0])
    # Blank badge variants: face is complete under the rim, no numerals.
    badge=component('cost_badge')
    a=np.array(badge); rgb=a[:,:,:3].astype(np.int16)
    gold=(rgb[:,:,0]>100)&(rgb[:,:,0]>rgb[:,:,2]*1.5)
    for name,col in [('counter_red',(211,32,53)),('badge_navy',(26,47,64))]:
        cp=a.copy(); face=(cp[:,:,3]>0)&(~gold)
        # Preserve outer dark contour, recolor only inner central region.
        yy,xx=np.indices(face.shape); face &= ((xx-128)**2+(yy-128)**2<65**2)
        cp[face,:3]=col
        write(Image.fromarray(cp),f'badges/{name}.png',['components/cost_badge.png'],'blank_badge_variant')
    # Selected button: reuse complete gold bevel, remove just its face.
    selected=fit(component('gold_button'),(320,224),8,True)
    a=np.array(selected); a[50:172,45:275,3]=0
    write(Image.fromarray(a),'controls/selected_border.png',['components/gold_button.png'],'blank_selection_overlay')
    # Pause is geometry, not typography: two independent silver bars.
    pause=Image.new('RGBA',(256,256)); d=ImageDraw.Draw(pause)
    for x in [66,145]:
        d.rectangle((x,56,x+44,200),fill=(143,172,189,255)); d.rectangle((x,56,x+8,190),fill=(207,224,235,255))
    write(pause,'controls/pause_symbol.png',[],'local_geometric_symbol')
    # Toggle: mirror the unobstructed right half to fully reconstruct the track.
    toggle=component('toggle'); box=toggle.getbbox(); t=toggle.crop(box)
    right=t.crop((t.width//2,0,t.width,t.height))
    track=Image.new('RGBA',(right.width*2,right.height)); track.alpha_composite(ImageOps.mirror(right),(0,0));track.alpha_composite(right,(right.width,0))
    track=fit(track,(512,256),16)
    a=np.array(t); rgb=a[:,:,:3].astype(np.int16)
    neutral=(rgb.min(2)>105)&(rgb.max(2)-rgb.min(2)<85)
    neutral[:,int(t.width*.48):]=False
    knob=a.copy(); knob[~neutral,3]=0
    knob=Image.fromarray(knob); knob=knob.crop(knob.getbbox())
    write(track,'controls/toggle_track.png',['components/toggle.png'],'mirrored_unoccluded_track')
    write(fit(knob,(224,224),12),'controls/toggle_knob.png',['components/toggle.png'],'isolated_knob')

def ui_compositions():
    # Per-group layers all share a canvas, like cards. The dictionaries also
    # document placements for games preferring reusable small source textures.
    groups={
      'crown_badge':((384,512),[('components/crown_backplate.png',(0,0,384,512)),('icons/crown.png',(72,118,240,240))]),
      'health_panel':((768,224),[('panels/stat_panel.png',(0,0,768,224)),('icons/heart.png',(16,0,224,224))]),
      'gold_panel':((768,224),[('panels/stat_panel.png',(0,0,768,224)),('icons/gold_coin.png',(16,0,224,224))]),
      'equipment_panel':((768,224),[('panels/stat_panel.png',(0,0,768,224)),('icons/equipment_sword.png',(24,0,224,224)),('icons/equipment_armor.png',(272,0,224,224)),('icons/equipment_potion.png',(520,0,224,224))]),
      'phase_panel':((768,224),[('panels/phase_panel.png',(0,0,768,224)),('icons/crossed_swords.png',(18,10,204,204))]),
      'start_button':((1024,360),[('components/gold_button.png',(0,0,1024,360)),('icons/crossed_swords.png',(70,68,224,224))]),
      'battle_control':((1000,440),[('panels/battle_control_panel.png',(0,0,1000,440)),('panels/speed_button_blank.png',(48,35,275,190)),('panels/speed_button_blank.png',(362,35,275,190)),('panels/speed_button_blank.png',(676,35,275,190)),('controls/pause_symbol.png',(103,62,144,144)),('controls/selected_border.png',(362,35,275,190)),('panels/auto_row_blank.png',(120,270,760,140)),('controls/toggle_track.png',(640,290,220,110)),('controls/toggle_knob.png',(650,296,98,98))]),
      'energy':((512,512),[('energy/00_core.png',(0,0,512,512)),('energy/10_rim.png',(0,0,512,512))]),
      'health_bar':((768,128),[('health/00_empty_bar.png',(0,0,768,128)),('health/10_fill.png',(0,0,768,128)),('health/20_border.png',(0,0,768,128))])
    }
    for name,icon in [('map_button','map'),('deck_button','deck_book'),('settings_button','gear')]:
        groups[name]=((512,224),[('panels/navigation_button.png',(0,0,512,224)),(f'icons/{icon}.png',(8,12,200,200))])
    for name,book in [('draw_pile','draw_book'),('discard_pile','discard_book')]:
        groups[name]=((512,512),[('panels/pile_backplate.png',(0,244,512,268)),(f'components/{book}.png',(56,0,384,384)),('badges/counter_red.png',(300,274,128,128))])
    metadata=[]
    for name,(canvas,specs) in groups.items():
        composed=Image.new('RGBA',canvas);layers=[]
        for k,(src,rect) in enumerate(specs):
            im=positioned(Image.open(ROOT/src).convert('RGBA'),rect,canvas,stretch=True)
            rel=f'ui_layers/{name}/{k:02d}_{Path(src).stem}.png'
            write(im,rel,[src],'aligned_ui_layer',anchor=[0,0],order=k,group=name)
            composed.alpha_composite(im);layers.append(dict(file=rel,source=src,rect=list(rect),order=k))
        write(composed,f'ui_layers/{name}/preview.png',[r['file'] for r in layers],'composited_ui_preview',preview=True)
        metadata.append(dict(name=name,canvas=list(canvas),origin=[0,0],layers=layers))
    return metadata

def main():
    simple_assets()
    ui_layers()
    layouts=cards()
    ui=ui_compositions()
    (ROOT/'manifest.json').write_text(json.dumps(RECORDS,ensure_ascii=False,indent=2),encoding='utf-8')
    (ROOT/'card_layouts.json').write_text(json.dumps(layouts,ensure_ascii=False,indent=2),encoding='utf-8')
    (ROOT/'ui_layouts.json').write_text(json.dumps(ui,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'Exported {len(RECORDS)} PNGs, {len(layouts)} cards with verified reassembly')

if __name__ == '__main__': main()
