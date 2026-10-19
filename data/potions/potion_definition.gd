# 这玩意儿是干嘛的（核心逻辑）：描述一瓶消耗品的伤害、范围和释放次数。
# 数据是咋流动的（数据流向）：背包中一瓶药水 → 选中 → 首次合法落点扣瓶 → 战斗运行器处理后续效果。
# 为啥这么写（选型决策）：资源只存配置，每瓶使用进度在战斗中单独记录。
# 性能咋样（复杂度）：未使用时不更新，只在使用期间结算范围伤害。
extends Resource
class_name PotionDefinition

enum Kind { TORNADO, LIGHTNING, FIRE, THUNDER_CLOUD, EFFECTS }
enum Targets { ENEMIES, ALLIES, BOTH }
enum Rarity { COMMON, RARE, LEGENDARY }
enum TargetMode { POINT, ENEMY_UNIT, ALLY_UNIT, ALL_ALLIES, ALL_ENEMIES, DEAD_ALLY, RANDOM_ALLY, SELF, PASSIVE }

@export_group("能力与投放")
@export var rarity: Rarity = Rarity.COMMON
@export var target_mode: TargetMode = TargetMode.POINT
@export var tags: Array[StringName] = []
@export_range(1, 3) var min_act := 1
@export_range(1, 3) var max_act := 3
@export var price := 50
@export var prep_usable := false
## 0 不限制；按本局成功消耗的瓶数计算，保存到征途存档。
@export var max_per_run := 0
@export var effects: Array[PotionEffect] = []
@export var tint := Color("8bd9fa")
## Eslabong 素材目录中的实际资源标识；视觉不参与伤害结算。
@export var impact_vfx := ""
@export_group("")
## 药水类型的唯一标识，用于识别配置与背包中的药水种类；相同类型可以拥有多瓶独立消耗品。
@export var id: StringName
## 药水的显示名称，用于背包、奖励和瞄准提示；不会改变技能类型。
@export var display_name := ""
## 药水说明文案。实际伤害、范围与次数由其它参数决定，修改说明不会修改玩法。
@export_multiline var description := ""
## 药水在背包 HUD 和奖励选择界面中的图标资源；只控制外观。
@export var icon: Texture2D
## 药水类型：龙卷风为移动持续伤害，闪电为分次点击释放，火焰持续至本轮结束，雷云在固定落点跨回合放电。成功的首次施放消耗一瓶，不消耗手牌能量。
@export var kind: Kind = Kind.TORNADO
## 药水范围伤害影响的阵营：敌方、己方或双方；己方始终按 team_a 判断。
@export var targets: Targets = Targets.ENEMIES
## 每次命中的直接效果伤害点数。雷云每次只命中一个锁定目标，其它持续类药水伤害范围内各单位；不按普通攻击的防御或闪避规则计算。
@export_range(1, 999, 1) var damage: int = 8
## 每次伤害判定的圆形半径，单位为世界像素；越大则能命中距离落点或当前龙卷风中心更远的单位。
@export_range(10, 500, 1) var radius: float = 70.0
## 重复伤害/索敌间隔，单位为秒。龙卷风与火焰落地先命中一次；雷云每次索敌后只向一个单位放电，雷线到达目标时命中，空范围不出雷。闪电不使用此周期。
@export_range(0.05, 10, 0.05) var interval: float = 0.5
## 龙卷风移动速度，单位为世界像素/秒；0 表示停在落点，触及战场矩形边缘会反弹。闪电和火焰不使用此值。
@export_range(0, 1000, 1) var speed: float = 90.0
## 龙卷风的持续秒数，结束后可使用下一瓶药水。火焰目前持续到本轮交锋结束，闪电由释放次数控制；这两类不使用此字段作为持续时间。
@export_range(0.1, 60, 0.1) var duration: float = 6.0
## 雷云持续的回合数，施放当回合算第1回合，最后一个回合结束时消失。准备与结算阶段暂停放电，跨回合保留世界坐标；整场战斗结束立即清理。其它药水不使用此值。
@export_range(1, 20, 1) var rounds: int = 3
## 一瓶闪电药水最多可点击释放的次数。首次合法落点后整瓶已消耗，未用完的次数在回合结束时清除；其它药水固定施放一次。
@export_range(1, 20, 1) var casts: int = 4
## 闪电两次点击释放之间的最短间隔，单位为秒；最后一次释放后也等待此间隔再解除使用状态。持续类药水不靠此值控制伤害频率。
@export_range(0.1, 5, 0.1) var cast_delay: float = 0.4

@export_group("使用特效")
## 普通药水使用 AnimatedSprite2D 根节点场景，自动播放选中的有效动画。雷云使用 PixelThunderCloud 根节点场景，留空时复用默认像素雷云；运行器驱动实例时钟，不修改源特效。
@export var effect_scene: PackedScene
## 特效场景原始缩放的倍率；只改变画面大小，不改变 Radius 伤害半径。
@export var effect_scale := Vector2.ONE
## 特效原点相对伤害中心的世界像素偏移；场景自身的 AnimatedSprite2D Offset 仍然保留，不改变伤害落点。
@export var effect_offset := Vector2.ZERO


func occupies_slot() -> bool:
	if kind != Kind.EFFECTS:
		return true
	for effect in effects:
		if effect != null and effect.kind in [PotionEffect.Kind.ZONE, PotionEffect.Kind.GRAVITY, PotionEffect.Kind.DELAYED_BLAST]:
			return true
	return false


func needs_aim() -> bool:
	return target_mode in [TargetMode.POINT, TargetMode.ENEMY_UNIT, TargetMode.ALLY_UNIT]
