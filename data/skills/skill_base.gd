# 这玩意儿是干嘛的（核心逻辑）：保存技能规则、目标选择方式和供详情面板显示的介绍。
# 数据是咋流动的（数据流向）：资源配置 → 技能管理器执行；详情面板只读取说明与参数。
# 为啥这么写（选型决策）：介绍和技能放在同一资源，修改文案不会改变战斗逻辑。
# 性能咋样（复杂度）：资源只保存数据，不进行每帧计算。
class_name SkillBase
extends Resource

## 技能的显示名称，用于单位详情和技能配置界面；实际技能行为由此资源绑定的脚本实现。
@export var skill_name: String = "普通攻击"
## 标记单位的普通攻击；剑矢强化只改变此攻击的射程与命中方式，沿用同一冷却。特殊技能不勾选。
@export var is_basic_attack: bool = false
## 士兵强化分支限定；留空为通用技能，slash为斩击，missile为飞弹。
@export var soldier_branch: String = ""
## 此技能生效的强化等级数组，元素为 0～99 的整数。0 表示未强化，1 表示强化一次，2 表示强化两次。[0,1] 仅在未强化和强化一次时生效；[0] 强化后失效；[1] 仅强化一次时生效；[] 始终不生效。主动技能和防守反击都按当前等级精确匹配。
@export var unlock_upgrade_levels: Array[int] = [0, 1]:
	set(value):
		# 技能副本编辑等级时不修改共享资源的数组。
		unlock_upgrade_levels = value.duplicate()
## 技能介绍文案，显示在单位详情等界面。修改说明不会自动修改伤害、冷却或目标选择规则。
@export_multiline var description: String = ""
## 技能的伤害或治疗倍率，常规技能按单位攻击力乘以此值取整；1 为原攻击力，2 为两倍。具体行为取决于技能实现，召唤技能不使用此倍率。
@export var attack_rate: float = 1.0
## 每次开始施法后启动的冷却时长，单位为秒；冷却完成才可再次选择此技能。需大于 0，技能播放时间可能使实际释放间隔更长。
@export var cooldown: float = 1.0        # 「最大」冷却时长（配置值）
## 动作前的咏唱秒数。0为立即开始动作；咏唱被状态打断时取消本次效果并进入完整冷却。
@export_range(0.0, 30.0, 0.05) var chant_duration: float = 0.0
## 技能选择优先级，数值越大越先检查。只有冷却完成且有合法目标时才会选中，不会强行打断正在施放的技能。
@export var priority: int = 0            # 越大越优先
## 允许发动技能的施法距离，单位为世界像素；超出距离时单位会尝试靠近目标。范围攻击的实际命中形状由单位 AttackArea 决定。
@export var cast_range: float = 80.0
## 是否由技能脚本主动结束施法。普通技能关闭时在非循环施法动画结束后解锁；冲刺等异步技能开启后必须调用 finish_skill，否则单位会持续处于施法状态。
@export var manual_finish: bool = false


## 单位 AnimatedSprite2D 中的施法动画名称，必须与 SpriteFrames 中已有的名称一致。普通技能应使用非循环动画，命中帧以此动画为准。
@export var cast_animation: String = "attack_01"
## 在施法动画的哪些帧执行技能，帧编号从 0 开始；可配置多个帧实现多次命中。每个编号必须小于该动画的总帧数。
@export var hit_frame: Array[int] = [3]
enum TargetType{
	ENEMY_NEAREST,
	ALLY_LOWEST_HP,
	SELF,
	# 新类型追加在末尾，保留已有资源保存的 0、1、2 三个编号。
	ENEMY_LOWEST_HP,
	ENEMY_LOWEST_HP_PERCENT,
	ENEMY_FARTHEST
}
## 技能的索敌方式：最近敌人、最低生命比例友军（含自身）、自身、最低当前生命敌人、最低生命比例敌人或最远敌人。强化治疗可在全员满血时改选当前生命最高友军。敌方隐身单位不能参与索敌；最远按世界直线距离计算。自身适用于召唤等无需敌方目标的技能。
@export var target_type: TargetType = TargetType.ENEMY_NEAREST
## 技能生效时播放的可选特效场景，常规命中特效根节点需为 AnimatedSprite2D。远程技能在投射物命中时播放；召唤技能必须配置此特效并等动画结束后生成单位。
@export var on_hit_effect: PackedScene

## 攻击真正命中且目标存活时附加的状态；可添加 UnitStatusEffect 配置流血伤害、混乱、禁疗、睡眠、晕眩与虚弱。同来源重复命中刷新期限。
@export var status_effects: Array[UnitStatusEffect] = []


## auto 按技能脚本与兵种匹配；silent 关闭出招声，其他选项指定音色。出招声与 Hit Frame 同步。
@export_enum("auto", "silent", "melee", "bow", "fire", "ice", "magic", "beast", "slime", "heal", "summon", "sword", "axe", "spear", "charge", "staff", "heavy", "claw", "bite", "stone", "lightning") var combat_sound_profile: String = "auto"

func execute(_caster: UnitBase, _target: UnitBase = null):
	pass


## 一次动作的多次命中平摊防御；范围攻击按每个目标独立计算，穿透人数不算段数。
func defence_segments() -> int:
	return maxi(1, hit_frame.size())


# 发射或结算时保留本次技能的伤害来源，延迟命中不读取单位后来施放的技能。
func combat_number_kind() -> StringName:
	# 旧资源与旧存档还没有普攻标记，沿用既有近战兼容规则，并识别普通射击。
	var script_path: String = get_script().resource_path
	var legacy_melee := script_path == "res://scripts/skills/normal_attack.gd" and cast_animation == "attack_01" and priority == 0
	var legacy_arrow := script_path == "res://scripts/skills/arrow_attack.gd" and priority == 0 and skill_name in ["普通攻击", "普通射击", "射击"]
	return &"normal" if is_basic_attack or legacy_melee or legacy_arrow else &"skill"


func apply_hit_statuses(caster: UnitBase, target: UnitBase) -> void:
	if not is_instance_valid(target) or target.current_state == UnitBase.State.DEATH or target.is_queued_for_deletion():
		return
	for effect: UnitStatusEffect in status_effects:
		if effect != null:
			effect.apply_to(target, caster, self)


# 反击的一次成功命中；first_hit防止多命中帧反复触发按次结算的破甲。
func apply_reaction_hit_statuses(caster: UnitBase, target: UnitBase, _first_hit: bool) -> void:
	apply_hit_statuses(caster, target)


func accepts_forced_target(_caster: UnitBase, _target: UnitBase) -> bool:
	return true


func is_global_cast() -> bool:
	return false


func begin_cast(_caster: UnitBase, _target: UnitBase) -> bool:
	return true


# 后撤后再起手等分阶段技能自行安排动画，其他技能由管理器立即播放。
func owns_cast_animation() -> bool:
	return false


func requires_live_target_on_hit() -> bool:
	return true


func has_custom_targeting() -> bool:
	return false


# 高优先级近战技能够不到时，先尝试已在距离内的其它技能；都够不到仍按原目标追击。
func try_other_skills_when_out_of_range() -> bool:
	return false


func select_target(_caster: UnitBase) -> UnitBase:
	return null


func card_effect_description() -> String:
	return effect_description() if is_passive() else ""


func is_passive() -> bool:
	return false


func create_passive(_caster: UnitBase) -> Node:
	return null


func passive_parameters() -> String:
	return "驻场技能"


func passive_icon() -> String:
	return ""


func effect_description() -> String:
	return description


func is_active_at_upgrade_level(level: int) -> bool:
	return unlock_upgrade_levels.has(level)


# 旧存档中显式保存的整数仍按原来的最低等级规则读取；下次保存只写新的数组。
func _set(property: StringName, value: Variant) -> bool:
	if property == &"unlock_upgrade_level" and value is int:
		unlock_upgrade_levels.clear()
		for level in range(clampi(value, 0, 99), 100):
			unlock_upgrade_levels.append(level)
		return true
	return false
