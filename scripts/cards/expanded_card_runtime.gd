# 扩展卡牌的本场状态；所有计数、复活队列和战术设施随战场结束释放。
extends Node

const K = CardEffect.Kind
const TARGET_ENEMY := [K.BLEED, K.HEALING_BAN, K.ARMOR_SHRED, K.SLEEP]
const TARGET_ALLY := [K.SHIELD, K.OVERFLOW_SHIELD, K.MISSING_HEALTH_SHIELD, K.KNOCKBACK_IMMUNITY]
const PERSISTENT := [K.SACRIFICE, K.DEATH_DRAW, K.ARMY_ATTACK, K.ARMY_DEFENCE, K.ARMY_SPEED, K.THRIFT]
const PROPS = preload("res://scripts/effects/tactical_prop.gd")
var runtime: Node2D
var army_attack := 0
var army_defence := 0
var army_speed := 0.0
var death_draw := 0
var sacrifices: Array[Dictionary] = []
var fallen: Array[Dictionary] = []
var structures: Array[Dictionary] = []
var energy_modifiers: Array[Dictionary] = []
var extra_draw := 0
var _catalog: Array[Resource] = []
var _death_ids: Dictionary = {}


func setup(owner_runtime: Node2D) -> void:
	runtime = owner_runtime
	set_physics_process(false)


func handles(kind: int) -> bool:
	return kind >= K.BLEED and kind <= K.THRIFT


func selection_effect(card: CardInstance) -> CardEffect:
	for effect: CardEffect in card.definition.effects:
		if effect != null and effect.kind in [K.TUTOR_UNIT, K.DISCARD_DRAW]:
			return effect
	return null


func candidates(card: CardInstance) -> Array[CardInstance]:
	var effect := selection_effect(card)
	var result: Array[CardInstance] = []
	if effect == null:
		return result
	var pile: Array = runtime.hand.draw_pile if effect.kind == K.TUTOR_UNIT else runtime.hand.hand
	for candidate: CardInstance in pile:
		if candidate != card and (effect.kind != K.TUTOR_UNIT or candidate.is_unit_card()):
			result.append(candidate)
	return result


func selection_count(card: CardInstance) -> int:
	var effect := selection_effect(card)
	return mini(int(effect.amount), candidates(card).size()) if effect != null and effect.kind == K.TUTOR_UNIT else 1


func needs_choice(context: Dictionary) -> bool:
	return selection_effect(context.card) != null and context.get("selected_cards", []).is_empty()


func random_choice(context: Dictionary) -> void:
	if not needs_choice(context):
		return
	var available := candidates(context.card)
	available.shuffle()
	context.selected_cards = available.slice(0, selection_count(context.card))


func validate(effect: CardEffect, context: Dictionary) -> String:
	if effect.lifetime != CardEffect.Lifetime.BATTLE:
		return "此扩展效果仅支持本场战斗。"
	if not is_finite(effect.amount) or effect.amount <= 0 or effect.amount != floorf(effect.amount):
		return "效果点数、比例和数量必须为正整数。"
	if effect.kind in TARGET_ENEMY + TARGET_ALLY:
		var unit := context.target as UnitBase
		if not is_instance_valid(unit) or not unit.is_alive():
			return "请选择场上的有效单位。"
		var team := "team_b" if effect.kind in TARGET_ENEMY else "team_a"
		if unit.unit_data.unit_team != team:
			return "请选择敌方单位。" if team == "team_b" else "请选择己方单位。"
		var unique := {K.ARMOR_SHRED: &"armor_shred", K.OVERFLOW_SHIELD: &"overflow_shield", K.KNOCKBACK_IMMUNITY: &"steadfast"}
		if unique.has(effect.kind) and unit.has_status(unique[effect.kind]):
			return "该单位已具有此状态，不能重复施加。"
	if effect.kind in [K.BLEED, K.HEALING_BAN, K.SLEEP, K.SPIKE_TRAP] \
		and (not is_finite(effect.status_seconds) or effect.status_seconds <= 0):
		return "状态持续时间必须为正数。"
	if effect.kind in PERSISTENT and context.card.definition.after_use != CardDefinition.AfterUse.PERSIST:
		return "此效果需要配置为常驻牌。"
	if effect.kind in [K.TUTOR_UNIT, K.DISCARD_DRAW]:
		var available := candidates(context.card)
		if available.is_empty():
			return "抽牌堆没有单位牌。" if effect.kind == K.TUTOR_UNIT else "需要另一张手牌用于弃置。"
		var selected: Array = context.get("selected_cards", [])
		if not selected.is_empty():
			if selected.size() != selection_count(context.card):
				return "请选择规定数量的卡牌。"
			var seen := {}
			for card in selected:
				if not card is CardInstance or not available.has(card) or seen.has(card.id):
					return "所选卡牌已离开目标牌堆或被重复选择。"
				seen[card.id] = true
	if effect.kind in [K.DISCARD_DRAW, K.TRANSCRIBE] and runtime.hand.draw_locked:
		return "本回合已禁止抽牌。"
	if effect.kind == K.TRANSCRIBE and runtime.hand.hand.size() <= (1 if runtime.hand.hand.has(context.card) else 0):
		return "需要至少一张其它手牌。"
	if effect.kind == K.RESURRECT:
		if resurrection_candidate().is_empty():
			return "本场没有可复活的己方阵亡单位。"
		if effect.amount > 100:
			return "复活生命百分比不能超过100。"
	if effect.kind == K.REFORMATION:
		var eligible := transform_candidates(context.card)
		if eligible.size() < int(effect.amount):
			return "需要至少%d张可变为同费用其它牌的手牌。" % int(effect.amount)
	if effect.kind in [K.BATTLE_STANDARD, K.SPIKE_TRAP] and (not is_finite(effect.radius) or effect.radius <= 0):
		return "设施范围必须大于零。"
	return ""


# 复活在支付费用前准备真实单位，场景损坏时不消耗卡牌和能量。
func prepare(context: Dictionary) -> bool:
	for effect: CardEffect in context.card.definition.effects:
		if effect.kind != K.RESURRECT:
			continue
		var entry := resurrection_candidate()
		if entry.is_empty():
			return false
		var original: CardInstance = entry.card
		var data: UnitData = original.get_summon_data() if original != null else entry.data.duplicate()
		context.prepared = runtime._prepare_unit(data)
		context.resurrection = entry
		return context.prepared != null
	return true


func apply(effect: CardEffect, context: Dictionary) -> void:
	var target := context.target as UnitBase
	var key := "card_%d" % context.card.id
	var amount := int(effect.amount)
	match effect.kind:
		K.BLEED:
			target.apply_status(&"bleed", effect.status_seconds, amount, null, key)
		K.HEALING_BAN:
			target.apply_status(&"mortal_wounds", effect.status_seconds, 0, null, key)
		K.SLEEP:
			target.status_runtime.apply_timed_sleep(effect.status_seconds, null, key)
		K.ARMOR_SHRED:
			target.apply_status(&"armor_shred", 0, amount, null, key)
		K.SHIELD:
			target.add_shield(amount)
		K.MISSING_HEALTH_SHIELD:
			target.add_shield(floori(maxi(0, target.unit_data.max_hp - int(target.current_health)) * effect.amount / 100.0))
		K.OVERFLOW_SHIELD:
			target.apply_status(&"overflow_shield", 0, 0, null, key)
		K.KNOCKBACK_IMMUNITY:
			target.apply_status(&"steadfast", 0, 0, null, key)
			var motion := target.get_node_or_null("KnockbackMotion")
			if motion != null:
				motion.finish()
		K.TUTOR_UNIT:
			for card: CardInstance in context.selected_cards:
				runtime.hand.draw_pile.erase(card)
				runtime.hand.hand.append(card)
				runtime.hand.card_motion_requested.emit(card, &"draw", Vector2.ZERO)
			_notify_piles()
		K.DISCARD_DRAW:
			var card: CardInstance = context.selected_cards[0]
			runtime.hand.hand.erase(card)
			runtime.hand.discard_pile.append(card)
			card.next_unit_discount = false
			card.free_until_discard = false
			runtime.hand.card_motion_requested.emit(card, &"discard", Vector2.ZERO)
			runtime.hand.draw_cards(amount)
		K.SACRIFICE:
			sacrifices.append({"threshold": amount, "kills": 0})
		K.RESURRECT:
			_resurrect(effect, context)
		K.DEATH_DRAW:
			death_draw += amount
		K.ARMY_ATTACK:
			army_attack += amount
		K.ARMY_DEFENCE:
			army_defence += amount
		K.ARMY_SPEED:
			army_speed += effect.amount
		K.BATTLE_STANDARD, K.SPIKE_TRAP:
			var prop := PROPS.new()
			prop.is_banner = effect.kind == K.BATTLE_STANDARD
			prop.radius = effect.radius
			runtime.add_child(prop)
			prop.global_position = context.position
			structures.append({"effect": effect.duplicate(), "position": context.position, "visual": prop})
			set_physics_process(true)
		K.TRANSCRIBE:
			var count: int = runtime.hand.hand.size()
			for card: CardInstance in runtime.hand.hand.duplicate():
				runtime.hand.hand.erase(card)
				runtime.hand.exhaust_pile.append(card)
				card.next_unit_discount = false
				card.free_until_discard = false
				runtime.hand.card_motion_requested.emit(card, &"exhaust", Vector2.ZERO)
			var drawn: Array[CardInstance] = runtime.hand.draw_cards(count)
			if effect.upgrades_drawn_cards:
				for card in drawn:
					var points := card.ability_points + maxi(0, card.unit_data.upgrade_ability_points) if card.is_unit_card() else 0
					card.temporary_upgrade(Vector2i(points, 0), "missile" if card.needs_soldier_choice() else "")
			_notify_piles()
		K.REFORMATION:
			var selected := transform_candidates(context.card)
			selected.shuffle()
			for card: CardInstance in selected.slice(0, amount):
				var options := transform_options(card)
				var index: int = runtime.hand.hand.find(card)
				# 替身只存在本场牌堆，原牌留在总牌组，保存/新战斗不会把临时变阵写成永久变牌。
				runtime.hand.hand[index] = CardInstance.new(options.pick_random())
			_notify_piles()
		K.HAND_DISCOUNT:
			for card: CardInstance in runtime.hand.hand:
				card.round_cost_reduction += amount
			runtime.hand._notify_hand_changed()
		K.OVERDRAFT:
			_energy_modifier(amount, runtime.rounds.current_round, runtime.rounds.current_round)
			_energy_modifier(-effect.next_round_penalty, runtime.rounds.current_round + 1, runtime.rounds.current_round + 1)
			runtime.rounds.gain_energy(amount)
		K.THRIFT:
			_energy_modifier(-1, runtime.rounds.current_round)
			extra_draw += 1
			runtime.hand.recurring_bonus_draw += 1
	runtime.tactics.refresh_all()
	runtime._refresh_zone_speeds()
	if is_instance_valid(target):
		runtime._refresh_unit_status(target)


func _energy_modifier(amount: int, start: int, end: int = 0) -> void:
	runtime.rounds.add_energy_modifier(&"card", amount, start, end)
	energy_modifiers.append(runtime.rounds.energy_modifiers[&"card"].back())


func _notify_piles() -> void:
	runtime.hand._notify_hand_changed()
	runtime.hand.piles_changed.emit(runtime.hand.draw_pile.size(), runtime.hand.discard_pile.size())


func hit_received(unit: UnitBase) -> void:
	if not unit.has_status(&"armor_shred"):
		return
	var stacks: Dictionary = unit.status_runtime.effects.get(&"armor_break", {})
	var previous: int = stacks.get("card_shred", {}).get("amount", 0)
	unit.apply_status(&"armor_break", 0, previous + unit.status_runtime.total_amount(&"armor_shred"), null, "card_shred")


func unit_died(unit: UnitBase) -> void:
	if _death_ids.has(unit.get_instance_id()):
		return
	_death_ids[unit.get_instance_id()] = true
	if unit.unit_data.unit_team == "team_b":
		for entry: Dictionary in sacrifices:
			entry.kills += 1
			if entry.kills >= entry.threshold:
				entry.kills -= entry.threshold
				runtime.rounds.gain_energy(1)
		return
	var original: CardInstance = runtime.hand.board_cards.get(unit.get_instance_id())
	var data := unit.unit_data.duplicate() as UnitData
	if original == null:
		runtime.tactics.strip_stat_contributions(unit, data)
		var state: Dictionary = runtime.states[unit.get_instance_id()]
		data.speed = float(state.base_speed)
		data.attack -= int(state.aura_bonus)
		for buff: Dictionary in state.buffs:
			match buff.effect.kind:
				K.ATTACK_UP: data.attack -= int(buff.effect.amount)
				K.DEFENCE_UP: data.defence -= int(buff.effect.amount)
				K.MAX_HP_UP: data.max_hp -= int(buff.effect.amount)
	fallen.append({"card": original, "data": data, "position": unit.global_position,
		"floor": unit.floor_id, "converted": unit.is_in_group("converted_enemy"),
		"buffs": runtime.states[unit.get_instance_id()].buffs.duplicate(true),
		"round": runtime.rounds.current_round})
	if death_draw > 0:
		runtime.hand.draw_cards(death_draw)


func resurrection_candidate() -> Dictionary:
	for entry: Dictionary in fallen:
		if entry.card == null or not runtime.hand.board_cards.values().has(entry.card):
			return entry
	return {}


func _resurrect(effect: CardEffect, context: Dictionary) -> void:
	var entry: Dictionary = context.resurrection
	fallen.erase(entry)
	var original: CardInstance = entry.card
	var prepared: UnitBase = context.prepared
	prepared.remove_from_group("team_b")
	prepared.add_to_group("team_a")
	prepared.set_collision_layer_value(2, false)
	prepared.set_collision_layer_value(1, true)
	if entry.converted:
		prepared.add_to_group("converted_enemy")
	var unit: UnitBase = runtime._spawn_prepared(context, entry.position, int(entry.floor))
	if original != null:
		for pile: Array in [runtime.hand.hand, runtime.hand.draw_pile, runtime.hand.discard_pile, runtime.hand.exhaust_pile]:
			pile.erase(original)
		runtime.hand.move_hand_card_to_board(original, unit)
		for saved: Dictionary in original.permanent_buffs:
			runtime._add_buff(unit, saved.effect, saved.label)
	unit.current_health = maxi(1, ceili(unit.unit_data.max_hp * effect.amount / 100.0))
	unit.get_node("HealthBar").update_hp_bar(unit.current_health)
	unit.health_changed.emit()
	_notify_piles()


func transform_options(card: CardInstance) -> Array[Resource]:
	if _catalog.is_empty():
		var rewards = preload("res://scripts/events/event_rewards.gd")
		_catalog.assign(rewards.pool([], "unit") + rewards.pool([], "effect"))
	var result: Array[Resource] = []
	for data: Resource in _catalog:
		if not CardInstance.is_player_card_data(data) or int(data.card_cost) != card.get_cost() or data.card_name == card.definition.card_name:
			continue
		result.append(data)
	return result


func transform_candidates(source: CardInstance) -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	for card: CardInstance in runtime.hand.hand:
		if card != source and not transform_options(card).is_empty():
			result.append(card)
	return result


func stat_bonus(unit: UnitBase) -> Vector2i:
	if unit.unit_data.unit_team != "team_a":
		return Vector2i.ZERO
	var attack := army_attack
	for entry: Dictionary in structures:
		if entry.effect.kind == K.BATTLE_STANDARD and unit.global_position.distance_to(entry.position) <= entry.effect.radius:
			attack += int(entry.effect.amount)
	return Vector2i(attack, army_defence)


func speed_multiplier(unit: UnitBase) -> float:
	return 1.0 + army_speed / 100.0 if unit.unit_data.unit_team == "team_a" else 1.0


func statuses_for(unit: UnitBase) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if unit.unit_data.unit_team != "team_a":
		return result
	if army_attack > 0:
		result.append({"icon": "attack", "tooltip": "战吼：本场全体友军攻击+%d。" % army_attack})
	if army_defence > 0:
		result.append({"icon": "defence", "tooltip": "坚守：本场全体友军防御+%d。" % army_defence})
	if army_speed > 0:
		result.append({"icon": "haste", "tooltip": "疾行：本场全体友军移速+%.0f%%。" % army_speed})
	var banner_bonus := stat_bonus(unit).x - army_attack
	if banner_bonus > 0:
		result.append({"icon": "banner", "tooltip": "战旗：位于光环范围内，攻击+%d；离开后失效。" % banner_bonus})
	return result


func _physics_process(_delta: float) -> void:
	if runtime.battle.battle_finished:
		return
	if Global.game_phase == Global.GamePhase.AUTO_BATTLE:
		for entry: Dictionary in structures.duplicate():
			if entry.effect.kind != K.SPIKE_TRAP:
				continue
			for unit: UnitBase in runtime.living_units():
				if unit.unit_data.unit_team == "team_b" and unit.global_position.distance_to(entry.position) <= entry.effect.radius:
					# 先消耗陷阱，再触发伤害/死亡回调，保证同帧多人进入也只命中一人。
					structures.erase(entry)
					entry.visual.queue_free()
					unit.take_effect_damage(int(entry.effect.amount))
					if unit.is_alive():
						unit.apply_status(&"stun", entry.effect.status_seconds, 0, null, "spike_%d" % entry.visual.get_instance_id())
					break
	runtime.tactics.refresh_all()
	if structures.is_empty():
		set_physics_process(false)


func end_round() -> void:
	for card: CardInstance in runtime.plays.known_cards():
		card.round_cost_reduction = 0


func clear_battle() -> void:
	army_attack = 0
	army_defence = 0
	army_speed = 0
	death_draw = 0
	sacrifices.clear()
	fallen.clear()
	_death_ids.clear()
	for entry: Dictionary in structures:
		if is_instance_valid(entry.visual):
			entry.visual.queue_free()
	structures.clear()
	for modifier: Dictionary in energy_modifiers:
		runtime.rounds.energy_modifiers.get(&"card", []).erase(modifier)
	energy_modifiers.clear()
	runtime.rounds.calculate_energy()
	runtime.hand.recurring_bonus_draw = maxi(0, runtime.hand.recurring_bonus_draw - extra_draw)
	extra_draw = 0
	set_physics_process(false)
