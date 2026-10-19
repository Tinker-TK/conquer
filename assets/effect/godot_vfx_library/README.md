# Godot VFX Library 项目资产包

从 [haowg/GODOT-VFX-LIBRARY](https://github.com/haowg/GODOT-VFX-LIBRARY) 下载整理，位于 `res://assets/effect/godot_vfx_library/`。

实际收录 **30 个粒子场景、24 个着色器、4 张粒子贴图**，另保留两个管理器、中文交互演示、原始说明、预览图和完整源码 ZIP。
上游说明的“35+”是效果/变体口径；本包按实际文件数量计数。

## 查找资源

- 双击 **[catalog.html](catalog.html)**：按中文名称、英文文件名、分类或参数搜索，点击“复制 Godot 路径”。
- **[CATALOG.md](CATALOG.md)**：全部资源的中文清单。
- **[catalog.json](catalog.json)**：供后续工具读取的路径、类型、参数和依赖清单。
- Godot 文件系统中的 `effects/` 和 `shaders/` 已按用途分类；英文文件名保留，方便与上游 API 对照。

| 目录 | 内容 |
| --- | --- |
| `effects/combat/` | 战斗粒子、血液、治疗、能量、护盾与连击 |
| `effects/movement/` | 冲刺、跳跃与滑墙 |
| `effects/magic/` | 魔法光环、毒雾、火球、冰霜、闪电与传送召唤 |
| `effects/environment/` | 火焰、烟雾、落叶、火花、灰烬及破碎飞溅 |
| `effects/weather/` | 雨、雪与瀑布水雾 |
| `shaders/status/` | 角色状态、受击、颜色、溶解及描边 |
| `shaders/screen/` | 模糊、抖动、雾、灰度、色差及暗角 |
| `shaders/environment/` | 水面、倒影、热浪与星空 |
| `shaders/magic/` | 能量屏障与传送门 |
| `textures/` | 四张原始粒子贴图 |
| `scripts/` | `vfx.gd`、`env_vfx.gd` 管理器 |
| `demo/` | F6 可运行的中文演示场景 |
| `docs/` | 上游原始文档与预览图（已排除 Godot 扫描） |
| `source/` | 原始仓库完整 ZIP（已排除 Godot 扫描） |

## 在项目中预览

打开 **[demo/vfx_demo.tscn](demo/vfx_demo.tscn)**，按 **F6**。
左侧选择粒子，右键点击场景生成；选择着色器后点 ✓ 应用、点 × 移除。Esc 退出。
演示展示上游的 34 个粒子/元素变体选项和 17 个着色器选项；全部 24 个着色器均在分类索引中。
管理器放在演示场景内，因此预览无需启用插件或添加全局单例。

## 取用粒子场景

将对应 `.tscn` 拖入自己的场景，可在 Inspector 中修改粒子数量、寿命、颜色和发射范围。
单次粒子需要触发 `restart()`；直接实例化不会自动删除，请连接完成信号或由技能生命周期管理。
例如在 Node2D 脚本中生成血液飞溅：

```gdscript
const BLOOD = preload("res://assets/effect/godot_vfx_library/effects/combat/blood_splash.tscn")

func play_blood(at: Vector2) -> void:
    var particles := BLOOD.instantiate() as CPUParticles2D
    add_child(particles)
    particles.global_position = at
    particles.finished.connect(particles.queue_free, CONNECT_ONE_SHOT)
    particles.restart()
```

`lightning_chain.tscn` 的根节点是 Node2D，需要逐个重启子节点 CPUParticles2D，或调用 `env_vfx.gd` 的 `spawn_lightning_chain()`。
`magic_aura.tscn` 使用 GPUParticles2D；其余粒子场景以 CPUParticles2D 为主。
持续粒子应挂在目标节点下，并随目标/技能结束清理。

## 取用着色器

在 Sprite2D、ColorRect 等 CanvasItem 的 **Material** 中新建 ShaderMaterial，把 `.gdshader` 拖到 Shader 字段。
在 **Shader Parameters** 中调节参数；参数名已列入 `catalog.json`，图文索引支持搜索。
`dissolve`、`heat_distortion`、`water`、`starSky` 等需要噪声或星点贴图参数；按清单和源码中的 uniform 设置。
为不同角色分别调整参数时，应复制材质或启用 Local to Scene，避免共享材质同时变化。

## 可选管理器 API

在自己的场景添加两个 Node，分别挂 `scripts/vfx.gd` 和 `scripts/env_vfx.gd`，即可通过节点调用 API，例如 `$VFX.spawn_blood_splash(position)`。
若后续需要上游的全局 `VFX`、`EnvVFX` 调用方式，可在项目设置 → 全局/Autoload 中手动添加这两个脚本。
接口参数见 [原始 API 文档](docs/upstream/API_REFERENCE.md)；其中 `addons/vfx_library/` 是上游路径，本项目应使用索引中的新路径。
本次只整理资产与演示，没有修改 `project.godot` 或接入正式战斗逻辑。

## 来源与许可

- 来源仓库：https://github.com/haowg/GODOT-VFX-LIBRARY
- 分支与提交：`main` / `6e8fc84ef426f82f747cd540823e1d5e1fdc563a`
- 上游提交时间：`2026-01-25T08:35:11Z`
- 下载日期：2026-10-09（Asia/Hong_Kong）
- 原始 ZIP SHA-256：`c7434f35f2927bf55a442a2addf1ce2188551ef225f7f04082cf4a1dab0cf914`
- 许可：**MIT**；再分发时保留 [LICENSE](LICENSE) 和相应版权声明。
- `starSky.gdshader` 保留原作者 Brian Smith 的 MIT 署名。

资源路径已迁移到本资产目录；演示使用场景内管理器、中文界面和适配本项目的字号。
上游原件完整保存在 `source/upstream.zip`；下载与文件校验记录见 [SOURCE.json](SOURCE.json)。
