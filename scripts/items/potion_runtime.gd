## 新药水执行器。仅活跃区域每 0.1 秒扫描；空闲时关闭物理更新。
extends Node2D

const K = PotionEffect.Kind
const TM = PotionDefinition.TargetMode
const VFX = preload("res://scripts/effects/combat_vfx.gd")
const LIBRARY = preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd")
const MOTION = preload("res://scripts/combat/knockback_motion.gd")
const PULSE = preload("res://scripts/items/potion_cast_visual.gd")
var items: Node2D
var battle: Node2D
var cards: Node2D
var field: Dictionary = {}
var error := ""
var _serial := 0
var _field_clock := 0.0
var _decoys: Array[WeakRef] = []
var _decoy_clock := 0.0
var _last_round := 0


func setup(owner_items: Node2D) -> void:
	items = owner_items
	battle = items.battle
	cards = battle.card_runtime
	set_physics_process(false)
	battle.battle_round_manager.battle_round_ended.connect(end_round)
	SignalBus.phase_change.connect(phase_changed)


func allies() -> Array[UnitBase]:
	return cards.living_units().filter(func(unit: UnitBase): return unit.unit_data.unit_team == "team_a")


func enemies() -> Array[UnitBase]:
	return cards.living_units().filter(func(unit: UnitBase): return unit.unit_data.unit_team == "team_b")


func copy_candidates() -> Array[UnitBase]:
	# 原征召单位是可复制对象；召唤、复活、旧复制品均没有原牌。
	return allies().filter(func(unit: UnitBase): return battle.hand_manager.board_cards.has(unit.get_instance_id()))


func fallen_candidate() -> Dictionary:
	var available: Array[Dictionary] = []
	for entry: Dictionary in cards.expanded.fallen:
		if int(entry.get("round", 0)) != battle.battle_round_manager.current_round:
			continue
		if entry.card != null and battle.hand_manager.board_cards.values().has(entry.card):
			continue
		if entry.card != null:
			return entry
		available.append(entry)
	return available[0] if not available.is_empty() else {}


func upgrade_candidates() -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	for card: CardInstance in RunManager.deck:
		if card.can_upgrade(false) and card.can_evolve():
			result.append(card)
	return result


func target_at(recipe: PotionDefinition, point: Vector2) -> UnitBase:
	var definition := CardDefinition.new()
	definition.target = CardDefinition.Target.ENEMY if recipe.target_mode == TM.ENEMY_UNIT else CardDefinition.Target.ALLY
	return cards.pick_target(definition, point)


func affected(recipe: PotionDefinition, effect: PotionEffect, point: Vector2, target: UnitBase) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	if recipe.target_mode in [TM.ENEMY_UNIT, TM.ALLY_UNIT, TM.RANDOM_ALLY]:
		if is_instance_valid(target) and target.is_alive():
			result.append(target)
		return result
	if recipe.target_mode == TM.ALL_ALLIES:
		return allies()
	if recipe.target_mode == TM.ALL_ENEMIES:
		return enemies()
	var radius := effect.radius if effect.radius > 0 else recipe.radius
	for unit: UnitBase in cards.living_units():
		var ally := unit.unit_data.unit_team == "team_a"
		if (recipe.targets == PotionDefinition.Targets.ENEMIES and ally) or (recipe.targets == PotionDefinition.Targets.ALLIES and not ally):
			continue
		if unit.global_position.distance_to(point) <= radius:
			result.append(unit)
	return result


func summon_floor(point: Vector2) -> int:
	var terrain := battle.get_node_or_null("Level/NavigationRegion2D")
	if terrain == null or not terrain.has_method("spawn_floor_at"):
		return 0
	var floor_id: int = terrain.spawn_floor_at(point)
	return floor_id if terrain.has_ground_at(point, floor_id) else 0


## 验证并准备所有单位，再扣瓶；失败不会改生命、卡牌、阵营或库存。
func prepare(recipe: PotionDefinition, point: Vector2) -> Dictionary:
	error = ""
	if recipe.effects.is_empty():
		return _reject("这瓶药水没有配置效果。")
	if recipe.max_per_run > 0 and int(RunManager.potion_use_counts.get(recipe.id, 0)) >= recipe.max_per_run:
		return _reject("这瓶药水已达到本局使用上限。")
	var context := {"point": point, "target": null, "prepared": [], "fallen": {}, "upgrade": null}
	if recipe.target_mode in [TM.ENEMY_UNIT, TM.ALLY_UNIT]:
		context.target = target_at(recipe, point)
		if context.target == null:
			return _reject("请选择有效的敌方单位。" if recipe.target_mode == TM.ENEMY_UNIT else "请选择有效的友军。")
	if recipe.target_mode == TM.ALL_ALLIES and allies().is_empty():
		return _reject("场上没有可影响的友军。")
	if recipe.target_mode == TM.ALL_ENEMIES and enemies().is_empty():
		return _reject("场上没有可影响的敌人。")
	if recipe.target_mode == TM.RANDOM_ALLY:
		var available := copy_candidates()
		if available.is_empty():
			return _reject("需要一名有原征召牌的友军，不能复制临时召唤物。")
		context.target = available.pick_random()
	for effect: PotionEffect in recipe.effects:
		var reason := ""
		match effect.kind:
			K.DRAW, K.DISCARD_DRAW:
				if battle.hand_manager.draw_locked:
					reason = "本回合已禁止抽牌。"
			K.HEAL_PLAYER:
				if RunManager.hp >= RunManager.max_hp:
					reason = "玩家生命已满。"
			K.PAY_HP:
				if RunManager.hp <= blood_cost(effect):
					reason = "生命不足，血契不能致死。"
			K.SKIP_ROUND:
				reason = battle.battle_round_manager.skip_round_error()
			K.CONVERT:
				if context.target == null or context.target.unit_data.monster_rank != UnitData.MonsterRank.NORMAL:
					reason = "只能策反普通敌军；精英、首领、传说无效。"
			K.UPGRADE_CARD:
				var available := upgrade_candidates()
				if available.is_empty():
					reason = "牌组中没有可强化的效果牌。"
				else:
					context.upgrade = available.pick_random()
			K.REVIVE:
				context.fallen = fallen_candidate()
				if context.fallen.is_empty():
					reason = "本轮没有可复活的阵亡友军。"
				else:
					var original: CardInstance = context.fallen.card
					var data: UnitData = original.get_summon_data() if original != null else context.fallen.data.duplicate()
					_prepare_spawn(context, data)
			K.COPY_ALLY:
				var unit: UnitBase = cards.prepare_potion_copy(context.target)
				if unit != null:
					context.prepared.append(unit)
				else:
					reason = "无法加载复制单位的场景。"
			K.SUMMON:
				if effect.unit_data == null or summon_floor(point) == 0:
					reason = "请在可行走地面上召唤。"
				else:
					for index in effect.count:
						_prepare_spawn(context, effect.unit_data)
		if not reason.is_empty():
			free_prepared(context)
			return _reject(reason)
		if not error.is_empty():
			free_prepared(context)
			return {}
	return context


func _reject(message: String) -> Dictionary:
	error = message
	return {}


func _prepare_spawn(context: Dictionary, data: UnitData) -> void:
	var snapshot := data.duplicate() as UnitData
	snapshot.unit_team = "team_a"
	var unit: UnitBase = cards._prepare_unit(snapshot)
	if unit == null:
		error = "无法加载药水召唤单位的场景。"
	else:
		context.prepared.append(unit)


func free_prepared(context: Dictionary) -> void:
	for unit: UnitBase in context.get("prepared", []):
		if is_instance_valid(unit) and not unit.is_inside_tree():
			unit.free()
	context.get("prepared", []).clear()


func blood_cost(effect: PotionEffect) -> int:
	return maxi(5, ceili(RunManager.max_hp * effect.amount / 100.0))


func cast(recipe: PotionDefinition, context: Dictionary) -> void:
	_serial += 1
	var point: Vector2 = context.point
	if is_instance_valid(context.target):
		point = context.target.global_position
	var show_point := point
	if recipe.target_mode in [TM.SELF, TM.ALL_ALLIES, TM.DEAD_ALLY]:
		show_point = allies()[0].global_position if not allies().is_empty() else battle.deployment_rect.get_center()
	flash(show_point, recipe)
	for effect: PotionEffect in recipe.effects:
		if battle.battle_finished:
			break
		var units := affected(recipe, effect, point, context.target)
		match effect.kind:
			K.DAMAGE:
				for unit in units:
					unit.take_effect_damage(int(effect.amount))
			K.STATUS:
				for unit in units:
					apply_status(unit, effect)
			K.POISON:
				for unit in units:
					cards.add_poison(unit, int(effect.amount))
			K.BUFF:
				for unit in units:
					var buff := CardEffect.new()
					buff.kind = effect.buff_kind
					buff.amount = effect.amount
					buff.radius = effect.radius
					buff.lifetime = CardEffect.Lifetime.ROUNDS if effect.rounds > 0 else CardEffect.Lifetime.BATTLE
					buff.lasting_rounds = effect.rounds
					if effect.buff_kind == CardEffect.Kind.DEATH_EXPLOSION:
						buff.set_meta("potion_enemy_only", true)
					if effect.buff_kind == CardEffect.Kind.DEATH_EXPLOSION:
						buff.set_meta("potion_enemy_only", true)
					cards.apply_potion_buff(unit, buff, recipe.display_name)
					VFX.spawn(unit, "PoisonVFX" if effect.buff_kind == CardEffect.Kind.POISON_ON_HIT else "HolyLightVFX", 0.8, 0.65)
			K.SHIELD:
				for unit in units:
					unit.add_shield(int(effect.amount))
			K.CLEANSE:
				for unit in units:
					cards.cleanse(unit)
					unit.get_heal(int(effect.amount))
					VFX.spawn(unit, "HolyHealImpactVFX", 0.9)
			K.HEAL_PLAYER:
				RunManager.hp += int(effect.amount)
			K.MAX_HP:
				RunManager.max_hp += int(effect.amount)
				RunManager.hp += int(effect.amount)
			K.PAY_HP:
				RunManager.hp -= blood_cost(effect)
			K.DRAW:
				battle.hand_manager.draw_cards(int(effect.amount))
			K.DISCARD_DRAW:
				var count: int = battle.hand_manager.hand.size()
				battle.hand_manager.discard_unused_card(true)
				battle.hand_manager.draw_cards(count + int(effect.amount))
			K.ENERGY:
				battle.battle_round_manager.gain_energy(int(effect.amount))
			K.TACTICS:
				cards.plays.potion_free_plays += int(effect.amount)
				cards.plays.refresh_costs()
				battle.hand_manager._notify_hand_changed()
			K.KNOCKBACK:
				for unit in units:
					MOTION.push_from_point(unit, point, effect.amount)
			K.CHAIN_LIGHTNING:
				_chain(recipe, effect, point)
			K.SUMMON:
				for index in effect.count:
					var offset := Vector2.ZERO if index == 0 else Vector2.from_angle(index * TAU / effect.count) * 32.0
					var at := point + offset
					if summon_floor(at) != summon_floor(point):
						at = point
					var unit := _spawn(context, at, summon_floor(point), maxi(1, effect.rounds))
					if effect.amount > 0:
						unit.set_meta("potion_decoy", true)
						unit.set_physics_process(false)
						unit.animated_sprite_2d.hide()
						unit.add_child(preload("res://scripts/items/potion_totem_visual.gd").new())
						unit.set_physics_process(false)
						unit.modulate = Color("b99568")
						_decoys.append(weakref(unit))
						_refresh_decoys()
						set_physics_process(true)
			K.COPY_ALLY:
				var source: UnitBase = context.target
				var at: Vector2 = cards._nearby_position(source.global_position)
				if summon_floor(at) != source.floor_id:
					at = source.global_position
				var unit := _spawn(context, at, source.floor_id, 1)
				cards.inherit_potion_buffs(unit, cards.states[source.get_instance_id()].buffs)
				unit.current_health = mini(int(source.current_health), unit.unit_data.max_hp)
				unit.get_node("HealthBar").update_hp_bar(unit.current_health)
			K.REVIVE:
				var entry: Dictionary = context.fallen
				cards.expanded.fallen.erase(entry)
				var unit := _spawn(context, entry.position, int(entry.floor), 1)
				cards.inherit_potion_buffs(unit, entry.get("buffs", []))
				unit.current_health = maxi(1, ceili(unit.unit_data.max_hp * effect.amount / 100.0))
				unit.get_node("HealthBar").update_hp_bar(unit.current_health)
				# 不接 hand.board_cards、不移除弃牌堆原牌，因此不返还卡、不撤销阵亡加费。
			K.CONVERT:
				cards.convert_enemy(context.target)
			K.UPGRADE_CARD:
				context.upgrade.enhance()
				RunManager.deck_changed.emit()
				battle.hand_manager._notify_hand_changed()
			K.SKIP_ROUND:
				battle.battle_round_manager.skip_round()
			K.ZONE, K.GRAVITY, K.DELAYED_BLAST:
				_start_field(recipe, effect, point)
	free_prepared(context)


func _spawn(context: Dictionary, point: Vector2, floor_id: int, rounds: int) -> UnitBase:
	var unit: UnitBase = context.prepared.pop_front()
	unit.remove_from_group("team_b")
	unit.add_to_group("team_a")
	unit.set_collision_layer_value(2, false)
	unit.set_collision_layer_value(1, true)
	unit.set_meta("potion_summon_end", battle.battle_round_manager.current_round + rounds - 1)
	unit.floor_id = floor_id
	unit.position = battle.get_node("Entities/TeamA").to_local(point)
	battle.get_node("Entities/TeamA").add_child(unit)
	return unit


func apply_status(unit: UnitBase, effect: PotionEffect) -> void:
	if not unit.is_alive():
		return
	var key := "potion_%d" % _serial
	var amount := int(effect.amount)
	if effect.stack_cap > 0:
		amount = mini(amount, maxi(0, effect.stack_cap - unit.status_runtime.total_amount(effect.status_id)))
		if amount == 0:
			return
	unit.apply_status(effect.status_id, effect.duration, amount, null, key)
	if effect.status_id == &"sleep":
		unit.set_meta("potion_sleep", true)
	elif effect.status_id == &"confusion":
		unit.set_meta("potion_confusion", true)
		unit.skill_manager.clear_target_cache()


func _chain(recipe: PotionDefinition, effect: PotionEffect, point: Vector2) -> void:
	var remaining := enemies()
	var at := point
	for index in effect.count:
		var nearest: UnitBase
		var distance := recipe.radius if index == 0 else effect.radius
		for unit in remaining:
			var candidate := at.distance_to(unit.global_position)
			if unit.is_alive() and candidate <= distance:
				distance = candidate
				nearest = unit
		if nearest == null:
			break
		remaining.erase(nearest)
		# 实验室 Chain Lightning 配方的同一条 Premium 雷线与命中素材。
		var visual := LIBRARY.spawn(self, "LightningBoltVFX_Premium", to_local(at), {
			"destination": nearest.global_position, "max_lifetime": 0.35,
			"properties": {"ability_vfx_id": "chain_lightning"}})
		if visual != null:
			VFX.use_physics_clock(visual)
		at = nearest.global_position
		VFX.spawn(nearest, "ElectricImpactVFX", 0.7)
		nearest.take_effect_damage(int(effect.amount), null, &"lightning")


func _start_field(recipe: PotionDefinition, effect: PotionEffect, point: Vector2) -> void:
	var terrain := battle.get_node("Level/NavigationRegion2D")
	var ground_z: int = terrain.get_floor_z_index(terrain.spawn_floor_at(point))
	z_as_relative = false
	z_index = ground_z + 5
	field = {"recipe": recipe, "effect": effect, "point": point, "elapsed": 0.0,
		"clock": 0.0, "impacted": false,
		"end_round": battle.battle_round_manager.current_round + effect.rounds - 1,
		"visual": null}
	_field_clock = 0.0
	if effect.kind == K.ZONE:
		var visual := preload("res://scripts/effects/mud_ground_zone.gd").new(effect.radius)
		add_child(visual)
		visual.global_position = point
		visual.z_as_relative = false
		visual.z_index = ground_z - 1
		field.visual = visual
	elif effect.kind == K.GRAVITY:
		field.visual = LIBRARY.spawn(self, "GravityWellEffect", to_local(point), {"scale": 1.0, "max_lifetime": 0.0, "ground_position": point})
	set_physics_process(true)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if get_tree().paused or battle.battle_finished or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		return
	_decoy_clock += delta
	if not _decoys.is_empty() and _decoy_clock >= 0.2:
		_decoy_clock = 0.0
		_refresh_decoys()
	if field.is_empty():
		if _decoys.is_empty():
			set_physics_process(false)
		return
	var effect: PotionEffect = field.effect
	field.elapsed += delta
	_field_clock += delta
	if _field_clock >= 0.1:
		var step := _field_clock
		_field_clock = 0.0
		for unit in enemies():
			var inside := unit.global_position.distance_to(field.point) <= effect.radius
			if effect.kind == K.ZONE:
				# 取最强，离开区域立刻移除本区域来源。
				if inside:
					unit.apply_status(&"slow", 0, roundi(float(cards.states[unit.get_instance_id()].base_speed) * effect.amount / 100.0), null, "potion_zone")
				else:
					unit.remove_status(&"slow", "potion_zone")
			elif effect.kind == K.GRAVITY and inside:
				unit.apply_status(&"slow", 0.2, int(effect.amount), null, "potion_gravity")
				_pull(unit, field.point, step)
	if effect.kind == K.DELAYED_BLAST:
		_advance_meteor(delta)
	elif effect.duration > 0 and field.elapsed >= effect.duration:
		finish_field()
	queue_redraw()


func _pull(unit: UnitBase, point: Vector2, delta: float) -> void:
	if unit.has_status(&"steadfast"):
		return
	var at: Vector2 = unit.global_position.move_toward(point, 180.0 * delta)
	if is_instance_valid(unit.floor_map) and not unit.floor_map.has_ground_at(at, unit.floor_id):
		return
	var motion := at - unit.global_position
	# 用地形碰撞层测试，避免拉过岩壁；不改变单位楼层。
	var old_mask := unit.collision_mask
	unit.collision_mask = (unit.floor_map.terrain_bit(unit.floor_id) | 4) if is_instance_valid(unit.floor_map) else 12
	var collision := unit.move_and_collide(motion, true)
	unit.collision_mask = old_mask
	unit.global_position += motion if collision == null else collision.get_travel()
	unit.navigation_agent_2d.reset_after_teleport()


func _advance_meteor(delta: float) -> void:
	var effect: PotionEffect = field.effect
	var previous := float(field.elapsed) - delta
	var burn_delta := maxf(0, minf(field.elapsed, effect.delay + effect.duration) - maxf(previous, effect.delay))
	if not field.impacted and field.elapsed >= effect.delay:
		field.impacted = true
		var recipe: PotionDefinition = field.recipe
		flash(field.point, recipe, "MegaMeteorImpactVFX")
		for unit in affected(recipe, effect, field.point, null):
			unit.take_effect_damage(int(effect.amount), null, &"burn")
		if field.is_empty() or battle.battle_finished:
			return
	if not field.impacted:
		return
	field.clock += burn_delta
	while field.clock + 0.000001 >= effect.interval:
		field.clock -= effect.interval
		for unit in affected(field.recipe, effect, field.point, null):
			unit.take_effect_damage(effect.count, null, &"burn")
		if field.is_empty() or battle.battle_finished:
			return
	if field.elapsed >= effect.delay + effect.duration:
		finish_field()


func _refresh_decoys() -> void:
	for reference in _decoys.duplicate():
		var decoy := reference.get_ref() as UnitBase
		if not is_instance_valid(decoy) or not decoy.is_alive():
			_decoys.erase(reference)
			continue
		for enemy in enemies():
			var key := "potion_decoy_%d" % decoy.get_instance_id()
			if enemy.global_position.distance_to(decoy.global_position) <= 260.0 and enemy.is_on_same_floor(decoy):
				enemy.apply_status(&"taunt", 0.3, 0, decoy, key)


func persists_between_rounds() -> bool:
	return not field.is_empty() and field.effect.rounds > 0


func end_round() -> void:
	var round_number: int = battle.battle_round_manager.current_round
	if _last_round == round_number:
		return
	_last_round = round_number
	cards.plays.potion_free_plays = 0
	cards.plays.refresh_costs()
	for unit in cards.living_units():
		if unit.has_meta("potion_sleep"):
			unit.remove_status(&"sleep")
			unit.remove_meta("potion_sleep")
	if not field.is_empty() and (field.effect.rounds <= 0 or round_number >= int(field.end_round)):
		finish_field()


func phase_changed(phase: int) -> void:
	if battle.battle_finished or phase in [Global.GamePhase.VICTORY, Global.GamePhase.DEFEAT]:
		finish_field()
		_decoys.clear()
		set_physics_process(false)
	elif phase == Global.GamePhase.CARD_PLAY:
		for unit in cards.living_units():
			unit.remove_status(&"slow", "potion_gravity")


func finish_field() -> void:
	if field.is_empty():
		return
	var visual: Node2D = field.get("visual")
	if is_instance_valid(visual):
		visual.queue_free()
	field.clear()
	for unit in cards.living_units():
		unit.remove_status(&"slow", "potion_zone")
		unit.remove_status(&"slow", "potion_gravity")
	if items.potion != null and items.potion.kind == PotionDefinition.Kind.EFFECTS:
		items.clear_effect()
	queue_redraw()


func flash(point: Vector2, recipe: PotionDefinition, override_vfx: String = "") -> void:
	var visual := PULSE.new()
	visual.tint = recipe.tint
	visual.radius = recipe.radius
	add_child(visual)
	visual.global_position = point
	var terrain := battle.get_node("Level/NavigationRegion2D")
	var ground_z: int = terrain.get_floor_z_index(terrain.spawn_floor_at(point))
	visual.z_as_relative = false
	visual.z_index = ground_z + 5
	var effect_id := override_vfx if not override_vfx.is_empty() else recipe.impact_vfx
	if not effect_id.is_empty():
		var instance := LIBRARY.spawn(self, effect_id, to_local(point), {"scale": 0.8, "max_lifetime": 1.4, "ground_position": point})
		if instance != null:
			instance.z_as_relative = false
			instance.z_index = ground_z + 5
			VFX.use_physics_clock(instance)


func _draw() -> void:
	if field.is_empty():
		return
	var effect: PotionEffect = field.effect
	var point := to_local(field.point)
	var tint: Color = field.recipe.tint
	draw_circle(point, effect.radius, Color(tint, 0.08))
	draw_arc(point, effect.radius, 0, TAU, 64, Color(tint, 0.6), 2.0, true)
	if effect.kind == K.DELAYED_BLAST and not field.impacted:
		var progress := clampf(float(field.elapsed) / effect.delay, 0, 1)
		draw_arc(point, effect.radius * (1 - progress), 0, TAU, 48, tint, 3.0, true)
		draw_circle(point + Vector2(-100, -280) * (1 - progress), 12 + 8 * progress, tint)
