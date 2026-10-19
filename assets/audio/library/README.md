# 统一音效试听库

战斗 BGM 紧凑版修订：默认分类现为“战斗 BGM · 紧凑新版”，含 **144 BPM / 156 BPM** 两条本地编曲循环。
上方的 **Suno 战斗 A / B · 在线听** 按钮打开真实生成曲；该免费账号下载额度为 0，故在线曲没有冒充本地资源导入。
重建本次修订：`python tools/audio/ai/revise_battle_music.py`。

另新增 1 条真正通过 ElevenLabs 免费档生成并经官方 WAV 下载的挥剑音效；到“战斗 · 制作候选”中搜索 `ElevenLabs` 可试听。
生成模型在 2 秒内做了三次动作，已选择首个动作的 0.00–0.28 秒，原始文件、完整提示词、处理区间与生成记录一并保留。

2026-10-19 新增 **31 条本地声音设计试听**：剑、斧、格挡、弓箭、受击、火球、冰晶、落雷、治疗、卡牌、UI 各有 A/B 候选，另有森林/篝火环境循环、营地/战斗同主题 BGM 与转场示例。
打开场景后默认选择“本批试听 · 10月19日”，分类与搜索、收藏、循环按钮继续可用。
本批采用 CC0 录音分层和原创合成编曲，**没有调用 ElevenLabs/Suno**；平台提示词由 Codex 编写并保存在 `tools/audio/ai/batch_audition_20261019.json`。
完整说明见 `outputs/audio-audition-20261019/README.md`。一条命令重建此批音频与同一试听场景：`python tools/audio/ai/produce_audition.py`。

Godot 打开 `res://examples/scenes/audio_library.tscn`，按 **F6**。本场景是今后所有收集音效的固定试听入口。

当前收录 **386 条音效**，包括完整的 **Kenney Impact 130 条**、**Kenney RPG 52 条（含合集预览）**、原先的 127 条候选与其他 17 条对照素材。两包中与上一批相同的 13 条复用已有文件，并归入对应全集分类。覆盖刀剑碰撞、大锤挥摆候选、刀剑挥斩、弓箭射击、施法、普通受击、法术爆裂、雷击、火焰爆炸、格挡、死亡呼声和日常互动音效。

其中 23 条来自 AI 音频流水线（`tools/audio/ai/`）：UI 6 条、卡牌 4 条、AI 战斗候选 8 条、BGM 2 条、环境音 3 条。没有 API key 时这批是程序合成占位音（`CC0-1.0`），接入 ElevenLabs 后同分类会多出 `AI-ELEVENLABS` 版本用于 A/B。规则见 `docs/音频资产规范.md`。

左侧「Kenney · Impact 全集」与「Kenney · RPG 全集」可浏览两个目录内的所有音频。文件保持原样，保留原文件名及中文说明；可搜索 `Metal`、`heavy`、`knife` 或中文名称。

RPG 的 `Preview.ogg` 是整包串联预览。其原始 Vorbis 标签缺少等号，Godot 会显示标签格式警告；音频加载与播放已验证正常。

- 点击左侧分类，再点击音效行试听；切换会立即停止前一条。
- 空格／Esc 停止，R 重播；搜索框中可正常输入这些字符。
- 底部可调音量和音调，“原音调”还原为 1×。大锤可对比低音调的重破风候选。
- 底部“循环”开关可循环播放 BGM / 环境音，用来检查首尾接缝。
- 星标收藏，勾选“只看收藏”筛选。收藏、音量、音调保存到 `user://audio_library.cfg`，F6 再运行仍保留。
- “复制资源路径”便于记录选中的素材；“查看素材来源”打开原作品页。

重破风来自 Swishes Sound Pack，重斧来自真实武器录音，已在标题和说明中标明为大锤用途候选。人物包原作者未区分受伤／死亡的 19 条呼声也已明确注明，请试听后选用途。

这批是供选择的候选，游戏当前使用的映射仍在 `data/audio/combat_sounds.tres`。选定后将对应 AudioStream 拖入映射资源即可。

## 以后增加素材

所有新找到的音效必须放进这个试听场景，同时保存作者、来源和许可。不要再创建第二个音效试听场景。

推荐流程：将素材放进 `assets/audio/library/<来源包>/`，追加到 `manifest.json` 的 `files` 数组，再运行：

```text
python tools/audio/build_audio_library.py
```

AI 生成或程序合成的素材走另一条入口：先跑 `tools/audio/ai/pipeline.py`，由它处理音频并自动并入同一份 `manifest.json`，最后仍由 `build_audio_library.py` 生成同一个场景。

必填字段：`path`（完整 res:// 路径）、`title`、`category`、`notes`、`author`、`source`、`license`、`changes`、`sha256`。已有分类键见生成脚本 `CATEGORIES`；增加新分类时也更新此列表。新增来源还要更新 `CREDITS.md` 和打包署名文件。

生成器会校验文件 SHA256 和许可，合并上一批清单，再生成**同一个** `audio_library.tscn`。每条音效都是 `Samples/<分类>/Sample…` 下的 AudioStreamPlayer，可在 Godot Inspector 直接查看 stream 和来源元数据。

也可在场景中复制分类下的 AudioStreamPlayer、拖入 stream 并填写元数据，F6 会自动识别；但再次运行生成器前必须把它补进 manifest，避免覆盖手工添加的节点。

网上下载包与长录音保存在被忽略的 `.maintenance/audio-sources/`，原先的 127 条候选约 1.96 MB。两套本地 Kenney 原包已完整导入，新增文件约 1.96 MB；其中 13 条复用 `assets/audio/combat/` 的已有文件。素材文件在项目内，原目录移走后仍可正常试听。原文件路径、SHA256 和裁切信息见 `manifest.json`。

本地原包再次同步可运行（同一命令不会重复添加条目）：

```text
python tools/audio/import_kenney_packs.py --impact-dir "E:/MyGame/Game11/用的资源/kenney_impact-sounds" --rpg-dir "E:/MyGame/Game11/用的资源/kenney_rpg-audio" --collected-on 2026-10-11
```

`prepare_audio_library.py` 仅重新处理最初的候选，并保留后来导入的素材。

## 授权与发布

来源采用 CC0-1.0 和 CC-BY-3.0。署名与修改说明见 [CREDITS.md](CREDITS.md)。CC-BY 素材发布时需保留作者、来源、许可和修改说明，项目打包工具已自动纳入这些署名。上一批来源见 `../combat/CREDITS.md`。

## 验证

```text
python tools/maintenance/run_checks.py --checks audio-library combat-audio resources --label audio-library
```
