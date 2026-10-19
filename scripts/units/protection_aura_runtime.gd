# 每个光环只登记自己庇护的单位；离开、死亡和退树时撤销，资源不保存运行状态。
extends Node2D

var caster: UnitBase
var skill
var targets: Dictionary = {}
var visual: Node2D
var _visual_radius := -1.0


func _ready() -> void:
	name = "ProtectionAura"
	caster.unit_died.connect(_on_caster_died)
	if skill.aura_effect != null:
		visual = skill.aura_effect.instantiate() as Node2D
		if visual != null:
			# 与单位同层，避免负 Z 值被测试场的背景遮住。
			visual.z_index = 0
			if visual is GPUParticles2D:
				visual.process_material = visual.process_material.duplicate(true)
				visual.local_coords = true
			add_child(visual)
	_sync_visual()
	refresh.call_deferred()


func _alive(unit: UnitBase) -> bool:
	return is_instance_valid(unit) and unit.is_inside_tree() and not unit.is_queued_for_deletion() \
		and unit.current_state != UnitBase.State.DEATH and int(unit.current_health) > 0


func _sync_visual() -> void:
	if not is_instance_valid(visual) or is_equal_approx(_visual_radius, skill.aura_radius):
		return
	_visual_radius = maxf(1.0, skill.aura_radius)
	if visual is GPUParticles2D and visual.process_material is ParticleProcessMaterial:
		visual.process_material.emission_ring_radius = _visual_radius
		visual.process_material.emission_ring_inner_radius = maxf(0.0, _visual_radius - 7.0)
		visual.visibility_rect = Rect2(Vector2.ONE * (-_visual_radius - 40), Vector2.ONE * (2 * _visual_radius + 80))
	else:
		visual.scale = Vector2.ONE * _visual_radius / 60.0


func refresh() -> void:
	if not _alive(caster) or caster.unit_data.unit_team != "team_a" or caster._encounter_finished() \
		or not caster.unit_data.is_skill_unlocked(skill):
		clear()
		return
	if is_instance_valid(visual):
		visual.show()
	_sync_visual()
	var next: Dictionary = {}
	var radius_squared: float = maxf(0.0, skill.aura_radius) ** 2
	# 使用本阵营容器，避免其他战场或独立预览中的同名单位受到光环影响。
	for node in caster.get_parent().get_children():
		var unit := node as UnitBase
		if not _alive(unit) or unit.unit_data.unit_team != "team_a":
			continue
		if unit == caster and not skill.aura_include_caster:
			continue
		if caster.global_position.distance_squared_to(unit.global_position) <= radius_squared:
			unit.set_protection_source(get_instance_id(), skill.aura_attack_bonus, skill.skill_name, skill.aura_radius)
			next[unit.get_instance_id()] = weakref(unit)
	for id in targets:
		if not next.has(id):
			var unit = targets[id].get_ref()
			if is_instance_valid(unit):
				unit.remove_protection_source(get_instance_id())
	targets = next


func clear() -> void:
	for reference: WeakRef in targets.values():
		var unit = reference.get_ref()
		if is_instance_valid(unit):
			unit.remove_protection_source(get_instance_id())
	targets.clear()
	if is_instance_valid(visual):
		visual.hide()


func _on_caster_died(_unit: UnitBase) -> void:
	clear()


func _exit_tree() -> void:
	clear()


func _physics_process(_delta: float) -> void:
	refresh()
