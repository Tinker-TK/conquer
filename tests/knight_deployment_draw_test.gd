# 使用真实出牌、训练、牌堆和存档入口验证骑士的即时上场抽牌。
extends Node

var battle: Node2D
var hand: Node2D
var runtime: Node2D
var rounds: BattleRoundManager
var checks := 0
var failures: Array[String] = []
var draw_events := 0
var expected_deployment: CardInstance


func _ready() -> void:
	get_tree().create_timer(25.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _create_battle() -> void:
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	hand = battle.hand_manager
	runtime = battle.card_runtime
	rounds = battle.battle_round_manager
	runtime.set_physics_process(false)
	hand.card_motion_requested.connect(_on_motion)
	for unit: UnitBase in runtime.living_units():
		unit.set_physics_process(false)


func _on_motion(_card: CardInstance, motion: StringName, _position: Vector2) -> void:
	if motion == &"draw":
		draw_events += 1
		if expected_deployment != null:
			check(hand.board_cards.values().has(expected_deployment) and not hand.resolving.has(expected_deployment), "抽牌前原骑士牌已绑定场上单位")


func _give(card: CardInstance) -> void:
	hand.draw_pile.erase(card)
	hand.discard_pile.erase(card)
	if not hand.hand.has(card):
		hand.hand.append(card)


func _supply(draw_count: int, discard_count: int = 0) -> void:
	hand.draw_pile.clear()
	hand.discard_pile.clear()
	for i in draw_count:
		hand.draw_pile.append(CardInstance.new(load("res://data/units/soldier.tres")))
	for i in discard_count:
		hand.discard_pile.append(CardInstance.new(load("res://data/units/soldier.tres")))


func _deploy(card: CardInstance, expected_draws: int, from_draw: bool = false) -> UnitBase:
	if not from_draw:
		_give(card)
		rounds.current_energy = maxi(rounds.current_energy, card.get_cost())
	var before := draw_events
	var hand_before: int = hand.hand.size()
	expected_deployment = card
	check(runtime.try_play(card, Vector2(450, 450), from_draw, 1 if from_draw else 0, from_draw), "通过正式征召入口部署骑士")
	expected_deployment = null
	var unit := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	unit.set_physics_process(false)
	check(hand.board_cards.get(unit.get_instance_id()) == card, "场上骑士绑定自己的原牌")
	check(draw_events - before == expected_draws, "成功上场立刻抽入%d张牌且发送原抽牌动画信号" % expected_draws)
	check(hand.hand.size() == hand_before + expected_draws - (0 if from_draw else 1), "真实手牌数量立即变化")
	check(not hand.hand.has(card) and not hand.draw_pile.has(card) and not hand.discard_pile.has(card), "上场骑士牌不会被自己的抽牌效果抽回")
	return unit


func _play_unit_effect(kind: CardEffect.Kind, target: UnitBase) -> void:
	var effect := CardEffect.new()
	effect.kind = kind
	var definition := CardDefinition.new()
	definition.category = CardDefinition.Category.ENHANCEMENT
	definition.target = CardDefinition.Target.ALLY
	definition.effects.assign([effect])
	var card := CardInstance.new(definition)
	_give(card)
	var before := draw_events
	rounds.current_energy = 99
	check(runtime.try_play(card, target.global_position), "使用原有复制/收回效果入口")
	check(draw_events == before, "复制或收回骑士不触发上场抽牌")


func _run() -> void:
	var source := load("res://data/units/knight.tres") as UnitData
	var start := RunStartData.new()
	start.cards.assign([source, source])
	start.starting_relics.clear()
	start.starting_potions.clear()
	RunManager.start_new_run(start)
	var normal: CardInstance = RunManager.deck[0]
	var trained: CardInstance = RunManager.deck[1]
	check(trained.train(source.upgrade_ability_points, 0), "通过原训练入口强化骑士卡")
	check(normal.get_deployment_draw_count() == 1 and trained.get_deployment_draw_count() == 3, "同名骑士卡按自身强化次数抽1张或3张")
	check(source.card_upgrade_level == 0 and normal.upgrade_count == 0, "训练不改变共享资源或未强化原牌")
	check(normal.upgrade_summary().contains("立刻抽1张牌") and trained.upgrade_summary().contains("立刻抽3张牌"), "卡牌强化摘要显示当前抽牌张数")
	var view := load("res://scenes/cards/unit_card.tscn").instantiate() as UnitCard
	add_child(view)
	view.setup(normal)
	check(view.get_node("CardDiscription").text.contains("上场时，抽1张牌。"), "未强化骑士卡面只显示当前抽1张的说明")
	view.setup(trained)
	check(view.get_node("CardDiscription").text.contains("上场时，抽3张牌。") and view.tooltip_text.contains("上场时，抽3张牌。"), "强化骑士卡面与悬停说明同步显示当前抽3张的效果")
	check(not view.tooltip_text.contains("抽1张牌") and not view.tooltip_text.contains("强化后改为"), "强化卡牌说明不保留未强化或将来时文案")
	view.queue_free()
	var twice_source := source.duplicate() as UnitData
	twice_source.max_upgrade_count = 2
	var twice := CardInstance.new(twice_source)
	check(twice.train(source.upgrade_ability_points, 0) and twice.train(source.upgrade_ability_points, 0) and twice.get_deployment_draw_count() == 3, "多次强化仍抽3张，不继续累加")
	var enemy_source := source.duplicate() as UnitData
	enemy_source.unit_team = "team_b"
	check(enemy_source.get_deployment_draw_count() == 0, "敌方骑士不触发己方抽牌")
	var unrelated := CardDefinition.new()
	unrelated.summon_unit = source
	check(CardInstance.new(unrelated).get_deployment_draw_count() == 0, "非征召牌不触发骑士上场效果")
	_create_battle()
	_supply(4)
	_give(normal)
	var before := draw_events
	rounds.current_energy = 0
	check(not runtime.try_play(normal, Vector2(450, 450)) and hand.hand.has(normal), "能量不足不能部署或吞牌")
	rounds.current_energy = 99
	check(not runtime.try_play(normal, Vector2(1600, 800)) and hand.hand.has(normal), "落点不合法不能部署或吞牌")
	runtime.update_cast_preview(normal, Vector2(450, 450))
	check(draw_events == before and battle.get_node("Entities/TeamA").get_child_count() == 0, "失败出牌和预览不抽牌、不生成单位")
	var normal_unit := _deploy(normal, 1)
	before = draw_events
	var energy_before: int = rounds.current_energy
	check(not runtime.try_play(normal, Vector2(450, 450)) and draw_events == before and rounds.current_energy == energy_before, "同一次部署不会因重复调用再次抽牌")
	await get_tree().process_frame
	await get_tree().process_frame
	check(draw_events == before, "单位入树与后续帧不重复触发抽牌")
	_supply(3)
	var trained_unit := _deploy(trained, 3)
	trained_unit.global_position = Vector2(650, 550)
	check(trained_unit.unit_data.card_upgrade_level == 1 and normal_unit.unit_data.card_upgrade_level == 0, "出场单位保留各自强化等级")
	_play_unit_effect(CardEffect.Kind.COPY_ALLY, trained_unit)
	var copied := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	copied.set_physics_process(false)
	check(copied.unit_data.unit_english_name == "knight" and not hand.board_cards.has(copied.get_instance_id()), "骑士复制品没有原征召牌")
	_play_unit_effect(CardEffect.Kind.RECALL_ALLY, trained_unit)
	check(hand.hand.has(trained), "收回返回同一张强化骑士牌")
	_supply(3)
	trained_unit = _deploy(trained, 3)
	before = draw_events
	var unbound := load("res://scenes/units/knight.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamA").add_child(unbound)
	unbound.set_physics_process(false)
	check(draw_events == before, "直接生成骑士单位不抽牌")
	var soldier := CardInstance.new(load("res://data/units/soldier.tres"))
	_supply(2)
	_deploy(soldier, 0)
	check(soldier.get_deployment_draw_count() == 0, "其他兵种部署不获得骑士效果")
	rounds.start_auto_battle()
	check(Global.game_phase == Global.GamePhase.AUTO_BATTLE, "进入真实交锋阶段")
	_supply(2)
	_deploy(CardInstance.new(source), 1)
	_supply(3)
	var free_card := CardInstance.new(source)
	check(free_card.train(source.upgrade_ability_points, 0), "强化免费部署测试牌")
	hand.draw_pile.append(free_card)
	rounds.current_energy = 0
	_deploy(free_card, 3, true)
	check(rounds.current_energy == 0, "抽牌堆免费部署骑士不扣能量")
	_supply(2)
	hand.draw_locked = true
	_deploy(CardInstance.new(source), 0)
	check(hand.draw_pile.size() == 2, "禁抽时骑士仍可上场，牌堆保持不变")
	hand.draw_locked = false
	_supply(1)
	_deploy(twice, 1)
	check(hand.draw_pile.is_empty(), "强化骑士牌不足时只抽现有牌")
	_supply(0)
	_deploy(CardInstance.new(source), 0)
	_supply(0, 2)
	var reshuffle_card := CardInstance.new(source)
	check(reshuffle_card.train(source.upgrade_ability_points, 0), "强化洗牌测试牌")
	_deploy(reshuffle_card, 2)
	check(hand.discard_pile.is_empty() and hand.draw_pile.is_empty(), "上场抽牌沿用原弃牌堆洗回规则")
	check(RunManager.add_relic(load("res://data/relics/draw_engine.tres")), "启用原抽牌遗物")
	RunManager.relic_draw_counts[&"draw_engine"] = 9
	_supply(2)
	rounds.current_energy = source.card_cost
	_deploy(CardInstance.new(source), 1)
	check(RunManager.relic_draw_counts[&"draw_engine"] == 0 and rounds.current_energy == 1, "上场实际抽牌计入遗物并返还能量")
	battle.queue_free()
	await get_tree().process_frame
	check(RunManager.save_run().is_empty(), "保存骑士卡牌强化记录")
	RunManager.start_new_run(start)
	check(RunManager.deck[1].get_deployment_draw_count() == 1, "新局骑士恢复未强化抽1张")
	check(RunManager.load_saved_run().is_empty(), "恢复骑士卡牌存档")
	check(RunManager.deck[0].get_deployment_draw_count() == 1 and RunManager.deck[1].get_deployment_draw_count() == 3, "存档恢复后保留独立抽牌等级")
	check(RunManager.deck[1].get_description().contains("上场时，抽3张牌。") and not RunManager.deck[1].get_description().contains("抽1张牌"), "存档恢复后说明仍与当前强化效果一致")
	_create_battle()
	_supply(3)
	_deploy(RunManager.deck[1], 3)
	battle.queue_free()
	await get_tree().process_frame
	print("KNIGHT_DEPLOYMENT_DRAW_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
