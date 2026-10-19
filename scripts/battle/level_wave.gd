# 这玩意儿是干嘛的（核心逻辑）：按回合生成阵型，区间循环时给指定单位累加成长效果。
# 数据是咋流动的（数据流向）：回合号 → 共用循环算法 → 波次实例 → 独立单位属性 → TeamB。
# 为啥这么写（选型决策）：从基础场景计算倍率，避免共享资源污染；保留非循环耗尽后的 HP 战斗规则。
# 性能咋样（复杂度）：每轮只生成一个波次，每个单位检查三种属性。
extends Node2D

const SEQUENCE = preload("res://scripts/battle/wave_sequence.gd")
## 按回合排列的敌方波次场景，第一个对应第 1 回合。波次根节点的直接子节点需为 UnitBase；关卡 Waves 可覆盖此列表。非循环列表耗尽后会重用最后一个有效阵型。
@export var level_data: Array[PackedScene] = []
## 是否在原波次结束后循环指定区间；开启后循环次数参与波次成长效果计算。关闭后仍可重用最后一个有效阵型，但不产生循环成长。
@export var repeat_waves: bool = true
## 循环区间起始波次号，从 1 开始；仅在 Repeat Waves 开启时使用，需位于 Level Data 数组范围内。
@export var repeat_start: int = 1
## 循环区间结束波次号，包含此波次；0 自动使用数组末尾。需不小于 Repeat Start，关卡配置可覆盖此值。
@export var repeat_end: int = 0
## 默认楼层的怪物按出生落点选择最上方地面；显式配置的 Floor Id 2~4 保持不变。桥下阵型可关闭此项，完全使用单位的 Floor Id。
@export var auto_detect_spawn_floor: bool = true
var last_round := 0

# 作用：出牌阶段生成敌人；current_phase 为阶段、round 为一基实际回合，没有返回值。
func _on_battle_round_manager_phase_changed(current_phase: int, round_number: int) -> void:
	if current_phase != Global.GamePhase.CARD_PLAY or round_number <= last_round:
		return
	var battle := get_parent().get_parent() if get_parent() != null else null
	if battle != null and battle.get("battle_finished") == true:
		return
	last_round = round_number
	var entry := SEQUENCE.resolve(round_number, level_data.size(), repeat_waves, repeat_start, repeat_end)
	var scene: PackedScene
	if entry.index >= 0:
		scene = level_data[entry.index]
	elif not repeat_waves:
		# 非循环列表耗尽后仍重用最后有效阵型，但不产生循环成长。
		for i in range(level_data.size() - 1, -1, -1):
			if level_data[i] != null:
				scene = level_data[i]
				break
	if scene == null:
		return
	var terrain := battle.get_node_or_null("Level/NavigationRegion2D") if battle != null else null
	var wave := scene.instantiate()
	for unit in wave.get_children():
		if not unit is UnitBase:
			push_warning("波次直接子节点只支持 UnitBase，已跳过：%s" % unit.name)
			continue
		# 入树前加成，让生命条、技能第一次读取时就得到正确数值。
		SEQUENCE.apply_effects(unit, entry.cycle)
		var spawn_pos: Vector2 = unit.position
		unit.owner = null
		wave.remove_child(unit)
		unit.position = spawn_pos
		# 入树前确定楼层，保证第一次显示、碰撞、导航和飞行高度都使用出生地面。
		# 兼容旧波次编辑器只存坐标的关卡，不需要重新拖动或保存原有阵型。
		if auto_detect_spawn_floor and unit.floor_id == 1 and terrain != null and terrain.has_method("spawn_floor_at"):
			unit.floor_id = terrain.spawn_floor_at(to_global(spawn_pos))
		add_child(unit)
	wave.free()

# 作用：兼容编辑工具查询；没有参数，返回是否还有原始波次，不参与 HP 胜负。
func has_future_waves() -> bool:
	if repeat_waves:
		return false
	for i in range(last_round, level_data.size()):
		if level_data[i] != null:
			return true
	return false
