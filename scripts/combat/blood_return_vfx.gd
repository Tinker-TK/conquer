# 鲜血回归复用实验室 Vampiric · Psalm 的完整五次反向吸血光束配方。
extends "res://assets/effect/eslabong_vfx/skills/skill_player.gd"

var knight: WeakRef
var victim: WeakRef
var last_position := Vector2.ZERO


func start(caster: UnitBase, target: WeakRef, from: Vector2) -> void:
	knight = weakref(caster)
	victim = target
	last_position = from
	z_index = caster.z_index + 1
	var recipe: Dictionary = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd").find("shadow_priest_vampiric_psalm").duplicate(true)
	recipe.cast_seconds = 0.0
	var body := caster._smoke_body_rect()
	play(recipe, to_local(caster.to_global(body.get_center())), to_local(from), {
		"unit_height": body.size.y, "launch_offset": Vector2.ZERO, "ground_offset": Vector2.ZERO})
	set_process(false)


func _spawn(data: Dictionary, at: Vector2, controlled: bool = false) -> Node2D:
	var holder := super._spawn(data, at, controlled)
	if holder != null:
		var root: Node2D = holder.get_meta("visual_root")
		root.set_process(false)
	return holder


func _physics_process(delta: float) -> void:
	var caster: UnitBase = knight.get_ref()
	if not is_instance_valid(caster) or caster.current_state == UnitBase.State.DEATH or caster._encounter_finished() \
		or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		clear()
		queue_free()
		return
	var target: UnitBase = victim.get_ref()
	if is_instance_valid(target) and target.current_state != UnitBase.State.DEATH:
		last_position = target.to_global(target._smoke_body_rect().get_center())
	var center := caster.to_global(caster._smoke_body_rect().get_center())
	source = to_local(center)
	destination = to_local(last_position)
	super._process(delta)
	for holder in get_children():
		if holder.has_meta("visual_root"):
			# 子特效结束时可能已释放根对象，先检查再使用，避免类型赋值先触发失效引用错误。
			var root = holder.get_meta("visual_root")
			if is_instance_valid(root):
				root.points = PackedVector2Array([last_position, center])
				root._process(delta)
