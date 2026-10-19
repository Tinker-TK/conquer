# 事件插画与浅色叙事页

全部成品由内置 `image_gen.imagegen` 制作，绘画笔触参考项目的 `assets/ui/comic_menu/fantasy-battle.png`。统一采用明亮水粉、大色块、选择性细节与柔和边缘；每个主题使用不同构图、主体和辅助色。

| 事件 | 成品 | 构图与识别重点 |
| --- | --- | --- |
| 遗忘的圣匣 | `forgotten-reliquary.png` | 俯视神殿祭坛，象牙银色六角圣匣与紫色晶体 |
| 旅人的药剂 | `wandering-alchemist.png` | 药箱旁的递药近景，玫红药瓶与炼金师的手 |
| 岔路的援军 | `crossroads-recruitment.png` | 招募帐篷内的低视角，递出战术卷轴的新兵与矮人 |
| 篝火 | `campfire.png` | 围炉俯视，橙色火焰、取暖双手与淡紫色阴影 |
| 旧版遗弃兵营 | `abandoned-camp.png` | 无人的褪色帐篷、空地长影、补给木箱与少量金币 |
| 遗物宝箱（关闭） | `treasure-closed.png` | 独立木箱特写，深胡桃木、铁箍、铜环和红色蜡封 |
| 遗物宝箱（开启） | `treasure-open.png` | 同一机位与箱体，打开的平盖和一件金色护符 |

实际提示词和每张图的参考输入记录在 `prompts.json`。宝箱开启图仅编辑本组关闭图，保持切换前后构图一致。旧稿不作为游戏引用资源。

## 显示与兼容

- 四个正式事件在 `data/events/*.tres` 中直接引用各自的 PNG，篝火与援军各用独立插画。
- `scripts/events/event_illustrations.gd` 按事件选项解析旧 SVG 快照；旧版篝火/援军即使共用 `recruit_camp.svg`，也会分别显示正确插画。显式自定义插图优先。
- 旧版遗弃兵营、宝箱配方在 `scripts/map/fixed_map_config.gd` 中补齐插图；地图内容、奖励数量与领取规则不变。
- `scripts/map/event_panel.gd` 使用左插画、右标题/剧情/双行横条选项；`event_ui_style.gd` 只控制事件页，不修改其他页面的公共主题。
- `shaders/event_illustration_focus.gdshader` 保留插画中央叙事主体，外围降低饱和度并透明淡入明亮背景，不使用黑色暗角。原 PNG 完整保留，不烘焙 UI、文字或蒙版。
- 剧情关键名词自动着色，方括号按字面显示；选项的第一行是动作，第二行说明收益。文字装饰不接管鼠标，按钮、键盘焦点和奖励会话继续使用原有逻辑。

事件与宝箱回归分别为 `tests/event_system_test.gd`、`tests/treasure_node_test.gd`；篝火使用现有共用运行器的 `--campfire-regression`。事件编辑器继续使用同一个实际事件面板预览。

本次完整游戏 HUD 下的七种状态截图保存于 `.maintenance/event-illustrations/`，运行时布局报告为该目录的 `layout.json`。所有验收使用隔离用户目录。
