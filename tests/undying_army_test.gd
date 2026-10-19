# 验证常驻卡的正式出牌、跨回合原单位留存、死亡加费与跨战斗隔离。
extends Node

var battle: Node2D
var hand: Node2D
var runtime: Node2D
var rounds: BattleRoundManager
const CARD_PATH := "res://data/cards/undying_army.tres"


func _ready() -> void:
	get_tree().create_timer(25.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func _create_battle() -> void:
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


func _give(card: CardInstance) -> void:
	hand.draw_pile.erase(card)
	hand.discard_pile.erase(card)
	hand.hand.append(card)


func _recruit(card: CardInstance) -> UnitBase:
	_give(card)
	rounds.current_energy = card.get_cost()
	assert(runtime.try_play(card, Vector2(450, 450)))
	var unit: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	unit.set_physics_process(false)
	return unit


func _next_round() -> void:
	var previous := rounds.current_round
	rounds.start_auto_battle()
	await rounds.finish_unit_combat()
	await get_tree().process_frame
	assert(rounds.current_round == previous + 1 and not battle.battle_finished)


func _run() -> void:
	var definition := load(CARD_PATH) as CardDefinition
	assert(definition.card_cost == 4 and definition.rarity == CardDefinition.Rarity.RARE)
	assert(definition.after_use == CardDefinition.AfterUse.PERSIST and definition.target == CardDefinition.Target.NONE)
	assert(definition.effects[0].kind == CardEffect.Kind.RETAIN_ALLIES)
	var start := RunStartData.new()
	start.cards.assign([load("res://data/units/soldier.tres"), load("res://data/units/soldier.tres"), definition, definition])
	RunManager.start_new_run(start)
	_create_battle()
	var original: CardInstance = RunManager.deck[0]
	var peer: CardInstance = RunManager.deck[1]
	var power: CardInstance = RunManager.deck[2]
	var second: CardInstance = RunManager.deck[3]
	var base := original.get_cost()
	# 使用常驻牌前仍加1；启用后不追溯旧费用。
	var prior := _recruit(original)
	prior.die()
	assert(original.get_cost() == base + 1)
	battle.clear_round_units()
	var survivor := _recruit(original)
	survivor.take_effect_damage(1)
	var hp: int = survivor.current_health
	_give(power)
	rounds.current_energy = 3
	assert(not runtime.try_play(power, Vector2(450, 450)))
	assert(hand.hand.has(power) and hand.active_cards.is_empty() and not runtime.retain_allies)
	assert(rounds.current_energy == 3)
	rounds.current_energy = 4
	assert(not runtime.try_play(power, Vector2.ZERO))
	assert(hand.hand.has(power) and rounds.current_energy == 4)
	assert(runtime.try_play(power, Vector2(450, 450)))
	assert(rounds.current_energy == 0 and runtime.retain_allies and runtime.unit_discard_cost_increase == 2)
	assert(hand.active_cards == [power] and not hand.hand.has(power))
	assert(not hand.draw_pile.has(power) and not hand.discard_pile.has(power) and not hand.exhaust_pile.has(power))
	assert(power.can_upgrade(false))
	# 真实卡面与查看入口使用原牌，稀有金框不污染其它普通卡。
	var view: UnitCard = load("res://scenes/cards/unit_card.tscn").instantiate()
	add_child(view)
	view.setup(power)
	assert(view.get_node("CostIcon/CostLabel").text == "4")
	assert(view.get_node("FrameLayer").material.shader == view.RARE_FRAME_SHADER)
	assert(view.tooltip_text.contains("稀有") and view.tooltip_text.contains("常驻"))
	view.setup(peer)
	assert(view.get_node("FrameLayer").material == null)
	view.queue_free()
	var ui := battle.get_node("CardUI")
	assert(ui.get_node("CardButtons/ActiveButton").text == "常驻卡牌 · 1")
	ui._open_pile("ActiveButton")
	assert(get_tree().paused and ui.pile_view.grid.get_child_count() == 1)
	assert(ui.pile_view.grid.get_child(0).get_child(0).card_instance == power)
	ui._close_pile()
	assert(not get_tree().paused)
	# 原单位、无原牌召唤物、当前生命与本场强化都留存；回合型强化正常到期。
	var summoned: UnitBase = load("res://scenes/units/soldier.tscn").instantiate()
	battle.get_node("Entities/TeamA").add_child(summoned)
	summoned.set_physics_process(false)
	var buff := CardEffect.new()
	buff.amount = 3
	runtime._add_buff(survivor, buff, "本场攻击")
	var timed := CardEffect.new()
	timed.amount = 2
	timed.lifetime = CardEffect.Lifetime.ROUNDS
	timed.lasting_rounds = 1
	runtime._add_buff(survivor, timed, "一轮攻击")
	var attack: int = survivor.unit_data.attack
	await _next_round()
	assert(is_instance_valid(survivor) and survivor.is_inside_tree() and survivor.current_health == hp)
	assert(survivor.unit_data.attack == attack - 2)
	assert(hand.board_cards[survivor.get_instance_id()] == original and original.get_cost() == base + 1)
	assert(is_instance_valid(summoned) and summoned.is_inside_tree())
	assert(survivor.current_state == UnitBase.State.IDLE and not survivor.skill_manager.is_casting)
	assert(hand.active_cards == [power] and not hand.discard_pile.has(original))
	# 后续征召同样受益；重复使用不叠加惩罚，场上死亡仅处理原牌一次。
	var later := _recruit(peer)
	_give(second)
	rounds.current_energy = 4
	assert(runtime.try_play(second, Vector2(450, 450)))
	assert(hand.active_cards.size() == 2 and runtime.unit_discard_cost_increase == 2)
	survivor.die()
	survivor.unit_died.emit(survivor)
	assert(original.get_cost() == base + 3 and hand.discard_pile.count(original) == 1)
	assert(peer.get_cost() == base)
	var revived := _recruit(original)
	assert(rounds.current_energy == 0)
	# 回合末毒死的单位不可被留存；原牌加2，无原牌死亡不产生新牌。
	runtime.states[later.get_instance_id()].poison = later.current_health
	var enemy: UnitBase = load("res://scenes/units/orc.tscn").instantiate()
	battle.get_node("Entities/TeamB").add_child(enemy)
	enemy.set_physics_process(false)
	enemy.die()
	await _next_round()
	assert(not is_instance_valid(later) and not is_instance_valid(enemy))
	assert(peer.get_cost() == base + 2 and hand.discard_pile.count(peer) == 1)
	assert(is_instance_valid(revived) and hand.board_cards.has(revived.get_instance_id()))
	var discard_count: int = hand.discard_pile.size()
	summoned.die()
	assert(hand.discard_pile.size() == discard_count)
	# 收回仍回原牌且不加费；没有留存单位的额外抽牌或复制牌。
	assert(hand.recall_unit(revived))
	revived.get_parent().remove_child(revived)
	revived.queue_free()
	assert(original.get_cost() == base + 3 and hand.hand.has(original))
	hand.discard_unused_card()
	assert(original.get_cost() == base + 3)
	var final_survivor := _recruit(original)
	# 实际冲刺在交锋结束时中断，骑兵留下后恢复碰撞，不把位移带入准备阶段。
	var cavalry_card := CardInstance.new(load("res://data/units/lancer.tres"))
	var cavalry := _recruit(cavalry_card)
	var dash: SkillBase = load("res://data/skills/lancer_dash_attack.tres").duplicate()
	dash.dash_speed = 30.0
	var target: UnitBase = load("res://scenes/units/orc.tscn").instantiate()
	target.position = Vector2(900, 450)
	battle.get_node("Entities/TeamB").add_child(target)
	target.set_physics_process(false)
	rounds.start_auto_battle()
	cavalry.skill_manager.current_skill = dash
	cavalry.skill_manager.is_casting = true
	cavalry.switch_state(UnitBase.State.ATTACK)
	dash.execute(cavalry, target)
	for i in 4:
		await get_tree().physics_frame
	assert(cavalry.skill_manager.is_forced_moving)
	target.die()
	await _next_round()
	assert(is_instance_valid(cavalry) and cavalry.is_inside_tree())
	assert(not cavalry.skill_manager.is_forced_moving and not cavalry.skill_manager.is_casting)
	assert(not cavalry.get_node("CollisionShape2D").disabled)
	assert(not cavalry.get_node("AttackArea").monitoring)
	var stopped_position := cavalry.global_position
	for i in 3:
		await get_tree().physics_frame
	assert(cavalry.global_position.is_equal_approx(stopped_position))
	# 胜利结束常驻与单位留存，恢复所有牌费用；使用过的卡下场仍在总牌组。
	battle.finish_battle(true)
	assert(not runtime.retain_allies and runtime.unit_discard_cost_increase == 1)
	assert(hand.active_cards.is_empty() and hand.exhaust_pile.has(power) and hand.exhaust_pile.has(second))
	assert(original.get_cost() == base and peer.get_cost() == base and power.get_cost() == 4)
	assert(hand.board_cards.is_empty() and not final_survivor.is_inside_tree())
	final_survivor.unit_died.emit(final_survivor)
	assert(original.get_cost() == base)
	battle.queue_free()
	await get_tree().process_frame
	_create_battle()
	assert(not runtime.retain_allies and hand.active_cards.is_empty() and hand.draw_pile.has(power))
	var reset_unit := _recruit(original)
	await _next_round()
	assert(not is_instance_valid(reset_unit) and original.get_cost() == base + 1)
	# 交锋中使用也常驻本场，不受普通交锋强化仅持续一轮的规则影响。
	_recruit(peer)
	_give(power)
	rounds.current_energy = 4
	rounds.start_auto_battle()
	assert(runtime.try_play(power, Vector2(450, 450)))
	await rounds.finish_unit_combat()
	await get_tree().process_frame
	assert(runtime.retain_allies and hand.board_cards.size() == 1 and hand.active_cards.has(power))
	if "--capture" in OS.get_cmdline_user_args():
		ui = battle.get_node("CardUI")
		ui._open_pile("ActiveButton")
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.maintenance")
		get_viewport().get_texture().get_image().save_png("res://.maintenance/undying_army_preview.png")
		# 用独立渲染视口导出透明底卡面，便于直接查看金框与完整文案。
		var card_viewport := SubViewport.new()
		card_viewport.size = Vector2i(320, 440)
		card_viewport.transparent_bg = true
		card_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(card_viewport)
		var card_view: UnitCard = load("res://scenes/cards/unit_card.tscn").instantiate()
		card_view.is_playable = false
		card_viewport.add_child(card_view)
		card_view.setup(power)
		card_view.position = Vector2(174, 235)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		card_viewport.get_texture().get_image().save_png("res://.maintenance/undying_army_card.png")
		card_viewport.queue_free()
		ui._close_pile()
	battle.finish_battle(false)
	assert(not runtime.retain_allies and hand.active_cards.is_empty() and peer.get_cost() == base)
	battle.queue_free()
	await get_tree().process_frame
	assert(definition.card_cost == 4 and definition.effects[0].lifetime == CardEffect.Lifetime.BATTLE)
	print("UNDYING_ARMY_PASS")
	get_tree().quit()
