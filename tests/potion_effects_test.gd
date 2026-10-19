extends Node

const CATALOG = preload("res://scripts/items/potion_catalog.gd")
var checks := 0
var failures: Array[String] = []
var battle: Node2D
var items: Node2D
var runtime: Node2D
var ally: UnitBase
var other_ally: UnitBase
var enemy: UnitBase
var other_enemy: UnitBase


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func unit(friendly: bool, at: Vector2) -> UnitBase:
	var node := load("res://scenes/units/soldier.tscn" if friendly else "res://scenes/units/orc.tscn").instantiate() as UnitBase
	node.unit_data = node.unit_data.duplicate()
	node.unit_data.max_hp = 1000
	node.floor_id = battle.get_node("Level/NavigationRegion2D").spawn_floor_at(at)
	node.position = at
	battle.get_node("Entities/TeamA" if friendly else "Entities/TeamB").add_child(node)
	node.global_position = at
	node.set_physics_process(false)
	return node


func setup() -> void:
	var initial := load("res://data/run/run_start_data.tres").duplicate(true)
	initial.starting_relics.clear()
	initial.starting_potions.clear()
	RunManager.start_new_run(initial)
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle)
	for child in battle.get_node("Entities/TeamB").get_children():
		child.free()
	ally = unit(true, Vector2(550, 500))
	other_ally = unit(true, Vector2(590, 500))
	enemy = unit(false, Vector2(850, 500))
	other_enemy = unit(false, Vector2(890, 500))
	items = battle.get_node("BattleItems")
	runtime = items.potion_runtime
	battle.battle_round_manager.start_auto_battle()
	await get_tree().physics_frame
	await get_tree().physics_frame


func give(id: String) -> PotionDefinition:
	# 此组逐瓶验证效果；容量与替换由balance-framework真实背包回归覆盖。
	while RunManager.potions.size() >= RunManager.potion_capacity:
		RunManager.discard_potion(RunManager.potions[0])
	check(RunManager.add_potion(load("res://data/potions/" + id + ".tres")), id + "可获得")
	return RunManager.potions.back()


func use(id: String, point: Vector2 = Vector2(850, 500)) -> bool:
	var potion := give(id)
	if not items.select_potion(potion):
		return false
	return items.try_cast(point) if potion.needs_aim() else true


func _run() -> void:
	for recipe: PotionDefinition in CATALOG.all_potions():
		await setup()
		var id := String(recipe.id)
		var hp_before: int = RunManager.hp
		var energy_before: int = battle.battle_round_manager.current_energy
		var hand_before: int = battle.hand_manager.hand.size()
		var attack_before: int = ally.unit_data.attack
		var defence_before: int = ally.unit_data.defence
		var point := enemy.global_position
		var original: CardInstance
		if id in ["duplication_potion", "revive_potion"]:
			original = CardInstance.new(load("res://data/units/soldier.tres"))
			RunManager.deck.append(original)
			battle.hand_manager.hand.append(original)
			battle.hand_manager.move_hand_card_to_board(original, ally)
			ally.current_health = 43
			var inherited := CardEffect.new()
			inherited.kind = CardEffect.Kind.ATTACK_UP
			inherited.amount = 4
			inherited.lifetime = CardEffect.Lifetime.ROUNDS
			inherited.lasting_rounds = 3
			battle.card_runtime.apply_potion_buff(ally, inherited, "继承测试")
		if id == "revive_potion":
			ally.die()
		if id in ["healing_potion", "cleanse_water"]:
			RunManager.hp = 40
			ally.current_health = 80
			ally.apply_status(&"weakness", 8, 3)
			ally.apply_status(&"bleed", 8, 2)
			battle.card_runtime.add_poison(ally, 10)
		if id in ["decoy_totem", "reinforcement_horn", "undead_legion"]:
			for attempt in 100:
				point = battle.random_deployment_position()
				if battle.battlefield_rect.has_point(point) and runtime.summon_floor(point) > 0:
					break
		if id == "convert_potion":
			enemy.unit_data.monster_rank = UnitData.MonsterRank.NORMAL
		if id == "fairy_tear":
			var passive := give(id)
			check(not items.select_potion(passive), "仙女之泪不能手动喝")
			RunManager.hp = 0
			check(RunManager.hp == ceili(RunManager.max_hp * 0.3) and RunManager.potions.is_empty(), "致命伤前消耗仙女并回复30%")
			check(not RunManager.add_potion(recipe), "仙女每局最多一瓶")
		else:
			var success := use(id, point)
			check(success, id + "通过真实入口施放：" + items.last_error + " at " + str(point))
			check(RunManager.potions.is_empty(), id + "只消耗一瓶")
		match id:
			"blast":
				check(enemy.current_health == 950 and enemy.has_node("KnockbackMotion"), "爆裂50伤害及击退")
			"frost_flask":
				check(enemy.current_health == 975 and enemy.status_runtime.strongest_amount(&"slow") == 60, "寒霜伤害与减速")
				get_tree().paused = true
				enemy.status_runtime._physics_process(5)
				get_tree().paused = false
				check(enemy.has_status(&"slow"), "暂停不推进减益")
				enemy.status_runtime._physics_process(3.01)
				check(not enemy.has_status(&"slow"), "减速按秒到期")
			"poison_flask":
				check(enemy.current_health == 975 and battle.card_runtime.states[enemy.get_instance_id()].poison == 10, "毒雾伤害及10层毒")
				battle.card_runtime._on_round_ended()
				check(enemy.current_health == 965, "毒在本轮末结算")
			"mud_flask":
				runtime._physics_process(0.1)
				check(enemy.has_status(&"slow") and items.potion != null, "泥沼占槽并减速")
				enemy.global_position += Vector2(250, 0)
				runtime._physics_process(0.1)
				check(not enemy.has_status(&"slow"), "离开泥沼恢复速度")
				Global.game_phase = Global.GamePhase.ROUND_RESOLVE
				check(not runtime.field.is_empty(), "泥沼跨准备阶段保留")
			"weaken_gas", "sunder_acid":
				var status := &"weakness" if id == "weaken_gas" else &"armor_break"
				var amount := 3 if id == "weaken_gas" else 4
				check(enemy.status_runtime.total_amount(status) == amount, id + "减益生效")
				check(use(id) and use(id), id + "可连续施放")
				check(enemy.status_runtime.total_amount(status) == amount * 2, id + "叠加封顶")
			"strength_brew":
				check(ally.unit_data.attack == attack_before + 2, "力量全体攻击+2")
				check(battle.card_runtime.states[ally.get_instance_id()].buffs.back().left == 3, "交锋中药水增益保留3回合")
			"iron_brew":
				check(ally.unit_data.defence == defence_before + 3, "铁壁全体防御+3")
			"cleanse_water":
				check(not ally.has_status(&"weakness") and not ally.has_status(&"bleed") and ally.current_health == 95 and battle.card_runtime.states[ally.get_instance_id()].poison == 0, "净化清减益、毒并治疗15")
			"healing_potion":
				check(RunManager.hp == 65, "玩家治疗25")
			"insight_brew":
				check(battle.hand_manager.hand.size() == hand_before + 3, "智慧实际抽3张")
			"gambler_brew":
				check(battle.hand_manager.hand.size() == hand_before + 2, "赌徒弃全部后多抽2张")
			"chain_lightning":
				check(enemy.current_health == 978 and other_enemy.current_health == 978, "链电不重复命中")
			"corrosive_flask":
				check(enemy.current_health == 970 and enemy.status_runtime.total_amount(&"armor_break") == 4 and battle.card_runtime.states[enemy.get_instance_id()].poison == 8, "腐蚀伤害、破甲、中毒")
			"frost_nova", "time_stop":
				check(enemy.has_status(&"stun") and other_enemy.has_status(&"stun"), id + "群体眩晕")
			"sleep_dust":
				check(enemy.has_status(&"sleep"), "催眠生效")
				enemy.take_effect_damage(1, null, &"poison")
				check(not enemy.has_status(&"sleep"), "毒和直接伤害唤醒催眠")
			"confusion_gas":
				enemy.unit_data.is_flying = true
				check(enemy.is_potion_confused() and enemy.skill_manager.find_nearest_enemy() == other_enemy, "混乱选择同阵营单位")
				var before: int = other_enemy.current_health
				check(other_enemy.get_hurt(20, enemy, false), "混乱允许同阵营普攻")
				check(other_enemy.current_health < before, "混乱攻击实际扣血")
				enemy.remove_status(&"confusion")
				check(not other_enemy.get_hurt(20, enemy, false), "混乱结束禁止友伤")
			"gravity_well":
				var distance: float = other_enemy.global_position.distance_to(point)
				runtime._physics_process(0.5)
				check(other_enemy.has_status(&"slow") and other_enemy.global_position.distance_to(point) < distance, "重力井减速及聚怪")
				runtime._physics_process(1.6)
				check(runtime.field.is_empty() and items.potion == null, "重力井2秒到期释放槽")
			"aegis_brew":
				check(ally.shield_amount == 50, "圣盾50")
				ally.take_effect_damage(20)
				check(ally.current_health == 1000 and ally.shield_amount == 30, "护盾先扣")
				Global.game_phase = Global.GamePhase.ROUND_RESOLVE
				check(ally.shield_amount == 0, "护盾阶段清理")
			"envenom_brew":
				battle.card_runtime._on_hit(enemy, ally)
				check(battle.card_runtime.states[enemy.get_instance_id()].poison == 3, "淬毒普攻附毒3")
			"deathrattle_brew":
				ally.global_position = enemy.global_position
				other_ally.global_position = enemy.global_position + Vector2(20, 0)
				ally.die()
				check(enemy.current_health == 960 and other_ally.current_health == 1000, "亡语爆炸40，仅伤敌军")
			"energy_potion":
				check(battle.battle_round_manager.current_energy == energy_before + 2, "能量立即+2")
			"tactics_brew":
				check(runtime.cards.plays.potion_free_plays == 2 and battle.hand_manager.hand[0].get_cost() == 0, "战术2次零费")
				var effect := CardEffect.new()
				effect.kind = CardEffect.Kind.GAIN_ENERGY
				effect.amount = 1
				for index in 3:
					var definition := CardDefinition.new()
					definition.category = CardDefinition.Category.ABILITY
					definition.target = CardDefinition.Target.NONE
					definition.card_cost = 8
					definition.effects.append(effect)
					var card := CardInstance.new(definition)
					battle.hand_manager.hand.append(card)
					battle.hand_manager._notify_hand_changed()
					var played: bool = battle.card_runtime.try_play(card, Vector2(800, 500))
					check(played == (index < 2), "战术仅接下来2张手牌免能量：%d" % index)
				check(runtime.cards.plays.potion_free_plays == 0, "战术成功施放才消耗次数")
			"reinforcement_horn", "undead_legion", "decoy_totem":
				var count: int = {"reinforcement_horn": 2, "undead_legion": 3, "decoy_totem": 1}[id]
				check(runtime.allies().size() == 2 + count, id + "召唤正确数量")
				var summoned: UnitBase = runtime.allies().back()
				check(not battle.hand_manager.board_cards.has(summoned.get_instance_id()), id + "无原征召牌")
				if id == "decoy_totem":
					check(summoned.current_health == 60 and battle.card_runtime.should_retain_unit(summoned), "诱饵60生命且可留到第2回合")
				else:
					check(not battle.card_runtime.should_retain_unit(summoned), id + "本轮末消失")
			"forge_oil":
				check(RunManager.deck.any(func(c: CardInstance): return not c.is_unit_card() and c.upgrade_count > 0), "锻造强化原牌")
			"smoke_bomb":
				check(RunManager.hp == hp_before and battle.battle_round_manager.round_damage == 0, "烟雾弹无双方扣血")
			"meteor":
				runtime._physics_process(1.99)
				check(enemy.current_health == 1000, "陨石2秒前无伤害")
				runtime._physics_process(0.01)
				check(enemy.current_health == 840, "陨石落地160")
				runtime._physics_process(0.5)
				check(enemy.current_health == 830, "陨石每0.5秒燃烧10")
			"revive_potion":
				check(runtime.allies().size() == 2 and original.cost_increase > 0 and not battle.hand_manager.board_cards.values().has(original), "复活临时单位，不返还原牌和阵亡加费")
				check(runtime.allies().back().current_health == 50, "复活50%生命")
				check(runtime.allies().back().unit_data.attack == 14, "复活保留强化且只继承一次")
			"duplication_potion":
				check(runtime.allies().size() == 3 and runtime.allies().back().current_health == 43, "复制继承当前生命")
				check(runtime.allies().back().unit_data.attack == ally.unit_data.attack, "复制强化不重复累计")
			"convert_potion":
				check(enemy.unit_data.unit_team == "team_a" and enemy.get_parent() == battle.get_node("Entities/TeamA"), "策反实际换队")
			"life_fruit":
				check(RunManager.max_hp == 90 and RunManager.hp == hp_before + 10, "生命果实+10最大及当前生命")
			"blood_offering":
				check(RunManager.hp == hp_before - 12 and battle.battle_round_manager.current_energy == energy_before + 3 and battle.hand_manager.hand.size() == hand_before + 3, "血契支付15%、能量+3、抽3张")
		# 每瓶隔离真实战场，避免前一瓶的时钟与状态影响后一瓶。
		battle.battle_finished = true
		items.clear_effect()
		battle.queue_free()
		await get_tree().process_frame
	await constraints()
	print("POTION_EFFECTS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func constraints() -> void:
	await setup()
	var fire := give("fire")
	check(items.select_potion(fire) and items.try_cast(enemy.global_position), "持续药水先施放")
	check(use("energy_potion") and use("insight_brew"), "持续药水期间可连喝即时药水")
	var mud := give("mud_flask")
	check(not items.select_potion(mud), "第二个场地药水被拒绝")
	items.clear_effect()
	var convert := give("convert_potion")
	enemy.unit_data.monster_rank = UnitData.MonsterRank.BOSS
	check(items.select_potion(convert) and not items.try_cast(enemy.global_position) and RunManager.potions.has(convert), "策反Boss失败不扣瓶")
	items.clear_effect()
	var smoke := give("smoke_bomb")
	check(not items.select_potion(smoke) and RunManager.potions.has(smoke), "烟雾弹Boss波不扣瓶")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	var strength := give("strength_brew")
	check(items.select_potion(strength), "准备阶段可用增益")
	var blast := give("blast")
	check(not items.select_potion(blast), "准备阶段禁止伤害瓶")
	var shield := give("aegis_brew")
	check(not items.select_potion(shield), "准备阶段禁止圣盾")
	var healing := give("healing_potion")
	check(not items.select_potion(healing) and RunManager.potions.has(healing), "满血治疗失败不扣瓶")
	RunManager.hp = 5
	var blood := give("blood_offering")
	check(not items.select_potion(blood) and RunManager.hp == 5 and RunManager.potions.has(blood), "血契致死风险拒绝且不扣瓶")
	battle.hand_manager.draw_locked = true
	var insight := give("insight_brew")
	check(not items.select_potion(insight) and RunManager.potions.has(insight), "禁抽时智慧失败不扣瓶")
	battle.hand_manager.draw_locked = false
	check(use("life_fruit") and use("life_fruit"), "生命果实可使用两次")
	check(not RunManager.add_potion(load("res://data/potions/life_fruit.tres")), "生命果实本局限两瓶")
	check(RunManager.save_run().is_empty(), "药水进度可保存")
	RunManager.potion_use_counts.clear()
	check(RunManager.load_saved_run().is_empty() and int(RunManager.potion_use_counts.get(&"life_fruit", 0)) == 2, "药水使用上限读档后保留")
	battle.battle_finished = true
	items.clear_effect()
	battle.queue_free()
	await get_tree().process_frame
