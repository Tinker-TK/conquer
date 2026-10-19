# 风暴围绕受击目标持续；进入减速、离开恢复，同类风暴不叠加移速扣除。
extends Node2D

var source_team := ""
var source: WeakRef
var radius := 150.0
var amount := 0
var seconds_left := 0.0
var targets: Dictionary = {}


func _ready() -> void:
	SignalBus.phase_change.connect(_on_phase_changed)


func refresh(new_radius: float, new_amount: int, duration: float) -> void:
	radius = maxf(0.0, new_radius)
	amount = maxi(0, new_amount)
	seconds_left = maxf(0.01, duration)
	_update_targets()


func _physics_process(delta: float) -> void:
	var victim := get_parent() as UnitBase
	if Global.game_phase != Global.GamePhase.AUTO_BATTLE or victim._encounter_finished() \
		or victim.current_state == UnitBase.State.DEATH or victim.unit_data.unit_team == source_team:
		_clear()
		queue_free()
		return
	seconds_left -= delta
	if seconds_left <= 0.0:
		_clear()
		queue_free()
		return
	_update_targets()


func _update_targets() -> void:
	var next: Dictionary = {}
	var victim := get_parent() as UnitBase
	if amount > 0:
		# 目标所在队伍容器即本场敌军；策反单位仍按当前阵营过滤。
		for node in victim.get_parent().get_children():
			var unit := node as UnitBase
			if not is_instance_valid(unit) or unit.is_queued_for_deletion() or unit.current_state == UnitBase.State.DEATH \
				or unit.unit_data.unit_team == source_team or unit._encounter_finished():
				continue
			if global_position.distance_squared_to(unit.global_position) <= radius * radius:
				var entry: Dictionary = unit.status_runtime.effects.get(&"slow", {}).get(str(get_instance_id()), {})
				if int(entry.get("amount", -1)) != amount:
					unit.apply_status(&"slow", 0.0, amount, source.get_ref() if source != null else null, str(get_instance_id()))
				next[unit.get_instance_id()] = weakref(unit)
	for id in targets:
		if not next.has(id):
			var unit = targets[id].get_ref()
			if is_instance_valid(unit):
				unit.remove_status(&"slow", str(get_instance_id()))
	targets = next


func _clear() -> void:
	for reference: WeakRef in targets.values():
		var unit = reference.get_ref()
		if is_instance_valid(unit):
			unit.remove_status(&"slow", str(get_instance_id()))
	targets.clear()


func _on_phase_changed(phase: int) -> void:
	if phase != Global.GamePhase.AUTO_BATTLE:
		_clear()
		queue_free()


func _exit_tree() -> void:
	_clear()
