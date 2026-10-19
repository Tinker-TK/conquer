# 音效试听库素材来源与署名

## ElevenLabs 首条在线生成音效（2026-10-19）

`assets/audio/ai/elevenlabs/ai_combat/sfx_combat_sword_tight_v01.ogg` 来自用户 ElevenLabs 免费账号真实生成的四个候选中的 #1。
通过页面官方 WAV 48kHz 菜单下载，原文件 SHA256 和完整提示词保留在 `_raw/elevenlabs/` sidecar；
生成记录：[ElevenLabs History](https://elevenlabs.io/app/sound-effects/history?id=12Z5bcjfcmNIKPeuQ2Vc)。
作者 ElevenLabs（AI 生成），许可标记 **AI-ELEVENLABS**；免费档仅作非商业试听，发布时需署名 `elevenlabs.io`。
修改：裁剪首尾静音、单声道、44.1kHz、峰值归一与短淡入淡出，转换 OGG。

## 紧凑版战斗曲（2026-10-19 反馈修订）

`bgm_battle_tight_advance_v01.ogg`（144 BPM）、`bgm_battle_tight_assault_v01.ogg`（156 BPM）
为项目本地原创编曲与程序合成，CC0-1.0。制作源码：`tools/audio/ai/revise_battle_music.py`。
采用密集短弦乐音型、战鼓、切分重音和短铜管重拍；保留原有舒缓版作对比。

Suno 免费账号实际生成的两条《Steel and Stone》只保存在线试听链接，未下载、未转换成本地资源：
[A](https://suno.com/song/8c8f32eb-1055-438b-bde9-a6311cca6e89)、
[B](https://suno.com/song/a937f1a7-cc32-4e59-947a-34b188a4a77c)。
来源：Suno v6-mini / 当前用户账号生成；许可标记 AI-SUNO，仅非商业试听。
下载对话框显示 Free / Downloads 0，原始截图保存在 `outputs/audio-audition-20261019/suno-download-status.png`。
提示词及本地音频分析见 `tools/audio/ai/batch_battle_tight_20261019.json` 与 `outputs/audio-audition-20261019/battle_tight_report.json`。

## 2026-10-19 本地声音设计试听批次

31 条试听素材位于 `assets/audio/ai/local_design/`。由 Codex 按项目内容编写提示词，
在本地进行 CC0 实录素材分层、原创程序合成与原创编曲；这批没有调用 ElevenLabs/Suno，
也没有将文字提示词交给音频模型。许可沿用项目原创素材的 CC0-1.0。

分层素材作者：Ben Jaszczak & Brian Nelson / Still North Media（中世纪武器）、
artisticdude（Swishes）、Independent.nu / qubodup 投稿（身体受击）、Kenney（RPG / Impact）、
EZduzziteh（Explosions）。每条成品的 `.ogg.json` 保存实际使用的原作品链接、作者、许可与 SHA256。
制作配方和完整提示词见 `tools/audio/ai/batch_audition_20261019.json` 与
`tools/audio/ai/produce_audition.py`；质检数据见 `outputs/audio-audition-20261019/quality_report.json`。

修改：裁剪静音、声道相消检查、变速与分层、原创合成、峰值控制、44.1kHz 单声道 OGG 输出；
环境音和音乐保持完整循环长度，战斗与营地共用 96 BPM / D 小调主题。

免费候选采用 CC0-1.0 或 CC-BY-3.0。CC-BY 素材使用、修改及发布时需保留作者、来源、许可与修改说明。
CC0: https://creativecommons.org/publicdomain/zero/1.0/
CC-BY-3.0: https://creativecommons.org/licenses/by/3.0/

本次修改：部分长录音裁切为单次动作，保留原声道，重采样、调整峰值、边界淡入淡出，转为 OGG。MP3 呼声保持原文件。

| 目录 | 作品 | 作者 | 许可 |
| --- | --- | --- | --- |
| ../soundscape | 征途拨弦音乐、原野风声、雨天雨声 | 项目原创程序合成，源代码见 tools/audio/generate_settings_soundscape.py | CC0-1.0 |
| medieval-textures | [Medieval Weapon Textures](https://opengameart.org/content/medieval-sound-effects-weapon-textures) | Ben Jaszczak & Brian Nelson / Still North Media | CC0-1.0 |
| medieval-impacts | [Medieval Weapon Impacts](https://opengameart.org/content/medieval-sound-effects-weapon-impacts) | Ben Jaszczak & Brian Nelson / Still North Media | CC0-1.0 |
| swishes | [Swishes Sound Pack](https://opengameart.org/content/swishes-sound-pack) | artisticdude | CC0-1.0 |
| body-hits | [37 hits/punches](https://opengameart.org/content/37-hitspunches) | Independent.nu (submitted by qubodup) | CC0-1.0 |
| wet-impacts | [8 wet squish, slurp impacts](https://opengameart.org/content/8-wet-squish-slurp-impacts) | Independent.nu (submitted by qubodup) | CC0-1.0 |
| magic-spell | [Magic Spell SFX](https://opengameart.org/content/magic-spell-sfx) | JaggedStone | CC0-1.0 |
| qubodup-spells | [Ice & Electricity Magic](https://opengameart.org/content/ice-electricity-magic) | Iwan 'qubodup' Gabovitch | CC-BY-3.0 |
| human-voices | [11 male human pain/death sounds](https://opengameart.org/content/11-male-human-paindeath-sounds) | Michel Baradari | CC-BY-3.0 |
| badre-death | [Hurt / Death sound effect for character](https://opengameart.org/content/hurt-death-sound-effect-for-character) | Badre-Eddine | CC0-1.0 |
| fire-spell | [Spell 4 (fire)](https://opengameart.org/content/spell-4-fire) | Bart K. | CC-BY-3.0 |
| explosions | [Explosions](https://opengameart.org/content/explosions-4) | EZduzziteh | CC0-1.0 |
| rubberduck-sfx2 | [100 CC0 SFX #2](https://opengameart.org/content/100-cc0-sfx-2) | rubberduck | CC0-1.0 |
| kenney-impact-full | [Impact Sounds](https://kenney.nl/assets/impact-sounds) | Kenney | CC0-1.0 |
| kenney-rpg-full | [RPG Audio](https://kenney.nl/assets/rpg-audio) | Kenney | CC0-1.0 |
| ai/procedural | AI 流水线占位音 23 条（UI、卡牌、战斗、BGM、环境音） | 项目程序合成，源码见 tools/audio/ai/procedural.py | CC0-1.0 |

Ice and Electricity Magic by Iwan 'qubodup' Gabovitch https://opengameart.org/users/qubodup

完整逐条原文件、裁切时间、修改、SHA256 见 manifest.json。上一批素材署名见 ../combat/CREDITS.md。

本地 Kenney 全集导入：两个目录内全部音频（含 RPG Preview.ogg），原文件保持不变。与上一批相同的 13 条复用已有文件。原包许可保存在 licenses/kenney-*-full.txt。

## AI 生成素材

AI 音频流水线（`tools/audio/ai/`）产出的条目用独立许可标记，不与 CC0/CC-BY 混用：

| 标记 | 含义 | 商用状态 |
| --- | --- | --- |
| `CC0-1.0` | 程序合成占位音，项目原创 | 可直接使用 |
| `AI-ELEVENLABS` | ElevenLabs 免费档生成 | 仅内部试听；商用前需付费订阅并复核条款 |
| `AI-SUNO` | Suno 免费档生成 | 仅内部试听，免费档禁止商用 |

每条成品的 prompt、provider、生成时间、处理参数与 SHA256 保存在同目录的 `*.ogg.json`，作为来源证据链。正式发行前必须把 `AI-*` 条目替换为已授权素材或补齐商用授权。
