# 批量特效导入插件 (Batch Effect Importer)

一个 Godot 4 编辑器插件：**批量导入特效素材 → 批量重命名 → 自动生成 SpriteFrames → 导入到 AnimatedSprite2D**。

支持两种素材形式：

| 模式 | 说明 |
|---|---|
| 序列帧文件夹 | 一个文件夹里放多张图片（`1.png`、`2.png`…），每张图 = 动画的一帧 |
| 精灵表 (Sprite Sheet) | 一张大图（如 `effect_01.png`），按 列×行 网格自动拆分成多帧 |

---

## 安装

1. 把 `addons/batch_effect_importer/` 整个文件夹复制到你的项目 `addons/` 目录下
   （本仓库已经安装好，位于 `res://addons/batch_effect_importer/`）。
2. 打开项目 → 菜单 **项目 → 项目设置 → 插件 (Plugins)**。
3. 找到 **批量特效导入 (Batch Effect Importer)**，勾选 **启用 (Enable)**。
4. 编辑器会在 **右侧底部** 出现一个名为 **批量特效导入** 的 Dock 面板。

> 本项目已把插件写入 `project.godot` 的 `[editor_plugins]` 段，重新打开项目即可自动启用。

---

## 使用方法

### ① 选择素材

- **序列帧模式**：填 `res://` 下的文件夹路径（如 `res://assets/effect`），点「浏览」选择。
  插件会递归扫描该目录下所有 `png/jpg/webp/bmp/tga/svg/avif` 图片，并按数字自然排序
  （`2.png` 会排在 `10.png` 前面）。
- **精灵表模式**：选择一张图片，填好 **列数 / 行数**（可选勾选「自定义单帧尺寸」手动指定每帧宽高）。
  - 默认：整张表拆成一个动画（`列数×行数` 帧）。
  - 勾选 **「每行是一个动画」**：**每一行单独成为一个动画**，行数 = 动画数量，列数 = 每个动画的帧数。
    例如 13 列 × 9 行 → 导出 **9 个动画**，每个 13 帧。
  - 勾选后会出现一个多行文本框，**每行填一个动画名，从上到下对应每一行**：
    ```
    run
    jump
    attack
    ...
    ```
    留空的行会自动命名为 `前缀_01`、`前缀_02`…（前缀取自「批量重命名」的前缀框，为空则取图片文件名）。

### ② 批量重命名（可选）

在「批量重命名」区设置：

- **前缀**：如 `explosion` → 生成 `explosion_001.png`
- **起始**：序号起始值，默认 1
- **位数**：序号补零位数，默认 3 → `001`
- **后缀**：可选，如 `_fx` → `explosion_001_fx.png`

点「② 批量重命名」即可批量改名。改名后自动刷新编辑器文件系统，旧 `.import`
元数据会被清理，引擎会为新文件名重新导入。

> ⚠️ 重命名是直接改磁盘文件，**不可撤销**。建议先复制一份素材再试。

### ③ 导入到 AnimatedSprite2D

点「③ 导入到 AnimatedSprite2D」：

1. 自动构建 `SpriteFrames` 动画（动画名默认取文件夹名 / 精灵表文件名，可手动改；可设 FPS 与是否循环）。
2. 勾选「保存 SpriteFrames 为 .tres 资源」时，会把动画资源保存到指定目录
   （默认 `res://assets/animations/generated/`，如 `res://assets/animations/generated/explosion.tres`）。
3. 三种输出方式：
   - **创建独立特效场景 (.tscn)**：生成 `res://assets/animations/generated/explosion.tscn`
     （根节点 Node2D + 子节点 AnimatedSprite2D），并在编辑器中自动打开预览。
   - **插入到当前打开的场景**：新建一个 AnimatedSprite2D，添加为当前场景根节点
     （或选中节点）的子节点。
   - **导入到当前选中的 AnimatedSprite2D（合并动画）**：把新动画**合并进场景树中
     已选中的那个 AnimatedSprite2D 节点**（不会新建节点），保留该节点原有动画，
     同名动画会被覆盖。适合把多组特效导入到同一个角色节点上。

---

## 文件结构（怎么做一个插件）

```
addons/batch_effect_importer/
├── plugin.cfg                    # 插件清单: 名称/描述/入口脚本
├── batch_effect_importer.gd      # EditorPlugin 入口: 把 Dock 挂到编辑器
├── importer_core.gd              # 核心逻辑: 扫描/重命名/构建 SpriteFrames/建场景
└── ui/
    └── batch_effect_dock.gd      # Dock 面板 UI 与按钮事件
```

插件骨架三要素：

1. **`plugin.cfg`** — 声明插件名与入口脚本 `script="batch_effect_importer.gd"`。
2. **`EditorPlugin` 子类** — `_enter_tree()` 里 `add_control_to_dock(...)` 把自定义面板
   挂到编辑器 Dock；`_exit_tree()` 里 `remove_control_from_docks(...)` 清理。
3. **面板脚本** — 普通 `Control` 子类（这里是 `VBoxContainer` + `@tool`），在编辑器里运行，
   可以调用 `EditorInterface`（拿当前场景、刷新文件系统、操作选中节点等）。

## 在代码里复用核心逻辑

`importer_core.gd` 是纯逻辑脚本（不依赖编辑器 UI），也可以在游戏运行时用：

```gdscript
var Core = preload("res://addons/batch_effect_importer/importer_core.gd")

# 把一组图片变成 SpriteFrames
var frames: SpriteFrames = Core.build_sprite_frames_from_files(
    ["res://fx/f1.png", "res://fx/f2.png"], "explosion", 12.0, true)

# 把精灵表按网格拆帧
var frames2: SpriteFrames = Core.build_sprite_frames_from_sheet(
    "res://assets/effect/effect_01.png", "purple_tornado", 5, 4, 20.0, true)
```

主要接口：

| 函数 | 作用 |
|---|---|
| `scan_image_files(dir, recursive)` | 扫描目录下所有图片（自然排序） |
| `rename_files_batch(paths, prefix, start, digits, suffix)` | 批量重命名文件 |
| `build_sprite_frames_from_files(paths, anim, fps, loop)` | 图片序列 → SpriteFrames |
| `build_sprite_frames_from_sheet(path, anim, cols, rows, fps, loop, frame_size)` | 精灵表 → SpriteFrames |
| `build_sprite_frames_from_sheet_rows(path, anim_names, cols, rows, fps, loop, frame_size, prefix)` | 精灵表按行 → 每行一个动画 |
| `merge_sprite_frames(target, src)` | 把 src 动画合并进 target（同名覆盖） |
| `make_animated_sprite_2d(frames, anim, name)` | 创建 AnimatedSprite2D 节点 |
| `make_effect_scene(frames, anim, name)` | 生成独立特效 PackedScene |

## 与现有 effect.tscn 的关系

本项目的 `assets/animations/generated/effect.tscn` 是手写的 192px × 5列 × 4行 精灵表拆分（`purple_tornado` 动画）。
用本插件的 **精灵表模式** 选择 `res://assets/effect/effect_01.png`、填 列数 5 / 行数 4 / FPS 20，
即可一键复现同样的 SpriteFrames，并生成独立场景或插入到当前场景。
