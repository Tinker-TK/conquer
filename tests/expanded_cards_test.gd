# 使用正式出牌与真实兵种验证23张新卡，以及选择面板、阶段清理和持久化边界。
extends Node

const NAMES := ["rend", "healing_ban", "armor_shred", "slumber", "holy_bulwark", "overflow_prayer", "last_stand", "hold_ground", "mobilization", "letting_go", "sacrifice", "return_dead", "martyrdom", "war_cry", "fortify", "haste", "battle_standard", "spike_trap", "transcription", "reformation", "stratagem", "overdraft", "thrift"]
const COSTS := [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 2, 2, 1, 2, 2, 1, 2, 1, 2, 2, 1, 0, 1]
const UPGRADED_COSTS := [1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 2, 2, 1, 2, 2, 1, 2, 1, 2, 1, 1, 0, 0]
const AMOUNTS := [6, 1, 1, 1, 30, 1, 45, 1, 1, 2, 3, 50, 1, 1, 1, 30, 2, 15, 1, 3, 1, 3, 1]
const UPGRADED_AMOUNTS := [9, 1, 2, 1, 45, 1, 65, 1, 2, 3, 2, 75, 2, 2, 2, 45, 3, 25, 1, 3, 2, 4, 1]
var checks := 0
var failures: Array[String] = []
var battle
var hand
var runtime
var rounds


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _catalog() -> void:
	var start := RunStartData.new()
	var signatures: Array[String] = []
	for i in NAMES.size():
		var data := load("res://data/cards/%s.tres" % NAMES[i]) as CardDefinition
		start.cards.append(data)
		var card := CardInstance.new(data)
		var peer := CardInstance.new(data)
		check(data.card_image != null and data.card_image.get_width() >= 1000, NAMES[i] + "独立完整插画")
		check(data.max_upgrade_count == 1 and card.get_cost() == COSTS[i] and data.effects[0].amount == AMOUNTS[i], NAMES[i] + "基础配置")
		check(card.enhance() and card.get_cost() == UPGRADED_COSTS[i] and card.definition.effects[0].amount == UPGRADED_AMOUNTS[i], NAMES[i] + "强化数值及费用")
		check(peer.get_cost() == COSTS[i] and data.effects[0].amount == AMOUNTS[i], NAMES[i] + "同名牌独立")
		check(not card.enhance() and not card.get_description().is_empty(), NAMES[i] + "强化上限及说明")
		if NAMES[i] == "healing_ban":
			check(card.definition.effects[0].status_seconds == 12, "禁疗强化12秒")
		if NAMES[i] == "slumber":
			check(card.definition.effects[0].status_seconds == 8, "睡眠强化8秒")
		if NAMES[i] == "transcription":
			check(card.definition.effects[0].upgrades_drawn_cards and not data.effects[0].upgrades_drawn_cards, "誊抄强化新增规则")
	RunManager.start_new_run(start)
	for card: CardInstance in RunManager.deck:
		check(card.enhance(), "新牌可正式强化")
		signatures.append("%d|%s" % [card.get_cost(), card.get_description()])
	check(RunManager.save_run().is_empty() and RunManager.load_saved_run().is_empty(), "保存及读取新牌强化")
	for i in NAMES.size():
		check("%d|%s" % [RunManager.deck[i].get_cost(), RunManager.deck[i].get_description()] == signatures[i], NAMES[i] + "读档一致")
	var pool: Array[Resource] = preload("res://scripts/battle/battle_reward_session.gd").card_pool()
	var shop: Dictionary = preload("res://scripts/shop/shop_catalog.gd").read_catalog()
	check(not shop.has("error"), "新商品池合法")
	for name in NAMES:
		check(pool.any(func(data: Resource): return data.resource_path.ends_with("/%s.tres" % name)), name + "进入奖励池")
		check(shop.data.cards.any(func(entry: Dictionary): return entry.path.ends_with("/%s.tres" % name)), name + "进入商店池")


func _create() -> void:
	var start := RunStartData.new()
	for i in 24:
		start.cards.append(load("res://data/units/soldier.tres"))
	RunManager.start_new_run(start)
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	config.enemy_max_hp = 10000
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	hand = battle.hand_manager
	runtime = battle.card_runtime
	rounds = battle.battle_round_manager
	check(await preload("res://tests/battle_test_navigation.gd").install(battle), "新卡测试导航同步")
	runtime.set_physics_process(false)
	runtime.tactics.set_physics_process(false)
	runtime.expanded.set_physics_process(false)


func _give(name: String, upgraded: bool = false) -> CardInstance:
	var card := CardInstance.new(load("res://data/cards/%s.tres" % name))
	if upgraded:
		check(card.enhance(), name + "准备强化")
	hand.hand.append(card)
	return card


func _play(card: CardInstance, position: Vector2 = Vector2(450, 450), choice: Dictionary = {}) -> void:
	rounds.current_energy = card.get_cost()
	var reasons: Array[String] = []
	var callback := func(message: String): reasons.append(message)
	runtime.feedback.connect(callback)
	var played: bool = runtime.try_play(card, position, false, 0, false, choice)
	runtime.feedback.disconnect(callback)
	check(played, card.definition.card_name + "正式出牌 " + "；".join(reasons))
	runtime.tactics.set_physics_process(false)
	runtime.expanded.set_physics_process(false)


func _recruit(point: Vector2 = Vector2(450, 450)) -> UnitBase:
	var card: CardInstance = hand.draw_pile.pop_back()
	hand.hand.append(card)
	_play(card, point)
	var unit: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	unit.set_physics_process(false)
	return unit


func _enemy(point: Vector2 = Vector2(1050, 450)) -> UnitBase:
	var unit := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	unit.unit_data = unit.unit_data.duplicate()
	unit.unit_data.max_hp = 10000
	unit.unit_data.defence = 100
	var parent: Node2D = battle.get_node("Entities/TeamB")
	unit.position = parent.to_local(point)
	parent.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _tick(unit: UnitBase, delta: float) -> void:
	unit.status_runtime._physics_process(delta)
	unit.status_runtime.set_physics_process(false)


func _dispose() -> void:
	battle.finish_battle(false)
	battle.queue_free()
	await get_tree().process_frame


func _statuses() -> void:
	await _create()
	var ally := _recruit()
	var enemy := _enemy()
	_play(_give("rend"), enemy.global_position)
	_tick(enemy, 1)
	check(enemy.current_health == 10000, "准备阶段状态不计时")
	rounds.start_auto_battle()
	_tick(enemy, 8)
	check(enemy.current_health == 10000 - 48 and not enemy.has_status(&"bleed"), "割裂6点每秒8秒无视100防御")
	_play(_give("rend", true), enemy.global_position)
	_tick(enemy, 8)
	check(enemy.current_health == 10000 - 48 - 72, "强化割裂9点每秒8秒")
	_play(_give("healing_ban"), enemy.global_position)
	check(not enemy.get_heal(100) and not enemy.receive_healing(100, ally, true), "禁疗拦截治疗和溢出转盾")
	_tick(enemy, 7.9)
	check(enemy.has_status(&"mortal_wounds"), "禁疗8秒前生效")
	_tick(enemy, 0.1)
	check(enemy.get_heal(1), "禁疗8秒到期")
	_play(_give("healing_ban", true), enemy.global_position)
	_tick(enemy, 8)
	check(enemy.has_status(&"mortal_wounds"), "强化禁疗超过8秒仍生效")
	_tick(enemy, 4)
	check(not enemy.has_status(&"mortal_wounds"), "强化禁疗12秒到期")
	_play(_give("armor_shred"), enemy.global_position)
	enemy.get_hurt(1, ally, false)
	enemy.get_hurt(1, ally, false)
	check(enemy.unit_data.defence == 98, "破甲两次攻击命中累计减2")
	enemy.clear_combat_statuses()
	_play(_give("armor_shred", true), enemy.global_position)
	enemy.get_hurt(1, ally, false)
	enemy.get_hurt(1, ally, false)
	check(enemy.unit_data.defence == 96, "强化破甲每次减2")
	enemy.clear_combat_statuses()
	check(enemy.unit_data.defence == 100, "清理破甲恢复防御")
	_play(_give("slumber"), enemy.global_position)
	_tick(enemy, 4.9)
	check(enemy.has_status(&"sleep") and not enemy.can_use_skills(), "沉睡5秒前限制行动")
	_tick(enemy, 0.1)
	check(not enemy.has_status(&"sleep") and enemy.can_use_skills() and enemy.animated_sprite_2d.is_playing(), "沉睡5秒自然醒来并恢复动画")
	_play(_give("slumber", true), enemy.global_position)
	_tick(enemy, 5)
	check(enemy.has_status(&"sleep"), "强化沉睡超过5秒仍生效")
	enemy.get_hurt(1, ally, false)
	check(not enemy.has_status(&"sleep"), "攻击命中立即唤醒强化沉睡")
	_play(_give("slumber", true), enemy.global_position)
	_tick(enemy, 8)
	check(not enemy.has_status(&"sleep"), "强化沉睡8秒自然醒来")
	await _dispose()


func _shields_and_immunity() -> void:
	await _create()
	var ally := _recruit()
	var enemy := _enemy()
	ally.unit_data.max_hp = 1000
	ally.current_health = 1000
	_play(_give("holy_bulwark"), ally.global_position)
	ally.take_effect_damage(30)
	check(ally.shield_amount == 0 and ally.current_health == 1000, "30护盾先于生命吸收伤害")
	_play(_give("holy_bulwark", true), ally.global_position)
	check(ally.shield_amount == 45, "强化圣光壁垒45护盾")
	ally.clear_shield()
	ally.current_health = 700
	_play(_give("last_stand"), ally.global_position)
	check(ally.shield_amount == 135, "背水按缺失300生命的45%转盾")
	ally.clear_shield()
	_play(_give("last_stand", true), ally.global_position)
	check(ally.shield_amount == 195, "强化背水按缺失生命65%转盾")
	ally.clear_shield()
	_play(_give("overflow_prayer", true), ally.global_position)
	check(rounds.current_energy == 0 and ally.has_status(&"overflow_shield"), "强化溢流祷言1费")
	ally.receive_healing(350)
	check(ally.current_health == 1000 and ally.shield_amount == 50, "祷言普通治疗溢出50按1:1转盾")
	ally._on_shield_phase_changed(Global.GamePhase.ROUND_RESOLVE)
	check(ally.shield_amount == 0 and ally.has_status(&"overflow_shield"), "交锋结束清除护盾，保留本场祷言")
	_play(_give("hold_ground", true), ally.global_position)
	check(ally.has_status(&"steadfast") and rounds.current_energy == 0, "强化坚守阵地0费")
	preload("res://scripts/combat/knockback_motion.gd").push(ally, enemy, 200, 0.3, 2)
	check(ally.get_node_or_null("KnockbackMotion") == null, "坚守阵地阻止真实击退入口")
	battle.finish_battle(false)
	check(not ally.has_status(&"overflow_shield") and not ally.has_status(&"steadfast"), "战斗结束清理本场单位状态")
	await _dispose()


func _auras_and_props() -> void:
	await _create()
	var ally := _recruit()
	var enemy := _enemy()
	var attack := ally.unit_data.attack
	var defence := ally.unit_data.defence
	var speed := ally.unit_data.speed
	_play(_give("war_cry", true))
	_play(_give("fortify", true))
	_play(_give("haste", true))
	check(ally.unit_data.attack == attack + 2 and ally.unit_data.defence == defence + 2 and is_equal_approx(ally.unit_data.speed, speed * 1.45), "强化全体攻防+2及移速45%")
	var later := _recruit(Vector2(450, 650))
	check(later.unit_data.attack == attack + 2 and later.unit_data.defence == defence + 2 and is_equal_approx(later.unit_data.speed, speed * 1.45), "后来入场单位立即享受常驻")
	_play(_give("battle_standard"), ally.global_position)
	check(ally.unit_data.attack == attack + 4, "基础战旗范围内攻击额外+2")
	ally.global_position += Vector2(300, 0)
	runtime.expanded._physics_process(0)
	check(ally.unit_data.attack == attack + 2, "离开战旗立即撤销加成")
	_play(_give("battle_standard", true), ally.global_position)
	check(ally.unit_data.attack == attack + 5, "强化战旗范围内额外+3")
	_play(_give("spike_trap"), enemy.global_position)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://outputs/new-cards-20261018/battlefield-props.png")
	runtime.expanded._physics_process(0)
	check(enemy.current_health == 10000, "准备阶段陷阱不触发")
	rounds.start_auto_battle()
	runtime.expanded._physics_process(0)
	check(enemy.current_health == 9985 and enemy.is_stunned, "地刺触发15伤害无视防御并眩晕")
	_tick(enemy, 1)
	check(not enemy.is_stunned, "陷阱眩晕1秒到期")
	runtime.expanded._physics_process(0)
	check(enemy.current_health == 9985, "陷阱触发后不再重复命中")
	_play(_give("spike_trap", true), enemy.global_position)
	runtime.expanded._physics_process(0)
	check(enemy.current_health == 9960, "强化地刺25伤害")
	battle.finish_battle(false)
	check(runtime.expanded.structures.is_empty() and ally.unit_data.attack == attack and ally.unit_data.defence == defence and is_equal_approx(ally.unit_data.speed, speed), "结束清理设施及全体攻防移速")
	await _dispose()


func _click_button(button: Button) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		get_viewport().push_input(click, true)
	await get_tree().process_frame


func _selection() -> void:
	await _create()
	var tutor := _give("mobilization", true)
	rounds.current_energy = 1
	var count: int = hand.hand.size()
	check(runtime.try_play(tutor, Vector2(450, 450)) and get_tree().paused, "检索打开真实模态选牌")
	var ui = battle.card_ui.card_choice
	check(ui.visible and ui.confirm_button.disabled and rounds.current_energy == 1 and hand.hand.size() == count, "选择前不扣费不移牌")
	ui.close()
	check(not get_tree().paused and hand.hand.has(tutor), "取消检索保持原牌与能量")
	var chosen: Array[CardInstance] = [hand.draw_pile[0], hand.draw_pile[1]]
	check(not runtime.try_play(tutor, Vector2(450, 450), false, 0, false, {"cards": [chosen[0], chosen[0]]}), "重复选择被拒绝")
	check(rounds.current_energy == 1 and hand.hand.has(tutor), "非法检索无副作用")
	runtime.try_play(tutor, Vector2(450, 450))
	for card in chosen:
		await _click_button(ui.buttons[card.id])
	check(not ui.confirm_button.disabled, "暂停中真实点击选满两张才能确认")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://outputs/new-cards-20261018/recruit-selection.png")
	await _click_button(ui.confirm_button)
	check(not get_tree().paused and rounds.current_energy == 0 and hand.hand.has(chosen[0]) and hand.hand.has(chosen[1]), "确认精确检索两张单位牌")
	var discard := _give("letting_go", true)
	var previous: int = hand.hand.size()
	_play(discard, Vector2(450, 450), {"cards": [chosen[0]]})
	check(hand.discard_pile.has(chosen[0]) and hand.hand.size() == previous + 1, "强化断舍离弃1抽3")
	await _dispose()


func _transcription_and_reformation() -> void:
	await _create()
	var first := _give("power_enhance")
	var second := _give("defend")
	var transcription := _give("transcription", true)
	var drawn := CardInstance.new(load("res://data/cards/power_enhance.tres"))
	hand.draw_pile.append(drawn)
	RunManager.deck.append(drawn)
	_play(transcription)
	check(hand.exhaust_pile.has(first) and hand.exhaust_pile.has(second) and hand.hand.size() == 2, "誊抄直接消耗两张其它牌并抽等量")
	check(drawn.upgrade_count == 1 and drawn.definition.effects[0].amount == 5 and drawn.persistent_upgrade_state().upgrade_count == 0, "强化誊抄按进化规则临时强化抽到的牌")
	var save := RunManager.create_save_data()
	check(save.card_states.back().upgrade_count == 0 and save.card_definitions.back().effects[0].amount == 3, "誊抄强化不会写成永久存档")
	var soldier: CardInstance = hand.hand.filter(func(card: CardInstance): return card.is_unit_card())[0]
	check(soldier.upgrade_count == 1 and soldier.attack_points == 2 and soldier.soldier_specialization == "missile", "誊抄自动分配单位攻击及飞弹分支")
	_play(soldier)
	var unit: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	unit.set_physics_process(false)
	var attack := unit.unit_data.attack
	_play(drawn, unit.global_position)
	check(unit.unit_data.attack == attack + 5 and drawn.upgrade_count == 0 and drawn.definition.effects[0].amount == 3, "强化抽牌成功使用后按5点结算并还原")
	await _dispose()
	await _create()
	var peers := [_give("power_enhance"), _give("death_explosion"), _give("draw_hp")]
	for card: CardInstance in peers:
		RunManager.deck.append(card)
	var reformation := _give("reformation", true)
	_play(reformation)
	check(hand.hand.size() == 3 and rounds.current_energy == 0, "强化变阵1费替换3张手牌")
	for i in peers.size():
		check(hand.hand[i] != peers[i] and hand.hand[i].get_cost() == peers[i].get_cost() and hand.hand[i].definition.card_name != peers[i].definition.card_name, "变阵同费且为其它牌")
		check(RunManager.deck.has(peers[i]), "变阵不改写本局原牌")
	await _dispose()


func _round_economy() -> void:
	await _create()
	var card := _give("death_explosion")
	var peer := _give("draw_hp")
	var stratagem := _give("stratagem", true)
	_play(stratagem)
	check(card.get_cost() == 0 and peer.get_cost() == 0 and card.get_intrinsic_cost() == 1, "强化运筹当前手牌减2最低0，保留固有费用")
	var later := _give("power_enhance")
	check(later.get_cost() == 1, "运筹不修改之后新入手的牌")
	runtime._on_round_ended()
	check(card.get_cost() == 1 and card.round_cost_reduction == 0, "回合结束恢复临时减费")
	rounds.max_energy = 4
	rounds.energy_growth = 0
	rounds.base_energy_cap = 10
	rounds.calculate_energy()
	_play(_give("overdraft", true))
	check(rounds.final_energy_max == 8 and rounds.current_energy == 4, "强化透支本回合上限及能量+4")
	rounds.current_round += 1
	rounds.calculate_energy()
	check(rounds.final_energy_max == 1, "强化透支下回合仍只扣3上限")
	rounds.current_round += 1
	rounds.calculate_energy()
	check(rounds.final_energy_max == 4, "透支第三回合恢复正常上限")
	_play(_give("thrift", true))
	check(rounds.current_energy == 0 and rounds.final_energy_max == 3 and hand.recurring_bonus_draw == 1, "强化节流0费，持久上限-1与每轮多抽1")
	var count: int = hand.hand.size()
	hand._on_battle_round_manager_phase_changed(Global.GamePhase.CARD_PLAY, rounds.current_round + 1)
	check(hand.hand.size() == count + 1, "节流在新回合真实多抽1")
	await _dispose()


func _deaths_and_resurrection() -> void:
	await _create()
	var first := _recruit()
	var second := _recruit(Vector2(450, 650))
	var first_card: CardInstance = hand.board_cards[first.get_instance_id()]
	var second_card: CardInstance = hand.board_cards[second.get_instance_id()]
	var first_hp := first.unit_data.max_hp
	_play(_give("martyrdom", true))
	var count: int = hand.hand.size()
	first.die()
	check(hand.hand.size() == count + 2 and first_card.cost_increase == 1, "强化殉道真实阵亡抽2并沿用原牌加费")
	second.die()
	_play(_give("return_dead"))
	var revived: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	revived.set_physics_process(false)
	check(revived.current_health == ceili(first_hp * 0.5) and hand.board_cards[revived.get_instance_id()] == first_card, "亡者归来复活最早阵亡者50%生命")
	check(not hand.discard_pile.has(first_card) and first_card.cost_increase == 1, "复活重绑原牌，保留加费且不重复牌堆")
	var resurrection := _give("return_dead", true)
	_play(resurrection)
	var second_revived: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	second_revived.set_physics_process(false)
	check(second_revived.current_health == ceili(second_revived.unit_data.max_hp * 0.75) and hand.board_cards[second_revived.get_instance_id()] == second_card and hand.exhaust_pile.has(resurrection), "强化亡者归来75%生命并消耗")
	_play(_give("sacrifice", true))
	rounds.current_energy = 0
	var enemy := _enemy()
	enemy.die(revived)
	check(rounds.current_energy == 0 and runtime.expanded.sacrifices[0].kills == 1, "强化献祭第1次击杀累计")
	runtime.expanded.end_round()
	var other := _enemy(Vector2(1050, 650))
	other.die(revived)
	check(rounds.current_energy == 1 and runtime.expanded.sacrifices[0].kills == 0, "强化献祭跨回合第2次击杀获得1能量")
	other.unit_died.emit(other)
	check(rounds.current_energy == 1 and runtime.expanded.sacrifices[0].kills == 0, "重复死亡信号不重复计击杀")
	battle.finish_battle(false)
	check(runtime.expanded.fallen.is_empty() and runtime.expanded.sacrifices.is_empty() and hand.recurring_bonus_draw == 0, "战斗结束清理死亡队列与经济状态")
	await _dispose()


func _capture() -> void:
	for upgraded in [false, true]:
		for page in 2:
			var viewport := SubViewport.new()
			viewport.size = Vector2i(1440, 1170)
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(viewport)
			var background := ColorRect.new()
			background.color = Color("222631")
			background.size = viewport.size
			viewport.add_child(background)
			for index in range(page * 15, mini((page + 1) * 15, NAMES.size())):
				var card := CardInstance.new(load("res://data/cards/%s.tres" % NAMES[index]))
				if upgraded:
					card.enhance()
				var view := preload("res://scenes/cards/unit_card.tscn").instantiate() as UnitCard
				view.is_playable = false
				viewport.add_child(view)
				view.setup(card)
				view.position = Vector2(145 + ((index % 15) % 5) * 285, 205 + floori(float(index % 15) / 5) * 380)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			check(viewport.get_texture().get_image().save_png("res://outputs/new-cards-20261018/cards-%s-%d.png" % ["upgraded" if upgraded else "base", page + 1]) == OK, "保存真实卡面预览")
			viewport.queue_free()
			await get_tree().process_frame


func _run() -> void:
	_catalog()
	await _statuses()
	await _shields_and_immunity()
	await _auras_and_props()
	await _selection()
	await _transcription_and_reformation()
	await _round_economy()
	await _deaths_and_resurrection()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()
	print("EXPANDED_CARDS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
