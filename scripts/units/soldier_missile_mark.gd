# 使用实验室“减速”的原持续视觉作为飞弹标记，直到本场结束。
extends Node

var source_team := ""
var active := true
var visual: Node2D


func _ready() -> void:
	visual = preload("res://scripts/effects/combat_vfx.gd").spawn(get_parent(), "SlowVFX", 0.0)
	get_parent().unit_died.connect(_on_died)
	get_parent()._refresh_passive_status()


func apply_bonus() -> void:
	var target := get_parent() as UnitBase
	var soldiers: Array[UnitBase] = []
	for node in get_tree().get_nodes_in_group(source_team):
		var unit := node as UnitBase
		if not is_instance_valid(unit) or unit.is_queued_for_deletion() or unit.current_state == UnitBase.State.DEATH \
			or unit.unit_data.unit_english_name != "soldier" or unit.unit_data.unit_team != source_team \
			or unit.soldier_runtime == null or not unit.soldier_runtime.same_encounter(unit, target):
			continue
		if unit.soldier_runtime.attacks(target):
			soldiers.append(unit)
	for unit in soldiers:
		unit.soldier_runtime.gain_missile_bonus(soldiers.size())


func status_entry() -> Dictionary:
	return {"icon": "missile_mark", "tooltip": "飞弹标记：命中时统计正在攻击此目标的己方士兵N，每名攻击+N。\n斩击士兵下次优先飞向此目标；标记持续本场战斗。"}


func _physics_process(_delta: float) -> void:
	var target := get_parent() as UnitBase
	if target._encounter_finished() or target.unit_data.unit_team == source_team:
		clear_mark()


func _on_died(_unit: UnitBase) -> void:
	clear_mark()


func clear_mark() -> void:
	if not active:
		return
	active = false
	if is_instance_valid(visual):
		visual.hide()
		visual.queue_free()
	visual = null
	get_parent()._refresh_passive_status()
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(visual):
		visual.queue_free()
