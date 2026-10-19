# 真实鼠标检查奖励选牌、准备/交锋手牌和暂停中的牌堆；查看不能领取、扣费或创建单位。
extends Node

var checks := 0
var failures: Array[String] = []
var inspector
var battle
var _mouse := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(60.0, true, false, true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func _motion(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - _mouse
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_mouse = point
	get_viewport().push_input(event, true)


func _button(point: Vector2, code: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = code
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and code == MOUSE_BUTTON_LEFT else 0
	get_viewport().push_input(event, true)


func _click(control: Control, code: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var point: Vector2 = control.get_global_transform_with_canvas().origin if control is UnitCard else control.get_global_rect().get_center()
	_motion(point)
	await get_tree().create_timer(0.3, true).timeout
	point = control.get_global_transform_with_canvas().origin if control is UnitCard else control.get_global_rect().get_center()
	_motion(point)
	for pressed in [true, false]:
		_button(point, code, pressed)
		await get_tree().process_frame
	await get_tree().process_frame
	var overlay = get_viewport().get_node_or_null("CardUnitDetails")
	if overlay != null:
		inspector = overlay.inspector


func _shot(resource_name: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.maintenance/card-unit-details-%s.png" % resource_name)


func _effect_card() -> CardInstance:
	var definition := CardDefinition.new()
	definition.card_name = "抽牌测试"
	var effect := CardEffect.new()
	effect.kind = CardEffect.Kind.DRAW
	effect.amount = 1
	definition.effects.append(effect)
	return CardInstance.new(definition)


func _reward() -> void:
	var reward = load("res://scripts/battle/battle_reward_session.gd").new()
	reward.initialize(RunManager, {"gold": 10, "potion_chance": 0, "relic_chance": 0}, 16)
	reward.candidates.assign([load("res://data/units/soldier.tres"), load("res://data/units/knight.tres"), _effect_card().definition])
	var panel = load("res://scripts/ui/battle_reward_panel.gd").new()
	get_tree().root.add_child(panel)
	panel.open_rewards(reward)
	await _click(panel.reward_buttons[1])
	var soldier: UnitCard = panel.card_buttons[0].get_child(0)
	var knight: UnitCard = panel.card_buttons[1].get_child(0)
	var ability: UnitCard = panel.card_buttons[2].get_child(0)
	var deck_size := RunManager.deck.size()
	var gold := RunManager.gold
	await _click(soldier, MOUSE_BUTTON_RIGHT)
	check(inspector != null and inspector.panel.visible and inspector.card_preview == soldier.card_instance, "拿牌阶段真实右键打开兵种详情")
	if inspector == null:
		get_tree().quit(1)
		return
	check(RunManager.deck.size() == deck_size and RunManager.gold == gold and reward.available(1), "右键不会领取、选中或支付奖励")
	check(inspector.health_text.text == "100 / 100" and inspector.stat_labels.attack.get_parsed_text() == "攻击：10", "未部署的兵种展示出场生命和攻击")
	check(inspector.skill_cells.size() == 1 and inspector.skill_cells[0].icon.cooldown_fraction == 0.0, "未强化士兵详情只显示普攻，预览没有伪造冷却")
	check(get_tree().get_nodes_in_group("team_a").is_empty() and get_tree().get_nodes_in_group("team_b").is_empty(), "只读详情不实例化或登记战斗单位")
	await _shot("reward")
	await _click(knight, MOUSE_BUTTON_RIGHT)
	check(inspector.card_preview == knight.card_instance and inspector.unit_title.get_parsed_text().contains(knight.unit_data.unit_name), "右键另一张兵种牌切换同一详情面板")
	check(inspector.skill_cells.any(func(cell): return cell.skill == knight.unit_data.dodge_skill), "卡牌详情包含被动反击技能")
	await _click(ability, MOUSE_BUTTON_RIGHT)
	check(inspector.card_preview == knight.card_instance and reward.available(1), "效果牌右键不会冒充兵种或领取卡牌")
	await _click(inspector.close_button)
	check(not inspector.panel.visible, "关闭按钮可关闭拿牌详情")
	await _click(soldier, MOUSE_BUTTON_RIGHT)
	await _click(soldier)
	check(RunManager.deck.size() == deck_size + 1 and not reward.available(1), "查看后左键仍能正常选择奖励且只获得一张")
	check(not inspector.panel.visible, "完成拿牌后自动收起原卡详情")
	panel.free()


func _battle_cards() -> void:
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	var hand = battle.hand_manager
	var rounds = battle.battle_round_manager
	var presenter = battle.card_ui.hand_presenter
	var trained := CardInstance.new(load("res://data/units/soldier.tres"))
	trained.attack_points = 1
	trained.defence_points = 2
	trained.upgrade_count = 1
	for item in [[CardEffect.Kind.ATTACK_UP, 5], [CardEffect.Kind.MAX_HP_UP, 8], [CardEffect.Kind.POISON_ON_HIT, 2], [CardEffect.Kind.DEATH_EXPLOSION, 15]]:
		var effect := CardEffect.new()
		effect.kind = item[0]
		effect.amount = item[1]
		effect.lifetime = CardEffect.Lifetime.RUN
		trained.permanent_buffs.append({"effect": effect, "label": "永久强化测试"})
	var knight := CardInstance.new(load("res://data/units/knight.tres"))
	var ability := _effect_card()
	RunManager.deck.assign([trained, knight, ability])
	hand.hand.assign([trained, knight, ability])
	hand.hand_changed.emit(hand.hand)
	await get_tree().create_timer(1.0).timeout
	var view: UnitCard = presenter.views[trained.id]
	var units: int = battle.card_runtime.living_units().size()
	rounds.current_energy = 0
	rounds.energy_changed.emit(0, rounds.final_energy_max)
	await _click(view, MOUSE_BUTTON_RIGHT)
	check(inspector.panel.visible and inspector.card_preview == trained, "打牌阶段能量不足仍能右键查看")
	check(inspector.stat_labels.attack.get_parsed_text() == "攻击：16 (+6)" and inspector.stat_labels.defence.get_parsed_text() == "防御：7 (+2)", "本张牌的训练和永久强化计入出场属性及绿色增量")
	check(inspector.health_text.text == "108 / 108" and inspector.status_cells.size() == 6 and inspector.status_cells.has("sword_arrow"), "永久生命、附毒、死亡爆炸和士兵卡强化剑矢均在详情中展示")
	check(trained.unit_data.attack == 10 and trained.unit_data.max_hp == 100 and trained.attack_points == 1, "预览不修改共享兵种资源或训练记录")
	check(hand.hand.size() == 3 and rounds.current_energy == 0 and battle.card_runtime.living_units().size() == units, "查看手牌不出牌、不扣能量、不增加场上单位")
	var icon: Control = inspector.status_cells.poison_on_hit.icon
	_motion(icon.get_global_rect().get_center())
	await get_tree().create_timer(0.15).timeout
	check(inspector.status_tooltip.visible and inspector.status_text.text == "攻击附毒：每次命中叠加 2 层毒", "卡牌详情 Buff 悬停只显示当前生效值")
	await _shot("hand")
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	get_viewport().push_input(key, true)
	await get_tree().process_frame
	check(not inspector.panel.visible and not get_tree().paused, "Esc 仅关闭当前卡牌详情")
	# 查看后仍通过原生鼠标拖放部署同一张牌。
	rounds.current_energy = 99
	rounds.energy_changed.emit(99, rounds.final_energy_max)
	await _click(view, MOUSE_BUTTON_RIGHT)
	await _click(inspector.close_button)
	_motion(presenter.slots[trained.id].position)
	await get_tree().create_timer(0.3).timeout
	var point: Vector2 = view.get_global_transform_with_canvas().origin
	_motion(point)
	_button(point, MOUSE_BUTTON_LEFT, true)
	_motion(point + Vector2(0, -75), true)
	await get_tree().process_frame
	check(get_viewport().gui_is_dragging(), "右键查看后左键仍能拖动兵种牌")
	check(get_viewport().gui_get_drag_data().get("card_instance") == trained, "拖放来源仍是刚查看的原牌")
	var destination: Vector2 = presenter.world_to_ui(Vector2(650, 500))
	_motion(destination, true)
	await get_tree().process_frame
	var receiver: Control = battle.card_ui.get_node("PlayerDeployDropZone")
	check(get_viewport().gui_get_hovered_control() == receiver, "查看后拖牌仍能命中正式部署接收区")
	# 合成事件不移动系统鼠标；与 card-motion 回归一样，用正式接收入口结算事件落点。
	receiver._drop_data(receiver.get_global_transform_with_canvas().affine_inverse() * destination, get_viewport().gui_get_drag_data())
	_button(destination, MOUSE_BUTTON_LEFT, false)
	await get_tree().process_frame
	check(not hand.hand.has(trained) and battle.card_runtime.living_units().size() == units + 1, "正常拖放仍部署单位并移动原牌")
	if battle.get_node("Entities/TeamA").get_child_count() == 0:
		return
	var summoned: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	check(summoned.unit_data.attack == 16 and summoned.unit_data.defence == 7 and summoned.unit_data.max_hp == 108, "详情预览与实际召唤单位数值一致")
	var enemy: UnitBase = load("res://scenes/units/orc.tscn").instantiate()
	enemy.unit_data = enemy.unit_data.duplicate()
	enemy.unit_data.max_hp = 10000
	enemy.position = battle.get_node("Entities/TeamB").to_local(Vector2(900, 500))
	battle.get_node("Entities/TeamB").add_child(enemy)
	await get_tree().physics_frame
	rounds.start_auto_battle()
	await _click(presenter.views[knight.id], MOUSE_BUTTON_RIGHT)
	check(inspector.panel.visible and inspector.card_preview == knight and rounds.battle_state == BattleRoundManager.BattleState.COMBAT, "交锋中仍可右键查看手中兵种牌，战斗继续")
	get_tree().paused = true
	await get_tree().process_frame
	check(not inspector.panel.visible, "暂停收起战斗手牌详情，避免覆盖暂停菜单")
	get_tree().paused = false
	hand.draw_pile.assign([knight])
	battle.card_ui._open_pile("DrawButton")
	await get_tree().process_frame
	var pile = battle.card_ui.pile_view
	var pile_card: UnitCard = pile.grid.get_child(0).get_child(0)
	await _click(pile_card, MOUSE_BUTTON_RIGHT)
	check(get_tree().paused and inspector.panel.visible and inspector.card_preview == knight, "暂停中的牌堆查看也支持兵种右键详情")
	await _click(inspector.close_button)
	check(get_tree().paused and not inspector.panel.visible, "关闭牌堆详情不会提前恢复战斗")
	await _click(pile_card, MOUSE_BUTTON_RIGHT)
	await _click(pile.get_node("Margin/VBox/Header/Close"))
	check(not inspector.panel.visible and not get_tree().paused, "离开牌堆自动收起详情并恢复原暂停状态")
	await _click(presenter.views[knight.id], MOUSE_BUTTON_RIGHT)
	battle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not inspector.panel.visible and inspector.card_preview == null, "来源场景释放后清理详情与原牌引用")


func _run() -> void:
	RunManager.start_new_run()
	await _reward()
	await _battle_cards()
	print("CARD_UNIT_DETAILS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
