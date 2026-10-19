# 第三方素材来源与授权

本仓库的代码、配置与文档为作者原创；美术与音效使用了第三方素材或 AI 生成内容，来源如下。
**这些素材的版权归各自作者所有，不在本仓库的版权范围内。**

## 美术

| 位置 | 来源 | 说明 |
|---|---|---|
| `assets/cards/illustrations/` | AI 生成（内置 image_gen） | 项目作者设计提示词并筛选，生成后作为游戏正式资源 |
| `assets/ui/comic_menu/`、`assets/ui/events/`、`assets/ui_redrawn/` | AI 生成 + 作者重绘/拼版 | 主菜单插画、事件插图、UI 元素；提示词与过程记录在对应 README |
| `assets/characters/` | Tiny Swords（Pixel Frog）、Tiny RPG Character Asset Pack | 第三方免费像素素材包，按原素材包授权在项目内使用；未经授权不可单独再分发素材本身 |
| `assets/effect/pixel_vfx/` | 免费像素特效包（CC0） | 序列帧特效与贴图，索引见该目录 README |
| `assets/effect/godot_vfx_library/` | Godot VFX Library（MIT） | 粒子场景与着色器，许可证见该目录 LICENSE |

## 音频

| 位置 | 来源 | 说明 |
|---|---|---|
| `assets/audio/library/`、`assets/audio/combat/` | Kenney（CC0） | Impact / RPG 等音效包 |
| `assets/audio/ai/` | ElevenLabs 免费档 AI 生成 | 按 ElevenLabs 条款，发布时需署名 [elevenlabs.io](https://elevenlabs.io) |
| `assets/audio/bgm/` 中的紧奏版战斗曲 | 作者本地原创 / 程序合成（CC0-1.0） | 源脚本在 `tools/audio/ai/` |

## 字体

`assets/fonts/` 内为开源或系统字体，具体许可见各字体目录说明；未复制商业字体文件。

## 未包含的内容

`assets/effect/eslabong_vfx/`（ESLABONG 特效素材）**未包含在本仓库中**：该素材包附带的最终用户许可协议明确禁止再分发与创作衍生作品，因此不适合公开分发。
依赖它的 `examples/scenes/eslabong_vfx_demo.tscn` 一并排除；主游戏不依赖该目录。自行持有该素材并希望本地预览时，把素材放回原路径即可。

## 使用建议

如果你要基于本仓库二次开发：

- 代码与配置：联系作者获得许可。
- 第三方素材：请回到原始素材包获取授权，不要直接从本仓库复制。
- AI 生成内容：遵守对应平台（如 image_gen、ElevenLabs）的使用条款。
