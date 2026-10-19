# 免费 2D 像素特效素材库

本次下载 10 个原始包，合并 CodeManu 重复的 10 款后整理为 **9 组、164 款序列帧动画、12 张静态特效贴图、4 款像素化着色器**。Craftpix 的雷击按作者文件名拆出完整、持续、光点和局部四种取用形式；这些属于同一特效的变体。

打开 [中文动画索引](catalog.html)，支持名称/作者搜索、用途/素材包筛选、只看 CC0、动画暂停重播、背景切换与路径复制。页面离线可用，所有图像来自本地。统一 Godot 演示：打开 `res://assets/effect/pixel_vfx/demo/pixel_vfx_demo.tscn`，按 F6；有搜索、CC0 过滤、暂停、重播和路径复制。

## 在 Godot 中取用

1. 根据索引复制 `.tscn` 的 `res://` 路径，把对应场景拖入自己的 2D 场景；场景原点是特效锚点，已设置最近邻过滤。不要移动文件后继续使用旧路径。
2. 需要自己控制动画时，将相邻的 `.tres` 拖到 `AnimatedSprite2D.sprite_frames`，动画名均为 `default`。索引也能分别复制 SpriteFrames / PNG 路径。
3. 一次性动画默认不循环，但场景不会自动删除。可以连接 `animation_finished` 到 `queue_free()`；持续型特效按需要停止。索引和统一演示会为浏览自动重播单次动画。
4. 修改大小时优先使用整数倍率；推荐保持贴图无损压缩、关闭 mipmaps、使用 Nearest。PNG 颜色与透明度没有做替换，环境资源中有少量作者自带的水面背景。
5. **帧率来源已逐项标明**：Foozle 读取 Aseprite 原始时长；Warped 读取 GIF；PVFX 使用作者 manifest（20 FPS、帧坐标、循环标志、锚点）；Alenia PNG 保留 60 帧，按大多数作者 GIF 的 60 ms/帧设置。Craftpix / CodeManu 的帧率与部分循环模式是整理时的建议，可自行调整。CodeManu 保留每个 100×100 网格，包括末尾透明格。

Godot Asset Store 的 VFX 2D Free 是程序着色器补充，默认 `pixel_size=3`，只有 explosion / smoke / spark / fire 四款免费效果。在自己的脚本中可调用：

```gdscript
const PixelShaderVFX = preload("res://assets/effect/pixel_vfx/packs/godot_vfx/vfx_2d.gd")

func play_hit(at: Vector2) -> void:
    PixelShaderVFX.spawn(self, "explosion", at, {"pixel_size": 3})
```

## 素材包与来源

| 素材包 | 索引项数 | 现行许可 | 平台 / 获取方式 |
| --- | ---: | --- | --- |
| [Alenia · 像素环境特效](https://alenia-studios.itch.io/10-pixel-art-atmospheric-vfx-pack) | 40 | CC BY 4.0 + 附加条款 | itch.io |
| [Foozle · Lucifer RPG 特效](https://foozlecc.itch.io/lucifer-effects) | 19 | CC0 | itch.io |
| [PVFX Foundry · 战斗与交互](https://nerijs.itch.io/pvfx-foundry) | 44 | CC0（导出资产） | itch.io |
| [CodeManu · 魔法与爆发](https://opengameart.org/content/free-pixel-effects-pack) | 20 | CC0 | OpenGameArt.org |
| [Ansimuz · Warped 射击特效](https://opengameart.org/content/warped-shooting-fx) | 12 | CC0（作者 OGA 版本） | GameDev Market / OpenGameArt.org |
| [Kenney · Pixel Shmup 特效贴图](https://kenney.nl/assets/pixel-shmup) | 12 | CC0 | Kenney.nl |
| [Craftpix · 像素魔法](https://craftpix.net/freebies/free-pixel-magic-sprite-effects-pack/) | 15 | Craftpix 免费素材许可 | Craftpix.net / itch.io |
| [Craftpix · 像素爆炸](https://craftpix.net/freebies/11-free-pixel-art-explosion-sprites/) | 14 | Craftpix 免费素材许可 | Craftpix.net / itch.io |
| [Godot Store · VFX 2D Free](https://store.godotengine.org/asset/heyheythere/vfx-2d-free/) | 4 | CC BY 4.0 | Godot Asset Store |

Craftpix 本站下载要求登录，因此使用作者 Free Game Assets 的官方 itch.io 免费发行页；GameDev Market 的 Warped Shooting FX 使用作者在 OpenGameArt 发布的 CC0 版本。具体页面、许可链接、下载日期、原始 ZIP 哈希见 [SOURCE.json](SOURCE.json)、[catalog.json](catalog.json)。

**Alenia 当前版本与旧介绍不同**：现行下载为 40 款、每款 60 帧、320×180。许可是 “Alenia Studios Standard License (CC BY 4.0 + Additional Terms)”，要求署名 Alenia Studios / KXLT；它不是 CC0。原本 19200×180 超宽 PNG 已逐像素无损重排为 3200×1080 的 10×6 网格。

## 文件位置

| 目录 / 文件 | 用途 |
| --- | --- |
| `packs/<包名>/<用途>/` | 可直接取用的 PNG、SpriteFrames `.tres` 和独立 `.tscn` |
| `packs/craftpix_*/icons/` | 魔法 / 爆炸原包图标 |
| `packs/godot_vfx/` | 四款 Godot 程序着色器、VFX2D 脚本和场景 |
| `demo/` | Godot 原生统一演示 |
| `preview/` | 索引的静态代表帧，Godot 忽略此目录 |
| `licenses/` | 原始包内许可与中文核查说明，Godot 忽略此目录 |
| `source/` | 10 个完整原始 ZIP，包含 Aseprite、原始图像、PVFX packed 清单和未选入的附件；Godot 忽略此目录 |
| `CREDITS.md` | 可复制的署名文本，列明本地修改 |

CC0、CC BY 和站点专用许可分别标记。Alenia / Craftpix 的附加条款限制原始素材重新打包销售或分发；本地项目取用按各包许可执行，不应把本素材目录当作自己拥有版权的资源包再发布。完整许可见 [licenses/](licenses/)，必须署名项见 [CREDITS.md](CREDITS.md)。

下载与核查日期：2026-10-09。校验记录见 [VERIFICATION.json](VERIFICATION.json)。临时下载解压和测试文件不作为运行资产保存；素材不接入正式游戏入口。
