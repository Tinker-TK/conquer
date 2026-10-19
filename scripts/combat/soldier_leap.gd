# 复用实验室 Wild Boar Gore 的突进/残影流程，落点改为实战可站立位置。
extends "res://assets/effect/eslabong_vfx/skills/skill_player.gd"

const DASH_SECONDS := 0.28
const GHOST_OPACITY := 0.65
const GHOST_HOLD_SECONDS := 0.06
const GHOST_FADE_SECONDS := 0.18

var caster: UnitBase
var victim: WeakRef
var landing := Vector2.ZERO
var arrived := false


func start(unit: UnitBase, target: UnitBase, at: Vector2) -> void:
	caster = unit
	victim = weakref(target)
	landing = at
	# 原预览残影为-1层，在实战会落到不透明地形/测试场背景下面。
	z_index = maxi(caster.z_index, target.z_index) + 1
	caster.skill_manager.is_forced_moving = true
	caster.navigation_agent_2d.stop_navigation()
	caster.actions_interrupted.connect(_cancel)
	var recipe: Dictionary = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd").find("wild_boar_bite").duplicate(true)
	# 保留原突进与残影时序，拉长0.12秒的位移，仍在0.3秒命中帧前落地。
	for action: Dictionary in recipe.actions:
		if action.kind == "dash":
			action.duration = DASH_SECONDS
	caster_moved.connect(_move_caster)
	var direction := caster.global_position.direction_to(landing)
	# 原播放器在冲刺终点前留出1.3个人物高度，补偿后恰好落在有效落点。
	play(recipe, to_local(caster.global_position), to_local(landing + direction * 62.4), {"unit_height": 48.0, "ghost_sprite_offset": caster.animated_sprite_2d.position, "auto_free": true})
	_update_ghosts()
	set_process(false)


func _move_caster(point: Vector2) -> void:
	if not arrived and is_instance_valid(caster):
		caster.global_position = to_global(point)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(caster) or caster.current_state == UnitBase.State.DEATH or not caster.can_use_skills() \
		or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		_cancel()
		return
	super._process(delta)
	_update_ghosts()
	if not arrived and _flights.is_empty():
		arrived = true
		caster.global_position = landing
		var target: UnitBase = victim.get_ref()
		if is_instance_valid(target):
			caster.set_floor(target.floor_id)
		caster.navigation_agent_2d.reset_after_teleport()
		caster.skill_manager.is_forced_moving = false


func _update_ghosts() -> void:
	for entry: Dictionary in _expirations:
		var ghost := entry.node as Sprite2D
		if not is_instance_valid(ghost):
			continue
		# 只在生成时截取真实士兵帧，旧残影保持自己的姿势与位置。
		if not ghost.has_meta("soldier_ghost"):
			ghost.set_meta("soldier_ghost", true)
			ghost.texture = caster.animated_sprite_2d.sprite_frames.get_frame_texture(caster.animated_sprite_2d.animation, caster.animated_sprite_2d.frame)
			ghost.hframes = 1
			ghost.frame = 0
			ghost.global_scale = caster.animated_sprite_2d.global_scale
			ghost.global_rotation = caster.animated_sprite_2d.global_rotation
			ghost.offset = caster.animated_sprite_2d.offset
			ghost.flip_h = caster.animated_sprite_2d.flip_h
			ghost.flip_v = caster.animated_sprite_2d.flip_v
			ghost.z_index = 0
		# 原播放器保留0.06秒后淡出0.18秒；显式保持透明度连续，避免突然变实。
		var born := float(entry.time) - GHOST_HOLD_SECONDS
		ghost.modulate.a = GHOST_OPACITY * clampf(1.0 - (elapsed - born) / (GHOST_HOLD_SECONDS + GHOST_FADE_SECONDS), 0.0, 1.0)


func _cancel() -> void:
	if is_instance_valid(caster):
		caster.skill_manager.is_forced_moving = false
	clear()
	queue_free()
