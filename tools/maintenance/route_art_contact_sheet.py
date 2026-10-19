from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json

root=Path(__file__).resolve().parents[2]
art=root/'assets/ui/events/illustrations'
manifest=json.loads((art/'route-prompts.json').read_text(encoding='utf-8'))
canvas=Image.new('RGB',(1500,1280),'#eee7d1')
draw=ImageDraw.Draw(canvas)
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',17)
for i,entry in enumerate(manifest['images']):
    with Image.open(art/entry['file']) as image:
        thumb=image.convert('RGB'); thumb.thumbnail((282,282))
        x=(i%5)*300+9; y=(i//5)*320+8
        canvas.paste(thumb,(x,y))
        draw.text((x,y+286),entry['event'].removeprefix('act1_'),fill='#443b29',font=font)
out=root/'outputs/route_events_20261018/route-art-contact-sheet.jpg'
canvas.save(out,quality=92)
print(out)
