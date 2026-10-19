# 倍速只作用于交锋和回合结算。每步游戏时间保持不变，增加每秒步数而非放大单步。
# 在画面帧结束统一切换引擎参数，避免在一个物理步的中途改变 delta。
extends Node

signal multiplier_changed(value: int)
const MULTIPLIERS := [1, 2, 3]
var multiplier := 1
var _battle: WeakRef
var _battle_id := 0
var _base_ticks := 60
var _base_max_steps := 8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10000
	_base_ticks = Engine.physics_ticks_per_second
	_base_max_steps = Engine.max_physics_steps_per_frame


func set_multiplier(value: int) -> void:
	if value not in MULTIPLIERS or multiplier == value:
		return
	multiplier = value
	multiplier_changed.emit(value)


func bind_battle(owner_battle: Node) -> void:
	_battle = weakref(owner_battle)
	_battle_id = owner_battle.get_instance_id()
	owner_battle.tree_exiting.connect(_release_battle.bind(_battle_id), CONNECT_ONE_SHOT)


func _release_battle(id: int) -> void:
	if id != _battle_id:
		return
	_battle = null
	_battle_id = 0
	_apply(1)


func _process(_delta: float) -> void:
	var owner_battle = _battle.get_ref() if _battle != null else null
	var active: bool = is_instance_valid(owner_battle) and owner_battle.is_inside_tree() \
		and not owner_battle.is_queued_for_deletion() and not owner_battle.battle_finished \
		and not get_tree().paused and not SceneTransition.busy \
		and Global.game_phase in [Global.GamePhase.AUTO_BATTLE, Global.GamePhase.ROUND_RESOLVE]
	_apply(multiplier if active else 1)


func _apply(value: int) -> void:
	# 同时缩放物理频率和时间，delta 恒为 1 / 基础频率；低帧率时保留全部计算步骤。
	if Engine.physics_ticks_per_second != _base_ticks * value:
		Engine.physics_ticks_per_second = _base_ticks * value
		Engine.max_physics_steps_per_frame = _base_max_steps * value
	Engine.time_scale = float(value)


func reset() -> void:
	set_multiplier(1)
	_apply(1)


func _exit_tree() -> void:
	_apply(1)
