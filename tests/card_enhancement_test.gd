# 27张正式资源的篝火强化、独立存档、临时进化及特殊规则实战回归。
extends Node

# 文件、基础费用、品质、基础主数值、强化主数值、强化费用。
const CASES := [
	["power_enhance", 1, 0, [3.0], [5.0], 1],
	["defend", 1, 0, [2.0], [3.0], 1],
	["heal", 1, 0, [30.0], [45.0], 1],
	["poison_on_hit", 1, 0, [2.0], [3.0], 1],
	["death_explosion", 1, 0, [30.0], [45.0], 1],
	["copy_ally", 2, 0, [], [], 1],
	["frenzy", 2, 1, [20.0], [30.0], 2],
	["judger", 2, 1, [2.0], [3.0], 2],
	["vulnerability", 1, 0, [20.0], [30.0], 1],
	["weakness", 1, 0, [2.0], [3.0], 1],
	["intimidation", 1, 0, [2.0], [3.0], 1],
	["paralysis", 1, 0, [0.75], [1.25], 1],
	["convert_enemy", 2, 0, [], [], 2],
	["draw_four", 0, 0, [3.0], [4.0], 0],
	["draw_hp", 0, 0, [4.0, 3.0], [3.0, 4.0], 0],
	["master_strategy", 0, 0, [2.0], [3.0], 0],
	["random_play", 1, 0, [2.0], [3.0], 1],
	["recall_ally", 1, 0, [], [], 0],
	["retreat_draw", 1, 0, [1.0], [2.0], 1],
	["fire_zone", 2, 0, [5.0], [8.0], 2],
	["mud_zone", 1, 0, [100.0], [100.0], 1],
	["death_attack", 1, 0, [1.0], [2.0], 1],
	["undying_army", 4, 1, [2.0], [1.0], 4],
	["diverse_army", 2, 1, [2.0], [3.0], 2],
	["keep_distance", 2, 1, [130.0], [145.0], 2],
	["comrade", 2, 1, [6.0], [5.0], 2],
	["evolution", 1, 0, [], [], 0],
]
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


func _signature(card: CardInstance) -> Array:
	var result: Array = [card.get_cost(), card.upgrade_count, card.get_description(),
		card.definition.rarity, card.definition.after_use, card.definition.retain_in_hand, card.definition.starts_in_hand]
	for effect: CardEffect in card.definition.effects:
		result.append([effect.amount, effect.lifetime, effect.lasting_rounds, effect.radius,
			effect.interval, effect.can_convert_elite])
	return result


func _check_values(card: CardInstance, row: Array, upgraded: bool) -> void:
	check(card.get_cost() == row[5 if upgraded else 1] and card.definition.rarity == row[2], row[0] + "费用及品质")
	var values: Array = row[4 if upgraded else 3]
	for i in values.size():
		check(is_equal_approx(card.definition.effects[i].amount, values[i]), "%s效果%d" % [row[0], i])
	if row[0] == "mud_zone":
		check(card.definition.effects[0].lasting_rounds == (3 if upgraded else 2), "泥潭期限")
	if row[0] == "convert_enemy":
		check(card.definition.effects[0].can_convert_elite == upgraded, "策反精英开关")
	if row[0] in ["copy_ally", "draw_four", "master_strategy"]:
		check(card.definition.after_use == CardDefinition.AfterUse.EXHAUST, row[0] + "保留消耗规则")
	if row[0] == "master_strategy":
		check(card.definition.retain_in_hand and card.definition.starts_in_hand, "运筹帷幄保留固有及开局规则")


func _catalog_and_save() -> void:
	var start := RunStartData.new()
	for row: Array in CASES:
		start.cards.append(load("res://data/cards/%s.tres" % row[0]))
	RunManager.start_new_run(start)
	var expected: Array = []
	var event: Dictionary = preload("res://scripts/map/fixed_map_config.gd").default_event("campfire")
	for i in CASES.size():
		var card: CardInstance = RunManager.deck[i]
		var row: Array = CASES[i]
		_check_values(card, row, false)
		check(card.get_upgrade_limit() == 1, row[0] + "限强化一次")
		var peer := CardInstance.new(start.cards[i])
		var original := _signature(peer)
		var session = preload("res://scripts/events/event_session.gd").new()
		session.configure(event, RunManager)
		var offer: Dictionary = session.choose(2)
		check(offer.candidates[0] == card, row[0] + "可由篝火选中")
		check(not session.claim([0]).has("error"), row[0] + "正式强化成功")
		_check_values(card, row, true)
		check(_signature(peer) == original, row[0] + "同名牌及资源隔离")
		var signature := _signature(card)
		check(not card.enhance() and _signature(card) == signature, row[0] + "达到上限后无副作用")
		check(not card.upgrade_summary().contains("效果不变"), row[0] + "强化摘要反映实际效果")
		expected.append(signature)
		var temporary := CardInstance.new(start.cards[i])
		check(temporary.temporary_upgrade(Vector2i.ZERO), row[0] + "进化复用强化配置")
		check(temporary.persistent_definition() == peer.definition and temporary.persistent_upgrade_state().upgrade_count == 0, row[0] + "临时升级不写入永久状态")
		temporary.restore_evolution()
		check(_signature(temporary) == original, row[0] + "进化完整还原")
	check(RunManager.save_run().is_empty(), "保存全部强化牌")
	check(RunManager.load_saved_run().is_empty(), "读取全部强化牌")
	for i in CASES.size():
		check(_signature(RunManager.deck[i]) == expected[i], CASES[i][0] + "费用、效果及规则读档一致")
	RunManager.start_new_run(start)
	for i in CASES.size():
		_check_values(RunManager.deck[i], CASES[i], false)


func _create() -> void:
	var start := RunStartData.new()
	for i in 15:
		start.cards.append(load("res://data/units/soldier.tres"))
	RunManager.start_new_run(start)
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	config.enemy_max_hp = 1000
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	hand = battle.hand_manager
	runtime = battle.card_runtime
	rounds = battle.battle_round_manager
	runtime.set_physics_process(false)
	check(await preload("res://tests/battle_test_navigation.gd").install(battle), "强化测试导航同步")


func _give(name: String, upgraded: bool = true) -> CardInstance:
	var card := CardInstance.new(load("res://data/cards/%s.tres" % name))
	if upgraded:
		check(card.enhance(), name + "准备强化牌")
	hand.hand.append(card)
	return card


func _play(card: CardInstance, point: Vector2 = Vector2(450, 450), choice: Dictionary = {}) -> void:
	rounds.current_energy = card.get_cost()
	var reasons: Array[String] = []
	var on_feedback := func(reason: String): reasons.append(reason)
	runtime.feedback.connect(on_feedback)
	var played: bool = runtime.try_play(card, point, false, 0, false, choice)
	runtime.feedback.disconnect(on_feedback)
	check(played, card.definition.card_name + "正式出牌：" + "；".join(reasons))
	runtime.tactics.set_physics_process(false)


func _recruit(point: Vector2 = Vector2(450, 450)) -> UnitBase:
	var card: CardInstance = hand.draw_pile.pop_back()
	hand.hand.append(card)
	_play(card, point)
	var unit: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	unit.set_physics_process(false)
	return unit


func _enemy(point: Vector2, rank: UnitData.MonsterRank = UnitData.MonsterRank.NORMAL) -> UnitBase:
	var unit := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	unit.unit_data = unit.unit_data.duplicate()
	unit.unit_data.max_hp = 1000
	unit.unit_data.attack = 20
	unit.unit_data.defence = 10
	unit.unit_data.monster_rank = rank
	var parent: Node2D = battle.get_node("Entities/TeamB")
	unit.position = parent.to_local(point)
	parent.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _dispose() -> void:
	battle.finish_battle(false)
	battle.queue_free()
	await get_tree().process_frame


func _stats_and_tactics() -> void:
	await _create()
	var ally := _recruit()
	var enemy := _enemy(Vector2(1050, 450))
	ally.unit_data.attack = 20
	ally.unit_data.defence = 10
	ally.unit_data.max_hp = 1000
	ally.current_health = 100
	_play(_give("power_enhance"), ally.global_position)
	_play(_give("defend"), ally.global_position)
	_play(_give("heal"), ally.global_position)
	check(ally.unit_data.attack == 25 and ally.unit_data.defence == 13 and ally.current_health == 550, "强化攻防与45%治疗实际结算")
	_play(_give("weakness"), enemy.global_position)
	_play(_give("intimidation"), enemy.global_position)
	_play(_give("vulnerability"), enemy.global_position)
	check(enemy.unit_data.attack == 17 and enemy.unit_data.defence == 7, "强化减攻及减防各3")
	check(runtime.tactics.attack_damage(enemy, ally, 25) == int(18 * 1.3), "强化易伤30%")
	_play(_give("keep_distance"))
	check(runtime.tactics.attack_damage(enemy, ally, 100) == int((145 - 7) * 1.3), "600像素强化远端145%与易伤叠算")
	_play(_give("judger"), ally.global_position)
	_play(_give("poison_on_hit"), ally.global_position)
	_play(_give("frenzy"), ally.global_position)
	rounds.start_auto_battle()
	ally.current_health = 100
	var hp := enemy.current_health
	load("res://data/skills/normal_attack.tres").execute(ally, enemy)
	check(runtime.states[enemy.get_instance_id()].poison == 3, "强化命中附3层毒")
	check(ally.current_health == 100 + int((hp - enemy.current_health) * 0.3), "强化狂化按实际伤害30%吸血")
	var attack := ally.unit_data.attack
	enemy.take_effect_damage(2000, ally)
	check(ally.unit_data.attack == roundi((25 + 3) * 1.5) and ally.unit_data.attack > attack, "强化审判者击杀+3进入狂化倍率")
	await _dispose()


func _special_rules() -> void:
	await _create()
	var ally := _recruit()
	var elite := _enemy(Vector2(900, 450), UnitData.MonsterRank.ELITE)
	var conversion := _give("convert_enemy", false)
	rounds.current_energy = 2
	check(not runtime.try_play(conversion, elite.global_position) and hand.hand.has(conversion) and rounds.current_energy == 2, "基础策反拒绝精英且保留费用")
	check(conversion.enhance(), "手中的策反强化")
	for rank in [UnitData.MonsterRank.BOSS, UnitData.MonsterRank.LEGENDARY]:
		elite.unit_data.monster_rank = rank
		check(not runtime.try_play(conversion, elite.global_position) and rounds.current_energy == 2, "强化策反拒绝首领及传说")
	elite.unit_data.monster_rank = UnitData.MonsterRank.ELITE
	_play(conversion, elite.global_position)
	check(elite.unit_data.unit_team == "team_a" and elite.is_in_group("converted_enemy"), "强化策反精英换队")
	var mirror := _give("copy_ally")
	_play(mirror, ally.global_position)
	check(rounds.current_energy == 0 and hand.exhaust_pile.has(mirror), "强化镜像付1费且消耗")
	var recall := _give("recall_ally")
	var original: CardInstance = hand.board_cards[ally.get_instance_id()]
	_play(recall, ally.global_position)
	check(hand.hand.has(original) and rounds.current_energy == 0, "强化回撤0费返回原牌")
	var recruit := _recruit(Vector2(450, 650))
	var recruit_card: CardInstance = hand.board_cards[recruit.get_instance_id()]
	_play(_give("undying_army", false))
	check(runtime.unit_discard_cost_increase == 2, "基础不灭军势阵亡加2")
	_play(_give("undying_army"))
	_play(_give("undying_army", false))
	check(runtime.unit_discard_cost_increase == 1 and runtime.should_retain_unit(recruit), "强化不灭军势加1且普通版不会覆盖")
	recruit.die()
	check(recruit_card.cost_increase == 1, "强化不灭军势真实阵亡仅加1")
	var mud := _give("mud_zone")
	_play(mud)
	for left in [2, 1]:
		runtime._on_round_ended()
		check(runtime.zones.size() == 1 and runtime.zones[0].rounds_left == left, "强化泥潭跨回合持续")
	runtime._on_round_ended()
	check(runtime.zones.is_empty(), "强化泥潭第3回合后移除")
	var comrade := _give("comrade")
	_play(comrade)
	_play(_give("keep_distance"))
	check(not runtime.plays.next_unit_free, "强化战友不被低费触发")
	var threshold_card := _give("undying_army")
	threshold_card.cost_increase = 1 # 新基础4费，构造恰好5费验证战友阈值。
	_play(threshold_card)
	check(runtime.plays.next_unit_free and runtime.plays.comrade_threshold == 5, "强化战友恰好5费触发")
	var evolution := _give("evolution")
	var target := _give("recall_ally", false)
	_play(evolution, Vector2(450, 450), {"card": target})
	check(rounds.current_energy == 0 and target.get_cost() == 0 and target.upgrade_count == 1, "强化进化0费临时降低目标费用")
	# 策反单位没有原征召牌，回撤验证应失败；临时升级应继续保留。
	check(not runtime.try_play(target, elite.global_position) and hand.hand.has(target) and target.get_cost() == 0, "失败出牌保留临时强化")
	var recalled := _recruit(Vector2(450, 850))
	_play(target, recalled.global_position)
	check(target.get_cost() == 1 and target.upgrade_count == 0, "临时降费以0费结算后恢复原费用")
	var unplayed := _give("recall_ally", false)
	check(unplayed.temporary_upgrade(Vector2i.ZERO), "准备未用的临时降费")
	await _dispose()
	check(unplayed.get_cost() == 1 and unplayed.upgrade_count == 0, "战斗结束恢复临时降费")


func _draw_and_zones() -> void:
	await _create()
	var hp := RunManager.hp
	_play(_give("draw_hp"))
	check(RunManager.hp == hp - 3 and rounds.current_energy == 4, "强化血契支付3生命获得4能量")
	var count: int = hand.hand.size()
	_play(_give("master_strategy"))
	check(hand.hand.size() == count + 3, "强化运筹帷幄抽3")
	count = hand.hand.size()
	_play(_give("draw_four"))
	check(hand.hand.size() == count + 4 and hand.draw_locked, "强化孤注一掷抽4并禁抽")
	hand.draw_locked = false
	var ally := _recruit()
	_play(_give("retreat_draw"))
	runtime._on_round_ended()
	check(hand.pending_bonus_draw == 2, "强化鸣金收兵每名存活多抽2")
	var enemy := _enemy(Vector2(550, 450))
	_play(_give("fire_zone"), enemy.global_position)
	rounds.start_auto_battle()
	var enemy_hp := enemy.current_health
	runtime._physics_process(1.0)
	check(enemy.current_health == enemy_hp - 8, "强化火区每秒8点伤害")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	_play(_give("death_explosion"), ally.global_position)
	enemy_hp = enemy.current_health
	ally.die()
	check(enemy.current_health == enemy_hp - 45, "强化同生共死爆炸45点")
	await _dispose()


func _random_auras_and_paralysis() -> void:
	await _create()
	_play(_give("random_play"))
	check(hand.board_cards.size() == 3 and rounds.current_energy == 0, "强化战术涌现真实随机打出3张单位牌")
	var allies: Array[Node] = battle.get_node("Entities/TeamA").get_children()
	var attacks: Array[int] = []
	for i in allies.size():
		var unit := allies[i] as UnitBase
		unit.set_physics_process(false)
		unit.unit_data.unit_type = i as Global.UnitType
		attacks.append(unit.unit_data.attack)
	_play(_give("diverse_army"))
	check(allies[0].unit_data.attack == attacks[0] + 3, "强化合理搭配3兵种攻击+3")
	_play(_give("death_attack"))
	allies[2].die()
	check(allies[0].unit_data.attack == attacks[0] + 2, "失去3兵种加成后强化悼亡战意每阵亡+2")
	var enemy := _enemy(Vector2(1050, 450))
	_play(_give("paralysis"), enemy.global_position)
	rounds.start_auto_battle()
	runtime.tactics._physics_process(3.01)
	check(enemy.is_stunned, "强化麻痹每3秒触发")
	runtime.tactics._physics_process(0.6)
	enemy.status_runtime._physics_process(0.6)
	check(enemy.is_stunned, "强化麻痹0.6秒仍眩晕")
	runtime.tactics._physics_process(0.66)
	enemy.status_runtime._physics_process(0.66)
	check(not enemy.is_stunned, "强化麻痹1.25秒后恢复")
	await _dispose()


func _run() -> void:
	_catalog_and_save()
	await _stats_and_tactics()
	await _special_rules()
	await _draw_and_zones()
	await _random_auras_and_paralysis()
	print("CARD_ENHANCEMENT_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
