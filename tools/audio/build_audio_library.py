"""Build the single F6 audition scene from all collected audio manifests.

Append future candidates to assets/audio/library/manifest.json, then run this script.
No audio conversion or third-party Python modules required for scene generation.
"""
from collections import Counter
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / 'examples/scenes/audio_library.tscn'
# AI 生成音频用独立许可标记，和 CC0/CC-BY 分开，便于发布前逐条复核。
LICENSES = ('CC0-1.0', 'CC-BY-3.0', 'AI-ELEVENLABS', 'AI-SUNO')
CATEGORIES = [
    ('music', '背景 · 音乐', '游戏背景音乐与可循环 BGM，可在 data/audio/game_soundscape.tres 替换'),
    ('ambience', '背景 · 环境音', '风声、雨声、篝火、森林等循环环境音'),
    ('ui', '界面 · 交互', '按钮点击、悬停、确认、取消、报错、金币'),
    ('card', '卡牌 · 抽打', '抽牌、洗牌、打出、升级'),
    ('ai_combat', '战斗 · 制作候选', 'AI 生成与本地声音设计的攻击、受击、爆炸、施法候选，可查看逐条来源'),
    ('kenney_impact', 'Kenney · Impact 全集', '完整碰撞音效包：脚步、金属、木材、玻璃、拳击等；可搜索材质与力度'),
    ('kenney_rpg', 'Kenney · RPG 全集', '完整 RPG 音效包：刀剑、脚步、衣物、门、书本、金币等，含合集预览'),
    ('blade_clash', '攻击 · 刀剑碰撞', '真实刀剑、斧刃碰撞'),
    ('hammer_swing', '攻击 · 大锤挥摆', '重破风与重斧挥摆候选，可调整音调'),
    ('weapon_swing', '攻击 · 刀剑挥斩', '轻型武器破风、武士刀挥斩'),
    ('bow_shot', '攻击 · 弓箭射击', '长弓、反曲弓、弩箭、拉弦与飞行'),
    ('spell_cast', '攻击 · 释放法术', '不同质感的施法候选'),
    ('physical_hit', '受击 · 普通受击', '身体撞击、血肉受击、人物受伤呼声'),
    ('magic_hit', '受击 · 法术爆炸', '冰魔法冲击、爆裂候选'),
    ('lightning_hit', '受击 · 雷击', '电流爆裂与短雷声'),
    ('fire_hit', '受击 · 火焰爆炸', '爆炸与火焰冲击'),
    ('block', '防御 · 格挡', '武器格挡与剑柄碰撞'),
    ('death', '死亡 · 人物呼声', '死亡与受伤呼声候选'),
    ('previous', '上一批 · 对照', '保留先前收集的全部素材'),
]


def quoted(value):
    return json.dumps(value, ensure_ascii=False)


def collect():
    files = json.loads((ROOT / 'assets/audio/library/manifest.json').read_text(encoding='utf-8'))['files']
    old = json.loads((ROOT / 'assets/audio/combat/manifest.json').read_text(encoding='utf-8'))['files']
    current = {entry['path']: entry for entry in files}
    for entry in old:
        path = 'res://assets/audio/combat/' + entry['path']
        if path in current:
            if current[path]['sha256'] != entry['sha256']:
                raise ValueError('Reused combat asset hash changed: ' + path)
            continue
        files.append(dict(entry, path=path,
                          title='上一批 · ' + Path(entry['path']).stem, category='previous',
                          notes='上一批候选，原用途：' + '、'.join(entry['categories']), changes='原文件保持不变。'))
    known = {entry[0] for entry in CATEGORIES}
    paths = set()
    for entry in files:
        path = entry['path']
        if not path.startswith('res://assets/audio/') or '..' in Path(path).parts:
            raise ValueError('Audio must be inside assets/audio: ' + path)
        if path in paths:
            raise ValueError('Duplicate candidate: ' + path)
        paths.add(path)
        if entry['category'] not in known:
            raise ValueError('Unknown category: ' + entry['category'])
        source = ROOT / path.removeprefix('res://')
        if hashlib.sha256(source.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError('Audio hash changed: ' + path)
        for field in ('title', 'author', 'source', 'license'):
            if not entry.get(field):
                raise ValueError(f'Missing {field}: {path}')
        if entry['license'] not in LICENSES:
            raise ValueError('Unreviewed license: ' + path)
    return files


def main():
    files = collect()
    manifest = json.loads((ROOT / 'assets/audio/library/manifest.json').read_text(encoding='utf-8'))
    lines = ['; Unified audition library. Regenerate with tools/audio/build_audio_library.py.',
             '[gd_scene format=3]', '',
             '[ext_resource type="Script" path="res://examples/scripts/audio_library.gd" id="1"]']
    for index, entry in enumerate(files, 2):
        lines.append(f'[ext_resource type="AudioStream" path={quoted(entry["path"])} id="{index}"]')
    lines += ['', '[node name="AudioLibrary" type="Control"]', 'layout_mode = 3',
              'anchors_preset = 15', 'anchor_right = 1.0', 'anchor_bottom = 1.0',
              'grow_horizontal = 2', 'grow_vertical = 2', 'script = ExtResource("1")',
              'metadata/audition_batch = ' + quoted(manifest.get('audition_batch', '')),
              'metadata/audition_title = ' + quoted(manifest.get('audition_title', '本批试听 · 10月19日')),
              'metadata/audition_description = ' + quoted(manifest.get('audition_description', '本地声音设计 · 武器 / 法术 / 卡牌 / UI / 环境 / BGM；A 清脆，B 厚重。')),
              'metadata/audition_count = ' + str(sum(e.get('batch') == manifest.get('audition_batch') for e in files)),
              'metadata/online_previews = ' + quoted(json.dumps(manifest.get('online_previews', []), ensure_ascii=False)),
              '', '[node name="Samples" type="Node" parent="."]']
    for key, title, description in CATEGORIES:
        lines += ['', f'[node name="{key}" type="Node" parent="Samples"]',
                  'metadata/title = ' + quoted(title), 'metadata/description = ' + quoted(description)]
        for index, entry in enumerate(files, 2):
            if entry['category'] != key:
                continue
            lines += ['', f'[node name="Sample{index:03}" type="AudioStreamPlayer" parent="Samples/{key}"]',
                      f'stream = ExtResource("{index}")', 'volume_db = -8.0']
            for field in ('title', 'notes', 'author', 'source', 'license', 'changes', 'batch', 'provider', 'prompt', 'domain'):
                lines.append(f'metadata/{field} = {quoted(entry.get(field, ""))}')
    SCENE.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    counts = Counter(entry['category'] for entry in files)
    print(f'{SCENE.relative_to(ROOT)}: {len(files)} samples')
    for key, title, _ in CATEGORIES:
        print(f'  {key}: {counts[key]}')


if __name__ == '__main__':
    main()
