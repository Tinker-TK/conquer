"""Generate native 128px river tile previews and matching lossless height atlases."""
from pathlib import Path
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets' / 'tilemap' / 'river'
OUT.mkdir(parents=True, exist_ok=True)
SIZE = 128
y, x = np.mgrid[0:SIZE, 0:SIZE].astype(float)
x += 0.5
y += 0.5

def canonical(mask):
    for diagonal, a, b in [(1, 0, 2), (3, 2, 4), (5, 4, 6), (7, 6, 0)]:
        if not (mask & (1 << a) and mask & (1 << b)):
            mask &= ~(1 << diagonal)
    return mask

def narrow(mask):
    distance = np.hypot(x - 64, y - 64)
    for bit, end in [(1, (64, 0)), (2, (128, 64)), (4, (64, 128)), (8, (0, 64))]:
        if mask & bit:
            dx, dy = end[0] - 64, end[1] - 64
            t = np.clip(((x - 64) * dx + (y - 64) * dy) / (dx * dx + dy * dy), 0, 1)
            distance = np.minimum(distance, np.hypot(x - (64 + t * dx), y - (64 + t * dy)))
    shore_distance = (40 if mask == 0 else 48) - distance
    return np.clip(1 - shore_distance / 40, 0, 1), shore_distance >= 0

def wide(mask):
    distance = np.full((SIZE, SIZE), 1000.0)
    for bit, d in [(0, y), (2, SIZE - x), (4, SIZE - y), (6, x)]:
        if not mask & (1 << bit):
            distance = np.minimum(distance, d - 5)
    for diag, a, b, cx, cy in [(1, 0, 2, 128, 0), (3, 2, 4, 128, 128), (5, 4, 6, 0, 128), (7, 6, 0, 0, 0)]:
        if mask & (1 << a) and mask & (1 << b) and not mask & (1 << diag):
            distance = np.minimum(distance, np.hypot(x - cx, y - cy) - 5)
    return np.clip(1 - distance / 40, 0, 1), distance >= 0

def preview(height, alpha):
    # A restrained stone pattern keeps the native TileSet palette readable.
    stone = (np.sin(np.floor(x / 9) * 7.23 + np.floor(y / 11) * 13.37) + 1) / 2
    seams = ((x % 9 < 1) | (y % 11 < 1)).astype(float)
    grain = 0.74 + stone * 0.32 - seams * 0.14
    bed = np.stack([grain * 0.36, grain * 0.40, grain * 0.34], axis=-1)
    bank = np.stack([grain * 0.32, grain * 0.29, grain * 0.21], axis=-1)
    bank_t = np.clip((height - 0.65) / 0.31, 0, 1)[..., None]
    bed = bed * (1 - bank_t) + bank * bank_t
    depth = np.maximum(0.66 - height, 0)
    deep = np.clip(depth / 0.7, 0, 1)[..., None]
    water = np.array([0.29, 0.47, 0.51]) * (1 - deep) + np.array([0.13, 0.29, 0.37]) * deep
    opacity = 0.22 + deep * 0.5
    color = bed * (1 - opacity) + water * opacity
    foam = ((depth < 0.06) & (height <= 0.66))[..., None] * 0.80
    color = color * (1 - foam) + np.array([0.84, 0.93, 0.89]) * foam
    color = np.where((height <= 0.66)[..., None], color, bed)
    return np.dstack([np.clip(color * 255, 0, 255).astype('uint8'), alpha.astype('uint8') * 255])

manifest = {'tile_size': SIZE, 'bank_slope': 40, 'channel_masks': list(range(16)), 'water_masks': sorted({canonical(m) for m in range(256)})}
assert len(manifest['water_masks']) == 47
for name, masks, cols, fn in [('channel', manifest['channel_masks'], 4, narrow), ('water', manifest['water_masks'], 8, wide)]:
    rows = (len(masks) + cols - 1) // cols
    atlas = np.zeros((rows * SIZE, cols * SIZE, 4), dtype='uint8')
    heights = atlas.copy()
    for index, mask in enumerate(masks):
        h, a = fn(mask)
        tile = np.repeat(np.rint(h * 255).astype('uint8')[..., None], 4, axis=-1)
        tile[..., 3] = a.astype('uint8') * 255
        ox, oy = index % cols * SIZE, index // cols * SIZE
        heights[oy:oy + SIZE, ox:ox + SIZE] = tile
        atlas[oy:oy + SIZE, ox:ox + SIZE] = preview(h, a)
    Image.fromarray(atlas).save(OUT / f'river_{name}.png')
    Image.fromarray(heights).save(OUT / f'river_{name}_height.png')

(OUT / 'river_tiles_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(f'RIVER_ATLASES: channel=16; water=47; tile_size={SIZE}; output={OUT}')
