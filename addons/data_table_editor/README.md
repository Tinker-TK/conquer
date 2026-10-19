# 数据表格编辑器插件 (Data Table Editor)

一个 Godot 4 编辑器插件：用**类似 Excel 的表格**管理 `res://data` 下各数据类型文件夹里的 `.tres` 数据。
每一列对应一个参数（`@export` 字段），每一行对应一个数据文件。

---

## 功能

| 功能 | 说明 |
|---|---|
| 表格浏览 | 第一列是永久 ID，之后是文件与参数；按 ID 从小到大排列，文件列和前两个常用字段自动加宽 |
| 切换数据类型 | 顶部标签页对应 `data/` 下的每个子文件夹（`skilldata`、`statuseffectdata`、`unitdata` …），点击即可切换 |
| 新建数据 | 点「新建数据」输入文件名，生成一条新记录（**尚未写盘**） |
| 删除记录 | 选中后点「删除记录」，标记删除（**尚未删盘**） |
| 编辑脚本 | 每行「脚本」列显示该记录使用的 `.gd` 脚本，**双击**该列（或选中后点「✎ 脚本」/详情区「打开/编辑」）会在始终置顶的小窗口中打开源码 |
| 更换脚本 | 在详情区把 `.gd` 从 FileSystem 拖到「对应脚本」框；脚本必须继承当前类型的结构脚本，确认保存后才写入 `.tres` |
| 确认保存 | 点「确认保存」后才真正**写入/生成/删除本地文件**，符合“确认后再改本地”的要求 |
| 新增类型 | 点「＋新增类型」输入文件夹名，自动创建文件夹 + 结构脚本 |
| 刷新 | 重新从磁盘加载当前类型 |

所有编辑都在内存中缓冲，**只有点击「确认保存」才会修改本地文件**。

---

## 安装与启用

1. 插件已放在 `res://addons/data_table_editor/`。
2. 打开项目 → 菜单 **项目 → 项目设置 → 插件 (Plugins)**。
3. 勾选启用 **数据表格编辑器 (Data Table Editor)**。
4. 编辑器**右侧底部**会出现「数据表格编辑器」Dock 面板。

> 本项目已在 `project.godot` 的 `[editor_plugins]` 段登记该插件，重新打开项目即可自动启用。

---

## 使用方法

### 切换数据类型
顶部标签页列出 `res://data/` 下的所有子文件夹，点击小标题切换到对应文件夹的数据。

### 编辑数据
1. 在表格中点击一行，下方「编辑选中记录」区域会出现该记录每个参数对应的编辑控件：
   - `String` → 文本框
   - `int` / `float` → 数字框
   - `bool` → 勾选框
   - `@export_enum` / 脚本枚举（如 `Global.UnitType`）→ 下拉框
   - `PackedScene`（如 `projectile_scene`）→ 拖拽配置框：**直接把场景 `.tscn` 拖进来**，或点「…」选择、「×」清空
   - `Resource`（如 `on_hit_effect: StatusEffect`）→ 拖拽配置框：**直接把资源 `.tres` 拖进来**，或点「…」选择、「×」清空
   - `Array[int]`（如 `hit_frame`）→ 逗号分隔的整数文本框
   - `Array[SkillBase]`（如 `skills`）→ **资源列表编辑器**：像 Godot 原生检查器一样，
     直接从 FileSystem 面板**拖入 `.tres/.res` 资源**即可添加，每项可「↑/↓」调整顺序、「×」移除，
     也可点「＋ 添加」用文件选择器批量添加
2. 修改后表格对应单元格会立即更新，状态列显示「已修改」。

### 新建数据
点「新建数据」→ 输入文件名（如 `new_soldier`）→ 确定。会新增一行，自动取得当前类型下一个更大的永久 ID，状态为「新建」。
文件名会自动去重、去除非法字符。

### ID 与显示顺序

- 每条数据的第一列显示只读 ID，表格固定按 ID 从小到大排列；
- ID 保存在 `.tres` 的资源元数据中，不需要在业务数据脚本里增加 `@export` 字段；
- 每种数据类型独立编号，新建记录从 1 开始逐渐增大，删除记录后不会复用旧 ID；
- 旧数据首次加载时会按当前稳定顺序补发 ID，点击「确认保存」后永久写入。

### 编辑记录对应的脚本
表格「脚本」列显示**该行记录使用的 `.gd` 脚本文件名**（如 `Normal_attack.tres` → `normalattack.gd`，`soldier.tres` → `unitdata.gd`）；
选中记录后，下方「编辑选中记录」区域第一行也会显示**对应脚本**（含「打开/编辑」按钮）：

- **双击**表格中该行的「脚本」列单元格，或点详情区「打开/编辑」按钮（或工具栏「✎ 脚本」），
  会打开一个可缩放、始终位于 Godot 主编辑器前方的脚本编辑小窗口；
- 脚本会在一个**始终位于 Godot 主编辑器前方的独立小窗口**中打开；窗口是非模态的，可以一边查看数据表一边修改源码；
- 小窗口内为等宽字体的深色代码编辑区（带行号），可直接修改脚本源码，`Ctrl+S` 快速保存：
  - 源码使用较大的 18px 字号，路径、提示和按钮文字也同步放大；
  - 点「保存」立即写回该 `.gd` 文件，窗口会继续保持打开；
  - 有未保存修改时不能关闭或切换到其他脚本，避免误丢修改；
  - 若修改的是该类型**结构脚本**的 `@export` 字段，返回后点「刷新」即可更新表格列。

> 注意：同一类型的多条记录可能共用同一个脚本（如所有 unit 记录都使用 `unitdata.gd`），
> 修改后会影响所有使用该脚本的记录。

### 拖拽更换记录绑定的脚本

在详情区选中记录后，可以直接把 FileSystem 面板中的 `.gd` 拖到「对应脚本」输入框。插件会先检查继承关系：

- `unitdata` 记录只能绑定 `UnitData` 或其子类脚本；
- `skilldata` 记录可以绑定 `SkillBase` 或其子类脚本；
- 不兼容、丢失或空路径会被拒绝并恢复原路径。

更换操作只会把记录标记为「已修改」，点击「确认保存」后才真正更新 `.tres`。

### 保存 / 删除
- 点「确认保存」：把**新建**的记录生成 `.tres` 文件、把**已修改**的记录写回、把**已删除**的记录从磁盘删除，并刷新编辑器文件系统。
- 点「删除记录」：仅标记删除，点「确认保存」后才会真正删文件。

### 新增数据类型
点「＋新增类型」→ 输入文件夹名（如 `itemdata`）→ 会自动创建：
```
res://data/itemdata/
└── itemdata.gd      # class_name ItemData extends Resource，含一个示例 @export var id
```
之后即可在该类型下新建/编辑数据。

---

## 数据结构是怎么被识别的

插件自动扫描每个数据类型文件夹，把**含 `class_name` 且 `extends Resource` 的脚本**当作“结构脚本”，
它的所有 `@export var` 字段即表格的列：

- `data/units/unit_data.gd`（`class_name UnitData`）→ `unit_name`、`max_hp`、`unit_type`、`skills` …
- `data/skills/skillbase.gd`（`class_name SkillBase`）→ `skill_name`、`cooldown`、`hit_frame` …
- `data/statuseffectdata/statuseffect.gd`（`class_name StatusEffect`）→ 当前没有 `@export` 字段，表格暂无列；需要时在该脚本里加 `@export var` 即可自动出现对应列。

> 想增加/删除“列”，直接编辑对应结构脚本的 `@export` 字段，然后点「刷新」。

表格的界面骨架始终统一为「ID → 文件 → 当前类型的字段 → 脚本 → 状态」。其中业务字段会遵循当前数据类型的结构脚本：
`unitdata` 使用 `UnitData` 的单位字段，`skilldata` 使用 `SkillBase` 的技能字段。两者字段含义不同，不能用 `UnitData` 字段强行展示技能数据，否则会导致字段错配。

## 独立 ID

每个 `data/` 子文件夹都有自己的 ID 序列：`skilldata` 可为 `1-6`，`unitdata` 也独立从 `1` 开始。计数器保存在各自文件夹的隐藏 `.data_table_id_counter` 文件中。

如果项目曾使用旧版插件而得到跨文件夹连续的全局 ID，例如 `unitdata` 从 `7` 开始，插件会在首次打开该类型时按旧 ID 的先后顺序迁移为 `1、2、3……`；点击「确认保存」即可将迁移后的 ID 和该类型计数器写入磁盘。

---

## 额外属性（重要）

有些 `.tres` 里存在**脚本未声明**的字段（例如 `data/units/archer.tres` 的 `attack_cd`、`wizard.tres` 的 `projectile_speed`）。
Godot 原生加载/保存会静默丢弃这些字段。本插件在保存时会把它们**原样保留**，并在详情面板中以「额外属性」列出：

- 数值 / 字符串 / 布尔等简单类型可编辑；
- 数组、资源引用等复杂类型以「只读」方式原样保留。

> 建议把这些字段补进结构脚本的 `@export var`，即可作为正式列编辑。

---

## 文件结构

```
addons/data_table_editor/
├── plugin.cfg                    # 插件清单
├── data_table_editor.gd          # EditorPlugin 入口：挂载 Dock
├── core.gd                       # 纯逻辑：schema 反射 / 记录加载保存 / 额外属性保留 / 新建类型 / 拖拽解析
└── ui/
    ├── data_table_dock.gd        # Dock 面板 UI 与交互
    ├── resource_list_editor.gd   # 资源数组拖拽编辑器（Array[Resource]）
    └── resource_drop_box.gd      # 单个资源/场景字段的拖拽配置框
```

在代码里也可以复用核心逻辑（`core.gd` 是 `class_name DataTableCore` 的静态工具类）：

```gdscript
var Core = preload("res://addons/data_table_editor/core.gd")
var types = Core.list_types()
var schema = Core.detect_schema("unitdata")
var records = Core.list_records("unitdata")
```
