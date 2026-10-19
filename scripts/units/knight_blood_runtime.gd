# 各骑士独立归属流血层数、实际扣血和6秒回归计时，不保存到技能共享资源或卡牌。
extends Node

var unit: UnitBase
var interval := 6.0
var elapsed := 0.0
var pending_healing := 0
var contributors: Dictionary = {}


func _ready() -> void:
	unit = get_parent()
	for skill: SkillBase in unit.unit_data.get_unlocked_skills():
		if "blood_return_interval" in skill:
			interval = skill.blood_return_interval
	unit.unit_died.connect(_on_died)


func add_bleed(target: UnitBase, stacks: int) -> void:
	var key := "knight_blood_%d" % unit.get_instance_id()
	var previous: Dictionary = target.status_runtime.effects.get(&"bleed", {}).get(key, {})
	if not target.apply_status(&"bleed", 0.0, int(previous.get("amount", 0)) + stacks, unit, key):
		return
	var entry: Dictionary = target.status_runtime.effects[&"bleed"][key]
	entry["on_damage"] = _record_damage.bind(weakref(target))
	entry["blood_stacks"] = int(entry.amount)


func _record_damage(amount: int, reference: WeakRef) -> void:
	if amount <= 0 or unit.current_state == UnitBase.State.DEATH or unit._encounter_finished():
		return
	var target: UnitBase = reference.get_ref()
	if not is_instance_valid(target):
		return
	pending_healing += amount
	contributors[target.get_instance_id()] = {"target": reference,
		"position": target.to_global(target._smoke_body_rect().get_center())}


func _physics_process(delta: float) -> void:
	if unit.current_state == UnitBase.State.DEATH or unit._encounter_finished():
		clear()
		return
	if Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		return
	elapsed += delta
	while elapsed + 0.000001 >= interval:
		elapsed = maxf(0.0, elapsed - interval)
		_return_blood()


func _return_blood() -> void:
	if pending_healing <= 0:
		return
	var amount := pending_healing
	pending_healing = 0
	unit.receive_healing(amount, unit, false)
	for entry: Dictionary in contributors.values():
		var effect = preload("res://scripts/combat/blood_return_vfx.gd").new()
		unit.get_parent().add_child(effect)
		effect.start(unit, entry.target, entry.position)
	contributors.clear()


func clear() -> void:
	contributors.clear()
	elapsed = 0.0
	pending_healing = 0


func _on_died(_unit: UnitBase) -> void:
	clear()


func _exit_tree() -> void:
	clear()
