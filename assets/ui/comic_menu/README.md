# 主菜单：明亮手绘魔法征途

主场景为 `res://scenes/ui/main_ui.tscn`，F5 启动项目，F6 单独预览。标题、四行菜单、底部键位提示和左右斜分区沿用原 1920×1080 设计坐标；窄窗口等比例居中。

当前右侧主视觉为原创山谷讨伐战：持矛骑士、战锤矮人与披斗篷法师迎战晶角巨兽。只参考明亮手绘幻想的氛围与色彩，重新设计角色、怪物和构图；不采用鸟兽石桥场景。根据反馈，远景、草地、岩石、装备与队友简化为大色块，把视觉重心集中在骑士长矛与巨兽头部的对峙。左侧使用浅羊皮地图、赤陶红战旗与古金纹章。旧猫耳立绘与漫画资产保留为历史素材，不再作为默认主视觉。

四个入口依次为：**开始征途、继续征途、设置、退出**。按钮没有数字编号。继续征途占原路线工坊的位置，不再额外放置右下角按钮；无存档时第二行仍显示但不可点击，方向键与手柄跳过该项。有存档时恢复原有保存进度。主菜单不再建立路线工坊或导入文件对话框，地图工坊的“应用到游戏”与 RunManager 路线加载保持可用。

鼠标悬停同步键盘焦点，上下键或手柄选项，Enter 确认，Esc 关闭设置。返回菜单后会重新读取存档是否存在。设置继续共用游戏的视频和音频设置页。

- `scripts/ui/main_ui.gd`：布局、存档入口、设置、输入和切场。
- `scripts/ui/fantasy_menu_button.gd`：无编号的纹章按钮及焦点高亮。
- `scripts/ui/fantasy_menu_style.gd`：菜单独立配色与字体；不修改战斗、设置和加载主题。
- `assets/ui/comic_menu/fantasy-battle-extended.png`：当前手绘战斗插画，向左续绘以补齐斜分界；固定显示高度并右对齐，原有主体的大小与位置保持不变。
- `assets/ui/comic_menu/fantasy-battle.png`：保留的方形原画。
- `assets/ui/comic_menu/fantasy-battle-extended-prompt.md`：扩图提示词与原画保留方式。
- `assets/ui/comic_menu/fantasy-battle-prompt.md`：内置 imagegen 生成与简化提示词。
- `assets/ui/comic_menu/fantasy-backdrop.svg`：浅色羊皮地图分区与边框。
- `assets/ui/comic_menu/fantasy-ornaments.svg`：标题旗帜、王冠纹章、菜单标题牌与王命纸牌。

选中主场景 MainUI 可调整 `game_title`、`chinese_title` 和 `character_art`。英文优先 Georgia，中文优先宋体类系统衬线字体，均有后备字体；没有复制系统字体文件。

`tests/comic_ui_test.gd` 检查固定菜单坐标、无存档禁用与键盘跳过、有存档确认恢复、设置焦点、窗口比例、防双击及完整地图/战斗切场。图形模式导出 `.maintenance/comic_ui/main_menu.png` 和 `main_menu_no_save.png`。`settings_pause_test.gd` 检查真实战斗保存退出后从第二行继续。`map_direct_apply_test.gd`、`three_act_test.gd` 保留地图工坊与三幕路线回归。

检查使用项目内隔离的 APPDATA/LOCALAPPDATA，不操作玩家实际存档。加载仍由 `SceneTransition` 管理，正常短切场约 0.5 秒，使用真实资源加载进度。
