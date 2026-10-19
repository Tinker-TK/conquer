# 战术卡的独立状态：按单位保存可撤销贡献，统一处理阵容、伤害、击杀和回合清理。
# 不改共享资源；实时乘数从扣除旧贡献后的属性计算，避免重复刷新造成数值漂移。
extends Node

const K = CardEffect.Kind
const ROUND_KINDS := [K.WEAKNESS, K.VULNERABILITY, K.DEFENCE_DOWN, K.PARALYSIS]
const TARGET_KINDS := [K.WEAKNESS, K.VULNERABILITY, K.DEFENCE_DOWN, K.PARALYSIS, K.CONVERT_ENEMY, K.FRENZY, K.JUDGER]
var runtime: Node2D
var records: Dictionary = {}
var composition: CardEffect
var distance_effect: CardEffect
var retreat_uses := 0
var ally_count := 0
var unit_type_count := 0
var _refreshing := false


func setup(owner_runtime: Node2D) -> void:
	runtime = owner_runtime
	set_physics_process(false)


func _alive(unit: UnitBase) -> bool:
	return is_instance_valid(unit) and unit.is_alive()


func register_unit(unit: UnitBase) -> void:
	var id := unit.get_instance_id()
	if records.has(id):
		return
	records[id] = {"unit": unit, "effects": {}, "attack_delta": 0, "defence_delta": 0, "converted": false}
	unit.attack_resolved.connect(_on_attack_resolved)
	unit.kill_confirmed.connect(_on_kill)
	refresh_all()


func forget_unit(id: int) -> void:
	if records.has(id):
		_remove_contribution(records[id])
		records.erase(id)
	refresh_all()


func validate_effect(effect: CardEffect, context: Dictionary) -> String:
	if not is_finite(effect.amount) or effect.amount <= 0:
		return "战术效果数值必须大于零且为有限数字。"
	if effect.kind in [K.WEAKNESS, K.DEFENCE_DOWN, K.JUDGER, K.DIVERSE_ARMY, K.RETREAT_DRAW] and effect.amount != floorf(effect.amount):
		return "属性点数请填写整数。"
	if effect.kind in ROUND_KINDS:
		if effect.lifetime != CardEffect.Lifetime.ROUNDS or effect.lasting_rounds != 1:
			return "此减益只持续当前回合，请配置 Rounds、1 回合。"
	elif effect.lifetime != CardEffect.Lifetime.BATTLE:
		return "此战术效果只支持本场战斗。"
	if effect.kind in TARGET_KINDS:
		var unit := context.target as UnitBase
		if not _alive(unit) or not records.has(unit.get_instance_id()):
			return "请指定场上的有效单位。"
		if effect.kind in ROUND_KINDS + [K.CONVERT_ENEMY] and unit.unit_data.unit_team != "team_b":
			return "此牌只能施加给敌方单位。"
		if effect.kind in [K.FRENZY, K.JUDGER] and unit.unit_data.unit_team != "team_a":
			return "此牌只能施加给己方单位。"
		if effect.kind == K.CONVERT_ENEMY:
			var allowed_ranks := [UnitData.MonsterRank.NORMAL]
			if effect.can_convert_elite:
				allowed_ranks.append(UnitData.MonsterRank.ELITE)
			if unit.unit_data.monster_rank not in allowed_ranks:
				return "策反只能转化普通或精英敌军，不能转化首领或传说单位。" if effect.can_convert_elite else "策反只能转化普通敌军，不能转化精英、首领或传说单位。"
		if effect.kind not in [K.WEAKNESS, K.DEFENCE_DOWN, K.CONVERT_ENEMY] and records[unit.get_instance_id()].effects.has(effect.kind):
			return "该单位已具有此状态，不能叠加。"
	if effect.kind == K.PARALYSIS and (not is_finite(effect.interval) or effect.interval <= effect.amount):
		return "麻痹触发间隔必须大于眩晕时长。"
	if effect.kind == K.VULNERABILITY and effect.amount > 1000:
		return "易伤增幅不能超过 1000%。"
	if effect.kind == K.FRENZY:
		for value in [effect.crowded_stat_percent, effect.solo_attack_bonus_percent, effect.solo_defence_bonus_percent, effect.cooldown_reduction_percent]:
			if not is_finite(value) or value < 0:
				return "狂化百分比必须是非负有限数值。"
		if effect.crowded_unit_count < 2 or effect.crowded_stat_percent > 100 or effect.cooldown_reduction_percent >= 100:
			return "狂化拥挤阈值至少为2，拥挤攻防不超过100%，冷却减少不能达到100%。"
	if effect.kind in [K.DIVERSE_ARMY, K.KEEP_DISTANCE]:
		if context.card.definition.after_use != CardDefinition.AfterUse.PERSIST:
			return "全场持续效果需要设置为常驻卡牌。"
		if (effect.kind == K.DIVERSE_ARMY and composition != null) or (effect.kind == K.KEEP_DISTANCE and distance_effect != null):
			return "本场已启用此常驻效果，不能叠加。"
	if effect.kind == K.DIVERSE_ARMY and effect.required_unit_types < 1:
		return "所需兵种种类必须至少为1。"
	if effect.kind == K.KEEP_DISTANCE and (not is_finite(effect.minimum_attack_percent) \
		or not is_finite(effect.distance_for_max_bonus) or effect.distance_for_max_bonus <= 0 \
		or effect.minimum_attack_percent < 0 or effect.minimum_attack_percent > effect.amount):
		return "保持距离的远端距离必须大于零，近身攻击百分比不能大于远端。"
	return ""


func apply_effect(effect: CardEffect, context: Dictionary) -> void:
	if effect.kind in ROUND_KINDS and is_instance_valid(context.get("target")):
		context.target.skill_manager.interrupt_chant()
	var snapshot := effect.duplicate() as CardEffect
	set_physics_process(true)
	match effect.kind:
		K.RETREAT_DRAW:
			retreat_uses += int(effect.amount)
		K.DIVERSE_ARMY:
			composition = snapshot
		K.KEEP_DISTANCE:
			distance_effect = snapshot
		K.CONVERT_ENEMY:
			_convert(context.target)
		_:
			var record: Dictionary = records[context.target.get_instance_id()]
			if record.effects.has(effect.kind):
				record.effects[effect.kind].total += effect.amount
				record.effects[effect.kind].stacks += 1
			else:
				record.effects[effect.kind] = {"effect": snapshot, "total": effect.amount, "stacks": 1,
					"elapsed": 0.0, "kills": 0, "label": context.card.definition.card_name}
	refresh_all()


func _convert(unit: UnitBase) -> void:
	var id := unit.get_instance_id()
	unit.skill_manager.interrupt_actions()
	unit.navigation_agent_2d.stop_navigation()
	unit.target_position = null
	unit.unit_data.unit_team = "team_a"
	unit.remove_from_group("team_b")
	unit.add_to_group("team_a")
	# 策反单位只自动作战，不进入玩家的部署选择与右键操控。
	unit.add_to_group("converted_enemy")
	unit.set_collision_layer_value(2, false)
	unit.set_collision_layer_value(1, true)
	# 同树换队保持状态、血量和信号；临时断开退树清理，不重新登记同一单位。
	var exit_callback: Callable = runtime._forget_unit.bind(id)
	if unit.tree_exited.is_connected(exit_callback):
		unit.tree_exited.disconnect(exit_callback)
	unit.reparent(runtime.battle.get_node("Entities/TeamA"), true)
	unit.tree_exited.connect(exit_callback, CONNECT_ONE_SHOT)
	records[id].converted = true
	for record: Dictionary in records.values():
		var other := record.unit as UnitBase
		if not _alive(other):
			continue
		other.skill_manager.clear_target_cache()
		if other.skill_manager.current_target == unit or other.skill_manager.cast_target == unit:
			other.skill_manager.interrupt_actions()
	runtime._apply_aura(unit)
	runtime.rounds.request_round_check()


func _count_allies() -> void:
	ally_count = 0
	var types := {}
	for record: Dictionary in records.values():
		var unit := record.unit as UnitBase
		if _alive(unit) and unit.unit_data.unit_team == "team_a":
			ally_count += 1
			types[unit.unit_data.unit_type] = true
	unit_type_count = types.size()


func _remove_contribution(record: Dictionary) -> void:
	var unit = record.unit
	if is_instance_valid(unit):
		unit.unit_data.attack -= int(record.attack_delta)
		unit.unit_data.defence -= int(record.defence_delta)
	record.attack_delta = 0
	record.defence_delta = 0


func strip_stat_contributions(unit: UnitBase, data: UnitData) -> void:
	var record: Dictionary = records.get(unit.get_instance_id(), {})
	data.attack -= int(record.get("attack_delta", 0))
	data.defence -= int(record.get("defence_delta", 0))


# 驻场光环改变可撤销的基础加法时，先撤销当前战术贡献，避免百分比加成残留或漂移。
func adjust_base_attack(unit: UnitBase, delta: int) -> void:
	var record: Dictionary = records.get(unit.get_instance_id(), {})
	if not record.is_empty():
		_remove_contribution(record)
	unit.unit_data.attack += delta
	refresh_all()


func adjust_base_defence(unit: UnitBase, delta: int) -> void:
	var record: Dictionary = records.get(unit.get_instance_id(), {})
	if not record.is_empty():
		_remove_contribution(record)
	unit.unit_data.defence += delta
	refresh_all()


func refresh_all() -> void:
	if _refreshing or not is_instance_valid(runtime):
		return
	_refreshing = true
	_count_allies()
	for record: Dictionary in records.values():
		var unit := record.unit as UnitBase
		if not _alive(unit):
			continue
		_remove_contribution(record)
		var base_attack := unit.unit_data.attack
		var base_defence := unit.unit_data.defence
		var attack := float(base_attack)
		var defence := float(base_defence)
		if runtime.expanded != null:
			var bonus: Vector2i = runtime.expanded.stat_bonus(unit)
			attack += bonus.x
			defence += bonus.y
		var cooldown := 1.0
		var relics: Node = runtime.battle.get_node_or_null("RelicRuntime")
		var relic_mods: Dictionary = relics.stat_modifiers(unit, ally_count, unit_type_count) if relics != null else {}
		attack += int(relic_mods.get("attack", 0))
		defence += int(relic_mods.get("defence", 0))
		var attack_percent := float(relic_mods.get("attack_percent", 0.0))
		var defence_percent := float(relic_mods.get("defence_percent", 0.0))
		var cooldown_reduction := float(relic_mods.get("cooldown", 0.0))
		if record.effects.has(K.WEAKNESS):
			attack -= float(record.effects[K.WEAKNESS].total)
		if record.effects.has(K.DEFENCE_DOWN):
			defence -= float(record.effects[K.DEFENCE_DOWN].total)
		if record.effects.has(K.JUDGER):
			attack += int(record.effects[K.JUDGER].kills) * float(record.effects[K.JUDGER].total)
		if unit.unit_data.unit_team == "team_a" and composition != null and unit_type_count >= composition.required_unit_types:
			attack += composition.amount
		if record.effects.has(K.FRENZY):
			var effect: CardEffect = record.effects[K.FRENZY].effect
			if ally_count >= effect.crowded_unit_count:
				attack *= effect.crowded_stat_percent / 100.0
				defence *= effect.crowded_stat_percent / 100.0
			elif ally_count == 1:
				attack_percent += effect.solo_attack_bonus_percent / 100.0
				defence_percent += effect.solo_defence_bonus_percent / 100.0
				cooldown_reduction += effect.cooldown_reduction_percent / 100.0
		attack *= 1.0 + minf(0.60, attack_percent)
		defence *= 1.0 + minf(0.60, defence_percent)
		cooldown = 1.0 - minf(0.60, cooldown_reduction)
		unit.unit_data.attack = maxi(0, roundi(attack))
		unit.unit_data.defence = roundi(defence)
		record.attack_delta = unit.unit_data.attack - base_attack
		record.defence_delta = unit.unit_data.defence - base_defence
		unit.get_node("SkillManager").set_cooldown_multiplier(cooldown)
		if unit.status_runtime != null:
			unit.status_runtime.set_visual(&"weakness", record.effects.has(K.WEAKNESS))
			unit.status_runtime.set_visual(&"converted", record.converted)
		runtime._refresh_unit_status(unit)
	_refreshing = false


# 距离倍率在扣防御之前应用；易伤在扣防御之后应用，所有攻击入口共用。
func attack_damage(target: UnitBase, attacker: UnitBase, raw_damage: int, defence_segments: int = 1) -> int:
	var value := float(raw_damage)
	var percent := 0.0
	if is_instance_valid(attacker) and attacker.unit_data.unit_team == "team_a" and distance_effect != null:
		var fraction := clampf(attacker.global_position.distance_to(target.global_position) / distance_effect.distance_for_max_bonus, 0.0, 1.0)
		percent += lerpf(distance_effect.minimum_attack_percent, distance_effect.amount, fraction) / 100.0 - 1.0
	var relics: Node = runtime.battle.get_node_or_null("RelicRuntime")
	if relics != null:
		percent += relics.attack_percent(attacker, target)
	value *= 1.0 + clampf(percent, -0.99, 0.60)
	value -= ceili(float(target.unit_data.defence) / maxi(1, defence_segments))
	var record: Dictionary = records.get(target.get_instance_id(), {})
	if record.get("effects", {}).has(K.VULNERABILITY):
		value *= 1.0 + float(record.effects[K.VULNERABILITY].total) / 100.0
	return maxi(1, int(value))


func _on_attack_resolved(victim: UnitBase, attacker: UnitBase, actual_damage: int) -> void:
	if runtime.battle.battle_finished or not _alive(attacker) or actual_damage <= 0:
		return
	if attacker.unit_data.unit_team != "team_a" or victim.unit_data.unit_team == "team_a":
		return
	_count_allies()
	var record: Dictionary = records.get(attacker.get_instance_id(), {})
	if ally_count == 1 and record.get("effects", {}).has(K.FRENZY):
		var effect: CardEffect = record.effects[K.FRENZY].effect
		attacker.get_heal(int(actual_damage * effect.amount / 100.0))


func _on_kill(victim: UnitBase, killer: UnitBase) -> void:
	if runtime.battle.battle_finished or not _alive(killer):
		return
	if killer.unit_data.unit_team != "team_a" or victim.unit_data.unit_team == "team_a":
		return
	var record: Dictionary = records.get(killer.get_instance_id(), {})
	if record.get("effects", {}).has(K.JUDGER):
		record.effects[K.JUDGER].kills += 1
		refresh_all()


func unit_died(unit: UnitBase) -> void:
	var record: Dictionary = records.get(unit.get_instance_id(), {})
	if not record.is_empty():
		_remove_contribution(record)
		record.effects.clear()
		unit.set_stunned(false)
	refresh_all()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(runtime) or runtime.battle.battle_finished:
		return
	if Global.game_phase == Global.GamePhase.AUTO_BATTLE:
		for record: Dictionary in records.values():
			var unit := record.unit as UnitBase
			if not _alive(unit) or not record.effects.has(K.PARALYSIS):
				continue
			var entry: Dictionary = record.effects[K.PARALYSIS]
			var effect: CardEffect = entry.effect
			entry.elapsed += delta
			var elapsed := float(entry.elapsed)
			var cycle := floori(elapsed / effect.interval)
			if cycle > int(entry.get("control_cycle", 0)):
				entry.control_cycle = cycle
				unit.apply_status(&"stun", effect.amount, 0, null, "tactical_paralysis")
	refresh_all()


func end_round() -> void:
	_count_allies()
	runtime.hand.pending_bonus_draw += ally_count * retreat_uses
	retreat_uses = 0
	for record: Dictionary in records.values():
		for kind in ROUND_KINDS:
			record.effects.erase(kind)
		var unit = record.unit
		if is_instance_valid(unit):
			unit.set_stunned(false)
	refresh_all()


func clear_battle() -> void:
	composition = null
	distance_effect = null
	retreat_uses = 0
	runtime.hand.pending_bonus_draw = 0
	for record: Dictionary in records.values():
		_remove_contribution(record)
		record.effects.clear()
		record.converted = false
		var unit = record.unit
		if is_instance_valid(unit):
			unit.set_stunned(false)
			unit.get_node("SkillManager").set_cooldown_multiplier(1.0)
	set_physics_process(false)


func statuses_for(unit: UnitBase) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var record: Dictionary = records.get(unit.get_instance_id(), {})
	if record.is_empty():
		return result
	for kind in record.effects:
		var entry: Dictionary = record.effects[kind]
		var effect: CardEffect = entry.effect
		var text := ""
		var icon := ""
		match kind:
			K.WEAKNESS:
				icon = "weakness"
				text = "虚弱：攻击力降低 %d 点 · %d 层\n当前回合，回合结束清除。" % [int(entry.total), int(entry.stacks)]
			K.DEFENCE_DOWN:
				icon = "defence_down"
				text = "恐吓：防御降低 %d 点 · %d 层\n当前回合，回合结束清除。" % [int(entry.total), int(entry.stacks)]
			K.VULNERABILITY:
				icon = "vulnerability"
				text = "易伤：受到的攻击伤害在扣防御后增加 %.0f%%\n当前回合，不叠加，回合结束清除。" % entry.total
			K.PARALYSIS:
				icon = "paralysis"
				text = "麻痹：每 %.1f 秒眩晕 %.1f 秒\n眩晕期间不能移动、攻击、施法或反击。\n当前回合，不叠加。" % [effect.interval, effect.amount]
			K.FRENZY:
				icon = "frenzy"
				var mode := "攻防100%"
				if ally_count >= effect.crowded_unit_count:
					mode = "攻防%.0f%%" % effect.crowded_stat_percent
				elif ally_count == 1:
					mode = "攻击+%.0f%%，防御+%.0f%%，冷却-%.0f%%" % [effect.solo_attack_bonus_percent, effect.solo_defence_bonus_percent, effect.cooldown_reduction_percent]
				text = "狂化：己方存活 %d 个，%s\n本场战斗，随阵容实时变化。" % [ally_count, mode]
			K.JUDGER:
				icon = "judger"
				text = "审判者：已击杀 %d 名敌人，攻击+%d\n每次击杀攻击+%d，持续本场战斗。" % [int(entry.kills), int(entry.kills * entry.total), int(entry.total)]
		if not icon.is_empty():
			var status := {"icon": icon, "tooltip": text}
			if kind in [K.WEAKNESS, K.DEFENCE_DOWN]:
				status.count = int(entry.stacks)
			result.append(status)
		if kind == K.FRENZY and ally_count == 1:
			result.append({"icon": "lifesteal", "tooltip": "吸血：回复对敌人实际造成伤害的 %.0f%%\n不计过量伤害。" % effect.amount})
	if record.converted:
		result.append({"icon": "converted", "tooltip": "策反：该敌军已转为己方，协助攻击敌人。\n不可点击或框选操控，只自动作战。\n没有原征召牌，退场不产生新卡牌。"})
	if unit.unit_data.unit_team == "team_a":
		if composition != null:
			result.append({"icon": "composition", "tooltip": "合理搭配：己方 %d 种兵种，需至少 %d 种\n当前攻击+%d，随阵容实时变化，持续本场。" % [unit_type_count, composition.required_unit_types, int(composition.amount) if unit_type_count >= composition.required_unit_types else 0]})
		if distance_effect != null:
			result.append({"icon": "distance", "tooltip": "保持距离：攻击为 %.0f%%～%.0f%%\n近身为最低值，%.0f 像素达到最高值，中间线性变化。\n按攻击者与受击目标的实际距离，在扣防御前计算。" % [distance_effect.minimum_attack_percent, distance_effect.amount, distance_effect.distance_for_max_bonus]})
	return result
