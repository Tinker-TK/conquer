## 每场独立的遗物事件处理器。计数先占用再执行，禁止遗物效果递归触发其它遗物。
## 计时使用随战场暂停和倍速变化的 Timer；不逐帧扫描单位。
extends Node

const T = RelicDefinition.Trigger
const K = CardEffect.Kind
var battle: Node2D
var cards: Node2D
var hand: Node
var rounds: Node
var rng := RandomNumberGenerator.new()
var counters: Dictionary = {}
var owned: Dictionary = {}
var ordered: Array[RelicDefinition] = []
var elapsed := 0.0
var dispatching := false
var stopped := false
var deployed := 0
var played := 0
var round_deaths := 0
var next_energy := 0
var banner_ready := false
var fate_pending := false
var opening_pending := true
var hunter_hits: Dictionary = {}
var refunded_cards: Dictionary = {}
var _last_notice: Dictionary = {}

func setup(owner_battle: Node2D, seed_value: int = -1) -> void:
	battle = owner_battle
	cards = battle.card_runtime
	hand = battle.hand_manager
	rounds = battle.battle_round_manager
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	refresh_owned()
	RunManager.items_changed.connect(refresh_owned)
	var clock := Timer.new()
	clock.wait_time = 0.1
	clock.timeout.connect(_tick)
	add_child(clock)
	clock.start()
	hand.shuffled.connect(func(): fire(T.SHUFFLE))
	SignalBus.phase_change.connect(func(_phase): cards.tactics.refresh_all())
	for unit in cards.living_units():
		unit_registered(unit)

func refresh_owned() -> void:
	owned.clear()
	ordered.assign(RunManager.relics)
	ordered.sort_custom(func(a: RelicDefinition, b: RelicDefinition):
		return a.priority < b.priority if a.priority != b.priority else String(a.id) < String(b.id))
	for relic in ordered:
		owned[relic.id] = relic
		if not counters.has(relic.id):
			counters[relic.id] = {"battle": 0, "round": 0, "cooldowns": {}}

func has_relic(id: StringName) -> bool:
	return not stopped and owned.has(id)

func count(id: StringName, per_round: bool = false) -> int:
	return int(counters.get(id, {}).get("round" if per_round else "battle", 0))

func can_trigger(id: StringName, key: int = 0) -> bool:
	if not has_relic(id) or dispatching or battle.battle_finished:
		return false
	var relic: RelicDefinition = owned[id]
	var state: Dictionary = counters[id]
	return (relic.max_per_battle == 0 or int(state.battle) < relic.max_per_battle) \
		and (relic.max_per_round == 0 or int(state.round) < relic.max_per_round) \
		and elapsed + 0.00001 >= float(state.cooldowns.get(key, -100.0)) + relic.cooldown_seconds

func _record(id: StringName, unit: UnitBase = null, key: int = 0) -> void:
	var state: Dictionary = counters[id]
	state.battle += 1
	state.round += 1
	state.cooldowns[key] = elapsed
	# 高频命中遗物只节流提示，不节流真实效果。
	if elapsed - float(_last_notice.get(id, -100.0)) >= 0.8:
		_last_notice[id] = elapsed
		var relic: RelicDefinition = owned[id]
		SignalBus.relic_triggered.emit(id, relic.display_name)
		if is_instance_valid(unit):
			cards._show_card_effect_name(unit, relic.display_name)

func fire(trigger: int, payload: Dictionary = {}) -> void:
	if stopped or dispatching or battle.battle_finished:
		return
	for relic in ordered:
		if relic.trigger != trigger or not can_trigger(relic.id, int(payload.get("key", 0))):
			continue
		dispatching = true
		var success := _execute(relic.handler, payload)
		dispatching = false
		if success:
			_record(relic.id, payload.get("unit"), int(payload.get("key", 0)))

func begin_battle() -> void:
	fire(T.BATTLE_START)

func begin_round() -> void:
	played = 0
	round_deaths = 0
	banner_ready = false
	for state: Dictionary in counters.values():
		state.round = 0
	if next_energy > 0:
		rounds.gain_energy(next_energy)
		next_energy = 0
	# 敌阵在阶段信号的第一个监听器里生成；HandManager 抽牌前触发 ROUND_START。

func after_opening_draw() -> void:
	if has_relic(&"war_banner") and hand.hand.filter(func(card: CardInstance): return card.is_unit_card()).size() >= 2:
		banner_ready = true
	if fate_pending and not hand.hand.is_empty():
		var card: CardInstance = hand.hand[rng.randi_range(0, hand.hand.size() - 1)]
		card.round_cost_reduction += 2
		fate_pending = false
		_record(&"fate_coin")
	opening_pending = false
	hand._notify_hand_changed()

func card_discount(card: CardInstance) -> int:
	if stopped:
		return 0
	return (1 if has_relic(&"veteran_medal") and count(&"veteran_medal") == 0 else 0) \
		+ (1 if banner_ready and card.is_unit_card() else 0)

func modified_effect(effect: CardEffect, context: Dictionary) -> CardEffect:
	var result := effect
	var target: UnitBase = context.get("target")
	var enhance_number := effect.is_unit_buff() or effect.kind in [K.HEAL_PERCENT, K.SHIELD, K.MISSING_HEALTH_SHIELD]
	if can_trigger(&"anvil") and context.card.definition.category == CardDefinition.Category.ENHANCEMENT \
		and is_instance_valid(target) and target.unit_data.unit_team == "team_a" and enhance_number:
		result = effect.duplicate()
		result.amount = ceili(effect.amount * 1.5)
		if effect.kind == K.HEAL_PERCENT: result.amount = minf(100, result.amount)
		context["relic_anvil"] = true
	if effect.kind == K.PAY_HP and has_relic(&"sacrificial_dagger"):
		result = effect.duplicate()
		result.amount = maxi(1, int(effect.amount) - 2)
		context["relic_blood_paid"] = true
	if effect.kind == K.DAMAGE_ZONE and has_relic(&"ember"):
		if result == effect:
			result = effect.duplicate()
		result.amount += 2
		result.radius += 30
	return result

func card_played(context: Dictionary, cost: int) -> void:
	if stopped:
		return
	played += 1
	if has_relic(&"veteran_medal") and count(&"veteran_medal") == 0:
		_record(&"veteran_medal", context.target)
	if banner_ready and context.card.is_unit_card():
		banner_ready = false
		_record(&"war_banner", context.target)
	context["cost"] = cost
	fire(T.CARD_PLAYED, context)

func deployed_unit(unit: UnitBase) -> void:
	deployed += 1
	fire(T.UNIT_DEPLOYED, {"unit": unit})
	cards.tactics.refresh_all()

func unit_registered(unit: UnitBase) -> void:
	unit.health_changed.connect(cards.tactics.refresh_all)
	unit.tree_exiting.connect(_unit_exiting.bind(unit))
	unit.kill_confirmed.connect(_killed)

func _unit_exiting(unit: UnitBase) -> void:
	hunter_hits.erase(unit.get_instance_id())

func unit_died(unit: UnitBase) -> void:
	if unit.unit_data.unit_team == "team_a":
		round_deaths += 1
	if dispatching or unit.has_meta("relic_revived"):
		return
	fire(T.UNIT_DIED, {"unit": unit})

func _killed(victim: UnitBase, killer: UnitBase) -> void:
	if is_instance_valid(killer) and killer.is_alive() and killer.unit_data.unit_team == "team_a" and victim.unit_data.unit_team == "team_b":
		fire(T.UNIT_KILL, {"unit": killer})

func hit(target: UnitBase, attacker: UnitBase) -> void:
	if not is_instance_valid(attacker) or attacker.unit_data.unit_team == target.unit_data.unit_team:
		return
	if attacker.unit_data.unit_team == "team_a":
		fire(T.UNIT_HIT, {"unit": attacker, "target": target, "key": target.get_instance_id()})
	else:
		fire(T.UNIT_HURT, {"unit": target, "target": attacker, "key": attacker.get_instance_id()})

func dot_tick(unit: UnitBase, amount: int) -> void:
	if amount > 0 and unit.unit_data.unit_team == "team_b":
		fire(T.DOT_TICK, {"unit": unit, "amount": amount})

func end_round() -> void:
	fire(T.ROUND_END)
	for unit in enemies():
		unit.remove_status(&"weakness", "relic_fear")

func settled() -> void:
	fire(T.ROUND_SETTLED)
	rounds.health_changed.emit()

func finish(won: bool) -> void:
	if stopped:
		return
	if won:
		fire(T.BATTLE_WON)
	stopped = true

func allies() -> Array[UnitBase]:
	return cards.living_units().filter(func(unit: UnitBase): return unit.unit_data.unit_team == "team_a")

func enemies() -> Array[UnitBase]:
	return cards.living_units().filter(func(unit: UnitBase): return unit.unit_data.unit_team == "team_b")

func ranged(unit: UnitBase) -> bool:
	return unit.unit_data.unit_english_name in ["archer", "wizard", "priest"] or unit.unit_data.has_sword_arrow()

func _buff(unit: UnitBase, kind: int, amount: int, label: String) -> void:
	if not is_instance_valid(unit) or not unit.is_alive() or amount <= 0:
		return
	var effect := CardEffect.new()
	effect.kind = kind
	effect.amount = amount
	cards._add_buff(unit, effect, label)

func _poison(unit: UnitBase, amount: int) -> void:
	if cards.states.has(unit.get_instance_id()) and unit.is_alive():
		cards.states[unit.get_instance_id()].poison += amount
		cards._refresh_unit_status(unit)

func _damage(unit: UnitBase, amount: int) -> void:
	# 不传攻击者：不会触发吸血、反击或攻击命中；dispatching 阻断遗物死亡链。
	unit.take_effect_damage(amount, null, &"relic")

func _execute(id: StringName, p: Dictionary) -> bool:
	var unit: UnitBase = p.get("unit")
	var target: UnitBase = p.get("target")
	match id:
		&"war_banner", &"anvil":
			return bool(p.get("relic_anvil", false)) if id == &"anvil" else false
		&"muster_roll":
			if deployed % 3 != 0: return false
			for ally in allies(): _buff(ally, K.ATTACK_UP, 1, "征兵名册")
		&"beacon":
			if deployed != 3: return false
			for ally in allies():
				_buff(ally, K.ATTACK_UP, 2, "集结烽火")
				ally.set_meta("relic_beacon", true)
		&"duel_pact":
			if deployed != 1: return false
			unit.set_meta("relic_duel", true)
			_buff(unit, K.MAX_HP_UP, ceili(unit.unit_data.max_hp * 0.3), "决斗契约")
		&"earth_altar":
			if allies().size() < 4 or RunManager.hp <= 0: return false
			rounds.enemy_hp = maxi(0, rounds.enemy_hp - 4)
			RunManager.hp += 2
		&"bloodstone":
			if unit.current_health >= unit.unit_data.max_hp: unit.add_shield(5)
			else: unit.get_heal(5)
		&"kings_blade":
			_buff(unit, K.ATTACK_UP, 3, "王者之剑")
			rounds.gain_energy(1)
		&"legacy_seal", &"urn", &"mourner", &"fallen_roster", &"death_echo", &"martyr_crown", &"undying_throne":
			if unit.unit_data.unit_team != "team_a": return false
			return _death_effect(id, unit)
		&"sacrificial_dagger":
			if not p.get("relic_blood_paid", false): return false
			rounds.gain_energy(1)
		&"corrosive_vial": _poison(target, 1)
		&"hunter_mark":
			if not ranged(unit): return false
			var key := target.get_instance_id()
			hunter_hits[key] = int(hunter_hits.get(key, 0)) + 1
			if int(hunter_hits[key]) != 3: return false
		&"slow_death":
			if rng.randf() >= 0.25: return false
			var others := enemies().filter(func(enemy: UnitBase): return enemy != unit and enemy.global_position.distance_to(unit.global_position) <= 150)
			if others.is_empty(): return false
			_damage(others[rng.randi_range(0, others.size() - 1)], int(p.amount))
		&"sulfur_heart":
			if enemies().is_empty(): return false
			for enemy in enemies(): _poison(enemy, 1)
		&"fear_totem":
			var candidates := enemies()
			if candidates.is_empty(): return false
			candidates[rng.randi_range(0, candidates.size() - 1)].apply_status(&"weakness", 0, 2, null, "relic_fear")
		&"burning_city":
			if unit.unit_data.unit_team != "team_b": return false
			var effect := CardEffect.new()
			effect.kind = K.DAMAGE_ZONE
			effect.amount = 6 + (2 if has_relic(&"ember") else 0)
			effect.radius = 180 + (30 if has_relic(&"ember") else 0)
			effect.interval = 0.5
			effect.lifetime = CardEffect.Lifetime.ROUNDS
			effect.lasting_rounds = 2
			effect.affected_team = CardEffect.AffectedTeam.ENEMIES
			cards.create_zone(effect, unit.global_position, "焚城之焰", &"relic")
		&"stasis_field":
			if rounds.current_round != 3 or enemies().is_empty(): return false
			for enemy in enemies():
				enemy.apply_status(&"stun", 2.0, 0, null, "relic_stasis")
				enemy.set_meta("relic_stasis_hit", true)
		&"gloves":
			if int(p.get("cost", -1)) != 0 or hand.draw_locked: return false
			hand.draw_cards(1)
		&"fate_coin":
			fate_pending = true
			return false # 有真实起手牌后才计数。
		&"steady_hands":
			var candidates: Array = hand.hand.filter(func(card: CardInstance): return not card.definition.retain_in_hand)
			if candidates.is_empty(): return false
			hand.relic_retained = candidates[rng.randi_range(0, candidates.size() - 1)]
		&"borrowed_time":
			if hand.hand.size() < 3: return false
			next_energy += 1
		&"echo_crystal":
			var card: CardInstance = p.card
			if card.definition.after_use != CardDefinition.AfterUse.EXHAUST or card.is_unit_card(): return false
			var repeated := false
			for effect: CardEffect in card.definition.effects:
				if effect.kind in [K.DAMAGE_ZONE, K.MUD_ZONE, K.COPY_ALLY, K.RANDOM_PLAY, K.RECALL_ALLY, K.PAY_HP, K.RESURRECT, K.BATTLE_STANDARD, K.SPIKE_TRAP]: continue
				if not effect.validate(p).is_empty(): continue
				effect.execute(p)
				repeated = true
			return repeated
		&"perpetual_gear":
			if played != 3: return false
			rounds.gain_energy(2)
		&"thorn_mail":
			if not target.is_alive(): return false
			_damage(target, 3)
		&"holy_symbol":
			var candidates := allies()
			if candidates.is_empty(): return false
			candidates.sort_custom(func(a: UnitBase, b: UnitBase): return float(a.current_health) / a.unit_data.max_hp < float(b.current_health) / b.unit_data.max_hp)
			return candidates[0].get_heal(5)
		&"unfallen_fortress":
			if round_deaths != 0 or RunManager.hp <= 0: return false
			RunManager.hp += 2
			rounds.enemy_hp = maxi(0, rounds.enemy_hp - 2)
		&"volley_horn":
			if allies().filter(ranged).size() < 2 or enemies().is_empty(): return false
			var candidates := enemies()
			_damage(candidates[rng.randi_range(0, candidates.size() - 1)], 6)
		&"coin_purse": RunManager.gold += 10
		&"field_kit": RunManager.hp += 3
		&"greedy_cup": RunManager.hp += 5 if RunManager.gold >= 200 else 3
		&"tactical_map": hand.pending_bonus_draw += 2
		&"hourglass":
			if rounds.current_round != 1: return false
			rounds.gain_energy(2)
		&"spare_quiver":
			rounds.gain_energy(1)
			hand.pending_shuffle_draw += 2 # 等当前抽牌循环完成后补抽，避免重入抽空牌堆。
		_: return false
	return true

func _death_effect(id: StringName, unit: UnitBase) -> bool:
	var original: CardInstance = hand.board_cards.get(unit.get_instance_id())
	match id:
		&"fallen_roster":
			if original == null or refunded_cards.has(original.id): return false
			refunded_cards[original.id] = true
			unit.set_meta("relic_no_cost_increase", true)
		&"death_echo":
			if original == null: return false
			unit.set_meta("relic_return_hand", true)
		&"undying_throne":
			var revived: UnitBase = cards.prepare_potion_copy(unit)
			if revived == null: return false
			var buffs: Array = cards.states[unit.get_instance_id()].buffs.duplicate(true)
			revived.set_meta("relic_revived", true)
			var context := {"prepared": revived}
			hand.board_cards.erase(unit.get_instance_id())
			cards._spawn_prepared(context, unit.global_position, unit.floor_id)
			cards.inherit_potion_buffs(revived, buffs)
			if original != null: hand.move_hand_card_to_board(original, revived)
			revived.current_health = maxi(1, ceili(revived.unit_data.max_hp * 0.5))
			revived.get_node("HealthBar").update_hp_bar(revived.current_health)
			unit.set_meta("relic_resurrected", true)
		&"urn":
			var candidates := enemies()
			if candidates.is_empty(): return false
			candidates.sort_custom(func(a: UnitBase, b: UnitBase): return a.global_position.distance_squared_to(unit.global_position) < b.global_position.distance_squared_to(unit.global_position))
			_damage(candidates[0], 5)
		&"mourner":
			if hand.draw_locked or hand.draw_pile.size() + hand.discard_pile.size() == 0: return false
			hand.draw_cards(1)
		&"martyr_crown", &"legacy_seal":
			var candidates := allies()
			if id == &"martyr_crown":
				candidates = candidates.filter(func(ally: UnitBase): return int(ally.get_meta("relic_crown_stacks", 0)) < 3)
			if candidates.is_empty(): return false
			if id == &"martyr_crown":
				var heir := candidates[rng.randi_range(0, candidates.size() - 1)]
				heir.set_meta("relic_crown_stacks", int(heir.get_meta("relic_crown_stacks", 0)) + 1)
				_buff(heir, K.ATTACK_UP, 2, "殉道之冠")
			else:
				candidates.sort_custom(func(a: UnitBase, b: UnitBase): return a.unit_data.attack > b.unit_data.attack)
				_buff(candidates[0], K.ATTACK_UP, floori(unit.unit_data.attack * 0.5), "传承之证")
				_buff(candidates[0], K.DEFENCE_UP, floori(unit.unit_data.defence * 0.5), "传承之证")
	return true

func stat_modifiers(unit: UnitBase, ally_count: int, types: int) -> Dictionary:
	var result := {"attack": 0, "defence": 0, "attack_percent": 0.0, "defence_percent": 0.0, "cooldown": 0.0}
	if stopped or unit.unit_data.unit_team != "team_a": return result
	if has_relic(&"diverse_codex"):
		result.defence += mini(types, 3)
		if types >= 3: result.attack += 1
	if has_relic(&"lone_wolf") and ally_count == 1:
		result.attack_percent += 0.25
		result.defence_percent += 0.25
		result.cooldown += 0.15
	if unit.has_meta("relic_duel"): result.attack_percent += 0.15
	if has_relic(&"iron_wall") and Global.game_phase == Global.GamePhase.AUTO_BATTLE:
		result.defence += 2 if ally_count >= 3 else 1
	if has_relic(&"last_stand") and float(unit.current_health) < unit.unit_data.max_hp * 0.3:
		result.attack += 2
		result.defence += 3
	if unit.has_meta("relic_beacon"): result.cooldown += 0.15
	if has_relic(&"spell_focus") and ranged(unit): result.cooldown += 0.10
	if has_relic(&"scout_horn") and rounds.current_round == 1:
		result.attack += 1
		result.defence += 1
	return result

func incoming_damage(target: UnitBase, attacker: UnitBase, amount: int, kind: StringName, attack: bool) -> int:
	if stopped or kind == &"relic": return amount
	var percent := 0.0
	var flat := 0
	if target.unit_data.unit_team == "team_b":
		if has_relic(&"chains") and target.is_stunned: percent += 0.15
		if has_relic(&"executioner") and float(target.current_health) < target.unit_data.max_hp * 0.3: percent += 0.25
		if has_relic(&"hunter_mark") and int(hunter_hits.get(target.get_instance_id(), 0)) >= 3: percent += 0.15
		if has_relic(&"inquisitor"):
			var debuffs: Dictionary = {}
			for status: Dictionary in target.active_statuses():
				if String(status.icon) in ["stun", "sleep", "slow", "weakness", "bleed", "taunt", "silence", "mortal_wounds", "defence_down", "vulnerability", "paralysis", "confusion"]: debuffs[status.icon] = true
			for status: Dictionary in cards.tactics.statuses_for(target):
				if String(status.icon) in ["weakness", "defence_down", "vulnerability", "paralysis"]: debuffs[status.icon] = true
			if int(cards.states.get(target.get_instance_id(), {}).get("poison", 0)) > 0: debuffs["poison"] = true
			flat += mini(debuffs.size(), 4)
		if attack:
			if has_relic(&"sunder") and target.unit_data.defence <= 0: flat += 3
			if has_relic(&"plague_mask"): percent += minf(0.20, int(cards.states.get(target.get_instance_id(), {}).get("poison", 0)) * 0.02)
			if target.has_meta("relic_stasis_hit"):
				percent += 0.5
				target.remove_meta("relic_stasis_hit")
			if is_instance_valid(attacker) and attacker.unit_data.unit_team == "team_a":
				if has_relic(&"spell_focus") and ranged(attacker) and kind != &"normal": percent += 0.10
	elif has_relic(&"guardian_oath") and is_taunting(target):
		percent -= 0.20
	return maxi(0, roundi((amount + flat) * (1.0 + clampf(percent, -0.60, 0.60))))

func is_taunting(unit: UnitBase) -> bool:
	return unit.taunt_defence_bonus > 0 or unit.taunt_attackers > 0 or (unit.taunt_runtime != null and float(unit.taunt_runtime.left) > 0)

func movement_multiplier(unit: UnitBase) -> float:
	return 1.2 if has_relic(&"kite_boots") and unit.unit_data.unit_team == "team_a" and ranged(unit) else 1.0

func attack_percent(attacker: UnitBase, target: UnitBase) -> float:
	return 0.15 if has_relic(&"longbow_string") and is_instance_valid(attacker) and attacker.unit_data.unit_team == "team_a" and attacker.global_position.distance_to(target.global_position) >= 300 else 0.0

func statuses_for(unit: UnitBase) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if stopped or unit.unit_data.unit_team != "team_a": return result
	var mods := stat_modifiers(unit, cards.tactics.ally_count, cards.tactics.unit_type_count)
	if int(mods.attack) != 0 or int(mods.defence) != 0 or float(mods.attack_percent) != 0 or float(mods.defence_percent) != 0 or float(mods.cooldown) != 0:
		var sources: PackedStringArray = []
		for id: StringName in [&"diverse_codex", &"lone_wolf", &"iron_wall", &"last_stand", &"spell_focus", &"scout_horn", &"duel_pact", &"beacon"]:
			if has_relic(id): sources.append(owned[id].display_name)
		result.append({"icon": "composition", "tooltip": "遗物加成：" + "、".join(sources) + "\n攻击 +%d / +%.0f%%，防御 +%d / +%.0f%%，技能冷却 -%.0f%%\n随存活阵容、血量和阶段更新。" % [mods.attack, mods.attack_percent * 100, mods.defence, mods.defence_percent * 100, mods.cooldown * 100]})
	return result

func dodge_bonus(unit: UnitBase, attacker: UnitBase) -> float:
	return 0.10 if movement_multiplier(unit) > 1.0 and is_instance_valid(attacker) and unit.global_position.distance_to(attacker.global_position) >= 400 else 0.0

func healing_amount(unit: UnitBase, amount: int) -> int:
	if has_relic(&"blood_bank") and unit.unit_data.unit_team == "team_a":
		if can_trigger(&"blood_bank"): _record(&"blood_bank", unit)
		return ceili(amount * 1.25)
	return amount

func counter_damage(unit: UnitBase, amount: int) -> int:
	return ceili(amount * 1.5) if has_relic(&"counter_stance") and unit.unit_data.unit_team == "team_a" else amount

func countered(unit: UnitBase) -> void:
	if can_trigger(&"counter_stance") and unit.unit_data.unit_team == "team_a":
		dispatching = true
		unit.get_heal(2)
		dispatching = false
		_record(&"counter_stance", unit)

func _tick() -> void:
	if stopped or battle.battle_finished or get_tree().paused: return
	elapsed += 0.1
	if has_relic(&"guardian_oath") and Global.game_phase == Global.GamePhase.AUTO_BATTLE and int(elapsed * 10 + 0.01) % 10 == 0:
		for unit in allies():
			if is_taunting(unit): unit.get_heal(maxi(1, ceili(unit.unit_data.max_hp * 0.01)))


func _exit_tree() -> void:
	if RunManager.relic_battle == self:
		RunManager.relic_battle = null
