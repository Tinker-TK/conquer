# AI 音频流水线

2026-10-19：新增 `produce_audition.py`，一条命令制作 31 条项目试听素材并重建原有 Godot 试听场景。
配方与自编提示词在 `batch_audition_20261019.json`；产物标记为 `local_design`，采用 CC0 录音分层与原创合成编曲，
明确区别于 ElevenLabs/Suno 的模型生成结果。详见 `outputs/audio-audition-20261019/README.md`。

从提示词到 Godot 试听场景的一整条链路：**批量生成 → 自动裁剪/归一/转 OGG → 分类质检 → 并入清单 → 重建 F6 场景**。

规范（命名、风格、混音、授权）见 [`docs/音频资产规范.md`](../../../docs/音频资产规范.md)。所有成品最终进同一个试听场景 `res://examples/scenes/audio_library.tscn`，不另建第二个场景。

## 一次性准备

```text
python -m pip install numpy soundfile
```

ElevenLabs 的 key 三选一（不要写进仓库）：

1. 环境变量 `ELEVENLABS_API_KEY`
2. 文件 `tools/audio/ai/.elevenlabs_key`（已 gitignore）
3. 文件 `~/.elevenlabs/api_key`

没有 key 也能跑：`--provider procedural` 会离线合成占位音，链路和正式生成完全一致。

## 常用命令

```text
# 端到端（离线占位）
python tools/audio/ai/pipeline.py --provider procedural

# 只看 ElevenLabs 会花多少额度
python tools/audio/ai/generate.py --provider elevenlabs --dry-run
python tools/audio/ai/generate.py --check

# 正式生成（建议先跑 --only 试两条）
python tools/audio/ai/generate.py --provider elevenlabs --only ui_click_primary
python tools/audio/ai/pipeline.py --provider elevenlabs

# 分步执行
python tools/audio/ai/process.py --provider elevenlabs --force
python tools/audio/ai/classify.py --provider elevenlabs --strict
python tools/audio/ai/library.py --provider elevenlabs
python tools/audio/build_audio_library.py

# Suno 手动出稿接入
python tools/audio/ai/ingest_suno.py --list
python tools/audio/ai/ingest_suno.py
python tools/audio/ai/pipeline.py --provider suno --skip-generate
```

## 文件结构

```text
tools/audio/ai/
  spec.py            命名、风格、分类、混音目标（改规则先改这里）
  batch_sfx.json     18 条 SFX 提示词
  batch_music.json   5 条 BGM + 4 条环境音提示词（Suno 用）
  procedural.py      离线占位音合成
  elevenlabs.py      ElevenLabs 客户端（标准库，带缓存与重试）
  generate.py        生成原始文件 + sidecar
  dsp.py             裁剪、重采样、归一、循环接缝、特征提取
  process.py         原始 → OGG
  classify.py        质检 + 自动标签 + index.json
  library.py         并入 manifest.json
  pipeline.py        串起全流程
  ingest_suno.py     手动下载文件归档

assets/audio/ai/
  _raw/<provider>/   原始文件与 sidecar（gitignore）
  inbox/suno/        Suno 下载收件箱（gitignore）
  <provider>/<category>/*.ogg + *.ogg.json
```

## 免费档额度

- ElevenLabs 免费档约 1 万 credits/月；指定时长时按 **40 credits/秒** 计。18 条 SFX 各 1 个变体约 700～900 credits，够跑十几轮。
- 生成结果按 id 缓存，重复运行不会重复扣费；要重跑加 `--force`。
- Suno 免费档不能商用，只用来出 BGM/环境音的试听稿。

## 排错

| 现象 | 处理 |
| --- | --- |
| `HTTP 401` | key 无效或没读到；用 `generate.py --check` 确认 |
| `HTTP 402` | 额度不足；换 `--only` 少生成几条，或等下一周期 |
| `HTTP 429` | 触发限流；客户端会退避重试，仍有问题就降低并发（脚本本身串行） |
| Godot 里新文件 404 | 先跑 `Godot --headless --path . --import`，再重开场景 |
| 试听库里没有新条目 | 确认 `library.py` 已把条目并入 `manifest.json`，并重跑 `build_audio_library.py` |

## 关于 MCP

这台机器上的 DSH 自带 MCP 客户端（`@deepseek-ai/dsh-mcp-client`），但当前没有配置任何 MCP 服务器。本流水线批量调用官方 REST 接口，不需要 MCP；MCP 只适合在对话里做单次交互式生成。等有 key、确实需要交互式调用时，再在 `cordis.patch.yml` 里挂一个 ElevenLabs MCP 服务器即可。
