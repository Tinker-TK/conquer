# 用正式战场和鼠标拖放验证交锋中继续出牌、即时效果与本轮结束清理。
extends Node

var battle: Node2D
var hand: Node2D
var runtime: Node2D
var rounds: BattleRoundManager
var presenter: Control
var _mouse := Vector2.ZERO


func _ready() -> void:
	get_tree().create_timer(25.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func _give_effect(kind: CardEffect.Kind, amount: float, lifetime: CardEffect.Lifetime = CardEffect.Lifetime.BATTLE) -> CardInstance:
	var effect := CardEffect.new()
	effect.kind = kind
	effect.amount = amount
	effect.lifetime = lifetime
	effect.lasting_rounds = 3
	var definition := CardDefinition.new()
	definition.card_name = "交锋出牌测试"
	definition.effects.assign([effect])
	if kind in [CardEffect.Kind.DAMAGE_ZONE, CardEffect.Kind.MUD_ZONE, CardEffect.Kind.DRAW,
		CardEffect.Kind.LOCK_DRAW, CardEffect.Kind.GAIN_ENERGY, CardEffect.Kind.ENERGY_EACH_ROUND,
		CardEffect.Kind.DEATH_ATTACK_AURA, CardEffect.Kind.RANDOM_PLAY]:
		definition.category = CardDefinition.Category.ABILITY
		definition.target = CardDefinition.Target.POSITION
	var card := CardInstance.new(definition)
	hand.hand.append(card)
	hand.hand_changed.emit(hand.hand)
	return card


func _play_effect(kind: CardEffect.Kind, amount: float, point: Vector2, lifetime: CardEffect.Lifetime = CardEffect.Lifetime.BATTLE) -> CardInstance:
	var card := _give_effect(kind, amount, lifetime)
	assert(runtime.try_play(card, point))
	return card


func _motion(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - _mouse
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_mouse = point
	get_viewport().push_input(event, true)


func _click(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _drag_recruit(card: CardInstance, point: Vector2) -> UnitBase:
	var view: UnitCard = presenter.views[card.id]
	_motion(presenter.slots[card.id].position)
	await get_tree().create_timer(0.25).timeout
	var start := view.get_global_transform_with_canvas().origin
	_click(start, true)
	_motion(start + Vector2(0, -70), true)
	await get_tree().process_frame
	assert(get_viewport().gui_is_dragging() and presenter.dragged_card == view)
	var screen_point: Vector2 = presenter.world_to_ui(point)
	_motion(screen_point, true)
	await get_tree().process_frame
	var receiver := battle.card_ui.get_node("PlayerDeployDropZone") as Control
	assert(get_viewport().gui_get_hovered_control() == receiver)
	var local_point := receiver.get_global_transform_with_canvas().affine_inverse() * screen_point
	assert(receiver._can_drop_data(local_point, get_viewport().gui_get_drag_data()))
	receiver._drop_data(local_point, get_viewport().gui_get_drag_data())
	var unit := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	unit.set_physics_process(false)
	_click(screen_point, false)
	await get_tree().process_frame
	assert(not get_viewport().gui_is_dragging())
	return unit


func _run() -> void:
	RunManager.start_new_run(RunStartData.new())
	var first := CardInstance.new(load("res://data/units/soldier.tres"))
	var reserve := CardInstance.new(first.unit_data)
	RunManager.deck.assign([first, reserve])
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 2
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	hand = battle.hand_manager
	runtime = battle.card_runtime
	rounds = battle.battle_round_manager
	presenter = battle.card_ui.get_node("Hand")
	runtime.set_physics_process(false)
	assert(runtime.try_play(first, Vector2(450, 500)))
	var ally := battle.get_node("Entities/TeamA").get_child(0) as UnitBase
	ally.set_physics_process(false)
	var base_attack: int = ally.unit_data.attack
	rounds.current_energy = 99
	rounds.energy_changed.emit(99, rounds.final_energy_max)
	_play_effect(CardEffect.Kind.ATTACK_UP, 2, ally.global_position, CardEffect.Lifetime.RUN)
	_play_effect(CardEffect.Kind.DEATH_ATTACK_AURA, 1, Vector2(700, 500))
	_play_effect(CardEffect.Kind.MUD_ZONE, 25, Vector2(1000, 650))
	var unused := _give_effect(CardEffect.Kind.HEAL_PERCENT, 25)
	var enemy := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamB").add_child(enemy)
	enemy.global_position = Vector2(1400, 500)
	enemy.set_physics_process(false)
	await get_tree().create_timer(presenter.draw_duration + presenter.draw_stagger + 0.2).timeout
	var energy_before := rounds.current_energy
	var discard_before: int = hand.discard_pile.size()
	rounds.start_auto_battle()
	assert(hand.hand.has(reserve) and hand.hand.has(unused) and rounds.current_energy == energy_before)
	assert(hand.discard_pile.size() == discard_before and presenter.views.size() == 2)
	assert(presenter.views[reserve.id].energy_available and presenter.views[unused.id].energy_available)
	var summoned: UnitBase = await _drag_recruit(reserve, Vector2(650, 520))
	assert(hand.board_cards[summoned.get_instance_id()] == reserve)
	assert(rounds.current_energy == energy_before - reserve.get_cost())
	assert(Global.game_phase == Global.GamePhase.AUTO_BATTLE)
	# 目标预览和永久配方在交锋中可立即强化，但只保存一轮的独立效果。
	var attack := _give_effect(CardEffect.Kind.ATTACK_UP, 7, CardEffect.Lifetime.RUN)
	runtime.update_cast_preview(attack, ally.global_position)
	assert(ally.cast_preview_highlight)
	assert(runtime.try_play(attack, ally.global_position))
	assert(ally.unit_data.attack == base_attack + 9 and first.permanent_buffs.size() == 1)
	assert(attack.definition.effects[0].lifetime == CardEffect.Lifetime.RUN)
	_play_effect(CardEffect.Kind.DEFENCE_UP, 3, ally.global_position, CardEffect.Lifetime.ROUNDS)
	_play_effect(CardEffect.Kind.POISON_ON_HIT, 2, ally.global_position)
	_play_effect(CardEffect.Kind.DEATH_EXPLOSION, 1, ally.global_position)
	_play_effect(CardEffect.Kind.MAX_HP_UP, 10, ally.global_position)
	_play_effect(CardEffect.Kind.MUD_ZONE, 50, ally.global_position)
	var fire := _play_effect(CardEffect.Kind.DAMAGE_ZONE, 5, enemy.global_position, CardEffect.Lifetime.ROUNDS)
	assert(ally.unit_data.speed == float(runtime.states[ally.get_instance_id()].base_speed) * 0.5)
	var enemy_hp: int = enemy.current_health
	runtime._physics_process(1.0)
	assert(enemy.current_health == enemy_hp - 5 and fire.definition.effects[0].lasting_rounds == 3)
	# 补给和抽牌当场兑现，成长型能量在交锋中也只补本轮。
	energy_before = rounds.current_energy
	_play_effect(CardEffect.Kind.GAIN_ENERGY, 4, Vector2(700, 500))
	assert(rounds.current_energy == energy_before + 3)
	energy_before = rounds.current_energy
	_play_effect(CardEffect.Kind.ENERGY_EACH_ROUND, 3, Vector2(700, 500))
	assert(rounds.current_energy == energy_before + 2 and rounds.pending_recurring_energy == 0)
	var drawn := CardInstance.new(first.definition)
	hand.draw_pile.assign([drawn])
	_play_effect(CardEffect.Kind.DRAW, 1, Vector2(700, 500))
	assert(hand.hand.has(drawn) and presenter.views.has(drawn.id))
	_play_effect(CardEffect.Kind.LOCK_DRAW, 0, Vector2(700, 500))
	var blocked_draw := _give_effect(CardEffect.Kind.DRAW, 1)
	energy_before = rounds.current_energy
	assert(not runtime.try_play(blocked_draw, Vector2(700, 500)) and rounds.current_energy == energy_before)
	_play_effect(CardEffect.Kind.DEATH_ATTACK_AURA, 2, Vector2(700, 500))
	summoned.take_effect_damage(9999)
	assert(ally.unit_data.attack == base_attack + 12)
	assert(hand.discard_pile.count(reserve) == 1)
	# 暂停或能量不足不能吞牌，交锋中的复制也继承当前临时强化。
	get_tree().paused = true
	assert(not runtime.try_play(unused, ally.global_position))
	get_tree().paused = false
	rounds.current_energy = 0
	assert(not runtime.try_play(unused, ally.global_position) and hand.hand.has(unused))
	rounds.gain_energy(99)
	_play_effect(CardEffect.Kind.COPY_ALLY, 0, ally.global_position)
	var copied := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	copied.set_physics_process(false)
	assert(copied.unit_data.attack == ally.unit_data.attack)
	# 随机征召和收回也走交锋中的正式入口，收回仍不冒充死亡。
	var returned := CardInstance.new(first.definition)
	hand.draw_pile.assign([returned])
	_play_effect(CardEffect.Kind.RANDOM_PLAY, 1, Vector2(700, 500))
	var random_unit := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	random_unit.set_physics_process(false)
	assert(hand.board_cards[random_unit.get_instance_id()] == returned)
	assert(battle.is_deployment_position(random_unit.global_position))
	# 收回检查使用固定合法落点，避免随机征召的全导航落点与卡牌矩形范围混在同一断言中。
	random_unit.global_position = Vector2(600, 500)
	_play_effect(CardEffect.Kind.RECALL_ALLY, 0, random_unit.global_position)
	assert(hand.hand.has(returned) and returned.cost_increase == 0 and runtime.ally_deaths == 1)
	if "--combat-card-preview" in OS.get_cmdline_user_args():
		await get_tree().create_timer(presenter.draw_duration + 0.2).timeout
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("res://.maintenance/combat-card-preview.png") == OK)
	# 在回合末信号中检验撤销，避免清场把对象删掉后掩盖残留效果。
	var cleaned: Array[bool] = [false]
	rounds.battle_round_ended.connect(func():
		assert(ally.unit_data.attack == base_attack + 3)
		assert(runtime.states[ally.get_instance_id()].poison_on_hit == 0)
		assert(runtime.states[ally.get_instance_id()].explosions.is_empty())
		assert(ally.unit_data.max_hp == first.unit_data.max_hp)
		assert(runtime.zones.size() == 1 and runtime.death_attack_per_unit == 1)
		assert(ally.unit_data.speed == runtime.states[ally.get_instance_id()].base_speed)
		cleaned[0] = true)
	enemy.take_effect_damage(9999)
	rounds.finish_unit_combat()
	assert(rounds.battle_state == BattleRoundManager.BattleState.DAMAGE_SETTLEMENT and cleaned[0])
	energy_before = rounds.current_energy
	assert(not runtime.try_play(unused, ally.global_position) and not rounds.try_spend_energy(0))
	assert(not presenter.views[unused.id].energy_available)
	await rounds.settlement_finished
	assert(hand.hand.is_empty() and hand.board_cards.is_empty())
	for remaining in [unused, drawn, blocked_draw, returned]:
		assert(hand.discard_pile.count(remaining) == 1)
	assert(hand.discard_pile.count(first) == 1 and hand.discard_pile.count(reserve) == 1)
	assert(not hand.draw_locked and first.permanent_buffs.size() == 1)
	await get_tree().process_frame
	assert(rounds.current_round == 2 and rounds.current_energy == rounds.final_energy_max)
	assert(rounds.pending_recurring_energy == 0 and rounds.recurring_energy == 0)
	assert(runtime.zones.size() == 1 and runtime.death_attack_per_unit == 1)
	# 提前胜负也会结束效果并弃置手牌。
	battle.finish_battle(false)
	assert(hand.hand.is_empty() and runtime.zones.is_empty())
	assert(not runtime.try_play(unused, Vector2(700, 500)))
	battle.queue_free()
	await get_tree().process_frame
	print("COMBAT_CARD_PLAY_PASS: live drag, recruitment, preview, immediate effects, energy, draw, cleanup, settlement lock")
	get_tree().quit()
