# 这玩意儿是干嘛的（核心逻辑）：用真实示例资源验证三类卡牌与持续效果。
# 数据是咋流动的（数据流向）：示例牌 → 统一出牌入口 → 检查数值、牌堆、即时强化和跨回合行为。
# 为啥这么写（选型决策）：测试不依赖鼠标位置；逻辑正确后再添加正式动画。
# 性能咋样（复杂度）：只手动运行，游戏不会加载这个测试。
extends Node

@onready var root: Window = get_tree().root

var battle
var runtime
var hand
var rounds
var examples: Resource
var global


# 作用：Godot 初始化测试后延迟执行；没有参数，没有返回值。
func _ready() -> void:
	_run.call_deferred()


# 作用：把一张示例牌放进手牌；index 为示例序号，返回具体牌。
func _give(index: int) -> CardInstance:
	var card := CardInstance.new(examples.cards[index])
	hand.hand.append(card)
	return card


# 作用：使用示例牌；index 为示例序号、point 为落点，返回已使用的牌。
func _play(index: int, point: Vector2 = Vector2(700, 500)) -> CardInstance:
	rounds.current_energy = 99
	var card := _give(index)
	assert(runtime.try_play(card, point), "示例牌失败: %s" % card.definition.card_name)
	for unit in runtime.living_units():
		unit.set_physics_process(false)
	return card


# 作用：使用旧士兵资源召唤，验证向后兼容；point 是落点，返回新单位。
func _recruit(point: Vector2) -> UnitBase:
	rounds.current_energy = 99
	var card := CardInstance.new(load("res://data/units/soldier.tres"))
	hand.hand.append(card)
	assert(runtime.try_play(card, point))
	var unit: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	unit.set_physics_process(false)
	assert(hand.board_cards[unit.get_instance_id()] == card)
	assert(not hand.discard_pile.has(card))
	return unit


# 作用：覆盖全部内置效果与失败保护；没有参数，没有返回值。
func _run() -> void:
	global = root.get_node("Global")
	# 示例回归隔离策划开局遗物，避免抽牌赠能量改变固定能量断言。
	var start_data := load("res://data/run/run_start_data.tres").duplicate(true) as RunStartData
	start_data.starting_relics.clear()
	start_data.starting_potions.clear()
	RunManager.start_new_run(start_data)
	examples = _build_test_examples()
	assert(examples.cards.size() == 14)
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	root.add_child(battle)
	get_tree().current_scene = battle
	runtime = battle.card_runtime
	hand = battle.hand_manager
	rounds = battle.battle_round_manager
	runtime.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	# 可单独运行跨回合回归，不受手牌 UI 尺寸调整影响。
	if "--navigation-deploy-regression" in OS.get_cmdline_user_args():
		_test_navigation_deployment()
		battle.battle_finished = true
		battle.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	if "--energy-regression" in OS.get_cmdline_user_args():
		_test_energy_overflow()
		battle.battle_finished = true
		battle.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	if "--random-draw-regression" in OS.get_cmdline_user_args():
		_test_random_draw()
		battle.battle_finished = true
		battle.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	if "--level-regression" in OS.get_cmdline_user_args():
		await _test_level_template()
		get_tree().quit()
		return
	if "--zone-regression" in OS.get_cmdline_user_args():
		await _test_zone_lifetimes()
		battle.battle_finished = true
		battle.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	if "--buff-regression" in OS.get_cmdline_user_args():
		await _test_buff_lifetimes()
		battle.battle_finished = true
		battle.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	if "--inspector-regression" in OS.get_cmdline_user_args():
		await _test_unit_inspector()
		battle.battle_finished = true
		battle.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	if "--new-unit-regression" in OS.get_cmdline_user_args():
		_test_new_unit_enhancement()
		battle.battle_finished = true
		battle.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	if "--round-regression" in OS.get_cmdline_user_args():
		await _test_enhanced_unit_next_round()
		battle.battle_finished = true
		battle.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	var ally := _recruit(Vector2(450, 450))
	var other := _recruit(Vector2(510, 450))
	var enemy: UnitBase = battle.get_node("Entities/TeamB").get_child(0)
	enemy.global_position = Vector2(560, 450)
	enemy.current_health = 1000
	for unit in runtime.living_units():
		unit.set_physics_process(false)

	# 非法目标不吞牌，不扣能量；同一兵种的两个单位属性必须隔离。
	var invalid := _give(0)
	var energy: int = rounds.current_energy
	# 预览只能改颜色，目标切换、离开、阶段变化和拖放取消都必须清理。
	var unchanged_attack: int = ally.unit_data.attack
	ally.is_selected = true
	runtime.update_cast_preview(invalid, ally.global_position)
	assert(ally.cast_preview_highlight and runtime.preview_target == ally)
	assert(ally.get_node("AnimatedSprite2D").modulate == Color(0.35, 1.0, 0.45))
	assert(rounds.current_energy == energy and ally.unit_data.attack == unchanged_attack)
	assert(hand.hand.has(invalid))
	ally.is_selected = false
	assert(ally.get_node("AnimatedSprite2D").modulate == Color(0.35, 1.0, 0.45))
	ally.is_selected = true
	runtime.update_cast_preview(invalid, other.global_position)
	assert(not ally.cast_preview_highlight and other.cast_preview_highlight)
	assert(ally.get_node("AnimatedSprite2D").modulate == Color(1, 0.8, 0.3))
	runtime.update_cast_preview(invalid, Vector2(20, 20))
	assert(not other.cast_preview_highlight)
	rounds.current_energy = 0
	runtime.update_cast_preview(invalid, ally.global_position)
	assert(not ally.cast_preview_highlight)
	rounds.current_energy = energy
	runtime.update_cast_preview(invalid, ally.global_position)
	runtime.notification(Node.NOTIFICATION_DRAG_END)
	assert(not ally.cast_preview_highlight)
	runtime.update_cast_preview(invalid, ally.global_position)
	global.game_phase = global.GamePhase.AUTO_BATTLE
	assert(runtime.preview_target == null and not ally.cast_preview_highlight)
	rounds.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	global.game_phase = global.GamePhase.CARD_PLAY
	# 实际调用 Godot 拖放与鼠标事件，验证接收区的每帧接线，而不只测辅助方法。
	var source := Control.new()
	source.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle.card_ui.add_child(source)
	source.force_drag({"kind": &"unit_card", "card_instance": invalid, "source_card": source}, null)
	var motion := InputEventMouseMotion.new()
	motion.position = ally.get_global_transform_with_canvas().origin
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	assert(get_viewport().gui_is_dragging())
	assert(runtime.preview_target == ally)
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(20, 350)
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(runtime.preview_target == null)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	get_viewport().push_input(release, true)
	await get_tree().process_frame
	assert(not get_viewport().gui_is_dragging())
	assert(hand.hand.has(invalid) and ally.unit_data.attack == unchanged_attack)
	# 用接收区落点入口施放防御牌，验证高亮对象与施放对象一致。
	var gui_card := _give(2)
	var before_defence: int = ally.unit_data.defence
	source.force_drag({"kind": &"unit_card", "card_instance": gui_card, "source_card": source}, null)
	motion = InputEventMouseMotion.new()
	motion.position = ally.get_global_transform_with_canvas().origin
	get_viewport().push_input(motion, true)
	await get_tree().create_timer(0.1).timeout
	assert(runtime.preview_target == ally)
	var receiver = battle.card_ui.get_node("PlayerDeployDropZone")
	var local_point: Vector2 = receiver.get_global_transform_with_canvas().affine_inverse() * motion.position
	receiver._drop_data(local_point, {"kind": &"unit_card", "card_instance": gui_card, "source_card": source})
	release.position = motion.position
	get_viewport().push_input(release, true)
	await get_tree().process_frame
	assert(runtime.preview_target == null and not ally.cast_preview_highlight)
	assert(ally.unit_data.defence == before_defence + 3)
	assert(not hand.hand.has(gui_card))
	source.queue_free()
	energy = rounds.current_energy
	assert(not runtime.try_play(invalid, Vector2(1600, 800)))
	assert(hand.hand.has(invalid) and rounds.current_energy == energy)
	var original_attack: int = other.unit_data.attack
	var attack_card := _play(0, ally.global_position)
	assert(runtime.preview_target == null)
	assert(ally.unit_data.attack == original_attack + 5)
	assert(other.unit_data.attack == original_attack)
	assert(hand.discard_pile.has(attack_card))
	var defence: int = ally.unit_data.defence
	_play(2, ally.global_position)
	assert(ally.unit_data.defence == defence + 3)
	ally.current_health = 20
	_play(1, ally.global_position)
	assert(ally.current_health == 20 + int(ceil(ally.unit_data.max_hp * 0.25)))

	# 真正的 get_hurt 命中会叠毒，回合末才扣毒伤，不受防御减免。
	_play(3, ally.global_position)
	global.game_phase = global.GamePhase.AUTO_BATTLE
	enemy.get_hurt(1, ally, false)
	assert(runtime.states[enemy.get_instance_id()].poison == 2)
	var before_poison: int = enemy.current_health
	runtime._on_round_ended()
	assert(enemy.current_health == before_poison - 2)
	rounds.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	global.game_phase = global.GamePhase.CARD_PLAY

	# 删除的枚举编号不复用，无效效果必须在扣费和弃牌前拒绝。
	assert(not CardEffect.Kind.values().has(5))
	var unknown_effect := CardEffect.new()
	unknown_effect.set("kind", 5)
	var unknown_definition := CardDefinition.new()
	unknown_definition.target = CardDefinition.Target.NONE
	unknown_definition.effects.assign([unknown_effect])
	var unknown_card := CardInstance.new(unknown_definition)
	hand.hand.append(unknown_card)
	var previous_energy: int = rounds.current_energy
	assert(not runtime.try_play(unknown_card, Vector2(700, 500)))
	assert(hand.hand.has(unknown_card) and rounds.current_energy == previous_energy)
	# 开打后沿用本轮手牌和能量，剩余手牌等交锋结算清场才弃置。
	var unused_cards: Array[CardInstance] = hand.hand.duplicate()
	var discarded_before: int = hand.discard_pile.size()
	rounds.start_auto_battle()
	assert(global.game_phase == global.GamePhase.AUTO_BATTLE and hand.hand == unused_cards)
	assert(hand.discard_pile.size() == discarded_before)
	assert(rounds.battle_time.is_stopped())
	rounds.battle_time.stop()
	rounds.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	global.game_phase = global.GamePhase.CARD_PLAY

	# 复制品不增加拥有的牌；没有绑定原牌，因此不能收回。
	var deck_size: int = root.get_node("RunManager").deck.size()
	_play(5, ally.global_position)
	var copy: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	assert(copy.current_health == ally.current_health)
	assert(copy.unit_data.attack == ally.unit_data.attack)
	assert(not hand.board_cards.has(copy.get_instance_id()))
	assert(root.get_node("RunManager").deck.size() == deck_size)
	var invalid_recall := _give(13)
	assert(not runtime.try_play(invalid_recall, copy.global_position))
	assert(hand.hand.has(invalid_recall))
	var bound_card: CardInstance = hand.board_cards[other.get_instance_id()]
	var deaths: int = runtime.ally_deaths
	_play(13, other.global_position)
	assert(hand.hand.has(bound_card))
	assert(runtime.ally_deaths == deaths and not other.is_inside_tree())
	assert(not battle.battle_finished)

	# 伤亡光环统计真正死亡，死亡宣告同时伤害敌我，且不会改动共享资源。
	var aura_card := _play(11)
	assert(hand.exhaust_pile.has(aura_card))
	var victim := _recruit(Vector2(430, 450))
	_play(4, victim.global_position)
	var hp_before: int = ally.current_health
	var enemy_before: int = enemy.current_health
	var attack_before: int = ally.unit_data.attack
	victim.take_effect_damage(10000)
	assert(ally.current_health == hp_before - 20)
	assert(enemy.current_health == enemy_before - 20)
	assert(ally.unit_data.attack == attack_before + 2)

	# 区域伤害只伤指定阵营；泥潭减速双方，离开时恢复。
	_play(6, enemy.global_position)
	global.game_phase = global.GamePhase.AUTO_BATTLE
	var zone_before: int = enemy.current_health
	runtime._physics_process(1.0)
	assert(enemy.current_health == zone_before - 5)
	rounds.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	global.game_phase = global.GamePhase.CARD_PLAY
	_play(7, ally.global_position)
	runtime._physics_process(0.0)
	var base_speed: float = runtime.states[ally.get_instance_id()].base_speed
	assert(is_equal_approx(ally.unit_data.speed, base_speed * 0.5))
	ally.global_position = Vector2(850, 750)
	runtime._physics_process(0.0)
	assert(is_equal_approx(ally.unit_data.speed, base_speed))
	global.game_phase = global.GamePhase.AUTO_BATTLE
	runtime._physics_process(12.0)
	assert(runtime.zones.size() == 2)
	runtime.clear_battle_buffs()
	assert(runtime.zones.is_empty())
	rounds.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	global.game_phase = global.GamePhase.CARD_PLAY

	# 抽牌禁令只限制本打牌回合；被拒绝的支付生命牌不能先扣血。
	var draw_card := _give(8)
	var hand_count: int = hand.hand.size()
	assert(runtime.try_play(draw_card, Vector2(700, 500)))
	assert(hand.hand.size() == hand_count + 3)
	assert(hand.draw_locked)
	var blood_card := _give(9)
	var run = root.get_node("RunManager")
	var hp: int = run.hp
	assert(not runtime.try_play(blood_card, Vector2(700, 500)))
	assert(run.hp == hp and hand.hand.has(blood_card))
	# 加能量能力本回合不生效，从下一回合起每轮 +1。
	var energy_card := _play(10)
	assert(hand.exhaust_pile.has(energy_card))
	assert(rounds.recurring_energy == 0 and rounds.pending_recurring_energy == 1)
	rounds.current_round += 1
	rounds._start_card_phase()
	assert(not hand.draw_locked and rounds.current_energy == rounds.base_energy_max + 1)
	rounds.current_energy = 99
	hand_count = hand.hand.size()
	assert(runtime.try_play(blood_card, Vector2(700, 500)))
	assert(run.hp == hp - 3 and hand.hand.size() == hand_count + 1)

	# 随机打牌使用真实入口、免能量，实际造出两名士兵。
	hand.draw_pile.clear()
	for i in 2:
		hand.draw_pile.append(CardInstance.new(load("res://data/units/soldier.tres")))
	var units_before: int = battle.get_node("Entities/TeamA").get_child_count()
	_play(12)
	assert(battle.get_node("Entities/TeamA").get_child_count() == units_before + 2)
	assert(rounds.current_energy == 98)
	assert(hand.resolving.is_empty())
	# 生命不足和未实现的自定义效果不能吞牌；递归随机出牌必须有硬上限。
	run.hp = 2
	var unaffordable := _give(9)
	energy = rounds.current_energy
	assert(not runtime.try_play(unaffordable, Vector2(700, 500)))
	assert(run.hp == 2 and rounds.current_energy == energy and hand.hand.has(unaffordable))
	var custom := CardDefinition.new()
	custom.target = CardDefinition.Target.NONE
	var custom_effect := CardEffect.new()
	custom_effect.kind = CardEffect.Kind.CUSTOM
	custom.effects.append(custom_effect)
	var custom_card := CardInstance.new(custom)
	hand.hand.append(custom_card)
	assert(not runtime.try_play(custom_card, Vector2(700, 500)))
	hand.draw_pile.clear()
	hand.hand.clear()
	for i in 39:
		hand.draw_pile.append(CardInstance.new(examples.cards[12]))
	var chain_card := _give(12)
	assert(runtime.try_play(chain_card, Vector2(700, 500)))
	assert(runtime.chain_count == 32)
	assert(hand.draw_pile.size() == 8 and hand.hand.is_empty() and hand.resolving.is_empty())
	await _test_enhanced_unit_next_round()
	battle.battle_finished = true
	battle.queue_free()
	await get_tree().process_frame
	print("CARD_FRAMEWORK_SMOKE_PASS: all %d examples" % examples.cards.size())
	get_tree().quit()


# 作用：用独立导航资源验证左半边、空洞、变换和空导航；没有参数，没有返回值。
func _test_navigation_deployment() -> void:
	var region: NavigationRegion2D = battle.get_node("Level/NavigationRegion2D")
	var saved := region.navigation_polygon
	var transform := region.global_transform
	var mesh := NavigationPolygon.new()
	# 两块烘焙面之间留一个空洞，外包矩形覆盖它，但它不能成为合法部署位置。
	mesh.vertices = PackedVector2Array([Vector2(0, 0), Vector2(50, 0), Vector2(50, 200), Vector2(0, 200),
		Vector2(100, 0), Vector2(400, 0), Vector2(400, 200), Vector2(100, 200)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	mesh.add_polygon(PackedInt32Array([4, 5, 6, 7]))
	region.navigation_polygon = mesh
	region.global_transform = Transform2D(0.0, Vector2(2, 0.5), 0.0, Vector2(1000, 200))
	assert(battle.is_deployment_position(region.to_global(Vector2(25, 100))))
	assert(battle.is_deployment_position(region.to_global(Vector2(150, 100))))
	assert(not battle.is_deployment_position(region.to_global(Vector2(75, 100))))
	assert(not battle.is_deployment_position(region.to_global(Vector2(300, 100))))
	for i in 100:
		assert(battle.is_deployment_position(battle.random_deployment_position()))
	var card := CardInstance.new(load("res://data/units/soldier.tres"))
	hand.hand.append(card)
	rounds.current_energy = 3
	assert(not runtime.try_play(card, region.to_global(Vector2(75, 100))))
	assert(hand.hand.has(card) and rounds.current_energy == 3)
	assert(runtime.try_play(card, region.to_global(Vector2(150, 100))))
	region.navigation_polygon = null
	assert(not battle.is_deployment_position(Vector2(450, 450)))
	assert(battle.random_deployment_position() == null)
	region.navigation_polygon = saved
	region.global_transform = transform
	print("NAVIGATION_DEPLOYMENT_PASS")


# 作用：验证真实血契补给立即溢出能量、刷新 UI 和不足生命保护；没有参数，没有返回值。
func _test_energy_overflow() -> void:
	rounds.max_energy = 3
	rounds.current_energy = 3
	var hp: int = RunManager.hp
	var card := CardInstance.new(load("res://data/cards/draw_hp.tres"))
	# 独立配方固定回归条件，正式血契数值的平衡调整不影响溢出机制验证。
	card.definition = card.definition.duplicate(true)
	card.definition.card_cost = 0
	card.definition.effects[0].amount = 3
	hand.hand.append(card)
	assert(runtime.try_play(card, Vector2(700, 500)))
	assert(rounds.current_energy == 6 and rounds.max_energy == 3)
	assert(battle.card_ui.cost_number.text == "6")
	assert(RunManager.hp == hp - 3 and rounds.pending_recurring_energy == 0)
	assert(rounds.try_spend_energy(1) and battle.card_ui.cost_number.text == "5")
	rounds.current_round += 1
	rounds._start_card_phase()
	assert(rounds.current_energy == 4 and battle.card_ui.cost_number.text == "4")
	RunManager.hp = 3
	var rejected := CardInstance.new(card.definition)
	hand.hand.append(rejected)
	assert(not runtime.try_play(rejected, Vector2(700, 500)))
	assert(rounds.current_energy == 4 and RunManager.hp == 3 and hand.hand.has(rejected))
	print("ENERGY_OVERFLOW_PASS")


# 作用：验证随机效果只使用抽牌堆，并保留费用、缺牌与连锁限制；没有参数，没有返回值。
func _test_random_draw() -> void:
	hand.draw_pile.clear()
	var kept := CardInstance.new(load("res://data/units/soldier.tres"))
	hand.hand.append(kept)
	for i in 2:
		hand.draw_pile.append(CardInstance.new(kept.definition))
	var before: int = battle.get_node("Entities/TeamA").get_child_count()
	_play(12)
	assert(battle.get_node("Entities/TeamA").get_child_count() == before + 2)
	assert(hand.hand.has(kept) and hand.draw_pile.is_empty())
	assert(rounds.current_energy == 98)
	# 空抽牌堆不会洗弃牌堆，也不会改为随机使用手牌。
	_play(12)
	assert(battle.get_node("Entities/TeamA").get_child_count() == before + 2)
	hand.draw_pile.append(CardInstance.new(kept.definition))
	_play(12)
	assert(battle.get_node("Entities/TeamA").get_child_count() == before + 3)
	# 找不到合法目标时留在抽牌堆，不能丢牌；禁抽不会阻止直接打出。
	var invalid := CardInstance.new(CardDefinition.new())
	var effect := CardEffect.new()
	effect.kind = CardEffect.Kind.CUSTOM
	invalid.definition.effects.append(effect)
	hand.draw_pile.append(invalid)
	hand.draw_locked = true
	hand.draw_pile.append(CardInstance.new(kept.definition))
	_play(12)
	assert(hand.draw_pile.has(invalid) and hand.draw_pile.size() == 1)
	assert(battle.get_node("Entities/TeamA").get_child_count() == before + 4)
	hand.draw_pile.clear()
	for i in 39:
		hand.draw_pile.append(CardInstance.new(examples.cards[12]))
	_play(12)
	assert(runtime.chain_count == 32 and hand.draw_pile.size() == 8)
	assert(hand.resolving.is_empty() and hand.hand.has(kept))
	print("RANDOM_DRAW_PLAY_PASS")


# 作用：验证地图绑定、首轮参数、有限波次和空数组；没有参数，没有返回值。
func _test_level_template() -> void:
	battle.battle_finished = true
	battle.queue_free()
	await get_tree().process_frame
	var config := load("res://data/levels/level_template.tres") as BattleLevelConfig
	assert(config != null and config.validate().is_empty())
	var session = load("res://examples/scenes/game_session_example.tscn").instantiate()
	root.add_child(session)
	assert(session.resolve_level("level_template") == config)
	var custom: BattleLevelConfig = config
	custom.battle_duration = 17
	custom.energy_per_round = 4
	custom.cards_per_round = 2
	custom.waves = [config.waves[0], null, config.waves[0]]
	# 从当前波次场景读取数量和阵型，策划调整刷怪配置不应让加载测试误报。
	var wave_preview := config.waves[0].instantiate()
	var expected_count := wave_preview.get_child_count()
	var expected_position: Vector2 = wave_preview.get_child(0).position
	wave_preview.free()
	assert(session.resolve_level("level_template") == custom)
	assert(session.resolve_level("level_template") == config)
	RunManager.begin_battle("battle_a", "level_template")
	session._on_battle_requested("level_template")
	var encounter = session.current_battle
	assert(encounter != null and encounter.level_config == custom)
	assert(encounter.battle_round_manager.current_energy == 4)
	assert(encounter.battle_round_manager.battle_duration == 17)
	var innate_count := RunManager.deck.filter(func(card: CardInstance): return card.definition.starts_in_hand).size()
	assert(encounter.hand_manager.hand.size() == mini(2 + innate_count, RunManager.deck.size()))
	var team = encounter.get_node("Entities/TeamB")
	assert(team.get_child_count() == expected_count and not encounter.can_win_battle())
	assert(team.get_child(0).position == expected_position)
	# 波次之间清场不应提前胜利；同回合重复信号不重复刷怪。
	for enemy in team.get_children():
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not encounter.battle_finished)
	team._on_battle_round_manager_phase_changed(Global.GamePhase.CARD_PLAY, 2)
	assert(team.get_child_count() == 0 and team.has_future_waves())
	team._on_battle_round_manager_phase_changed(Global.GamePhase.CARD_PLAY, 3)
	team._on_battle_round_manager_phase_changed(Global.GamePhase.CARD_PLAY, 3)
	assert(team.get_child_count() == expected_count and not encounter.can_win_battle())
	team._on_battle_round_manager_phase_changed(Global.GamePhase.CARD_PLAY, 4)
	assert(team.get_child_count() == expected_count * 2)
	team.level_data.clear()
	team._on_battle_round_manager_phase_changed(Global.GamePhase.CARD_PLAY, 5)
	assert(not team.has_future_waves())
	session.queue_free()
	await get_tree().process_frame
	print("LEVEL_TEMPLATE_PASS")


# 作用：构造地面区域测试牌；kind 为区域类型，lifetime 为期限，返回具体牌。
func _zone_card(kind: CardEffect.Kind, lifetime: CardEffect.Lifetime) -> CardInstance:
	var definition := CardDefinition.new()
	definition.target = CardDefinition.Target.POSITION
	var effect := CardEffect.new()
	effect.kind = kind
	effect.lifetime = lifetime
	effect.lasting_rounds = 2
	effect.amount = 50 if kind == CardEffect.Kind.MUD_ZONE else 5
	definition.effects.append(effect)
	var card := CardInstance.new(definition)
	hand.hand.append(card)
	rounds.current_energy = 99
	return card


# 作用：验证区域不按秒过期、各自扣回合、恢复速度及拒绝永久；没有参数，没有返回值。
func _test_zone_lifetimes() -> void:
	var unit := _recruit(Vector2(450, 450))
	var speed: float = unit.unit_data.speed
	assert(runtime.try_play(_zone_card(CardEffect.Kind.MUD_ZONE, CardEffect.Lifetime.ROUNDS), unit.global_position))
	var mud_visual: Node2D = runtime.zones[0].visual
	assert(mud_visual.global_position.is_equal_approx(unit.global_position))
	assert(mud_visual.get_meta("effect_id") == "scenes_vfx_leapgrounddecal")
	assert(mud_visual.get_node("Sprite2D").texture.resource_path == "res://assets/effect/eslabong_vfx/source/Art/VFX/slamdunk_leap.png")
	await get_tree().create_timer(2.0).timeout
	assert(is_instance_valid(mud_visual) and mud_visual.is_visible_in_tree() and mud_visual.modulate.a > 0.8, "泥沼印记不能按原素材的秒数淡出")
	if "--capture-mud-zone" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.maintenance/mud-zone-preview.png"))
	runtime._physics_process(20.0)
	assert(runtime.zones.size() == 1 and runtime.zones[0].rounds_left == 2)
	assert(unit.unit_data.speed == speed * 0.5)
	runtime._on_round_ended()
	assert(runtime.try_play(_zone_card(CardEffect.Kind.MUD_ZONE, CardEffect.Lifetime.ROUNDS), unit.global_position))
	var second_mud: Node2D = runtime.zones[1].visual
	assert(second_mud != mud_visual, "重叠泥沼拥有独立印记")
	runtime._on_round_ended()
	assert(runtime.zones.size() == 1 and runtime.zones[0].rounds_left == 1)
	assert(mud_visual.is_queued_for_deletion() and not mud_visual.visible and second_mud.visible)
	assert(unit.unit_data.speed == speed * 0.5)
	runtime._on_round_ended()
	assert(runtime.zones.is_empty() and unit.unit_data.speed == speed)
	assert(second_mud.is_queued_for_deletion() and not second_mud.visible)
	var enemy: UnitBase = battle.get_node("Entities/TeamB").get_child(0)
	enemy.current_health = 10000
	assert(runtime.try_play(_zone_card(CardEffect.Kind.DAMAGE_ZONE, CardEffect.Lifetime.BATTLE), enemy.global_position))
	var fire_visual: Node2D = runtime.zones[0].visual
	assert(fire_visual.global_position.is_equal_approx(enemy.global_position))
	assert(fire_visual.get_meta("effect_id") == "pixel_burned_ground")
	assert(is_equal_approx(fire_visual.radius, runtime.zones[0].effect.radius), "焦草范围必须匹配真实伤害半径")
	assert(fire_visual.find_children("*", "CollisionObject2D", true, false).is_empty(), "地面特效不能重复结算伤害")
	assert(fire_visual.find_children("*", "Timer", true, false).is_empty(), "地形期限由回合管理，不能沿用素材的秒数计时")
	await get_tree().create_timer(2.0).timeout
	assert(is_instance_valid(fire_visual) and fire_visual.is_visible_in_tree(), "焦草与火星随区域持续显示")
	if "--capture-fire-zone" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.maintenance/fire-zone-preview.png"))
	var surface := fire_visual.get_node("ScorchedGrass") as ColorRect
	assert(surface.material is ShaderMaterial)
	var sparks := fire_visual.get_node("Sparks/Particles") as CPUParticles2D
	assert(sparks != null and sparks.emitting, "区域应使用实验室「灼烧 · 地面」的原火星节点")
	assert(sparks.get_meta("source_scene") == "res://assets/effect/eslabong_vfx/source/Scenes/VFX/BurnGroundVFX.tscn")
	assert(fire_visual.get_node("BurningFlames/BurningSurface").material is ShaderMaterial, "焦草上应叠加沿面燃烧 Shader")
	var clock_before: float = surface.material.get_shader_parameter("clock_time")
	get_tree().paused = true
	await get_tree().create_timer(0.1, true).timeout
	assert(not fire_visual.can_process() and is_equal_approx(surface.material.get_shader_parameter("clock_time"), clock_before), "焦草与火星时钟随游戏暂停")
	get_tree().paused = false
	global.game_phase = global.GamePhase.AUTO_BATTLE
	runtime._physics_process(12.0)
	assert(enemy.current_health == 9940 and runtime.zones.size() == 1)
	rounds.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	global.game_phase = global.GamePhase.CARD_PLAY
	runtime._on_round_ended()
	assert(runtime.zones.size() == 1)
	assert(runtime.try_play(_zone_card(CardEffect.Kind.DAMAGE_ZONE, CardEffect.Lifetime.ROUNDS), enemy.global_position))
	var short_fire: Node2D = runtime.zones[1].visual
	assert(short_fire != fire_visual, "重叠火焰拥有各自的视觉实例")
	runtime._on_round_ended()
	assert(runtime.zones.size() == 2 and short_fire.visible)
	runtime._on_round_ended()
	assert(runtime.zones.size() == 1 and short_fire.is_queued_for_deletion() and not short_fire.visible)
	assert(fire_visual.visible, "一块火焰到期不能清除其它区域")
	var rejected := _zone_card(CardEffect.Kind.MUD_ZONE, CardEffect.Lifetime.RUN)
	assert(not runtime.try_play(rejected, unit.global_position))
	assert(hand.hand.has(rejected) and rounds.current_energy == 99)
	assert(runtime.try_play(_zone_card(CardEffect.Kind.MUD_ZONE, CardEffect.Lifetime.BATTLE), unit.global_position))
	var battle_mud: Node2D = runtime.zones.back().visual
	runtime._physics_process(0.0)
	battle.finish_battle(true)
	assert(runtime.zones.is_empty() and unit.unit_data.speed == speed)
	assert(fire_visual.is_queued_for_deletion() and not fire_visual.visible, "战斗结束立即清除火焰")
	assert(battle_mud.is_queued_for_deletion() and not battle_mud.visible, "战斗结束立即清除泥沼印记")
	print("ZONE_LIFETIMES_PASS")


# 作用：构造并施放持续强化；unit 为目标，kind 为效果，lifetime 为期限，amount 为点数，返回强化牌。
func _buff(unit: UnitBase, kind: CardEffect.Kind, lifetime: CardEffect.Lifetime, amount: int = 5) -> CardInstance:
	var definition := CardDefinition.new()
	definition.card_name = "持续强化测试"
	var effect := CardEffect.new()
	effect.kind = kind
	effect.lifetime = lifetime
	effect.amount = amount
	effect.lasting_rounds = 2
	definition.effects.append(effect)
	var card := CardInstance.new(definition)
	hand.hand.append(card)
	rounds.current_energy = 99
	assert(runtime.try_play(card, unit.global_position))
	return card


# 作用：验证独立到期、永久记录、死亡重召和跨场；没有参数，没有返回值。
func _test_buff_lifetimes() -> void:
	var unit := _recruit(Vector2(450, 450))
	var base: int = unit.unit_data.attack
	var original: CardInstance = hand.board_cards[unit.get_instance_id()]
	_buff(unit, CardEffect.Kind.ATTACK_UP, CardEffect.Lifetime.ROUNDS)
	runtime._on_round_ended()
	_buff(unit, CardEffect.Kind.ATTACK_UP, CardEffect.Lifetime.ROUNDS)
	assert(unit.unit_data.attack == base + 10)
	runtime._on_round_ended()
	assert(unit.unit_data.attack == base + 5)
	var descriptions: Array[String] = runtime.describe_buffs(unit)
	assert(descriptions.any(func(text: String): return text.contains("持续强化测试") and text.contains("剩余 1")),
		"仍生效的临时强化应显示剩余一回合，不依赖被动说明的排列位置")
	runtime._on_round_ended()
	assert(unit.unit_data.attack == base)
	# 其它附着效果也要按自己的记录撤销。
	var defence: int = unit.unit_data.defence
	for kind in [CardEffect.Kind.DEFENCE_UP, CardEffect.Kind.POISON_ON_HIT, CardEffect.Kind.DEATH_EXPLOSION]:
		_buff(unit, kind, CardEffect.Lifetime.ROUNDS)
	runtime._tick_buffs()
	runtime._tick_buffs()
	assert(unit.unit_data.defence == defence)
	assert(runtime.states[unit.get_instance_id()].poison_on_hit == 0)
	assert(runtime.states[unit.get_instance_id()].explosions.is_empty())
	_buff(unit, CardEffect.Kind.ATTACK_UP, CardEffect.Lifetime.BATTLE, 7)
	_buff(unit, CardEffect.Kind.ATTACK_UP, CardEffect.Lifetime.RUN, 11)
	runtime._tick_buffs()
	assert(unit.unit_data.attack == base + 18 and original.permanent_buffs.size() == 1)
	var other := _recruit(Vector2(700, 450))
	assert(other.unit_data.attack == base)
	assert(load("res://data/units/soldier.tres").attack == base)
	# 复制品继承当前加成，但没有可以保存永久强化的原牌。
	_play(5, unit.global_position)
	var copy: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	assert(copy.unit_data.attack == base + 18)
	var invalid := CardInstance.new(CardDefinition.new())
	var permanent := CardEffect.new()
	permanent.lifetime = CardEffect.Lifetime.RUN
	invalid.definition.effects.append(permanent)
	hand.hand.append(invalid)
	assert(not runtime.try_play(invalid, copy.global_position))
	assert(hand.hand.has(invalid))
	# 死亡进弃牌，再召唤同一张牌，只有永久加成恢复。
	unit.die()
	assert(hand.discard_pile.has(original))
	hand.discard_pile.erase(original)
	hand.hand.append(original)
	assert(runtime.try_play(original, Vector2(450, 600)))
	var revived: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	revived.set_physics_process(false)
	assert(revived.unit_data.attack == base + 11)
	battle.finish_battle(true)
	assert(copy.unit_data.attack == base and revived.unit_data.attack == base)
	assert(original.permanent_buffs.size() == 1)
	# 创建全新战场，验证不是旧运行时碰巧保留了加成。
	battle.queue_free()
	await get_tree().process_frame
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	root.add_child(battle)
	get_tree().current_scene = battle
	runtime = battle.card_runtime
	hand = battle.hand_manager
	rounds = battle.battle_round_manager
	runtime.set_physics_process(false)
	hand.hand.append(original)
	rounds.current_energy = 99
	assert(runtime.try_play(original, Vector2(450, 450)))
	var next_unit: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	assert(next_unit.unit_data.attack == base + 11)
	assert(CardInstance.new(original.definition).permanent_buffs.is_empty())
	print("BUFF_LIFETIMES_PASS")


# 作用：发送真实鼠标移动和点击；point 为屏幕位置，double 为双击标记，button 为鼠标键。
func _inspector_click(point: Vector2, double := false, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	var click := InputEventMouseButton.new()
	click.position = point
	click.button_index = button
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	click.pressed = true
	click.double_click = double
	get_viewport().push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	click.button_mask = 0
	click.double_click = false
	get_viewport().push_input(click, true)


# 作用：验证双击详情、单击选择、右键部署、相机变换、界面遮挡和清理；没有参数，没有返回值。
func _test_unit_inspector() -> void:
	var unit := _recruit(Vector2(450, 450))
	var inspector = battle.card_ui.get_node("UnitInspector")
	var enemy: UnitBase = battle.get_node("Entities/TeamB").get_child(0)
	enemy.set_physics_process(false)
	enemy.global_position = Vector2(1000, 450)
	assert(inspector.pick_unit(unit.global_position) == unit)
	# 悬停和单击不打开详情，双击通过未被界面消费的真实输入打开。
	var motion := InputEventMouseMotion.new()
	motion.position = unit.get_global_transform_with_canvas().origin
	get_viewport().push_input(motion, true)
	await get_tree().create_timer(0.1).timeout
	assert(not inspector.panel.visible and inspector.inspected == null, "悬停不打开单位详情")
	_inspector_click(motion.position)
	assert(not inspector.panel.visible, "单击不打开单位详情")
	# 无窗口测试的系统鼠标位置不跟随注入事件，选择逻辑使用明确的世界坐标验证。
	battle.get_node("MouseSlectionController")._finish_selected(unit.global_position, unit.global_position)
	assert(unit.is_selected, "单击选择功能仍可用")
	_inspector_click(motion.position, true)
	assert(inspector.panel.visible and inspector.health_text.text == "100 / 100")
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(700, 350)
	get_viewport().push_input(motion, true)
	await get_tree().create_timer(0.1).timeout
	assert(inspector.panel.visible and inspector.inspected == unit, "移开鼠标保留双击打开的详情")
	# 左右位置只由阵营决定，连续切换查看对象也要重新定位。
	assert(inspector.panel.anchor_left == 0.0 and inspector.panel.offset_left == 20.0)
	_inspector_click(enemy.get_global_transform_with_canvas().origin)
	assert(inspector.inspected == unit, "单击其他单位不切换详情")
	_inspector_click(enemy.get_global_transform_with_canvas().origin, true)
	assert(inspector.inspected == enemy)
	assert(inspector.panel.anchor_left == 1.0 and inspector.panel.offset_right == -20.0)
	_inspector_click(unit.get_global_transform_with_canvas().origin, true)
	assert(inspector.inspected == unit)
	assert(inspector.panel.anchor_left == 0.0 and inspector.panel.offset_left == 20.0)
	unit.unit_data.attack = 123
	var skill: SkillBase = inspector.skill_cells[0].skill
	unit.skill_manager._skill_time_cd[skill].start(3.0)
	inspector.refresh_details()
	assert(inspector.stat_labels.attack.get_parsed_text() == "攻击：123")
	assert(is_equal_approx(inspector.skill_cells[0].icon.cooldown_fraction, 1.0))
	# 详情不消费右键，准备阶段可同时选中和移动单位。
	rounds.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	global.game_phase = global.GamePhase.CARD_PLAY
	unit.is_selected = true
	_inspector_click(Vector2(700, 350), false, MOUSE_BUTTON_RIGHT)
	assert(inspector.panel.visible and inspector.inspected == unit)
	assert(unit.target_position != null)
	# 关闭按钮通过真实 UI 输入生效，离开面板后不会因悬停重新打开。
	await get_tree().process_frame
	var close: Button = inspector.close_button
	_inspector_click(close.get_global_rect().get_center())
	assert(not inspector.panel.visible and inspector.inspected == null)
	_inspector_click(Vector2(700, 350), true, MOUSE_BUTTON_RIGHT)
	assert(not inspector.panel.visible, "双击右键不打开详情")
	_inspector_click(Vector2(700, 350), true)
	assert(not inspector.panel.visible, "双击空地不打开详情")
	# 相机缩放平移后，仍通过屏幕坐标找到单位；界面按钮挡住单位时不打开。
	var camera := battle.get_node("Camera2D") as Camera2D
	camera.zoom = Vector2.ONE * 1.4
	camera.global_position = Vector2(800, 500)
	camera.force_update_scroll()
	var point: Vector2 = unit.get_global_transform_with_canvas().origin
	var blocker := Button.new()
	blocker.position = point - Vector2(40, 40)
	blocker.size = Vector2(80, 80)
	battle.card_ui.add_child(blocker)
	await get_tree().process_frame
	_inspector_click(point, true)
	assert(not inspector.panel.visible, "UI 双击不会打开身后单位详情")
	blocker.free()
	_inspector_click(point, true)
	assert(inspector.panel.visible and inspector.inspected == unit, "相机缩放平移后双击仍准确")
	get_tree().paused = true
	assert(not inspector.panel.visible, "暂停立即隐藏详情")
	get_tree().paused = false
	# 交锋中也可双击，目标死亡和战斗结束时不会留下详情。
	global.game_phase = global.GamePhase.AUTO_BATTLE
	_inspector_click(point, true)
	assert(inspector.panel.visible and inspector.inspected == unit, "战斗中仍允许双击详情")
	unit.current_state = UnitBase.State.DEATH
	inspector._process(0.1)
	assert(not inspector.panel.visible and inspector.inspected == null)
	_inspector_click(point, true)
	assert(not inspector.panel.visible, "双击死亡单位不打开详情")
	_inspector_click(enemy.get_global_transform_with_canvas().origin, true)
	assert(inspector.panel.visible and inspector.inspected == enemy)
	battle.battle_finished = true
	inspector._process(0.1)
	assert(not inspector.panel.visible and inspector.inspected == null)
	_inspector_click(enemy.get_global_transform_with_canvas().origin, true)
	assert(not inspector.panel.visible, "战斗结束后不打开详情")
	print("UNIT_INSPECTOR_PASS")


# 作用：检查刚召唤的单位可在同一回合强化；没有参数，没有返回值。
func _test_new_unit_enhancement() -> void:
	var unit := _recruit(Vector2(450, 450))
	var card := CardInstance.new(load("res://data/cards/power_enhance.tres"))
	hand.hand.append(card)
	# 不等待下一帧或下一轮：召唤调用返回后立即对同一单位出牌。
	rounds.current_energy = 2
	assert(runtime.targets_for(card.definition).has(unit))
	var before: int = unit.unit_data.attack
	runtime.update_cast_preview(card, unit.global_position)
	assert(runtime.preview_target == unit)
	assert(runtime.try_play(card, unit.global_position))
	assert(unit.unit_data.attack > before and rounds.current_energy == 1)
	# 同一单位可以继续强化；没能量后必须保留手牌，不能再增加属性。
	var second := CardInstance.new(card.definition)
	hand.hand.append(second)
	assert(runtime.try_play(second, unit.global_position) and rounds.current_energy == 0)
	var third := CardInstance.new(card.definition)
	hand.hand.append(third)
	before = unit.unit_data.attack
	assert(not runtime.try_play(third, unit.global_position))
	assert(hand.hand.has(third) and unit.unit_data.attack == before)
	print("NEW_UNIT_ENHANCEMENT_LOGIC_PASS")


# 作用：模拟攻击没播完就结束一轮，再强化并开战；没有参数，没有返回值。
func _test_enhanced_unit_next_round() -> void:
	rounds.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	global.game_phase = global.GamePhase.CARD_PLAY
	var unit := _recruit(Vector2(450, 500))
	var enemy: UnitBase = battle.get_node("Entities/TeamB").get_child(0)
	enemy.current_health = 10000
	var manager = unit.skill_manager
	var skill: SkillBase = manager.group_skills.back()
	global.game_phase = global.GamePhase.AUTO_BATTLE
	manager.current_skill = skill
	manager.current_target = enemy
	unit.switch_state(UnitBase.State.ATTACK)
	manager.attack()
	assert(manager.is_casting)
	# 原来的 bug：待机动画替换攻击动画后，animation_finished 永远等不到。
	rounds.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	global.game_phase = global.GamePhase.CARD_PLAY
	_play(0, unit.global_position)
	global.game_phase = global.GamePhase.AUTO_BATTLE
	assert(not manager.is_casting, "跨回合施法锁未解除，强化后的单位无法行动")
	assert(unit.current_state != UnitBase.State.ATTACK)
	assert(unit.unit_data.speed > 0)
	# 中断动作不会退还已经开始的冷却；等真实技能时钟结束后再验证重新行动。
	var cooldown_left := float(manager.get_cooldown_left(skill))
	assert(cooldown_left > 0.0, "切阶段必须保留已开始的技能冷却")
	await get_tree().create_timer(cooldown_left + 1.0 / 60.0, false, true).timeout
	# 不只检查变量：让真实物理帧运行，确认强化后的单位确实重新向敌人移动。
	for opponent in battle.get_node("Entities/TeamB").get_children():
		opponent.global_position = Vector2(900, 500)
	var start_position := unit.global_position
	unit.set_physics_process(true)
	await get_tree().create_timer(0.35).timeout
	unit.set_physics_process(false)
	assert(unit.global_position.distance_to(start_position) > 1.0, "解除状态后单位仍未移动")
	# 再次使用同一个技能，动画应正常结束，不受上一轮被打断的攻击影响。
	manager.current_skill = skill
	manager.current_target = enemy
	unit.switch_state(UnitBase.State.ATTACK)
	manager.attack()
	await get_tree().create_timer(2.0).timeout
	assert(not manager.is_casting, "新一轮攻击播完后施法锁未解除")
	print("ENHANCED_UNIT_NEXT_ROUND_PASS")


# 作用：建立测试专用配方，不依赖玩家已删除或改名的示例资源；没有参数，返回配方集合。
func _build_test_examples() -> Resource:
	var result: Resource = load("res://data/run/run_start_data.gd").new()
	var recipes: Array = [
		[[0, 5]], [[1, 25]], [[2, 3]], [[3, 2]], [[4, 20]],
		[[6, 1]], [[7, 5]], [[8, 50]],
		[[9, 4], [10, 1]], [[11, 3], [9, 2]], [[12, 1]], [[13, 2]],
		[[14, 2]], [[15, 1]],
	]
	for i in recipes.size():
		var definition := CardDefinition.new()
		definition.card_name = "测试牌 %d" % i
		definition.category = CardDefinition.Category.ABILITY if i >= 8 else CardDefinition.Category.ENHANCEMENT
		definition.target = CardDefinition.Target.ALLY if i in [0, 1, 2, 3, 4, 5, 13] else CardDefinition.Target.NONE
		if i in [6, 7]:
			definition.target = CardDefinition.Target.POSITION
		if i in [10, 11]:
			definition.after_use = CardDefinition.AfterUse.EXHAUST
		for recipe in recipes[i]:
			var effect := CardEffect.new()
			effect.kind = recipe[0]
			effect.amount = recipe[1]
			definition.effects.append(effect)
		result.cards.append(definition)
	return result

