# 每个单位独立保存异常状态与来源；持续伤害按完整的一秒结算，脱离交锋时冻结计时。
extends Node

const Visuals = preload("res://scripts/effects/combat_vfx.gd")
const IDS := [&"bleed", &"confusion", &"mortal_wounds", &"sleep", &"stun", &"weakness", &"slow", &"taunt", &"armor_break", &"overflow_shield", &"steadfast", &"armor_shred"]
var unit: Node2D
var effects: Dictionary = {}
var visuals: Dictionary = {}
var _visual_sources: Dictionary = {}
var _weakness_penalty := 0
var _armor_break_penalty := 0
var _last_taunt: WeakRef
var _wander_left := 0.0
var _wander_goal := Vector2.ZERO
var _display_left := 0.0
var boss_control_count := 0
var boss_recovery := 0.0


## 首领硬控首次50%、第二次25%；两次后需连续自由行动2秒，避免无限控制。
func control_duration(duration: float) -> float:
	if unit.unit_data.monster_rank < UnitData.MonsterRank.BOSS:
		return duration
	if boss_control_count >= 2:
		return 0.0
	boss_control_count += 1
	boss_recovery = 2.0
	set_physics_process(true)
	return (duration if duration > 0 else 5.0) * (0.5 if boss_control_count == 1 else 0.25)


func _ready() -> void:
	unit = get_parent()
	process_physics_priority = -100
	set_physics_process(false)


func has_status(id: StringName) -> bool:
	return effects.has(id) and not effects[id].is_empty()


func apply_status(id: StringName, duration: float, amount: int, source: Node, source_key: String) -> bool:
	if id not in IDS or unit.is_queued_for_deletion() or unit.current_state == unit.State.DEATH or unit._encounter_finished() \
		or not is_finite(duration) or duration < 0 or (id in [&"bleed", &"weakness", &"armor_break"] and amount <= 0):
		return false
	if id == &"taunt" and (not source is UnitBase or source == unit or source.unit_data.unit_team == unit.unit_data.unit_team \
		or not source.can_be_targeted_by(unit) or not unit.shares_encounter(source)):
		return false
	if source_key.is_empty():
		source_key = str(source.get_instance_id()) if is_instance_valid(source) else "default"
	var boss_sleep: bool = id == &"sleep" and unit.unit_data.monster_rank >= UnitData.MonsterRank.BOSS
	if id in [&"stun", &"sleep"] and unit.unit_data.monster_rank >= UnitData.MonsterRank.BOSS:
		duration = control_duration(duration)
		if duration <= 0:
			return false
	if not effects.has(id):
		effects[id] = {}
	var previous: Dictionary = effects[id].get(source_key, {})
	effects[id][source_key] = {"left": 0.0 if id == &"sleep" and not boss_sleep else duration,
		"permanent": duration == 0 or (id == &"sleep" and not boss_sleep), "amount": amount,
		"elapsed": float(previous.get("elapsed", 0.0)), "source": weakref(source) if is_instance_valid(source) else null}
	unit.skill_manager.interrupt_chant()
	if id in [&"sleep", &"confusion"]:
		unit.stop_status_actions()
		_wander_left = 0.0
	_refresh()
	set_physics_process(true)
	return true


# 卡牌睡眠有自然醒来的期限；技能睡眠仍沿用受击前永久保持的既有规则。
func apply_timed_sleep(duration: float, source: Node, key: String) -> bool:
	if not apply_status(&"sleep", duration, 0, source, key):
		return false
	if unit.unit_data.monster_rank < UnitData.MonsterRank.BOSS:
		effects[&"sleep"][key].left = duration
	effects[&"sleep"][key].permanent = false
	_refresh()
	return true


func remove_status(id: StringName, source_key: String = "") -> void:
	if not effects.has(id):
		return
	if source_key.is_empty():
		effects.erase(id)
	else:
		effects[id].erase(source_key)
		if effects[id].is_empty():
			effects.erase(id)
	if id in [&"sleep", &"confusion"]:
		unit.stop_status_actions()
	_refresh()


func clear() -> void:
	effects.clear()
	boss_control_count = 0
	boss_recovery = 0.0
	_refresh()
	unit.stop_status_actions()
	for visual: Node2D in visuals.values():
		if is_instance_valid(visual):
			visual.hide()
			visual.queue_free()
	visuals.clear()
	_visual_sources.clear()
	set_physics_process(false)


func _refresh() -> void:
	if unit.has_meta("potion_confusion") and not has_status(&"confusion"):
		unit.remove_meta("potion_confusion")
		unit.stop_status_actions()
	unit.set_stunned(has_status(&"stun"), &"status")
	var armor := total_amount(&"armor_break")
	var defence_delta := _armor_break_penalty - armor
	_armor_break_penalty = armor
	if defence_delta != 0:
		unit.adjust_combat_defence(defence_delta)
	_sync_taunt()
	var penalty := total_amount(&"weakness")
	var delta := _weakness_penalty - penalty
	_weakness_penalty = penalty
	if delta != 0:
		var tactics: Node = unit._tactical_runtime()
		if tactics != null:
			tactics.adjust_base_attack(unit, delta)
		else:
			unit.unit_data.attack += delta
	for id: StringName in IDS:
		set_visual(id, has_status(id), &"status")
	unit._refresh_passive_status()
	if effects.is_empty():
		set_physics_process(false)


func total_amount(id: StringName) -> int:
	var result := 0
	for entry: Dictionary in effects.get(id, {}).values():
		result += int(entry.amount)
	return result


func strip_stat_contributions(data: Resource) -> void:
	data.attack += _weakness_penalty
	data.defence += _armor_break_penalty


# 同时受到多个嘲讽时实时比较直线距离；死亡、隐身、策反和跨战场来源均无效。
func taunt_target() -> UnitBase:
	var nearest: UnitBase
	var distance := INF
	for entry: Dictionary in effects.get(&"taunt", {}).values():
		var reference: WeakRef = entry.source
		var source: UnitBase = reference.get_ref() if reference != null else null
		if not is_instance_valid(source) or not source.can_be_targeted_by(unit) \
			or source.unit_data.unit_team == unit.unit_data.unit_team or not unit.shares_encounter(source):
			continue
		var squared: float = unit.global_position.distance_squared_to(source.global_position)
		if squared < distance:
			nearest = source
			distance = squared
	return nearest


func _sync_taunt() -> void:
	var target := taunt_target()
	var previous = _last_taunt.get_ref() if _last_taunt != null else null
	if previous != target:
		unit.skill_manager.clear_target_cache()
		_last_taunt = weakref(target) if target != null else null
	if target != null:
		unit.skill_manager.redirect_to_taunt(target)


func strongest_amount(id: StringName) -> int:
	var result := 0
	for entry: Dictionary in effects.get(id, {}).values():
		result = maxi(result, int(entry.amount))
	return result


# 逻辑来源可重叠；战术卡、技能和外部眩晕共享一个对应动画。
func set_visual(id: StringName, enabled: bool, source: StringName = &"tactics") -> void:
	if not Visuals.STATUS_EFFECTS.has(id):
		return
	if not _visual_sources.has(id):
		_visual_sources[id] = {}
	if enabled:
		_visual_sources[id][source] = true
	else:
		_visual_sources[id].erase(source)
	var active: bool = not _visual_sources[id].is_empty() and unit.current_state != unit.State.DEATH and not unit._encounter_finished()
	var visual: Node2D = visuals.get(id)
	if active and not is_instance_valid(visual):
		visuals[id] = Visuals.spawn(unit, Visuals.STATUS_EFFECTS[id], 0.0)
	elif not active and is_instance_valid(visual):
		visual.hide()
		visual.queue_free()
		visuals.erase(id)


func _physics_process(delta: float) -> void:
	if unit.current_state == unit.State.DEATH or unit._encounter_finished():
		clear()
		return
	if get_tree().paused or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		return
	if boss_control_count > 0 and not unit.is_stunned and not has_status(&"sleep"):
		boss_recovery = maxf(0.0, boss_recovery - delta)
		if boss_recovery <= 0:
			boss_control_count = 0
	var changed := false
	# 回调可能因死亡清空字典；只在快照上遍历，结算每一条来源的有效时间。
	for id: StringName in effects.keys():
		for key: String in effects.get(id, {}).keys():
			var entry: Dictionary = effects[id][key]
			if id == &"taunt":
				var source: Node = entry.source.get_ref() if entry.source != null else null
				if not is_instance_valid(source) or not source.can_be_targeted_by(unit) \
					or source.unit_data.unit_team == unit.unit_data.unit_team or not unit.shares_encounter(source):
					effects[id].erase(key)
					changed = true
					continue
			var step := delta if entry.permanent else minf(delta, float(entry.left))
			if id == &"bleed":
				entry.elapsed += step
				while float(entry.elapsed) + 0.000001 >= 1.0:
					entry.elapsed = maxf(0.0, float(entry.elapsed) - 1.0)
					var reference: WeakRef = entry.source
					var before := maxi(0, int(unit.current_health))
					unit.take_effect_damage(int(entry.amount), reference.get_ref() if reference != null else null, &"bleed")
					var actual := maxi(0, before - maxi(0, int(unit.current_health)))
					var callback: Callable = entry.get("on_damage", Callable())
					if actual > 0 and callback.is_valid():
						callback.call(actual)
					if unit.current_state == unit.State.DEATH or unit._encounter_finished():
						return
			if not entry.permanent:
				entry.left = maxf(0.0, float(entry.left) - delta)
				if float(entry.left) <= 0.000001:
					effects[id].erase(key)
					changed = true
		if effects.has(id) and effects[id].is_empty():
			effects.erase(id)
			if id == &"sleep":
				unit.stop_status_actions()
	if changed:
		_refresh()
	elif has_status(&"taunt"):
		_sync_taunt()
	_display_left -= delta
	if _display_left <= 0:
		_display_left = 0.2
		unit._refresh_passive_status()


# 混乱只提交同层合法导航落点，沿用墙体、避让和飞行规则，不直接穿越地形。
func wander(delta: float) -> void:
	_wander_left -= delta
	if _wander_left <= 0.0 or unit.global_position.distance_to(_wander_goal) < 12.0:
		_wander_left = randf_range(0.45, 1.0)
		var radius := clampf(float(unit.unit_data.speed) * _wander_left, 40.0, 140.0)
		var point: Vector2 = unit.global_position + Vector2.RIGHT.rotated(randf() * TAU) * radius
		if not unit.unit_data.is_flying:
			var map: RID = unit.navigation_agent_2d.get_navigation_map()
			if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
				unit.navigation_agent_2d.stop_navigation()
				return
			point = NavigationServer2D.map_get_closest_point(map, point)
		_wander_goal = point
	unit.navigation_agent_2d.move_to(_wander_goal, unit.floor_id)


func status_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var descriptions := {&"bleed": "流血：每秒受到 %d 点固定伤害，无视防御。" % total_amount(&"bleed"),
		&"confusion": "混乱：随机方向行走，无法自主攻击或施法。", &"mortal_wounds": "禁止治疗：治疗、吸血和生命恢复无效。",
		&"sleep": "睡眠：无法行动，被攻击命中后苏醒。",
		&"stun": "晕眩：无法移动、攻击、施法或反击。", &"weakness": "虚弱：攻击力降低 %d 点。" % total_amount(&"weakness"),
		&"slow": "霜暴减速：移动速度降低 %d，离开风暴范围后恢复，同类取最强。" % strongest_amount(&"slow"),
		&"taunt": "嘲讽：优先攻击有效嘲讽者，多名来源时攻击最近者。",
		&"armor_break": "破甲：防御降低%d，可叠加。" % total_amount(&"armor_break"),
		&"armor_shred": "破甲：每次受到攻击命中，防御降低%d，持续本场。" % total_amount(&"armor_shred"),
		&"overflow_shield": "溢流祷言：本场治疗溢出按1:1转为护盾，交锋结束清除护盾。",
		&"steadfast": "坚守阵地：本场不会被击退。"}
	if unit.is_potion_confused():
		descriptions[&"confusion"] = "混乱药剂：使用普通攻击攻击附近同阵营单位。"
	for id: StringName in effects:
		var left := 0.0
		var permanent := false
		for entry: Dictionary in effects[id].values():
			left = maxf(left, float(entry.left))
			permanent = permanent or bool(entry.permanent)
		var duration := "处于霜暴范围内" if id == &"slow" and permanent else ("受到攻击时解除" if id == &"sleep" and permanent else ("持续本场战斗" if permanent else "剩余 %.1f 秒" % left))
		var status := {"icon": String(id), "tooltip": descriptions[id] + "\n" + duration}
		if id == &"armor_break":
			status["count"] = total_amount(id)
		if id == &"bleed":
			var stacks := 0
			for entry: Dictionary in effects[id].values():
				stacks += int(entry.get("blood_stacks", 0))
			if stacks > 0:
				status["count"] = stacks
				status.tooltip += "\n血影斩击：%d层，每层1点/秒。" % stacks
		result.append(status)
	return result
