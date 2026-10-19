# 实验室位移配方只负责视觉，残影使用当前单位帧和真实轨迹，不控制战斗位移。
extends "res://assets/effect/eslabong_vfx/skills/skill_player.gd"

var unit: UnitBase


func start(caster: UnitBase, id: String, from: Vector2, to: Vector2, seconds: float) -> void:
	unit = caster
	z_index = unit.z_index + 1
	unit.actions_interrupted.connect(cancel)
	var recipe := movement_recipe(id, seconds)
	play(recipe, to_local(from), to_local(to), {"unit_height": unit._smoke_body_rect().size.y})
	set_process(false)
	_update_ghosts()


func movement_recipe(id: String, seconds: float) -> Dictionary:
	var recipe: Dictionary = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd").find(id).duplicate(true)
	for action: Dictionary in recipe.actions:
		if action.kind == "dash":
			action.duration = maxf(0.01, seconds)
			action.react = false
	return recipe


func _physics_process(delta: float) -> void:
	if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEATH or unit._encounter_finished() \
		or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		cancel()
		return
	super._process(delta)
	_update_ghosts()


func _spawn(data: Dictionary, at: Vector2, controlled: bool = false) -> Node2D:
	var holder := super._spawn(data, at, controlled)
	if holder != null:
		preload("res://scripts/effects/combat_vfx.gd").use_physics_clock(holder)
	return holder


func _update_ghosts() -> void:
	for entry: Dictionary in _expirations:
		var ghost := entry.node as Sprite2D
		if not is_instance_valid(ghost):
			continue
		if not ghost.has_meta("unit_ghost"):
			ghost.set_meta("unit_ghost", true)
			ghost.texture = unit.animated_sprite_2d.sprite_frames.get_frame_texture(unit.animated_sprite_2d.animation, unit.animated_sprite_2d.frame)
			ghost.hframes = 1
			ghost.frame = 0
			ghost.global_position = unit.animated_sprite_2d.global_position
			ghost.global_scale = unit.animated_sprite_2d.global_scale
			ghost.offset = unit.animated_sprite_2d.offset
			ghost.flip_h = unit.animated_sprite_2d.flip_h
			ghost.z_index = 0
		ghost.modulate.a = 0.55 * clampf(1.0 - (elapsed - (float(entry.time) - 0.06)) / 0.24, 0.0, 1.0)


func cancel() -> void:
	clear()
	queue_free()
