# 回归测试

冒险图鉴：`--checks encyclopedia settings-pause settings-controls items-ui relics potion-catalog` 验证五类配置完整性、每页三条且不重复、完整技能与长文滚动、实际左右纸面点击和页内按钮、满版动画边界、搜索/目录、暂停嵌套、退出清理与只读状态。追加 `--graphical --checks encyclopedia` 保存各类纸面、翻动中的书本、暂停菜单与清理后的地图截图，见 [说明](../docs/冒险图鉴说明.md)。

数值框架：`--checks balance-framework` 验证11单位目标三围、16张降费牌、5张加强牌、多段扣防、首领控制递减、三幕36份波次、品质概率、开局赠品、药水带和存档；`--graphical --checks balance-ui` 以真实鼠标验证开局三选一、满格替换与放弃并保存截图。`--checks route-events random-map` 覆盖现有路线投放。见[数值接入说明](../docs/数值设计/数值框架接入说明.md)。

遗物流派：`--checks relics` / `--relics-regression` 检查66件有效遗物、十个流派的正式战斗入口、触发上限、真实死亡与复活的原牌唯一性、增伤上限、奖励与商店、存档往返。`--graphical --checks relics` 额外检查图鉴并保存三选一和图鉴截图。F6入口为 `examples/scenes/relic_builds_demo.tscn`，在根节点 Inspector 的 Relic Build 选择流派。见[实装说明](../docs/遗物流派实装说明.md)。

药水：`--checks potion-catalog potion-effects`检查40瓶配方与逐瓶真实施放，包括场地槽和即时连喝、状态期限、零费次数、召唤、复活、免死、非法目标不扣瓶与限量存档。F6入口为`examples/scenes/potion_effects_demo.tscn`，见[药水实现说明](../docs/药水效果实现说明.md)。

新增23张卡牌：`--checks expanded-cards` 覆盖基础/强化、插画、状态/护盾/击退、选牌、复活、战旗/陷阱、临时进化、变阵及回合经济；图形运行共用入口追加`--expanded-cards-regression --capture`导出真实卡面、检索与战场设施。见[说明](../docs/新增23张卡牌说明.md)。

卡牌强化：`--checks card-enhancement card-description tactical-cards strategy-cards undying-army campfire` 验证27张效果/能力牌的完整强化表、篝火入口、同名牌隔离、存档与临时进化还原，并覆盖零费出牌、精英策反、泥潭三回合、阵亡加费、吸血30%及战友5费阈值。

启动、单位初始化与日志保护：`--checks unit-lifecycle game_session_smoke tactical-cards round-damage`。测试入口在自动加载完成后再加载领域类型；旧 `--script tests/game_session_smoke.gd` 入口保留为安全启动壳。未知 `--xxx-regression` 参数以非零退出码结束。

`run_checks.py` 每项默认限制真实时长 60 秒、合计日志 16 MiB；`--timeout`、`--max-log-mb` 可覆盖。遇到引擎/断言错误立即终止该子进程，文件和控制台日志都受监控，不在内存中无限捕获。结果的 `status=partial` 与 `skipped` 会明确标出 headless 下未执行的 GPU 部分；这只表示对应逻辑完成，不能当作视觉通过。指定 `--graphical --checks rain-floors snow-floors` 可单独运行其图形分支。

开发预览可用 `python tools/maintenance/run_game.py --out <项目外会话目录> -- --no-mcp-server`，默认 30 分钟真实时长、16 MiB 日志上限；调试时按需覆盖。省略 `--out` 会生成独立的 `.maintenance/sessions/` 会话目录。进程保护测试：`python -B -m unittest discover -s tools/maintenance -p "test_*.py"`。

弓箭手穿刺射击：`--checks archer-piercing` 使用正式训练和真实 `monster_test` 自动攻击动画，验证基础1.0倍率/最多2人、强化1.2倍率/沿途全体、射线外敌军与友军排除、每箭每人只命中一次，以及快速箭矢整段检测和按路径先后消耗上限。见 [说明](../docs/弓箭手穿刺射击说明.md)。

独立测试场牧师治疗：`--checks monster-test-priest` 在真实 `monster_test.tscn` 中保持牧师全程自动行为开启，覆盖普通/强化治疗、自疗、满血时的基础与强化差异、最高生命友军转盾及护盾罩，要求没有 `battle_owner` 标记也能正常运行且没有引擎报错。

牧师护盾与咏唱：`--checks priest-chant-shield` 验证比例选友军与自身、强化满血选最高当前生命、1.4治疗及溢出护盾、原版护盾罩、各类伤害吸收和清理，以及牧师0.3/0.7秒、巫师0.5/1.5秒咏唱、进度条、异常状态打断后完整CD、真实动画命中、暂停与三倍速。图形模式追加 `--priest-chant-shield-regression --capture` 保存实际截图，见 [说明](../docs/牧师护盾与咏唱说明.md)。

巫师霜暴：`--checks wizard-frost-storm` 验证真实训练、出牌、攻击动画帧、3+x/5+x颗冰晶、固定10点单体伤害、8秒冷却、150范围减速100及到期/死亡/阶段清理；对比完整配方确认直接复用实验室的“冰霜·风暴”，仅修改数量和已播放的前摇。图形模式追加 `--wizard-frost-storm-regression --capture`，导出基础弹雨、强化弹雨和命中效果。见 [说明](../docs/巫师霜暴说明.md)。

Eslabong 特效库：`--checks eslabong-vfx` 逐项检查 432 条目录、全部恢复脚本、场景实例化与回收；图形检查使用 `tests/eslabong_vfx_preview.gd`（搜索、空结果、暂停、九宫格和代表效果截图）及 `tests/eslabong_vfx_render_audit.gd`（全量四个时间点渲染），输出在 `.maintenance/eslabong/`。入口与取用见 [特效库说明](../assets/effect/eslabong_vfx/README.md)。

卡牌说明：`--checks card-description` 覆盖61张正式卡牌和14张示例牌的基础、强化卡面及悬停，检查当前效果数值、技能替换、同名牌隔离、持续期限、多次强化、存档恢复和文字完整显示。完整文案见 [卡牌效果说明](../docs/卡牌效果说明.md)。

飞行单位：`--checks flying` 验证大黄蜂、小恶魔、巨型蝙蝠和蝙蝠无导航直行、跨越地形墙和水面、三层升降、逐层 64 像素／0.1 秒、眩晕中断恢复、死亡、索敌与真实自动攻击，并在正式第5关关闭所有楼梯后往返。图形模式共用入口追加 `--flying-preview`，逐像素比较四种单位升降中的身体与强制前景画面，确认不被岩壁遮住、暂停冻结；24 张截图保存在 `.maintenance/checks/flying-visual/`。

多层征召：`--checks deployment-floors navigation-deploy combat-card` 验证左半边四层部署、统一左右分界、重叠时选择上层、相机缩放与拖放坐标、碰撞/导航/绘制楼层、随机征召、无效落点不扣费，以及正式第5关的左侧高地。

第108关高地通行：`python tools/maintenance/run_checks.py --checks level108-navigation wave-spawn-floors`，使用真实 `level_108_1` 第2回合，验证士兵／骑士和全部六只敌人自动索敌、实际接敌与双方命中；桥柱使用关卡独立碰撞变体，保留24像素导航留白。四处一二层切换与四座桥的双向、连续跨桥移动案例位于 `tests/fixtures/battle_007_movement.json`。

第108关跨层追击：`--checks level108-cross-floor` 验证地形保存重载后四处坡道端点仍有效，真实士兵逐个往返四处坡道，并使用 `level_108_1` 第5回合的四只一层近战怪主动上楼、实际命中固定在二层的目标。图形模式执行 `tests/level108_cross_floor_test.gd -- --capture --no-mcp-server` 保存 `.maintenance/battle007-round5/round5-upstairs.png`。

四层地形与高地增伤：`--checks floors counter tactical-cards` 验证同层碰撞与避让、桥下通行、楼梯寻路、射程内全部攻击跨层命中，以及高打低每层增加10%最终伤害、无楼梯索敌、真实近战/远程动画、射手退场和穿透逐目标结算。`floors` 还验证 `level_107_1` 的全部五波及循环首波：出生点在配置楼层内、路线可达、全部怪物自动移动并实际命中，且不会从错误楼层瞬移到导航边缘；三处楼梯从不同方向上下时连续行走、不被岩壁遮身，离开或瞬移后恢复绘制层，桥下普通经过不抬高绘制。详见 [四层地形与桥梁配置说明](../docs/四层地形与桥梁配置说明.md)。

坡道遮挡的 GPU 像素回归：图形模式运行 `--fixed-fps 60 --script tests/card_framework_test_runner.gd -- --no-mcp-server --stair-visual-regression`。测试完整 `level_107_1` 首波四只怪物的真实自动行进，对同一暂停帧比较实际身体与强制前景参考的像素，覆盖脚底尚未进入台阶但头部/武器已经碰到坡道的过程。天气在此测试中关闭以便逐像素比较；失败截图和结果保存到 `.maintenance/stair-visual-render/`。

书本翻页：以图形模式运行 `tests/book_flip_render_test.tscn -- --no-mcp-server`，验证真实鼠标拖动/回弹、双向翻页和落页连续性、空白过渡页、整本书挤压/平移/缩放与回弹、暂停/续播、首尾边界、自动换向与失焦清理；追加 `--capture-book-loop` 导出往返帧。见 [说明](../docs/书本翻页效果说明.md)。

配置缓存与开局性能：`--checks config-cache fixed-map map-direct-apply three-act events comic-ui` 覆盖同秒修改/损坏/修复路线、外部资源依赖更新、缓存返回值隔离、旧本局快照保留与短切场。运行时只在菜单读取路线时检查配置内容，不在帧循环中扫描；主菜单点击开始才创建新局，F6 和脚本测试保留独立初始化。

关卡 UI 编辑器预览：`--checks level-ui-preview` 验证隐藏期间保存内容完全一致、运行实例的 UI 可见状态、原有隐藏控件、单独编辑 UI，以及战斗模板和继承关卡。图形模式运行 `tests/level_ui_preview_test.gd -- --no-mcp-server --capture`，另行检查隐藏、恢复与离开场景后的实际渲染像素。

单位卡牌施放光带：`python tools/maintenance/run_checks.py --checks card-motion combat-card tactical-cards` 覆盖真实拖放起点、快速绕行半圈后吸收、己方金色／敌方紫色、移动目标与相机缩放、随机施放、并发实例、策反配色及目标退场后的清理。默认飞行 0.5 秒、尾迹吸收 0.15 秒。图形模式运行共用入口追加 `--card-motion-regression --card-motion-preview`，导出 `.maintenance/card-motion-unit-ribbon-teams.png`；`pixel_soul_ribbon_render_test.tscn` 另行验证两种环绕配色与完整吸收过程的 GPU 渲染。节奏和半径在 CardUI/Hand 的“单位施放光带”分组调整。

技能强化等级数组：`--checks skill-unlock game-config-editor` 验证 `[0]` 在强化后移除、`[0,1]` 仅在等级0和1生效、`[1]` 与 `[2]` 接替、非连续数组和空数组；覆盖真实训练、征召、优先级、动画命中、直接施法拦截、防守反击、卡牌与场上单位详情、资源保存回读和旧整数存档兼容。配置表覆盖数组编辑、非法输入、正式保存校验与 HTML 导出导入；图形运行 `tests/game_config_editor_test.gd -- --no-mcp-server --capture` 导出 `.maintenance/skill-level-array-config.png`。

暂停与设置：`--checks settings-pause` 覆盖顶部按钮、模态拦截、嵌套暂停、视频应用、音频总线、后台静音、设置落盘、独立强化卡牌存档及保存退出/继续流程。图形模式运行 `tests/settings_pause_test.gd` 会导出实际界面截图，详见 [说明](../docs/暂停菜单与设置.md)。

战斗倍速：`python tools/maintenance/run_checks.py --checks battle-speed` 通过顶部按钮的真实点击选择原速、2 倍和 3 倍，并用相同阵容与种子完成近战、远程、冲刺、召唤和持续效果战斗；逐项对比胜负、幸存生命、回合扣血以及全部命中、死亡、召唤事件，覆盖途中切档和暂停。以图形模式运行共用入口并追加 `--battle-speed-regression --capture`，导出按钮截图；对比明细保存在 `.maintenance/battle-speed-comparison.json`。战斗逻辑、技能冷却及单位动画统一按固定物理步推进，地图、部署和奖励阶段保持正常速度。

单位战斗音效：`--combat-audio-regression` 检查真实动画帧、箭矢命中、闪避/死亡、限频和池上限、阶段/场景清理，并捕获实际非静音混音。见 [说明](../docs/单位战斗音效说明.md)。

雷云药水：`--thunder-cloud-potion-regression` 检查真实战场选点、固定区域伤害、暂停、跨三回合与清理；有显示运行追加 `--capture-thunder-cloud` 保存战场截图。详见 [说明](../docs/雷云药水说明.md)。

像素雷击乌云的 GPU 与预览交互检查：以图形模式运行 `tests/pixel_thunder_cloud_render_test.tscn`，覆盖云团翻滚、局部闪光、落雷同步、实例隔离与预览控制，详见 [说明](../docs/像素雷击乌云说明.md)。

像素落雷的 GPU 与预览交互检查：以图形模式运行 `tests/pixel_lightning_render_test.tscn`，覆盖单雷、树状分支、亮片、火花、余光、时间轴与单帧控制，详见 [说明](../docs/像素落雷说明.md)。

保留有实际断言的行为、资源与 GPU 检查。纯截图脚本、重复启动包装和旧基地测试别名已归档，见 [项目清理记录](../docs/项目清理记录.md)。配置工具的导出入口位于 `addons/game_config_editor/config_catalog_export.gd`。

完整逻辑回归：

```text
python tools/maintenance/run_checks.py --godot <Godot控制台程序>
python tools/maintenance/audit_paths.py
```

日志默认写到 `.maintenance/checks/current/`，再次运行覆盖同名日志，不需要每次增加新文件夹。运行器要求检查完成标记、退出码和干净错误日志；独立用户目录隔离游戏存档、设置与工具草稿。支持 `--list`、`--checks cards battle shop campfire` 和 `--out <项目外日志目录>`。

单项 Node 测试共用一个入口，例如：

```text
Godot --headless --path . --script res://tests/card_framework_test_runner.gd -- --no-mcp-server --shop-regression
Godot --headless --path . --script res://tests/card_framework_test_runner.gd -- --no-mcp-server --campfire-regression
```

地图工坊直接应用路线：`python tools/maintenance/run_checks.py --checks map-direct-apply map-editor fixed-map --label map-direct-apply`。检查实际“应用到游戏”按钮、未提交输入、原始草稿保留、无效路线和写入失败保护、项目路线优先加载、真实新征途地图/事件/奖励，以及更新路线后的继续存档和内置地图兼容。应用目标使用隔离用户目录，不改写项目正式路线。图形运行 `res://tests/map_direct_apply_test.gd -- --no-mcp-server --capture` 可导出工坊按钮及游戏地图截图。

三幕征途：`python tools/maintenance/run_checks.py --checks three-act map-direct-apply map-editor fixed-map settings-pause --label three-act`。通过真实工坊幕选择、Boss 战斗和奖励继续按钮验证第一幕→第二幕→第三幕→整局胜利，覆盖跨幕资源及强化保留、同名节点进度与商店缓存清理、第二幕保存/继续、后续幕快照、下一幕缺失/损坏及补齐重试、旧存档迁移和坏幕编号拦截。目标 JSON 与存档均使用隔离用户目录。图形运行 `res://tests/three_act_test.gd -- --no-mcp-server --capture` 导出 `.maintenance/three-act-workshop.png`、`three-act-act-2.png` 和 `three-act-victory.png`。

单位详情面板：`python tools/maintenance/run_checks.py --checks inspector unit-details status camera combat-card` 检查双击打开、实时属性增减、状态悬停、叠层与到期更新、滚动和真实技能冷却。以图形模式运行上述共用入口，追加 `--unit-details-regression --capture`，会导出 `.maintenance/unit-details-panel.png` 和五个冷却阶段截图，并检查遮罩四象限的实际像素。

兵种牌右键详情：`python tools/maintenance/run_checks.py --checks card-unit-details` 检查奖励拿牌、准备/交锋手牌及暂停中的牌堆查看；右键不领取、不扣费、不创建单位，左键选择与原生拖放继续有效。卡牌详情复用单位面板，展示训练和永久强化后的出场数值、配置技能与状态悬停说明；关闭、卡牌离场或原界面隐藏时自动清理。图形运行共用入口追加 `--card-unit-details-regression --capture`，导出 `.maintenance/card-unit-details-reward.png` 和 `.maintenance/card-unit-details-hand.png`。

鼠标与框选：`python tools/maintenance/run_checks.py --checks pointer camera inspector card-unit-details` 检查真实拖框、0.75～2 倍镜头投影、只选己方、整队实际导航落点、重复右键替换、UI 拦截和阶段清理。图形运行共用入口追加 `--pointer-regression --capture`，导出 `.maintenance/pointer-selection.png`、`pointer-click-start.png`、`pointer-click-mid.png`，供核对九宫格四角和下降收束效果；原生系统光标不包含在视口截图中。

GPU 测试需用图形模式运行 `rain_surface_render_test.tscn`、`rain_particles_render_test.tscn`、`snow_surface_render_test.tscn`、`dynamic_river_render_test.tscn`、`pixel_flame_render_test.tscn`、`pixel_soul_ribbon_render_test.tscn`。逻辑回归不会将 headless 下跳过的 GPU 检查算为通过。部分行为测试仍保留可选截图参数，截图写入 `.maintenance/`。

多层积水：`--checks rain rain-floors floors` 验证四层遮罩、子瓦片层、非默认楼层 Z 间隔、切层倒影、脚步水花、天气切换与桥下河流。图形模式运行 `tests/rain_floors_test.tscn -- --no-mcp-server`，进一步对比四层真实像素、单位和悬崖遮挡，确认倒影不会串层，并导出 `.maintenance/rain-floors/battle-005-fixed.png` 与关闭高层积水时的对比图。

多层积雪：`--checks snow snow-floors` 验证四层独立遮罩、子瓦片与附属楼梯、非默认楼层 Z 间隔、堆积/融化、开关/预设、雨雪切换与刷新清理。图形模式运行 `tests/snow_floors_test.tscn -- --no-mcp-server`，进一步验证四层实际积雪像素、单位/悬崖遮挡和正式第 5 关，并导出 `.maintenance/snow-floors/battle-005-fixed.png` 与关闭高层积雪时的对比图。

导航烘焙输出属于维护工具，入口已移动到 `tools/maintenance/navigation_bake.gd`；不会写回地图，按需运行。它不属于默认行为回归。
# 音效试听库回归

战斗状态特效：`--checks status-effects` 验证固定每秒流血、睡眠唤醒、禁疗、控制重叠、随机导航、技能与投射物附加状态、原有策反/虚弱动画及暂停和清理。配置见 `docs/状态特效配置.md`；图形模式追加 `--status-effects-regression --capture` 导出九种效果截图。

Eslabong 技能组合：`python tools/maintenance/run_checks.py --checks eslabong-skills eslabong-vfx --label eslabong-skills` 验证505套组合的引用、唯一ID、投石前摇／弧线／抵达后命中／眩晕顺序、结束回收、暂停、技能／素材切换与九宫格。图形模式运行 `eslabong_skills_preview.gd` 截取双单位界面；附加 `--all-skills` 分批渲染全部组合，截图在 `outputs/eslabong-skill-review-20261017/`。

火焰／冰霜波浪：图形模式运行 `eslabong_wave_render_test.gd`，实际渲染完整波浪、单独弹片、单热扭曲与9层重叠，检测大面积纯黑像素和技能区域中的火焰暖色／冰霜蓝色，避免标签颜色使检查误通过；`--wave-ui` 核对完整展示界面。截图和像素统计在 `outputs/eslabong-skill-review-20261017/waves/`。

`python tools/maintenance/run_checks.py --checks audio-library combat-audio resources --label audio-library`

`audio-library` 验证全部素材、14 类播放按钮的真实混音输出、两套 Kenney 包的完整数量、音频路径不重复、切换停止前一条、音量／音调调节、搜索、收藏筛选和再次 F6 的设置持久化。

士兵远近普攻：`--checks sword-arrow` 验证现有篝火训练入口、单牌强化隔离、300 射程边界、完整动画发箭与伤害、弓箭手同款箭矢、近战切换、共享普攻冷却、撤回再部署、跨场与存档恢复。详见 [剑矢强化说明](../docs/剑矢强化说明.md)。

骑士上场抽牌：`--checks knight-draw` 验证普通抽1张／强化抽3张、原牌隔离、部署失败和重复调用、准备与交锋阶段、免费部署、收回再部署、单位复制／直接生成不触发、禁抽、牌不足、弃牌堆洗回、遗物抽牌计数及存档恢复。

通用庇护光环（显式测试配置，圣殿骑士已替换为嘲讽）：`--checks protection-aura` 验证技能配置、真实训练部署、范围边界、重叠、来源死亡/收回、狂化组合、复制加成隔离、存档恢复和独立怪物测试场。共用入口追加 `--protection-aura-preview` 导出实际魔法光环截图。配置说明见 [庇护光环](../docs/圣殿骑士庇护光环.md)。

旧通用连续命中被动（显式配置，正式剑士已替换为七伤）：`--checks consecutive-attack game-config-editor` 验证真实普攻、三连击和六连刺伤害递增、换目标首击清零、闪避与毒伤、临时属性隔离、狂化和庇护组合、死亡收回、强化等级与测试场。配置说明见 [剑士被动](../docs/剑士连续攻击被动.md)。

怪物测试场：`--checks monster-test` 覆盖按各兵种上限生成的强化等级按钮、零次／双次强化配置、两次训练的属性累计与二级技能解锁、上限拦截及数据隔离、强化士兵在 `attack_03` 第7帧真实发箭及近战切换、战斗中强化增兵、清空和再次开战。图形运行共用入口追加 `--monster-test-preview`，保存 `.maintenance/monster-test-preview.png` 和使用独立双次强化配置的 `.maintenance/monster-test-upgrade-levels-preview.png`。


士兵强化分支：`--checks soldier-branches` 验证训练/进化显式选择、单牌与共享资源隔离、存档、真实飞弹命中及3名士兵各加3攻击、实验室“减速”持续标记、350范围斩击优先标记、原Wild Boar Gore突进、每敌一次与目标死亡成长、战斗结束清理。图形模式追加 `--capture` 输出 `.maintenance/soldier-branches/`。详见 [士兵斩击与飞弹说明](../docs/士兵斩击与飞弹说明.md)。

装甲斧手：`--checks armored-axeman` 验证基础/强化同时保留劈砍与旋转、真实动画击退200像素、地形/通用实体撞墙停止及强化2秒眩晕、实验室奥术祈祷、自身护盾双刀快照与多单位隔离、无盾再施法、动作中断、死亡/阶段停止、真实多层墙体与隔层排除。图形追加 `--capture` 输出 `.maintenance/armored-axeman/`。

骑士血影斩击：`--checks knight-blood` 验证基础10秒/强化8秒、真实动画叠层、每层固定1点/秒、各骑士回血归属、实际扣血与护盾/致死边界、6秒手动边界及真实自动时钟、禁疗和最大生命、战斗清理与死亡、完整Vampiric Psalm反向光束和强化反击2秒眩晕。图形追加 `--capture` 输出 `.maintenance/knight-blood/vampiric-psalm.png`。

圣殿骑士嘲讽与破甲：`--checks templar-taunt` 验证基础3秒／强化5秒、10秒冷却、200范围、原光环视觉、多来源择近、控制状态、真实自动接敌、动态防御、反击每次破甲、训练存档、复制和狂化组合。图形模式追加 `--capture` 导出 `.maintenance/templar-taunt/taunt.png`。见[嘲讽说明](../docs/圣殿骑士嘲讽攻击.md)。

骑兵两段冲锋：`--checks cavalry-charge` 验证真实释放、按等级替换、1次／2次冲锋、300／600速度、原版Blazing火花和Flying Kick残影与命中、逐段伤害、一次CD、碰墙、中断、死亡及多骑兵独立运行；图形模式加 `--capture` 导出 `.maintenance/cavalry-charge/base.png` 和 `upgraded.png`。见[骑兵冲锋说明](../docs/骑兵冲锋说明.md)。

剑士七伤与吹风三连击：`--checks sword-wind` 验证七次计数、3+x/5+x真伤、原牌费用及0费正式部署、复制隔离、真实后撤和动画帧、基础风加两刀、强化三方向风、160%路径穿透、中断与原版特效。图形运行加 `--capture` 导出 `.maintenance/sword-wind/`，见[剑士说明](../docs/剑士七伤与吹风三连击.md)。

熊人跳跃与连锁闪电：`--checks bear-leap-chain` 验证基础/强化技能替换、真实两次爪击的2/3段连锁、少量敌人不重复连接、击杀后续链、密集敌群选点、真实腾空残影、落地伤害和印记、250击退、第二跳重新选点、眩晕/混乱/死亡/阶段打断、冷却保留、地形碰撞、嘲讽优先和多熊人隔离。图形模式追加 `--capture` 输出 `.maintenance/bear-leap-chain/`，见[熊人说明](../docs/熊人撼地与连锁闪电.md)。

狼人五连斩击扑击：`--checks wolf-pounce were-wolf-skills` 验证350/450距离、最大生命索敌、Angel原金色残影和实际位移、原五个伤害帧、强化2秒眩晕、击杀锁定目标立即刷新与其它击杀不刷新、中断/死亡/阶段清理、墙体和落点、原隐身被动与正式部署/存档。图形模式 `--wolf-pounce-regression --capture` 输出 `.maintenance/wolf-pounce/`，见[狼人说明](../docs/狼人五连斩击扑击说明.md)。
