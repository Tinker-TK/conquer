# UI 像素组件接入

公共样式入口是 `scripts/ui/pixel_ui_style.gd`，场景编辑器中的战斗按钮主题是 `themes/pixel_ui_theme.tres`。

| 素材 | 用途 |
| --- | --- |
| `assets/ui/Banners/Carved_9Slides.png` | 事件正文、战斗奖励、幕间总结和商店说明底板；中间平铺，边角保留原尺寸 |
| `assets/ui/Banners/Carved_3Slides.png` | 事件底部提示、战斗名称和牌堆查看说明 |
| `assets/ui/Buttons/*_3Slides.png` | 普通横向按钮，包含蓝色、红色及悬停、按下和禁用状态 |
| `assets/ui/Buttons/*_9Slides.png` | 选牌共用整排底板、卡牌强化的较高按钮，以及进化面板 |
| `assets/ui/Buttons/Button_Blue.png` 等小尺寸版本 | 顶部倍速、设置步进按钮和单位详情关闭按钮 |
| `assets/ui/Ribbons/Ribbon_*_3Slides.png` | 事件标题、卡牌分组、战斗回合、回合胜负及奖励标题 |
| `assets/ui/Icons/Regular_01.png` | 单位详情关闭图标，裁掉透明边距后显示；倍速按钮使用完整文字，避免数字与“倍”错位 |
| `assets/ui/Pointers/01.png`、`02.png` | 原生鼠标光标和战场框选四角；沿用原热点和交互 |

正文在浅色底板上使用深色文字；丝带标题使用带描边的浅色文字。蓝色按钮承载普通操作，红色按钮用于开打、删牌确认和重置；选卡通过金色纹理持续标记选择。

按钮样式仅裁掉素材底部 8 像素透明留白，以不对称的上下内容边距对齐可见底板；按下和禁用素材的表面更低，使用对应的文字位置。丝带保留完整图像，通过内容边距对齐标题。场景主题采用相同参数，编辑器预览与运行时一致。奖励行的独立图标和文字也跟随底板按压位移。

接入按钮时先设置尺寸或最小尺寸，再调用 `UI.button(button, font_size)`。高度超过 110 的按钮采用九宫格，普通横条采用三段纹理；尺寸尚未由容器分配的小按钮可传第四个参数 `true`，显式选择紧凑样式。`UI.select(button, selected)` 更新选卡状态，`UI.caption(label, color, font_size)` 添加丝带。

## 选牌界面

`scripts/ui/card_choice_button.gd` 为事件两组五选一与战斗胜利三选一提供共同的选牌样式。每排共用一块完整蓝色底板，单张卡牌的按钮背景透明。悬停卡面或费用徽章时，卡面在 0.14 秒内放大至原尺寸的 135%，移开后恢复；底板和其他卡牌不移动，底板空隙不触发放大。事件中已选择的卡牌保留金色外框；左键选择和兵种牌右键详情沿用原会话。

选牌截图及实际鼠标检查记录位于 `.maintenance/card-choice-row/`，包含 1920×1080、1280×720 的正常、悬停与选中画面。每种分辨率检查 198 项，覆盖悬停命中、还原、固定布局、选择、领取和右键详情。事件、战斗奖励及卡牌详情检查见 `.maintenance/checks/card-choice-row-input/`，事件工坊布局检查见 `.maintenance/checks/card-choice-row-final/`。

## 单位详情栏

`scripts/ui/unit_inspector.gd` 使用羊皮纸主底板、蓝色标题丝带和黄色分组丝带。属性直接排在主底板上，技能说明和状态悬停说明使用浅色羊皮纸；头像直接显示图像。只读信息不使用按钮底板，关闭按钮保留按钮样式。浅色底板上的增减值分别使用深绿和深红；状态角标继续使用适合深色图标框的亮色。

`scripts/ui/unit_detail_icon.gd` 使用平面细框承载状态与技能图标，保留真实冷却的方形遮罩。生命条使用连续细边框和 `UI Elements/Bars/SmallBar_Fill.png` 填充，不再将带有深色内区的端帽叠在填充上。缺少专用头像时优先显示卡牌插图，敌人则回退到裁掉透明留白的场上动画帧。

开打按钮下方不再保留上一轮扣血组成说明。结算动画中的标题和伤害说明由原生 `VBoxContainer`、`Label` 按丝带的内容边距居中，避免手工字体基线造成错位。

攻击、防御、最大生命、附毒和死亡爆炸的 Buff 悬停提示只显示当前汇总值，例如“最大生命提升：+10”。战场图标、单位详情和卡牌预览不再追加来源、循环次数或期限明细；底层独立来源及到期逻辑、详情图标下的期限角标继续保留。相关回归结果见 `.maintenance/checks/buff-summary/`，实机悬停、叠加与到期截图见 `.maintenance/buff-summary/`。

单位详情的最新截图位于 `.maintenance/ui-info-polish/`，包含己方、敌方、卡牌预览、滚动后的技能、空血/半血/满血，以及胜利/失败/平局横幅，分别导出 1920×1080 与 1280×720。详情交互与冷却渲染测试共 61 项通过；详情交互、卡牌预览和回合结算 4 组检查结果见 `.maintenance/checks/ui-info-polish/results.json`，两种分辨率的横幅边界与居中检查见 `.maintenance/ui-info-polish/preview-results.json`。测试夹具明确使用士兵斩击分支，以保证两项冷却技能和无基础剑矢状态的断言不受默认分支变化影响。

验证限制：独立的旧 `status` 测试仍假设士兵开局无状态，与现有基础剑矢配置冲突；此次未修改该测试或战斗状态逻辑，原日志保留于 `.maintenance/checks/unit-details-skin/status.log`。

事件插图、卡面、已重绘的顶部 HUD、能量球和书本图标继续使用现有素材。装饰不拦截鼠标，牌堆查看、领奖、训练和暂停仍由各自原有会话处理。

## 验证

- 独立交互检查：`.maintenance/checks/ui-refresh-independent/results.json`，7 组通过。
- 游戏流程检查：`.maintenance/checks/ui-refresh-integration/results.json`，7 组通过，覆盖事件、宝箱、战斗奖励、商店、暂停设置、回合结算和三幕流程。
- 实际渲染截图：`.maintenance/ui-refresh/` 中的 `event.png`、`event-choices.png`、`event-result.png`、`battle.png`、`rewards.png`、`settings.png`。
- 倍速测试另有已有的持续效果切档断言失败；修改前文件的对照结果位于 `.maintenance/checks/ui-refresh-baseline/`，本次 UI 不修改倍速或战斗计算。
