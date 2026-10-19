"""Configure Enemy Pack's two-pixel shader and hand-picked legacy-character palettes.

Reads source PNG palettes only; never rewrites an image or an animation/combat setting.
Run with --check to verify generated resources and complete source-color coverage.
"""
from pathlib import Path
import argparse
import re
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
COMMON = "161c2e:1f1a1a ffffff:f4edea"
# Explicit source:target pairs preserve each material's hue and light/shadow ordering.
# Legacy color sources: Orc, Soldier, Archer, Wizard, Necromancer, Knight and Slime.
PAIRS = {
    "bear": "7a624c:735d50 584c51:534545 9f8e6c:b78c61 9cbeaa:afc3b7 8c9e9c:7f909a",
    "bomb_fish": "e6d579:edcf8b be7a42:ce894f 945656:8f3838 b98664:b78c61 f780cd:edbeb6 785680:655457 c4a05c:ddb75f b55eac:b16363 fef07c:edcf8b ced9e0:c5d0d5 405e86:425c6b 473e60:3a3c4f 6faaaf:90c0ce aa805f:8d6534 e0e07f:ddb75f f9ff74:edcf8b",
    "bumblebee": "b28d5a:ba974b efe054:ddb75f 9f866e:98857d 6c554b:735d50 dad9bb:d0c7b5 c6b799:b7a88e",
    "giant_bat": "4d4162:3a3c4f 5d657c:5e6274 8f9eae:9badb7 71568d:473c9a 464554:2a2b3c d5e5de:d1dadb abc1c4:a7bfc3 8d4848:8f3838 ca8451:ce894f e4ee67:ddb75f",
    "gnoll": "6d5e51:735d50 efe054:ddb75f af8c58:ba974b 514744:534545 b492a7:b19e9a efe1ab:edcf8b b1a174:b7a88e",
    "gnome": "ef6735:be633d 975454:8f3838 6d5e51:735d50 9cbeaa:afc3b7 a79158:9d7e39 efe1ab:edcf8b c8a876:d9bc78 f7bd90:ebc4b8 4d4541:534545",
    "harpoon_shark": "289092:90c0ce bfc3bf:c5d0d5 195d6b:425c6b 6f9193:6f828d 365862:374147 9ec9be:a7bfc3 e0dbcf:d5cac5 40ac92:a5d5d3 fef07c:edcf8b",
    "hex_shaman": "f6d6a1:edcf8b af9e93:b7a59b 4f4f70:3a3c4f a479cd:5562b7 457c71:3d554e fdb2fc:edeaf1 95d562:a3be71 ba876a:b78c61 ebaaea:edbeb6 816563:655457",
    "imp": "c96540:be633d 964949:8f3838 5b303e:4c1a1a efe054:ddb75f e0d0b9:d0c7b5 cf8935:ce894f ae466d:943838 ab9482:b19e9a 743d6a:5b1b3e e0966b:e0b3a5 d58a8a:b16363 f1e46d:edcf8b",
    "lizard": "3cbe57:63ab3f 4b867b:3b7d4f ffed44:ddb75f 693d5b:5b1b3e",
    "minotaur": "78a7ab:8fa1ae 667279:607581 789e9c:7f909a b8d2c3:afc3b7 576064:4d585a 3e4151:2a2b3c cfbb85:d9bc78 7a685d:735d50 92806f:98857d 9f976a:9d7e39 e9e5b2:edcf8b ac8aa0:b19e9a 435060:425c6b d3c08c:d9bc78 fff977:edcf8b e1cbd1:d5cac5",
    "paddle_shark": "6f9193:6f828d a79158:9d7e39 365862:374147 b9cbc4:c5d0d5 6d5e51:735d50 c8b686:d9bc78 e0dbcf:d5cac5 fef07c:edcf8b 8db3a5:afc3b7",
    "panda": "b3845f:b78c61 2d3047:2a2b3c dab667:ddb75f faf1cd:f4edea d7bca3:ebc4b8 435060:425c6b 6e5850:735d50 dec48b:edcf8b 886664:7b6a6b 9cbeaa:afc3b7 f0e792:edcf8b",
    "skull": "efe1ab:edcf8b c8a876:d9bc78 7a6756:735d50 d4edc2:cddbd3 9f976a:9d7e39 494544:534545 9cbeaa:afc3b7 688c8a:7f909a a88774:b78c61 ff4242:a63125",
    "slingshot_gnome": "9c664b:a16a47 e09844:ce894f 9cbeaa:afc3b7 efe1ab:edcf8b c8a876:d9bc78 6d5e51:735d50 a79158:9d7e39 cdcf93:edcf8b f2ec7d:edcf8b 433b37:44373d b6b184:b7a88e",
    "snake": "ffb13e:ffc568 7a5f74:655457 b97091:b16363 ffea94:edcf8b b9a58e:b7a59b",
    "spear_goblin": "688c8a:7f909a 9cbeaa:afc3b7 417168:3d554e 95d562:a3be71 b65555:8f3838 693d5b:5b1b3e d4edc2:cddbd3",
    "spider": "764e7b:473c9a 4c375e:312942 b487a3:b19e9a dde678:edcf8b 2c283e:201b2c beb080:b7a88e",
    "thief": "3a4859:374147 596975:607581 352945:312942 aaab90:b7a88e efe1ab:edcf8b 9cbeaa:afc3b7 c8a876:d9bc78 d4edc2:cddbd3 688c8a:7f909a",
    "torch_goblin": "8abc61:a3be71 714646:59413b cf8935:ce894f ffdc00:ddb75f 417168:425916 8d6e52:8d6534 9a7655:946835 404e55:374147 955c3c:7b4e16 aea076:b7a88e a66d79:b16363 715a68:655457 c99696:be9b97",
    "troll": "718f5a:7d984b 597557:5d772d 845e54:7b4e16 b09377:b78c61 4e5c56:425916 574045:534545 e0bf6d:b78c61 a6805b:8d6534 bbad7c:b7a59b 99a676:a3be71 9e5ba2:5e433d e1609e:7b0808",
    "turtle": "5b8243:5d772d 665a47:735d50 94a35c:7d984b 7e7b55:9d7e39 4f3939:4c3029 375c46:425916 a7ab7a:a3be71 fff977:edcf8b",
    "pig_rider": "db8594:be9b97 688c8a:7f909a a76883:b16363 9cbeaa:afc3b7 815773:655457 417168:3d554e 95d562:a3be71 ebb39f:ebc4b8 b65555:8f3838 693d5b:5b1b3e d4edc2:cddbd3",
}
RANGED = {"bomb_fish", "gnoll", "harpoon_shark", "hex_shaman", "slingshot_gnome"}


def opaque_colors(scene):
    colors = set()
    for sheet in re.findall(r'path="res://([^\"]+\.png)"', scene):
        image = Image.open(ROOT / sheet).convert("RGBA")
        colors.update(bytes(c[:3]).hex() for n, c in image.getcolors(image.width * image.height) if c[3] == 255)
    return colors


def packed_colors(colors):
    return "PackedColorArray(" + ", ".join(
        ", ".join(f"{int(c[i:i + 2], 16) / 255:.9f}" for i in (0, 2, 4)) + ", 1" for c in colors
    ) + ")"


def palette_resource(mapping):
    colors = sorted(mapping)
    return '\n'.join([
        '[gd_resource type="Resource" script_class="" format=3]', '',
        '[ext_resource type="Script" path="res://scripts/units/enemy_pixel_palette.gd" id="palette"]', '',
        '[resource]', 'script = ExtResource("palette")',
        'source_colors = ' + packed_colors(colors),
        'target_colors = ' + packed_colors([mapping[c] for c in colors]), '',
    ]).replace(' script_class=""', '')


def configured_scene(text, name, root_sprite=False):
    # Idempotent and narrow: preserve every animation frame, node position and combat setting.
    if 'id="pixel_style"' in text:
        return text
    resources = (
        '[ext_resource type="Script" path="res://scripts/units/enemy_pixel_style.gd" id="pixel_style"]\n'
        f'[ext_resource type="Resource" path="res://data/visuals/enemy_pack/{name}.tres" id="pixel_palette"]\n'
    )
    text = text.replace('\n[sub_resource', '\n' + resources + '\n[sub_resource', 1)
    if 'id="flash"' in text:
        text = text.replace('res://shaders/hurt_flash.gdshader', 'res://shaders/unit_pixel_style.gdshader')
        text = text.replace('shader_parameter/flash_intensity = 0.0',
                            'shader_parameter/pixel_step = 2.0\nshader_parameter/match_palette = true\nshader_parameter/flash_intensity = 0.0', 1)
    else:
        text = text.replace('\n[sub_resource', '\n[ext_resource type="Shader" path="res://shaders/unit_pixel_style.gdshader" id="pixel_shader"]\n\n[sub_resource type="ShaderMaterial" id="pixel_material"]\nresource_local_to_scene = true\nshader = ExtResource("pixel_shader")\nshader_parameter/pixel_step = 2.0\nshader_parameter/match_palette = true\n\n[sub_resource', 1)
        text = text.replace('texture_filter = 1', 'texture_filter = 1\nmaterial = SubResource("pixel_material")', 1)
    parent = '.' if root_sprite else 'AnimatedSprite2D'
    child = (f'\n[node name="PixelStyle" type="Node" parent="{parent}"]\n'
             'script = ExtResource("pixel_style")\n'
             'palette = ExtResource("pixel_palette")\n')
    sprite_start = text.index('[node ') if root_sprite else text.index('[node name="AnimatedSprite2D"')
    following_node = text.find('\n[node ', sprite_start + 1)
    if following_node == -1:
        following_node = len(text)
    return text[:following_node] + child + text[following_node:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    expected = {}
    legacy_colors = set()
    for name in ['orc', 'soldier', 'archer', 'wizard', 'necromancer', 'knight', 'slime']:
        legacy_colors.update(opaque_colors((ROOT / f'scenes/units/{name}.tscn').read_text(encoding='utf-8')))
    for name, pairs in PAIRS.items():
        mapping = dict(pair.split(':') for pair in (COMMON + ' ' + pairs).split())
        unit = ROOT / f'scenes/units/{name}.tscn'
        text = unit.read_text(encoding='utf-8')
        used = opaque_colors(text)
        paths = [unit]
        if name in RANGED:
            projectile = ROOT / f'scenes/projectiles/{name}_projectile.tscn'
            used.update(opaque_colors(projectile.read_text(encoding='utf-8')))
            paths.append(projectile)
        if name == 'hex_shaman':
            hit = ROOT / 'scenes/effects/hex_shaman_hit.tscn'
            used.update(opaque_colors(hit.read_text(encoding='utf-8')))
            expected[hit] = configured_scene(hit.read_text(encoding='utf-8'), name, root_sprite=True)
        assert not used - mapping.keys(), (name, 'unmapped source colors', used - mapping.keys())
        mapping = {c: mapping[c] for c in used}
        assert len(mapping) <= 32
        assert not set(mapping.values()) - legacy_colors, (name, 'non-legacy target color', set(mapping.values()) - legacy_colors)
        expected[ROOT / f'data/visuals/enemy_pack/{name}.tres'] = palette_resource(mapping)
        for path in paths:
            expected[path] = configured_scene(path.read_text(encoding='utf-8'), name)
    for path, content in expected.items():
        if args.check:
            assert path.exists() and path.read_text(encoding='utf-8') == content, f'Outdated: {path}'
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding='utf-8', newline='\n')
    print(f'ENEMY_PIXEL_STYLE_CONFIG_PASS: {len(PAIRS)} units, {len(RANGED)} projectiles, shaman impact; complete color coverage, legacy targets only')


if __name__ == '__main__':
    main()
