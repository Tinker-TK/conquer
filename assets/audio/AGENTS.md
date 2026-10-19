# 音效素材约定

用户要求今后所有收集到的音效都加入同一个 Godot 试听场景：
`res://examples/scenes/audio_library.tscn`。打开该场景按 F6，可以分类点击试听。

新增音效时保留作者、原始作品链接、许可及修改说明；更新
`assets/audio/library/manifest.json`、`CREDITS.md`，然后运行
`python tools/audio/build_audio_library.py` 更新同一场景，不另建试听场景。

免费不代表无需署名；CC-BY 素材须将署名纳入打包说明。
素材来源、分类键及具体流程见 `assets/audio/library/README.md`。

AI 生成或程序合成的音频走 `tools/audio/ai/pipeline.py`，成品同样并入这份清单和这同一个试听场景；
命名、风格、混音与授权规则见 `docs/音频资产规范.md`。
