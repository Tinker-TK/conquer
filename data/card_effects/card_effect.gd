# 这玩意儿是干嘛的（核心逻辑）：描述卡牌的一条效果，可以在同一张牌里按顺序组合多条。
# 数据是咋流动的（数据流向）：参数与持续类型 → 验证 → 出牌 → 独立强化记录或一次性效果。
# 为啥这么写（选型决策）：已有类型可直接选；新机制可继承此资源重写两个方法。
# 性能咋样（复杂度）：只在出牌或结算时执行，资源本身不每帧运行。
extends Resource
class_name CardEffect

enum Kind {
	ATTACK_UP, HEAL_PERCENT, DEFENCE_UP, POISON_ON_HIT, DEATH_EXPLOSION,
	# 编号 5 已删除；显式保留后续编号，防止已有资源被解释为其他效果。
	COPY_ALLY = 6, DAMAGE_ZONE, MUD_ZONE,
	DRAW, LOCK_DRAW, PAY_HP, ENERGY_EACH_ROUND, DEATH_ATTACK_AURA,
	RANDOM_PLAY, RECALL_ALLY, CUSTOM,
	# 新类型放最后，避免改变旧 .tres 中已经保存的效果编号。
	GAIN_ENERGY, MAX_HP_UP, RETAIN_ALLIES,
	WEAKNESS, VULNERABILITY, DEFENCE_DOWN, PARALYSIS, CONVERT_ENEMY,
	FRENZY, RETREAT_DRAW, DIVERSE_ARMY, KEEP_DISTANCE, JUDGER,
	COMRADE, TEMPORARY_UPGRADE,
	# 扩展卡牌仅追加编号，兼容已保存的配方。
	BLEED, HEALING_BAN, ARMOR_SHRED, SLEEP, SHIELD, OVERFLOW_SHIELD,
	MISSING_HEALTH_SHIELD, KNOCKBACK_IMMUNITY, TUTOR_UNIT, DISCARD_DRAW,
	SACRIFICE, RESURRECT, DEATH_DRAW, ARMY_ATTACK, ARMY_DEFENCE, ARMY_SPEED,
	BATTLE_STANDARD, SPIKE_TRAP, TRANSCRIBE, REFORMATION, HAND_DISCOUNT,
	OVERDRAFT, THRIFT
}
enum AffectedTeam { ENEMIES, ALLIES, BOTH }
enum Lifetime { BATTLE, ROUNDS, RUN }

# 单位强化与地面区域共用期限；地面区域仅支持本场和指定回合，不支持永久。
## 单位强化或地面区域的有效期限：BATTLE 持续本场，ROUNDS 持续指定回合，RUN 为本局永久。地面区域不支持 RUN；抽牌、支付生命等即时效果不使用持续期限。
@export var lifetime: Lifetime = Lifetime.BATTLE
## 期限为 ROUNDS 时的有效回合数，到期后撤销单位强化或移除地面区域；其它期限和即时效果不读取此值。
@export_range(1, 99, 1) var lasting_rounds: int = 2

## 此条卡牌效果执行的玩法，如攻击提升、治疗、伤害区域、抽牌或能量。不同类型读取的字段不同；CUSTOM 需由对应脚本实现。
@export var kind: Kind = Kind.ATTACK_UP
# 回复填写百分数（25 表示 25%）；泥潭填写减速百分数。
## 此效果的主要数值：属性、伤害、抽牌和能量填点数或数量；治疗、减速、易伤、狂化吸血填百分数（20 表示20%）。麻痹填眩晕秒数；保持距离填远端攻击百分数（130表示130%）；留存友军填阵亡征召牌增加的费用。具体限制由出牌验证检查。
@export var amount: float = 5.0
# 每次篝火强化对 amount 的增量；0 保留占位，不擅自改变尚未设计的效果。
## 每次篝火强化给此条效果 Amount 增加的数值。0 表示强化不增加此效果；与 Amount 使用相同单位。
@export var upgrade_amount: float = 0.0
## 每次强化对指定回合期限的增量；仅 Lifetime 为 ROUNDS 时应用。
@export_range(0, 99, 1) var upgrade_lasting_rounds: int = 0
## 策反是否允许精英敌军；始终不能转化首领或传说单位。
@export var can_convert_elite: bool = false
## 强化后允许策反精英敌军，不改变其它策反规则。
@export var upgrade_can_convert_elite: bool = false
## 流血、禁疗、睡眠和陷阱眩晕的有效交锋秒数。准备和暂停期间冻结计时。
@export_range(0.1, 300, 0.1) var status_seconds: float = 8.0
## 每次强化增加的状态持续秒数。
@export_range(0, 300, 0.1) var upgrade_status_seconds: float = 0.0
## 誊抄抽到的牌临时强化，下次成功使用后还原；单位训练点自动加攻击，士兵采用飞弹。
@export var upgrades_drawn_cards: bool = false
## 强化后开启誊抄的临时强化抽牌。
@export var upgrade_upgrades_drawn_cards: bool = false
## 透支下回合的能量上限惩罚；强化只增加当回合收益，不增加此惩罚。
@export_range(0, 99, 1) var next_round_penalty: int = 3
## 圆形范围效果的半径，单位为世界像素；用于地面区域、死亡爆炸等范围判定，越大则影响范围越广。单体属性强化不使用此字段。
@export_range(1, 2000, 1) var radius: float = 150.0
# 仅控制伤害区域每隔几秒结算伤害，不决定区域何时消失。
## 伤害区域的结算间隔，或麻痹的眩晕触发间隔，单位秒；麻痹需大于 Amount 眩晕时长。效果期限由 Lifetime 与 Lasting Rounds 决定，此值不控制期限。
@export_range(0.1, 10, 0.1) var interval: float = 1.0
## 范围区域等效果影响的阵营：敌方、己方或双方。与卡牌 Target 的出牌目标限制不同，单体效果仍按指定目标执行。
@export var affected_team: AffectedTeam = AffectedTeam.ENEMIES

@export_group('阵容与战术效果')
## 狂化触发拥挤惩罚的己方存活单位数下限；3 表示 3 个及以上时降低攻防。
@export_range(2, 99, 1) var crowded_unit_count: int = 3
## 狂化在拥挤阵容下的攻防百分比；70 表示原攻防的 70%，不会逐帧累乘。
@export_range(0, 100, 1) var crowded_stat_percent: float = 70.0
## 狂化只剩自身时的攻击增幅百分比；50 表示攻击提升 50%。
@export_range(0, 1000, 1) var solo_attack_bonus_percent: float = 50.0
## 狂化只剩自身时的防御增幅百分比；30 表示防御提升 30%。
@export_range(0, 1000, 1) var solo_defence_bonus_percent: float = 30.0
## 狂化只剩自身时的技能冷却减少百分比；20 表示冷却变为原来的 80%，同时调整正在运行的冷却。
@export_range(0, 99, 1) var cooldown_reduction_percent: float = 20.0
## 合理搭配所需的不同己方兵种数量，按 Unit Type 去重；3 表示至少 3 种时生效。
@export_range(1, 99, 1) var required_unit_types: int = 3
## 保持距离在近身（距离为零）时的攻击百分比；80 表示原攻击的 80%，远端百分比使用 Amount。
@export_range(0, 1000, 1) var minimum_attack_percent: float = 80.0
## 保持距离达到 Amount 攻击百分比所需的世界像素距离；近身到该距离间线性变化，超过后不再增长。
@export_range(1, 2000, 1) var distance_for_max_bonus: float = 600.0


func is_tactical() -> bool:
	return kind >= Kind.WEAKNESS and kind <= Kind.JUDGER


# 作用：判断是否属于可到期撤销的单位强化；没有参数，返回是否支持三种持续类型。
func is_unit_buff() -> bool:
	return kind in [Kind.ATTACK_UP, Kind.DEFENCE_UP, Kind.POISON_ON_HIT, Kind.DEATH_EXPLOSION, Kind.MAX_HP_UP]


# 作用：出牌前检查效果；context 含战场、目标和位置，返回空串表示允许。
func validate(context: Dictionary) -> String:
	return context.runtime.validate_effect(self, context)


# 作用：执行已通过检查的效果；context 与检查时相同，没有返回值。
func execute(context: Dictionary) -> void:
	context.runtime.apply_effect(self, context)
