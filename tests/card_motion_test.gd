# 这玩意儿是干嘛的（核心逻辑）：用正式战场验证圆弧手牌、能量光效、真实鼠标拖放与连续动画。
# 数据是咋流动的（数据流向）：真实抽牌与出牌入口 → UI 卡面与鼠标事件 → 牌堆、能量和动画节点断言。
# 为啥这么写（选型决策）：鼠标事件经过 Godot 视口，能发现单独调用函数看不到的零尺寸命中和置顶问题。
# 性能咋样（复杂度）：仅手动验收运行；最多十二张牌，完成后关闭测试战场。
extends Node

var battle: Node2D
var hand: Node2D
var rounds: BattleRoundManager
var presenter: Control
var cards: Array[CardInstance] = []
var _last_mouse_position := Vector2.ZERO


# 作用：Godot 入树时安排验收并防止失败后无限运行；没有参数，没有返回值。
func _ready() -> void:
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


# 作用：生成有低费和高费的测试牌；count 是张数，没有返回值。
func _make_cards(count: int) -> void:
	for i in count:
		var card := CardInstance.new(load("res://data/units/soldier.tres"))
		card.definition.card_name = "征召 %d" % (i + 1)
		card.definition.card_cost = 1 if i % 2 == 0 else 4
		cards.append(card)
	RunManager.deck.assign(cards)


# 作用：模拟鼠标移到某个屏幕位置；point 是位置，held 表示是否按着左键，没有返回值。
func _motion(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - _last_mouse_position
	_last_mouse_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	get_viewport().push_input(event, true)


# 作用：模拟按下或松开左键；point 是屏幕位置，pressed 是按下与否，没有返回值。
func _click(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	get_viewport().push_input(event, true)


# 作用：更新正式回合能量并发送正式 UI 信号；energy 是新剩余能量，没有返回值。
func _energy(energy: int) -> void:
	rounds.current_energy = energy
	rounds.energy_changed.emit(energy, rounds.final_energy_max)


# 作用：向正式卡面发送点击、拖动与松开事件；view 是原卡面，point 是屏幕落点，没有返回值。
func _drag(view: UnitCard, point: Vector2) -> void:
	var start: Vector2 = presenter.slots[view.card_instance.id].position
	_motion(start)
	await get_tree().create_timer(0.25).timeout
	start = view.get_global_transform_with_canvas().origin
	_motion(start)
	_click(start, true)
	_motion(start + Vector2(0.0, -70.0), true)
	await get_tree().process_frame
	assert(get_viewport().gui_is_dragging(), "真实鼠标无法从中心式卡面开始拖放")
	assert(presenter.dragged_card == view and is_zero_approx(view.modulate.a))
	_motion(point, true)
	await get_tree().process_frame
	# 合成事件不会移动操作系统鼠标；正式接收区用事件坐标结算，再发送松开来结束原生拖放。
	var receiver := battle.card_ui.get_node("PlayerDeployDropZone") as Control
	assert(get_viewport().gui_get_hovered_control() == receiver)
	var local_point := receiver.get_global_transform_with_canvas().affine_inverse() * point
	receiver._drop_data(local_point, get_viewport().gui_get_drag_data())
	# 上面已按合成坐标结算；原生松开仅结束拖放，不能按系统鼠标位置再施放一次。
	get_viewport().gui_cancel_drag()
	_click(point, false)
	await get_tree().process_frame
	assert(not get_viewport().gui_is_dragging())


# 作用：保存真实渲染结果；name 是截图名称，没有返回值，只有预览模式执行。
func _capture(resource_name: String) -> void:
	if not "--card-motion-preview" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image != null and not image.is_empty())
	image.save_png("res://.maintenance/card-motion-" + resource_name + ".png")


# 作用：检查布局、能量、悬停、拖放和连锁牌堆操作；没有参数，没有返回值。
func _run() -> void:
	_make_cards(12)
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	hand = battle.hand_manager
	rounds = battle.battle_round_manager
	presenter = battle.card_ui.get_node("Hand")
	await get_tree().process_frame
	_energy(3)
	hand.draw_pile.assign(cards)
	hand.draw_cards(8)
	assert(presenter.views.size() == 8 and presenter.entering.size() == 8)
	await get_tree().create_timer(presenter.draw_duration + 7 * presenter.draw_stagger + 0.15).timeout
	assert(presenter.entering.is_empty())
	# 中间卡更高、两边向外旋转，且同名或同配方的每张具体牌都有独立卡面。
	var first: UnitCard = presenter.views[hand.hand[0].id]
	var middle: UnitCard = presenter.views[hand.hand[3].id]
	var last: UnitCard = presenter.views[hand.hand[7].id]
	assert(first.rotation < 0.0 and last.rotation > 0.0)
	assert(first._has_point(Vector2(-137, -179)), "突出的费用徽章也应能命中卡面")
	assert(first.position.y > middle.position.y and last.position.y > middle.position.y)
	for card in hand.hand:
		var view: UnitCard = presenter.views[card.id]
		assert(view.energy_available == (card.get_cost() <= 3))
		assert(view.glow.visible == view.energy_available)
	await _capture("fan")
	# 用鼠标移动触发悬停，卡面扶正、放大、抬高，并真实成为鼠标命中的最上层。
	var base: Vector2 = presenter.slots[middle.card_instance.id].position
	_motion(base)
	await get_tree().create_timer(0.3).timeout
	var hovered: UnitCard = presenter.hovered_card
	assert(hovered != null and is_zero_approx(hovered.rotation))
	assert(is_equal_approx(hovered.scale.x, presenter.hover_scale))
	assert(hovered.position.y < base.y - 80.0)
	_motion(hovered.position + Vector2(0.0, -50.0))
	await get_tree().process_frame
	assert(get_viewport().gui_get_hovered_control() == hovered)
	await _capture("hover")
	_motion(Vector2(950, 350))
	await get_tree().create_timer(0.3).timeout
	assert(presenter.hovered_card == null)
	# 能量降低立即熄灭；零费牌在零能量时仍应发光，增加能量后高费牌重新点亮。
	_energy(0)
	for view: UnitCard in presenter.views.values():
		assert(not view.glow.visible)
	var zero_card := hand.hand[0] as CardInstance
	zero_card.definition.card_cost = 0
	hand.hand_changed.emit(hand.hand)
	assert(presenter.views[zero_card.id].energy_available)
	_energy(8)
	for view: UnitCard in presenter.views.values():
		assert(view.energy_available)
	# 追加抽牌时旧卡面不重建；整手仍在限宽圆弧内。
	var saved_id := middle.get_instance_id()
	hand.draw_cards(4)
	assert(presenter.views[middle.card_instance.id].get_instance_id() == saved_id)
	await get_tree().create_timer(presenter.draw_duration + 3 * presenter.draw_stagger + 0.15).timeout
	assert(presenter.views.size() == 12)
	assert(presenter.slots[hand.hand.back().id].position.x - presenter.slots[hand.hand.front().id].position.x <= presenter.max_hand_width + 1.0)
	await _capture("twelve")
	# 无效落点必须回弹且保留同一原牌与能量；来源卡面隐藏后也不能挡住战场接收区。
	var playable := cards[0]
	var source: UnitCard = presenter.views[playable.id]
	var energy_before := rounds.current_energy
	var invalid_deploy := Vector2(1650, 400)
	assert(not battle.is_deployment_position(invalid_deploy))
	await _drag(source, presenter.world_to_ui(invalid_deploy))
	await get_tree().create_timer(0.35).timeout
	assert(hand.hand.has(playable) and rounds.current_energy == energy_before)
	assert(presenter.views[playable.id] == source and is_equal_approx(source.modulate.a, 1.0))
	assert(source.position.distance_to(presenter.slots[playable.id].position) < 1.0)
	# 相机移动和缩放后仍用同一世界落点，成功出牌只移走使用的原牌。
	var camera := battle.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.position += Vector2(70, 35)
		camera.zoom = Vector2.ONE * 0.9
		camera.force_update_scroll()
	var world_point := Vector2(450, 450)
	var screen_point: Vector2 = presenter.world_to_ui(world_point)
	await _drag(source, screen_point)
	assert(not hand.hand.has(playable) and not presenter.views.has(playable.id))
	assert(rounds.current_energy == energy_before - playable.get_cost())
	assert(presenter.animation_layer.get_child_count() > 0)
	await get_tree().create_timer(0.7).timeout
	assert(presenter.animation_layer.get_child_count() == 0)
	await _test_unit_release(playable)
	# 能力牌飞入弃牌堆；消耗牌进入消耗堆；随机出牌不凭空增加手牌。
	var ability_definition := CardDefinition.new()
	ability_definition.category = CardDefinition.Category.ABILITY
	ability_definition.target = CardDefinition.Target.POSITION
	var energy_effect := CardEffect.new()
	energy_effect.kind = CardEffect.Kind.GAIN_ENERGY
	energy_effect.amount = 1
	ability_definition.effects.assign([energy_effect])
	for exhaust in [false, true]:
		var ability := CardInstance.new(ability_definition.duplicate(true))
		if exhaust:
			ability.definition.after_use = CardDefinition.AfterUse.EXHAUST
		hand.hand.append(ability)
		hand.hand_changed.emit(hand.hand)
		await get_tree().create_timer(presenter.draw_duration + 0.15).timeout
		assert(battle.card_runtime.try_play(ability, world_point))
		assert(hand.exhaust_pile.has(ability) if exhaust else hand.discard_pile.has(ability))
		await get_tree().create_timer(presenter.play_duration + presenter.discard_duration + 0.2).timeout
		assert(presenter.animation_layer.get_child_count() == 0)
	var random_card := CardInstance.new(ability_definition)
	hand.draw_pile.append(random_card)
	var count_before: int = presenter.views.size()
	assert(battle.card_runtime.try_play(random_card, world_point, true, 1, true))
	assert(presenter.views.size() == count_before and hand.discard_pile.has(random_card))
	await get_tree().create_timer(presenter.play_duration + presenter.discard_duration + 0.2).timeout
	# 开打弃牌与紧接着再次抽牌可以重叠，但旧动画不能删掉新一手卡面。
	var discard_count: int = presenter.views.size()
	hand.discard_unused_card()
	assert(presenter.views.is_empty() and presenter.animation_layer.get_child_count() > 0)
	hand.draw_cards(5)
	assert(presenter.views.size() == 5)
	var overlapping_duration: float = maxf(presenter.draw_duration + 4 * presenter.draw_stagger,
		presenter.discard_duration + (discard_count - 1) * presenter.discard_stagger)
	await get_tree().create_timer(overlapping_duration + 0.15).timeout
	assert(presenter.views.size() == 5 and presenter.animation_layer.get_child_count() == 0)
	# 飞入尚未完成就再次弃置，必须停止入口动画并且清理所有临时卡面。
	hand.draw_cards(1)
	discard_count = presenter.views.size()
	hand.discard_unused_card()
	await get_tree().create_timer(presenter.discard_duration + (discard_count - 1) * presenter.discard_stagger + 0.15).timeout
	assert(presenter.entering.is_empty() and presenter.views.is_empty())
	assert(presenter.animation_layer.get_child_count() == 0 and presenter.pending_motions.is_empty())
	await _test_board_discard(playable)
	battle.battle_finished = true
	battle.queue_free()
	await get_tree().process_frame
	print("CARD_MOTION_PASS: fan, hover, glow, mouse drag, draw, discard, play, gold/purple unit ribbons, orbit, tracking, exhaust, board discard, overlapping animations")
	get_tree().quit()


# 作用：真实释放强化牌，检查追踪移动单位、随相机换算、消耗和目标退场后的动画清理；recruit 为已上场原牌，没有返回值。
func _test_unit_release(recruit: CardInstance) -> void:
	var target: UnitBase
	for unit_id: int in hand.board_cards:
		if hand.board_cards[unit_id] == recruit:
			target = instance_from_id(unit_id) as UnitBase
	assert(is_instance_valid(target))
	target.set_physics_process(false)
	var saved_position := target.global_position
	var camera := battle.get_node("Camera2D") as Camera2D
	var saved_camera_position := camera.position
	var saved_zoom := camera.zoom
	var definition := CardDefinition.new()
	definition.card_name = "攻击力提升"
	definition.card_discription = "目标单位攻击力增加 5 点"
	definition.card_image = recruit.definition.card_image
	var effect := CardEffect.new()
	effect.kind = CardEffect.Kind.ATTACK_UP
	effect.amount = 5
	definition.effects.assign([effect])
	var attack := CardInstance.new(definition)
	hand.hand.append(attack)
	hand.hand_changed.emit(hand.hand)
	_energy(99)
	await get_tree().create_timer(presenter.draw_duration + 0.15).timeout
	var view: UnitCard = presenter.views[attack.id]
	var energy_before := rounds.current_energy
	assert(not battle.card_runtime.try_play(attack, Vector2(1600, 800)))
	assert(presenter.views[attack.id] == view and presenter.animation_layer.get_child_count() == 0)
	assert(rounds.current_energy == energy_before)
	var attack_before: int = target.unit_data.attack
	# 松手点偏离单位中心，动画仍须命中实际选择的单位。
	await _drag(view, presenter.world_to_ui(target.global_position + Vector2(30, 10)))
	assert(target.unit_data.attack == attack_before + 5 and hand.discard_pile.count(attack) == 1)
	assert(rounds.current_energy == energy_before - attack.get_cost())
	assert(view.get_parent() == presenter.animation_layer and not view.energy_available)
	var ribbons := _unit_ribbons()
	assert(ribbons.size() == 1)
	var ribbon := ribbons[0]
	var ribbon_duration := ribbon.get_duration()
	assert(ribbon.palette_preset == 1, "己方单位施放光带必须为金色")
	var release_point: Vector2 = presenter.world_to_ui(saved_position + Vector2(30, 10)) + Vector2(0, -28)
	assert(ribbon.start_point.distance_to(release_point) < 1.0, "光带必须从拖动卡面的中心发出")
	assert(ribbon.end_point.distance_to(presenter.world_to_ui(target.global_position)) < 1.0)
	assert(ribbon.point_at(0.0) == ribbon.start_point and ribbon.point_at(1.0) == ribbon.end_point)
	# 实际路径须绕半圈，再向内进入单位。
	var total_angle := 0.0
	var previous := ribbon.point_at(PixelSoulRibbon.ORBIT_APPROACH_END) - ribbon.end_point
	for i in range(1, 33):
		var progress := lerpf(PixelSoulRibbon.ORBIT_APPROACH_END, PixelSoulRibbon.ORBIT_CIRCLE_END, float(i) / 32.0)
		var radial := ribbon.point_at(progress) - ribbon.end_point
		assert(is_equal_approx(radial.length(), presenter.unit_ribbon_radius))
		total_angle += previous.angle_to(radial)
		previous = radial
	assert(is_equal_approx(total_angle, PI))
	assert(ribbon.point_at(PixelSoulRibbon.ORBIT_CIRCLE_END - 0.0001).distance_to(ribbon.point_at(PixelSoulRibbon.ORBIT_CIRCLE_END)) < 1.0, "半圈结束后应连续收束，不能跳回另一侧")
	assert(ribbon.point_at(0.95).distance_to(ribbon.end_point) < presenter.unit_ribbon_radius * 0.3)
	await get_tree().create_timer(presenter.discard_duration * 0.2).timeout
	await _capture("unit-release-flight")
	target.global_position += Vector2(130, 60)
	camera.position += Vector2(70, -40)
	camera.zoom = Vector2.ONE * 0.8
	camera.force_update_scroll()
	await get_tree().create_timer(presenter.discard_duration * 0.65).timeout
	assert(is_instance_valid(view) and view.scale.x < 0.3 and view.modulate.a < 1.0)
	assert(view.position.distance_to(presenter.world_to_ui(target.global_position)) < 80.0)
	assert(ribbon.end_point.distance_to(presenter.world_to_ui(target.global_position)) < 1.0, "镜头和目标移动后光带仍须跟随吸收点")
	assert(ribbon.start_point.distance_to(release_point) < 1.0)
	await _capture("unit-release-absorb")
	var remaining: float = maxf(ribbon_duration, presenter.discard_duration) - presenter.discard_duration * 0.85
	await get_tree().create_timer(remaining + 0.15).timeout
	assert(not is_instance_valid(view))
	assert(presenter.animation_layer.get_child_count() == 0, "光带吸收后必须清理，且不再飞向弃牌堆")
	# 随机施放从抽牌堆飞入单位，真实卡牌仍遵循消耗规则。
	var exhausted := CardInstance.new(definition.duplicate(true))
	exhausted.definition.after_use = CardDefinition.AfterUse.EXHAUST
	hand.draw_pile.append(exhausted)
	var hand_count: int = presenter.views.size()
	assert(battle.card_runtime.try_play(exhausted, target.global_position, true, 1, true))
	assert(presenter.views.size() == hand_count and hand.exhaust_pile.count(exhausted) == 1)
	assert(presenter.animation_layer.get_child_count() == 2 and presenter.pending_motions.is_empty())
	assert(_unit_ribbons()[0].start_point.distance_to(presenter.pile_position("DrawButton")) < 1.0)
	assert(_unit_ribbons()[0].palette_preset == 1)
	await get_tree().create_timer(presenter.unit_ribbon_duration + presenter.unit_ribbon_trail + 0.15).timeout
	assert(presenter.animation_layer.get_child_count() == 0)
	await _test_enemy_unit_ribbon()
	# 释放后立刻收回或清掉目标，弱引用不能留下动画或报错。
	var departing := load("res://scenes/units/soldier.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamA").add_child(departing)
	departing.global_position = Vector2(720, 600)
	departing.set_physics_process(false)
	var final_card := CardInstance.new(definition)
	hand.hand.append(final_card)
	hand.hand_changed.emit(hand.hand)
	assert(battle.card_runtime.try_play(final_card, departing.global_position))
	departing.get_parent().remove_child(departing)
	departing.queue_free()
	await get_tree().create_timer(presenter.unit_ribbon_duration + presenter.unit_ribbon_trail + 0.15).timeout
	assert(presenter.animation_layer.get_child_count() == 0 and presenter.pending_motions.is_empty())
	target.global_position = saved_position
	camera.position = saved_camera_position
	camera.zoom = saved_zoom
	camera.force_update_scroll()


func _unit_ribbons() -> Array[PixelSoulRibbon]:
	var result: Array[PixelSoulRibbon] = []
	for child in presenter.animation_layer.get_children():
		if child is PixelSoulRibbon:
			result.append(child)
	return result


# 作用：对敌军施加减益、同时强化己方，并检查策反不会让紫色光带中途变金。
func _test_enemy_unit_ribbon() -> void:
	var enemy := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamB").add_child(enemy)
	enemy.global_position = Vector2(1120, 550)
	enemy.set_physics_process(false)
	var defence_before: int = enemy.unit_data.defence
	var debuff := CardInstance.new(load("res://data/cards/intimidation.tres"))
	hand.hand.append(debuff)
	hand.hand_changed.emit(hand.hand)
	await get_tree().create_timer(presenter.draw_duration + 0.15).timeout
	var view: UnitCard = presenter.views[debuff.id]
	var source := view.position
	assert(battle.card_runtime.try_play(debuff, enemy.global_position))
	assert(enemy.unit_data.defence < defence_before)
	var purple := _unit_ribbons()[0]
	assert(purple.palette_preset == 2 and purple.start_point.distance_to(source) < 1.0)
	# 同时播放两种阵营，不能共享画布或改变前一条光带的颜色。
	var ally := battle.get_node("Entities/TeamA").get_child(0) as UnitBase
	var buff := CardInstance.new(load("res://data/cards/intimidation.tres").duplicate(true))
	buff.definition.target = CardDefinition.Target.ALLY
	buff.definition.category = CardDefinition.Category.ENHANCEMENT
	buff.definition.effects[0].kind = CardEffect.Kind.DEFENCE_UP
	buff.definition.effects[0].lifetime = CardEffect.Lifetime.BATTLE
	hand.draw_pile.append(buff)
	assert(battle.card_runtime.try_play(buff, ally.global_position, true, 1, true))
	var golden := _unit_ribbons()[1]
	assert(golden.palette_preset == 1 and purple.palette_preset == 2)
	assert(golden.get_node("Display").texture != purple.get_node("Display").texture)
	await get_tree().create_timer(presenter.unit_ribbon_duration * 0.65).timeout
	await _capture("unit-ribbon-teams")
	await get_tree().create_timer(presenter.unit_ribbon_duration * 0.35 + presenter.unit_ribbon_trail + 0.15).timeout
	assert(presenter.animation_layer.get_child_count() == 0)
	var conversion := CardInstance.new(load("res://data/cards/convert_enemy.tres"))
	hand.draw_pile.append(conversion)
	assert(battle.card_runtime.try_play(conversion, enemy.global_position, true, 1, true))
	assert(enemy.unit_data.unit_team == "team_a" and _unit_ribbons()[0].palette_preset == 2)
	await get_tree().create_timer(presenter.unit_ribbon_duration + presenter.unit_ribbon_trail + 0.15).timeout
	assert(presenter.animation_layer.get_child_count() == 0)
	enemy.get_parent().remove_child(enemy)
	enemy.queue_free()


# 作用：实际结算后从单位位置弃牌，并验证同一原牌重抽时旧动画安全结束；card 为已上场原牌，没有返回值。
func _test_board_discard(card: CardInstance) -> void:
	var second := CardInstance.new(card.definition)
	hand.hand.append(second)
	hand.hand_changed.emit(hand.hand)
	_energy(99)
	assert(battle.card_runtime.try_play(second, Vector2(680, 500)))
	await get_tree().create_timer(presenter.play_duration + 0.3).timeout
	assert(presenter.animation_layer.get_child_count() == 0)
	var starts: Dictionary = {}
	var costs: Dictionary = {}
	for unit_id: int in hand.board_cards:
		var unit := instance_from_id(unit_id) as UnitBase
		unit.set_physics_process(false)
		var original: CardInstance = hand.board_cards[unit_id]
		starts[original.id] = presenter.world_to_ui(unit.global_position)
		costs[original.id] = original.get_cost()
	# 无原牌的复制品也会清场，但不应生成额外卡面或弃牌。
	var unbound := load("res://scenes/units/soldier.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamA").add_child(unbound)
	unbound.position = Vector2(720, 600)
	unbound.set_physics_process(false)
	rounds.start_auto_battle()
	await rounds.finish_unit_combat()
	assert(hand.board_cards.is_empty() and battle.get_node("Entities/TeamA").get_child_count() == 0)
	assert(presenter.views.is_empty() and presenter.pending_motions.is_empty())
	var ghosts: Array[Node] = presenter.animation_layer.get_children()
	assert(ghosts.size() == 2)
	for ghost: UnitCard in ghosts:
		var original := ghost.card_instance
		assert(original == card or original == second)
		assert(hand.discard_pile.count(original) == 1 and original.get_cost() == costs[original.id] + 1)
		assert(ghost.position.distance_to(starts[original.id]) < 1.0, "镜头移动缩放后，弃牌仍应从单位的屏幕位置出发")
		assert(not ghost.is_playable and ghost.mouse_filter == Control.MOUSE_FILTER_IGNORE and not ghost.energy_available)
	# 后一张保持在起点等待，前一张已经沿普通弃牌弧线缩小。
	await get_tree().create_timer(presenter.discard_stagger * 0.5).timeout
	assert(ghosts[0].scale.x < presenter.hand_scale)
	assert(ghosts[1].position.distance_to(starts[ghosts[1].card_instance.id]) < 1.0)
	await get_tree().create_timer(presenter.discard_duration * 0.35).timeout
	await _capture("board-discard")
	# 旧卡面尚在飞行时，原牌已经可以洗回并建立独立的新手牌卡面。
	hand.draw_pile.clear()
	hand.discard_pile.assign([card, second])
	hand.draw_cards(2)
	assert(presenter.views.size() == 2 and presenter.animation_layer.get_child_count() == 2)
	for original in [card, second]:
		assert(presenter.views[original.id].get_node("CostIcon/CostLabel").text == str(original.get_cost()))
	var wait_time: float = maxf(presenter.draw_duration + presenter.draw_stagger,
		presenter.discard_duration + presenter.discard_stagger) + 0.2
	await get_tree().create_timer(wait_time).timeout
	assert(presenter.views.size() == 2 and presenter.animation_layer.get_child_count() == 0)
	assert(presenter.pending_motions.is_empty() and presenter.entering.is_empty())
