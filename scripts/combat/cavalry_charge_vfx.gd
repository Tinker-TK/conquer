# Flying Kick原冲刺残影和蓝色命中配方，Blazing火花沿实际移动路径生成。
# 实战位移由冲锋节点负责，预览的瞬移和伤害回调不控制骑兵。
extends "res://assets/effect/eslabong_vfx/skills/skill_player.gd"

const SPARKS := "scenes_vfx_blazingdashtrailsparks"
var caster: UnitBase
var moving := true
var spark_left := 0.0
var hit_recipe: Array[Dictionary] = []


func start(unit: UnitBase, from: Vector2, to: Vector2, seconds: float) -> void:
	caster = unit
	caster.actions_interrupted.connect(cancel)
	z_index = caster.z_index + 1
	var recipe: Dictionary = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd").find("flyingkick_monk").duplicate(true)
	var motion: Dictionary = recipe.actions[0].duplicate(true)
	for action: Dictionary in recipe.actions:
		if action.kind == "melee":
			for hit: Dictionary in action.on_hit:
				hit_recipe.append(hit.merged({"delay": action.start}, true))
	motion.duration = seconds
	motion.on_hit = []
	motion.react = false
	recipe.actions = [motion]
	recipe.cast_seconds = 0.0
	var direction := from.direction_to(to)
	var height := caster._smoke_body_rect().size.y
	play(recipe, to_local(from), to_local(to + direction * height * 1.3), {"unit_height": height, "auto_free": true})
	set_process(false)
	_update_ghosts()
	_spawn_sparks()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(caster) or caster.current_state == UnitBase.State.DEATH or caster._encounter_finished() \
		or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		cancel()
		return
	super._process(delta)
	_update_ghosts()
	if moving:
		spark_left -= delta
		if spark_left <= 0:
			spark_left += 0.04
			_spawn_sparks()


func _spawn_sparks() -> void:
	_spawn({"effect": SPARKS, "duration": 0.24}, to_local(caster.global_position))


func impact(target: UnitBase) -> void:
	var at := to_local(target.to_global(target._smoke_body_rect().get_center()))
	for hit: Dictionary in hit_recipe:
		_schedule(elapsed + float(hit.delay), "effect", hit.merged({"position": at}, true))


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
		if not ghost.has_meta("cavalry_ghost"):
			ghost.set_meta("cavalry_ghost", true)
			ghost.texture = caster.animated_sprite_2d.sprite_frames.get_frame_texture(caster.animated_sprite_2d.animation, caster.animated_sprite_2d.frame)
			ghost.hframes = 1
			ghost.frame = 0
			ghost.global_position = caster.animated_sprite_2d.global_position
			ghost.global_scale = caster.animated_sprite_2d.global_scale
			ghost.global_rotation = caster.animated_sprite_2d.global_rotation
			ghost.offset = caster.animated_sprite_2d.offset
			ghost.flip_h = caster.animated_sprite_2d.flip_h
			ghost.flip_v = caster.animated_sprite_2d.flip_v
			ghost.z_index = 0
		var born := float(entry.time) - 0.06
		ghost.modulate.a = 0.55 * clampf(1.0 - (elapsed - born) / 0.24, 0.0, 1.0)


func stop_movement() -> void:
	moving = false
	_flights.clear()


func cancel() -> void:
	clear()
	queue_free()
