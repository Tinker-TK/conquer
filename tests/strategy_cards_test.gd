# 三张牌的正式出牌、选牌面板、临时升级、费用恢复、固有开局与存档隔离。
extends Node

var checks := 0
var failures: Array[String] = []
var battle
var hand
var runtime
var rounds


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(50.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)


func _create(standard: bool = false, continue_run: bool = false) -> void:
	if continue_run:
		pass
	elif standard:
		RunManager.start_new_run()
	else:
		var start := RunStartData.new()
		for i in 12:
			start.cards.append(load("res://data/units/soldier.tres"))
		RunManager.start_new_run(start)
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 5 if standard else 0
	config.enemy_max_hp = 1000
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	hand = battle.hand_manager
	runtime = battle.card_runtime
	rounds = battle.battle_round_manager


func _give(resource_name: String) -> CardInstance:
	var card := CardInstance.new(load("res://data/cards/%s.tres" % resource_name))
	hand.hand.append(card)
	hand._notify_hand_changed()
	return card


func _play(card: CardInstance, point: Vector2 = Vector2(450, 450), choice: Dictionary = {}) -> bool:
	rounds.current_energy = maxi(card.get_cost(), 0)
	var result: bool = runtime.try_play(card, point, false, 0, false, choice)
	check(result, card.definition.card_name + "正式出牌")
	return result


func _recruit(card: CardInstance) -> UnitBase:
	if not hand.hand.has(card):
		hand.draw_pile.erase(card)
		hand.discard_pile.erase(card)
		hand.hand.append(card)
		hand._notify_hand_changed()
	_play(card)
	var unit: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	unit.set_physics_process(false)
	return unit


func _high_card(cost: int) -> CardInstance:
	var definition := CardDefinition.new()
	definition.card_name = "高费触发样本"
	definition.category = CardDefinition.Category.ABILITY
	definition.target = CardDefinition.Target.NONE
	definition.card_cost = cost
	var effect := CardEffect.new()
	effect.kind = CardEffect.Kind.GAIN_ENERGY
	effect.amount = 1
	definition.effects.append(effect)
	var card := CardInstance.new(definition)
	hand.hand.append(card)
	return card


func _dispose() -> void:
	battle.finish_battle(false)
	battle.queue_free()
	await get_tree().process_frame


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


func _run() -> void:
	await _strategy()
	await _comrade()
	await _evolution()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_cards()
	print("STRATEGY_CARDS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _strategy() -> void:
	_create(true)
	var strategies: Array[CardInstance] = []
	for card: CardInstance in hand.hand:
		if card.definition.resource_path.ends_with("master_strategy.tres"):
			strategies.append(card)
	check(RunManager.deck.size() == 12 and strategies.size() == 2, "初始牌组新增两张独立运筹帷幄")
	check(strategies[0] != strategies[1] and hand.hand.size() == 7 and hand.draw_pile.size() == 5, "两张开局先入手，再常规抽五张")
	check(hand.hand[0] in strategies and hand.hand[1] in strategies, "固有牌的入手顺序在常规五张之前")
	var strategy := strategies[0]
	check(strategy.get_cost() == 0 and strategy.definition.rarity == CardDefinition.Rarity.COMMON, "运筹帷幄0费普通")
	check(strategy.get_description().contains("抽2张") and strategy.get_description().contains("固有") and strategy.get_description().contains("消耗"), "卡面说明含抽牌、固有、消耗")
	_play(strategy)
	check(hand.hand.size() == 8 and hand.draw_pile.size() == 3 and hand.exhaust_pile == [strategy], "使用立刻抽二并进入消耗牌堆")
	check(not hand.hand.has(strategy) and not hand.discard_pile.has(strategy), "已使用策略不参与弃牌堆")
	var previous: int = rounds.current_round
	rounds.start_auto_battle()
	await rounds.finish_unit_combat()
	await get_tree().process_frame
	check(rounds.current_round == previous + 1 and hand.hand.has(strategies[1]), "真实回合结束保留未使用的运筹帷幄")
	check(hand.hand.size() == 6 and hand.exhaust_pile == [strategy], "下轮只多保留一张固有牌，不重复发开局牌")
	_play(strategies[1])
	hand.draw_cards(99)
	check(hand.exhaust_pile.size() == 2 and not hand.hand.has(strategy) and not hand.hand.has(strategies[1]), "大量抽牌与洗牌均不会抽回已消耗牌")
	await _dispose()
	_create(true, true)
	check(hand.hand.size() == 7 and hand.exhaust_pile.is_empty() and hand.hand.has(strategy) and hand.hand.has(strategies[1]), "同一局下一场恢复原策略牌并重新优先发入手牌")
	hand.draw_locked = true
	var locked: CardInstance = hand.hand[0]
	var count: int = hand.hand.size()
	check(not runtime.try_play(locked, Vector2(450, 450)) and hand.hand.size() == count and hand.exhaust_pile.is_empty(), "禁抽时出牌失败，不消耗策略")
	battle.finish_battle(false)
	check(hand.hand.is_empty(), "战斗结束回收固有手牌")
	await _dispose()


func _comrade() -> void:
	_create()
	var comrade := _give("comrade")
	check(comrade.get_cost() == 2 and comrade.definition.rarity == CardDefinition.Rarity.RARE, "战友2费稀有")
	_play(comrade)
	check(hand.active_cards.has(comrade) and runtime.plays.comrade_threshold == 6, "战友常驻本场并按6费触发")
	_play(_high_card(5))
	check(not runtime.plays.next_unit_free, "5费不触发战友")
	_play(_high_card(6))
	check(runtime.plays.next_unit_free, "恰好6费触发战友")
	hand.draw_cards(1)
	check(hand.hand.back().is_unit_card() and hand.hand.back().get_cost() == 0, "触发后新抽到的单位牌也立即显示0费")
	var unit_card := CardInstance.new(load("res://data/units/soldier.tres"))
	unit_card.cost_increase = 5
	var peer := CardInstance.new(load("res://data/units/soldier.tres"))
	hand.hand.append_array([unit_card, peer])
	hand._notify_hand_changed()
	check(unit_card.get_cost() == 0 and peer.get_cost() == 0 and unit_card.cost_increase == 5, "待使用单位牌均显示0费且不改已有加费")
	var view := load("res://scenes/cards/unit_card.tscn").instantiate() as UnitCard
	add_child(view)
	view.setup(unit_card)
	check(view.get_node("CostIcon/CostLabel").text == "0", "实际卡面费用显示减免")
	view.queue_free()
	rounds.current_energy = 0
	check(not runtime.try_play(unit_card, Vector2.ZERO) and runtime.plays.next_unit_free and hand.hand.has(unit_card), "无效部署不消耗战友减费")
	_play(_high_card(1))
	check(runtime.plays.next_unit_free, "打出非单位低费牌不消耗减费")
	var unit := _recruit(unit_card)
	check(unit_card.get_cost() == 0 and not runtime.plays.next_unit_free and peer.get_cost() == peer.definition.card_cost, "只消费下一张单位牌，未打出的其它单位恢复费用")
	check(unit.unit_data.attack == unit_card.unit_data.attack and unit_card.definition.card_cost == 1, "减费不改基础资源和单位属性")
	unit.die()
	check(unit_card.get_cost() == 7 and unit_card.cost_increase == 6 and hand.discard_pile.count(unit_card) == 1, "回弃牌恢复原6费再加1，原牌只弃一次")
	unit.unit_died.emit(unit)
	check(unit_card.get_cost() == 7, "重复死亡不重复加费")
	var paid := _recruit(unit_card)
	check(rounds.current_energy == 0 and runtime.plays.next_unit_free, "已涨到7费的单位本身也触发战友")
	var free_peer := _recruit(peer)
	check(not runtime.plays.next_unit_free, "被减为0费的单位不再自触发高费效果")
	check(hand.recall_unit(free_peer) and peer.get_cost() == 0, "收回到手牌尚未进入弃牌堆，继续保留0费")
	free_peer.get_parent().remove_child(free_peer)
	free_peer.queue_free()
	free_peer = _recruit(peer)
	var army := _give("undying_army")
	_play(army)
	free_peer.die()
	check(peer.get_cost() == peer.definition.card_cost + 2, "不灭军势生效时沿用普通单位的加2规则")
	_play(_high_card(7))
	runtime._on_round_ended()
	check(runtime.plays.next_unit_free, "未用的下一单位减免跨回合保留")
	var repeat := _give("comrade")
	rounds.current_energy = 3
	check(not runtime.try_play(repeat, Vector2(450, 450)) and rounds.current_energy == 3 and hand.hand.has(repeat), "战友不重复启用且失败不扣费")
	battle.finish_battle(false)
	check(not runtime.plays.next_unit_free and unit_card.get_cost() == unit_card.definition.card_cost + unit_card.cost_increase, "战斗结束清理减费")
	check(not paid.is_inside_tree(), "原有留存结算仍清理单位")
	await _dispose()


func _evolution() -> void:
	_create()
	var source := _give("evolution")
	check(source.get_cost() == 1 and source.definition.rarity == CardDefinition.Rarity.COMMON, "进化1费普通")
	var only_source_count: int = hand.hand.size()
	rounds.current_energy = 1
	check(not runtime.try_play(source, Vector2(450, 450)) and hand.hand.size() == only_source_count and rounds.current_energy == 1, "没有其它可升级手牌时不吞牌不扣费")
	var target: CardInstance = RunManager.deck[0]
	hand.draw_pile.erase(target)
	hand.hand.append(target)
	hand._notify_hand_changed()
	var ui = battle.card_ui.upgrade_choice
	check(runtime.try_play(source, Vector2(450, 450)) and get_tree().paused and ui.visible, "进化打开手牌选择并暂停战斗")
	check(rounds.current_energy == 1 and hand.hand.has(source) and target.upgrade_count == 0, "选择与预览之前不提前扣费或升级")
	await _click_button(ui.grid.get_child(0))
	check(ui.target == target, "暂停中的选牌按钮响应真实鼠标点击")
	ui.soldier_choice.select_branch("missile")
	ui.attack_input.value = 1
	check(ui.defence_input.value == 1 and target.upgrade_count == 0 and ui.preview.card_instance.upgrade_count == 1, "攻击防御分配联动，预览不改原牌")
	ui.close()
	check(not get_tree().paused and hand.hand.has(source) and rounds.current_energy == 1, "取消恢复战斗且不消耗进化")
	check(not runtime.try_play(source, Vector2(450, 450), false, 0, false, {"card": target, "allocation": Vector2i(1, 0), "soldier_branch": "missile"}), "未分配全部能力点时拒绝升级")
	check(hand.hand.has(source) and rounds.current_energy == 1 and target.upgrade_count == 0, "错误分配没有副作用")
	runtime.try_play(source, Vector2(450, 450))
	ui.choose_card(target)
	ui.soldier_choice.select_branch("missile")
	ui.attack_input.value = 1
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.maintenance/strategy_evolution_choice.png")
	ui.confirm()
	check(not get_tree().paused and not ui.visible and not hand.hand.has(source) and rounds.current_energy == 0, "确认后才扣费并结算进化")
	check(target.upgrade_count == 1 and target.attack_points == 1 and target.defence_points == 1 and not target.can_evolve(), "临时升级生效且不能重复叠加")
	var saved := RunManager.create_save_data()
	check(saved.card_states[0].upgrade_count == 0 and saved.card_states[0].attack_points == 0, "未使用的临时升级不会误写入永久存档")
	var unit := _recruit(target)
	check(unit.unit_data.attack == target.unit_data.attack + 1 and unit.unit_data.defence == target.unit_data.defence + 1, "进化后的单位按分配属性出场")
	check(unit.unit_data.card_upgrade_level == 1 and target.upgrade_count == 0 and target.attack_points == 0 and target.defence_points == 0, "场上单位保留本次升级，原牌使用后恢复")
	unit.die()
	check(target.get_cost() == target.definition.card_cost + 1 and target.upgrade_count == 0, "进化单位退场正常加费，原升级已撤销")
	var stronger_data := target.unit_data.duplicate() as UnitData
	stronger_data.max_upgrade_count = 3
	var trained := CardInstance.new(stronger_data)
	check(trained.train(2, 0), "准备已有永久训练的单位牌")
	RunManager.deck.append(trained)
	hand.hand.append(trained)
	var second := _give("evolution")
	_play(second, Vector2(450, 450), {"card": trained, "allocation": Vector2i(0, 2)})
	check(trained.upgrade_count == 2 and trained.attack_points == 2 and trained.defence_points == 2, "进化叠加在已有永久训练之后")
	hand.discard_unused_card()
	check(hand.discard_pile.has(trained) and trained.upgrade_count == 2, "未使用的进化目标弃置后仍保留临时升级")
	hand.discard_pile.erase(trained)
	hand.draw_pile.append(trained)
	hand.draw_cards(1)
	check(hand.hand.has(trained) and trained.upgrade_count == 2, "重新抽到目标时进化继续生效")
	var permanent := RunManager.create_save_data()
	check(permanent.card_states.back().upgrade_count == 1 and permanent.card_states.back().attack_points == 2 and permanent.card_states.back().defence_points == 0, "存档只保留原来的永久升级")
	# 非单位牌复用其真实升级增量，施放后还原原配方，已施加效果保留升级数值。
	var recruit := _recruit(RunManager.deck[1])
	var definition := load("res://data/cards/power_enhance.tres").duplicate(true) as CardDefinition
	definition.rarity = CardDefinition.Rarity.RARE
	definition.effects[0].upgrade_amount = 3
	var enhance := CardInstance.new(definition)
	hand.hand.append(enhance)
	var third := _give("evolution")
	_play(third, Vector2(450, 450), {"card": enhance})
	check(enhance.definition.effects[0].amount == 6 and definition.effects[0].amount == 3, "强化牌升级快照不污染共享资源")
	var attack: int = recruit.unit_data.attack
	_play(enhance, recruit.global_position)
	check(recruit.unit_data.attack == attack + 6 and enhance.definition.effects[0].amount == 3 and enhance.upgrade_count == 0, "升级效果按6点结算，原牌恢复3点")
	check(enhance.definition.rarity == CardDefinition.Rarity.RARE, "恢复升级前原品质，不把稀有牌改为普通品质")
	await _dispose()
	check(trained.upgrade_count == 1 and trained.attack_points == 2 and trained.defence_points == 0, "战斗结束撤销未使用进化但保留原永久训练")


func _capture_cards() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 440)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(960, 440)
	background.color = Color("0b1c2b")
	viewport.add_child(background)
	var names := ["comrade", "evolution", "master_strategy"]
	var views: Array[UnitCard] = []
	for i in names.size():
		var view := load("res://scenes/cards/unit_card.tscn").instantiate() as UnitCard
		view.is_playable = false
		viewport.add_child(view)
		view.position = Vector2(175 + i * 320, 220)
		view.setup(CardInstance.new(load("res://data/cards/%s.tres" % names[i])))
		views.append(view)
	await get_tree().process_frame
	for view in views:
		var label := view.get_node("CardDiscription") as RichTextLabel
		check(label.get_content_height() <= label.size.y, view.card_instance.definition.card_name + "文案完整显示")
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://.maintenance/strategy_cards_preview.png")
	viewport.queue_free()
