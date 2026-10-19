# 单位基础战斗音效

30 个网上收集的原始 CC0 短音效，分为 21 个播放类别，已接入正式战场和怪物测试场。
来源与作者见 [CREDITS.md](CREDITS.md)，逐文件校验见 `manifest.json`。

在 Godot 打开 `scenes/testing/monster_test.tscn`，按 F6，布置双方单位后开始战斗即可试听。
打开 `data/audio/combat_sounds.tres` 可替换变体和调整战斗音量。
接入位置、匹配规则、参数与回归命令见 [单位战斗音效说明](../../../docs/单位战斗音效说明.md)。

原始 ZIP 放在 `.maintenance/audio-sources/`，不进入游戏导出。
`tools/audio/prepare_combat_assets.py` 可从这些包重新提取选定文件并生成资源、来源清单。
