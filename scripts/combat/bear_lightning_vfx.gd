# 每条连接直接播放实验室雷电Strike配方；起点为上一个受伤单位，而非熊人。
extends "res://assets/effect/eslabong_vfx/skills/skill_player.gd"


func start(caster: UnitBase, from: UnitBase, to: UnitBase) -> void:
	z_index = caster.z_index + 1
	var recipe: Dictionary = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd").find("lightning_strike").duplicate(true)
	# 爪击伤害帧已经完成起手，只复用原版释放、电弧及命中火花。
	recipe.cast_seconds = 0.0
	recipe.windup = []
	play(recipe, to_local(from.to_global(from._smoke_body_rect().get_center())), to_local(to.to_global(to._smoke_body_rect().get_center())), {
		"unit_height": caster._smoke_body_rect().size.y, "launch_offset": Vector2.ZERO, "ground_offset": Vector2.ZERO})
	set_process(false)


func _physics_process(delta: float) -> void:
	if Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		clear()
		queue_free()
		return
	super._process(delta)


func _spawn(data: Dictionary, at: Vector2, controlled: bool = false) -> Node2D:
	var holder := super._spawn(data, at, controlled)
	if holder != null:
		preload("res://scripts/effects/combat_vfx.gd").use_physics_clock(holder)
	return holder
