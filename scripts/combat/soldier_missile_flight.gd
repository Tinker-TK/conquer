# 直接复用 Wounding Arrow 的箭矢与命中；持续视觉交给目标标记管理。
extends "res://assets/effect/eslabong_vfx/skills/skill_player.gd"

var caster_ref: WeakRef
var target_ref: WeakRef
var source_team := ""
var source_floor := 1
var damage := 0


func start(caster: UnitBase, target: UnitBase, value: int) -> void:
	caster_ref = weakref(caster)
	target_ref = weakref(target)
	source_team = caster.unit_data.unit_team
	source_floor = caster.floor_id
	damage = value
	z_index = maxi(caster.z_index, target.z_index)
	var recipe: Dictionary = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd").find("archer_wounding_arrow").duplicate(true)
	recipe.cast_seconds = 0.0
	recipe.actions[0].on_hit = recipe.actions[0].on_hit.filter(func(item: Dictionary): return item.get("stage") != "持续效果")
	target_hit.connect(_hit)
	play(recipe, to_local(caster.global_position), to_local(target.global_position), {"unit_height": 48.0})
	set_process(false)


func _spawn(data: Dictionary, at: Vector2, controlled: bool = false) -> Node2D:
	var holder := super._spawn(data, at, controlled)
	if holder != null:
		preload("res://scripts/effects/combat_vfx.gd").use_physics_clock(holder)
	return holder


func _physics_process(delta: float) -> void:
	var target: UnitBase = target_ref.get_ref()
	var caster: UnitBase = caster_ref.get_ref()
	if Global.game_phase != Global.GamePhase.AUTO_BATTLE or not is_instance_valid(target) or target.is_queued_for_deletion() \
		or target.current_state == UnitBase.State.DEATH or target._encounter_finished() or target.unit_data.unit_team == source_team \
		or (is_instance_valid(caster) and caster.unit_data.unit_team != source_team):
		clear()
		queue_free()
		return
	destination = to_local(target.global_position)
	for flight: Dictionary in _flights:
		flight["to"] = destination
	super._process(delta)


func _hit(_point: Vector2) -> void:
	var target: UnitBase = target_ref.get_ref()
	var caster: UnitBase = caster_ref.get_ref()
	if not is_instance_valid(target) or not target.get_hurt(damage, caster, false, &"bow", source_floor, false, &"skill") or target.current_state == UnitBase.State.DEATH:
		return
	var mark := target.get_node_or_null("SoldierMissileMark")
	if mark == null:
		mark = load("res://scripts/units/soldier_missile_mark.gd").new()
		mark.name = "SoldierMissileMark"
		mark.source_team = source_team
		target.add_child(mark)
	mark.apply_bonus()
