"""AI 音频资产规范：命名、风格、分类与混音目标都在这里定义。

改风格先改这个文件，生成、处理、分类、入清单都从这里读，避免四份规则各说各话。
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
AI_ROOT = ROOT / 'assets/audio/ai'
RAW_ROOT = AI_ROOT / '_raw'
INBOX_ROOT = AI_ROOT / 'inbox'
SAMPLES_ROOT = ROOT / 'assets/audio/library'

SAMPLE_RATE = 44100
CHANNELS = 1

# 分类键必须与 tools/audio/build_audio_library.py 的 CATEGORIES 对齐。
CATEGORY_INFO = {
    'ui': ('界面 · 交互', '按钮点击、悬停、确认、取消、报错、金币；要求短促、辨识度高、可连续触发'),
    'card': ('卡牌 · 抽打', '抽牌、洗牌、打出、升级；纸张质感为主，避免和战斗打击混淆'),
    'ai_combat': ('战斗 · 制作候选', '攻击、受击、爆炸、施法；AI 生成与本地制作候选均保留逐条来源'),
    'music': ('背景 · 音乐', '可循环 BGM，情绪与战斗/非战斗状态对应'),
    'ambience': ('背景 · 环境音', '可循环环境音，要求无明显接缝'),
}

LOOP_CATEGORIES = {'music', 'ambience'}

# 声音底色：像素中世纪奇幻 + 卡牌 roguelike，偏原声、干燥、近场。
STYLE = {
    'palette': 'medieval fantasy, handmade acoustic material, wood, leather, iron, parchment, stone',
    'positive': 'close-miked, dry, clean transient, game-ready one-shot, high detail',
    'negative': 'no reverb, no room tail, no music bed, no vocals, no crowd, no modern synth',
}

# 每类处理目标：峰值、最长时长、是否需要循环接缝。
TARGETS = {
    'ui': {'peak_dbfs': -1.5, 'max_seconds': 1.2, 'loop': False},
    'card': {'peak_dbfs': -1.5, 'max_seconds': 2.0, 'loop': False},
    'ai_combat': {'peak_dbfs': -1.0, 'max_seconds': 2.5, 'loop': False},
    'music': {'peak_dbfs': -1.0, 'max_seconds': 45.0, 'loop': True},
    'ambience': {'peak_dbfs': -1.5, 'max_seconds': 40.0, 'loop': True},
}

LOOP_BLEND_SECONDS = {'music': 2.0, 'ambience': 1.2}

# 许可标记：免费档只做内部试听，商用前必须复核。
LICENSES = {
    'elevenlabs': 'AI-ELEVENLABS',
    'procedural': 'CC0-1.0',
    'suno': 'AI-SUNO',
}

AUTHOR = {
    'elevenlabs': 'ElevenLabs（AI 生成）',
    'procedural': '项目程序合成（占位）',
    'suno': 'Suno（AI 生成）',
}

SOURCE = {
    'elevenlabs': 'https://elevenlabs.io/docs/overview/capabilities/sound-effects',
    'procedural': 'res://tools/audio/ai/procedural.py',
    'suno': 'https://suno.com',
}

PROMPT_LIMIT = 450


def build_prompt(item: dict) -> str:
    """把项目风格拼进单条提示词，并保证不超过接口长度。"""
    prompt = item['prompt'].strip().rstrip('.')
    text = f"{prompt}. {STYLE['palette']}. {STYLE['positive']}. {STYLE['negative']}."
    return text[:PROMPT_LIMIT]


def asset_name(item: dict, variant: int) -> str:
    """统一命名：sfx_/bgm_/amb_ 前缀 + 分类内唯一 id + 两位变体号。"""
    stem = item['id']
    if not stem.startswith(('sfx_', 'bgm_', 'amb_')):
        prefix = 'bgm' if item['category'] == 'music' else 'amb' if item['category'] == 'ambience' else 'sfx'
        stem = f'{prefix}_{stem}'
    return f'{stem}_v{variant:02d}'


def output_dir(provider: str, category: str) -> Path:
    return AI_ROOT / provider / category


def ensure_ignored_dirs() -> None:
    """原始素材和收件箱不参与 Godot 导入，避免把临时 WAV/MP3 打进包。"""
    for folder in (RAW_ROOT, INBOX_ROOT):
        folder.mkdir(parents=True, exist_ok=True)
        marker = folder / '.gdignore'
        if not marker.exists():
            marker.write_text('', encoding='utf-8')
