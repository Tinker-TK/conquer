# Tiny Swords Enemy Pack 怪物配置

已配置 `assets/characters/Enemy Pack/` 的 22 种主要怪物，以及 `Extra/Pig Rider Spear Goblin` 的骑猪哥布林，共 23 个独立敌方单位。建筑、船、坐骑猪、装饰和防守/受击扩展属于辅助素材，不单独作为战斗怪物。

这 23 种只作为敌方战斗单位，未配置卡牌名称、卡面和招募文案；不进入玩家初始牌组、事件招募、胜利奖励或商店招募。单位场景仍可从波次编辑器和怪物测试场正常使用。

事件单位奖励按阵营过滤，`RunManager` 的开局与入库入口也拒绝敌方单位，包括包成 `CardDefinition` 的敌方征召牌。继续旧存档时会自动跳过此前误入的怪物牌，按原存档索引保留其余牌的顺序、训练和永久增益，以及生命、金币与征途进度；下一场创建抽牌堆前同样清理旧会话残留。无需重开征途。

## 查看与使用

- `examples/scenes/enemy_pack_preview.tscn`：F6 查看全部怪物；支持待机、移动、攻击、白烟退场和重新生成。点击“攻击”只播放一套完整动作，每只单位按自己的时长结束并回到待机；再次点击从头重播。左上角旧兽人用于体型对照；巨魔在预览格中略缩小，实际战斗使用原尺寸。
- `scenes/testing/monster_test.tscn`：F6，右侧已加入全部新怪物，可增兵并与己方真实对战。
- 波次编辑器自动扫描 `scenes/units/`，可按中文名或英文标识选择新怪物，拖入波次。
- 每种怪物对应 `scenes/units/<英文标识>.tscn`、`data/units/<英文标识>.tres` 和 `data/skills/<英文标识>_attack.tres`。修改后两者即可调整生命、攻防、速度、射程、冷却和命中帧。

## 动画和攻击

大黄蜂、小恶魔、巨型蝙蝠及旧蝙蝠已启用单位资源的 `is_flying`：直接飞越任意地形，跨层每层用 0.1 秒升降 64 像素，不需要导航或楼梯。配置与验收见 [四层地形与桥梁](四层地形与桥梁配置说明.md)。

场景沿用 `orc.tscn` 的 CharacterBody2D、AnimatedSprite2D、碰撞体、NavigationAgent2D、HealthBar、SkillManager 和 frame_changed 信号结构。所有新单位只有一个主动技能，动画统一为 `idle`、`walk`、非循环 `attack_01`。受击使用通用闪红，死亡使用白烟，不要求素材提供 hurt/death 动画。

依据 [Pixel Frog 官方 Tiny Swords 页面](https://pixelfrog-assets.itch.io/tiny-swords) 标注的 10 FPS，按源 Aseprite 标签和实际 PNG 尺寸切帧，保留透明画布以避免动作抖动。新素材使用原生显示尺寸，并以材质统一为 2 像素颗粒与旧角色配色；脚底影子对齐单位原点，碰撞与血条按体型分别配置。旧单位原有的 4 倍精灵缩放不用于这批素材。

- 巨魔：5 帧 Windup + 6 帧 Attack × 3 轮 + 10 帧 Recovery × 2 轮，共 43 帧，合并为一次 `attack_01`。三轮挥棒包含六次挥击，在第 7、10、13、16、19、22 帧命中，然后喘息收招；整套动作共用一次 4.8 秒冷却。
- 小恶魔：4 帧 Start + 4 帧 Loop × 3 轮 + 4 帧 End，共 20 帧，合并为一次 `attack_01`。持续喷火在第 4、8、12 帧各造成 0.5 倍攻击伤害，整套喷火共用一次 2.4 秒冷却。
- 熊猫武僧：完整起手与旋转双节棍为一套，第 5、7、9 帧分别命中；火把哥布林在第 2、5 帧两次旋转挥击命中。其它怪物沿用自己的起手、命中和收招时长，各单位技能冷却独立配置。
- 炸弹鱼、豺狼人、鱼叉鲨鱼、咒术萨满、弹弓地精：分别使用包内炸弹、骨头、鱼叉、法术弹、橡果；对应投射物位于 `scenes/projectiles/<标识>_projectile.tscn`。
- 咒术萨满命中使用自己的紫色爆裂；炸弹命中复用已有 `pvfx/元素魔法/warm_explosion` 特效。
- `Global.UnitType` 在末尾追加新兵种，原有编号保持不变。每个新单位都有独立数据、一个攻击技能和显式音色，不共用兽人属性资源。

## 2 像素与旧角色配色

全部 23 个正式单位场景及 5 种专属投射物已接入该方案，咒术萨满的命中爆裂也同步配色；怪物预览、测试场和正常对战加载的是同一套场景。原始 PNG 保留，动画帧数、速度、命中帧、冷却、碰撞和显示大小不变。

- `shaders/unit_pixel_style.gdshader`：在每帧内部按 2×2 原像素固定采样，再映射颜色。网格以图集帧为原点，限定在该帧内；转身仍沿用精灵翻转。保留受击 `flash_intensity` / `flash_color` 和选中、隐身的颜色调制。
- `scripts/units/enemy_pixel_style.gd`：位于精灵下的 `PixelStyle` 子节点，只监听动画/帧切换并更新当前材质，不驱动播放时钟。UnitBase 复制材质后也会更新正确实例，避免攻击切片错位及受击串色。
- `data/visuals/enemy_pack/<英文标识>.tres`：每个单位独立的源色/目标色色板，投射物与发射者共享同一个色板。巨魔沿用已选中的试做配色；其它怪物按毛皮、金属、绿皮、骨骼、火焰、衣物分别对应到旧 Orc、Soldier、Archer、Wizard、Necromancer、Knight、Slime 资源中的颜色，保留各自的明暗层次。同种单位共享只读色板纹理，受击参数各自独立。
- 白烟使用自己的白色和灰蓝色，不经过单位换色材质。

色板的生成与核验脚本是 `tools/maintenance/configure_enemy_pixel_style.py`，保存人工选定的源色/目标色对。调整该脚本后运行它可重新生成色板；加 `--check` 只验证当前数据。核验会读取全部已用动画及投射物 PNG，检查不透明源色是否全部覆盖、目标色是否确实存在于旧角色、以及生成配置是否一致，不改写图片。

`examples/scenes/troll_pixel_style_preview.tscn` 保留原版 / 2 / 4 像素动态对照，并直接读取正式巨魔色板。

## 白烟死亡

通用实现位于 `scripts/units/unit_base.gd`、`scripts/effects/unit_death_smoke.gd` 和 `scenes/effects/unit_death_smoke.tscn`，适用于所有新旧战斗单位。

死亡立即取消移动与未完成的攻击，退出碰撞/避让并隐藏血条；保留原单位约 0.14 秒，让白色灰蓝阴影的像素烟盖住身体，然后隐藏身体。云团继续上升、散开、缩小并淡出，约 0.85 秒后清理单位和特效。烟团按待机可见像素与精灵缩放计算大小，巨魔、牛头人与旧单位无需单独配置；使用物理时钟，暂停冻结、战斗倍速同步。死亡和击杀信号仍在死亡当帧发送，不等待视觉收尾。

## 验证

新增 `tests/enemy_pack_test.gd`，通过真实动画推进、远程落点、死亡中断、暂停和清理验证所有单位；可运行：

```text
python tools/maintenance/run_checks.py --godot <Godot控制台程序> --checks enemy-pack monster-test counter combat-audio battle undying-army game-config-editor
```

敌方单位与卡牌隔离的专项验收为 `tests/enemy_only_units_test.gd`，执行 `python tools/maintenance/run_checks.py --checks enemy-only`。覆盖 23 个新怪物的配置、自动与指定奖励池、入库、封装旧牌、旧存档清理、训练/进度保留和真实抽牌堆；日志在 `.maintenance/checks/enemy-only-fix/`，修改前的复现日志在 `.maintenance/checks/enemy-only-baseline/`。

怪物验收覆盖真实攻击命中、连击节奏、白烟退场，以及预览按钮只触发一套动作、短动作先结束、巨魔不被统一定时重播打断、再次点击从头重播。还通过怪物测试场、反击、音效、战斗架构、不死军团和策划配置编辑器回归；使用 OpenGL 实际渲染检查了待机、攻击和白烟清理。

画风调整后，怪物验收扩展为 **652 项检查通过**，覆盖所有新单位、投射物、萨满命中特效的材质、换动画及跨切片后的网格参数、同种单位受击材质隔离和只读色板共享；怪物测试场回归通过。Godot / OpenGL 实际渲染检查待机、移动、完整攻击、闪红与白烟退场。日志在 `.maintenance/checks/enemy-pixel-style-final/`，实机截图和渲染日志在 `.maintenance/enemy_pack/style/`；`idle.png` 是调整后，`original.png` 为同一预览中的原始画风对照，`projectiles.png` 是专属投射物和萨满命中特效。

扩大检查时还发现以下现有问题；恢复原单位脚本和原怪物目录后也得到相同失败，未混入此次修改：

- 全资源扫描：河流演示脚本引用不存在的 `scenes/world/tree.tscn`；另外四处已有场景根类型与 StaticBody2D 脚本不匹配。
- 波次编辑器测试：鼠标坐标转换、重做拖动、保存拖动坐标三项失败；新增怪物目录加载和搜索等检查通过。
- 倍速回归：仅 effects 场景的中途切档/暂停对比失败；固定 1/2/3 倍对比及其它四组场景通过。

最新攻击节奏与单次预览验收日志在 `.maintenance/checks/enemy-pack-rhythm/`；白烟验收及光环、状态栏、反击回归日志在 `.maintenance/checks/enemy-pack-acceptance/`，其它回归在 `.maintenance/checks/enemy-pack-final/`；原版对照在 `.maintenance/checks/enemy-pack-baseline/` 与 `.maintenance/checks/enemy-pack-original-catalog/`。
