# 使用正式卡面拖放和单位贴图检查强化目标，避免只在脚底调用 try_play 的测试漏掉界面遮挡。
extends Node

var checks := 0
var failures: Array[String] = []
var battle
var runtime
var hand
var rounds
var presenter
var camera: Camera2D
var ally: UnitBase
var mouse := Vector2.ZERO


func _ready() -> void:
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit(1))
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
	event.relative = point - mouse
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	mouse = point
	get_viewport().push_input(event, true)


func _button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _card(target: CardDefinition.Target = CardDefinition.Target.ALLY) -> CardInstance:
	var definition := load("res://data/cards/power_enhance.tres").duplicate(true) as CardDefinition
	definition.target = target
	var card := CardInstance.new(definition)
	hand.hand.append(card)
	hand.hand_changed.emit(hand.hand)
	return card


func _drag_to(card: CardInstance, world_point: Vector2, expect_success: bool, label: String) -> void:
	await get_tree().create_timer(presenter.draw_duration + 0.1).timeout
	var view: UnitCard = presenter.views[card.id]
	_motion(presenter.slots[card.id].position)
	await get_tree().create_timer(0.25).timeout
	var start := view.get_global_transform_with_canvas().origin
	_motion(start)
	_button(start, true)
	_motion(start + Vector2(0, -70), true)
	await get_tree().process_frame
	check(get_viewport().gui_is_dragging(), label + "：鼠标能开始拖牌")
	var point: Vector2 = battle.get_canvas_transform() * world_point
	_motion(point, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var receiver := battle.card_ui.get_node("PlayerDeployDropZone") as Control
	var hovered := get_viewport().gui_get_hovered_control()
	if expect_success:
		check(hovered == receiver, label + "：落点不能被透明原卡面挡住（实际 %s）" % (str(hovered.name) if hovered != null else "null"))
		check(runtime.preview_target == ally and ally.cast_preview_highlight, label + "：预览命中同一单位")
	var energy_before: int = rounds.current_energy
	var attack_before: int = ally.unit_data.attack
	# 合成鼠标事件不改变系统鼠标位置；只在引擎确实命中接收区时，按事件落点释放。
	if hovered == receiver:
		var local := receiver.get_global_transform_with_canvas().affine_inverse() * point
		receiver._drop_data(local, get_viewport().gui_get_drag_data())
	get_viewport().gui_cancel_drag()
	_button(point, false)
	await get_tree().process_frame
	check(not get_viewport().gui_is_dragging() and runtime.preview_target == null, label + "：结束拖放清理高亮")
	check(hand.hand.has(card) != expect_success, label + "：牌堆去向正确")
	check(rounds.current_energy == energy_before - (card.get_cost() if expect_success else 0), label + "：按成功与否扣费")
	check(ally.unit_data.attack == attack_before + (int(card.definition.effects[0].amount) if expect_success else 0), label + "：目标属性正确")
	if hand.hand.has(card):
		check(view.mouse_filter == Control.MOUSE_FILTER_STOP and is_equal_approx(view.modulate.a, 1.0), label + "：回弹牌恢复可见与交互")
		hand.hand.erase(card)
		hand.hand_changed.emit(hand.hand)
	await get_tree().create_timer(0.25).timeout


func _run() -> void:
	RunManager.start_new_run(RunStartData.new())
	RunManager.deck.clear()
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	runtime = battle.card_runtime
	hand = battle.hand_manager
	rounds = battle.battle_round_manager
	presenter = battle.card_ui.get_node("Hand")
	camera = battle.get_node("Camera2D")
	runtime.set_physics_process(false)
	presenter.draw_duration = 0.05
	presenter.layout_duration = 0.05
	await get_tree().physics_frame
	await get_tree().physics_frame
	var recruit := CardInstance.new(load("res://data/units/soldier.tres"))
	hand.hand.append(recruit)
	check(runtime.try_play(recruit, Vector2(650, 500)), "通过正式征召建立原牌绑定")
	ally = battle.get_node("Entities/TeamA").get_child(0)
	ally.set_physics_process(false)
	rounds.current_energy = 99
	rounds.energy_changed.emit(99, rounds.final_energy_max)
	await _drag_to(_card(), ally.global_position, true, "普通落点")
	ally.global_position = Vector2(960, 740)
	await _drag_to(_card(), ally.global_position, true, "移入被拖起卡牌原来的范围")
	ally.global_position = Vector2(700, 950)
	check(battle.is_deployment_position(ally.global_position), "底部落点属于真实可部署导航")
	camera.global_position = Vector2(900, 850)
	camera.force_update_scroll()
	await _drag_to(_card(), ally.global_position, true, "旧战场矩形之外的己方单位")
	ally.global_position = Vector2(650, 500)
	camera.global_position = Vector2(900, 520)
	camera.force_update_scroll()
	for zoom_value in [0.75, 2.0]:
		camera.zoom = Vector2.ONE * zoom_value
		camera.global_position = Vector2(650, 500)
		camera.force_update_scroll()
		await _drag_to(_card(), ally.global_position + Vector2(0, -40), true, "%s倍缩放和平移后的身体落点" % zoom_value)
	camera.zoom = Vector2.ONE
	camera.global_position = Vector2(900, 520)
	camera.force_update_scroll()
	var definition := CardDefinition.new()
	# 遍历各兵种实际有像素的待机身体和装备，整张透明图集边缘不作为命中范围。
	for scene_path in DirAccess.get_files_at("res://scenes/units"):
		if not scene_path.ends_with(".tscn") or scene_path == "player_base.tscn":
			continue
		var unit := load("res://scenes/units/" + scene_path).instantiate() as UnitBase
		if unit == null or unit.unit_data == null or unit.unit_data.unit_team != "team_a":
			if unit != null:
				unit.free()
			continue
		battle.get_node("Entities/TeamA").add_child(unit)
		unit.global_position = Vector2(1200, 500)
		unit.set_physics_process(false)
		var sprite := unit.animated_sprite_2d
		sprite.stop()
		sprite.frame = 0
		var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		var image := texture.get_image()
		for flipped in [false, true]:
			sprite.flip_h = flipped
			var missed := 0
			for y in image.get_height():
				for x in image.get_width():
					if image.get_pixel(x, y).a < 0.5:
						continue
					var pixel_x := image.get_width() - x - 0.5 if flipped else x + 0.5
					var local := Vector2(pixel_x, y + 0.5) - texture.get_size() * 0.5 + sprite.offset
					if runtime.pick_target(definition, sprite.to_global(local)) != unit:
						missed += 1
			check(missed == 0, "%s 翻转%s可见身体与装备不得漏判（漏 %d 像素）" % [scene_path, flipped, missed])
			var blank := sprite.to_global(-texture.get_size() * 0.5 + Vector2(5, 5))
			check(runtime.pick_target(definition, blank) == null, scene_path + " 大片透明图集留白不应误选")
		unit.free()
	# 长枪上部超出旧圆圈，仍需通过完整拖放施放；准备和交锋的同一目标都可命中。
	var lancer_card := CardInstance.new(load("res://data/units/lancer.tres"))
	hand.hand.append(lancer_card)
	check(runtime.try_play(lancer_card, Vector2(850, 500)), "正式征召长枪单位")
	var soldier := ally
	ally = battle.get_node("Entities/TeamA").get_children().back()
	ally.set_physics_process(false)
	ally.animated_sprite_2d.stop()
	ally.animated_sprite_2d.frame = 0
	var spear_point := ally.global_position + Vector2(20, -100)
	check(spear_point.distance_to(ally.global_position) > 65, "长枪测试点确实超出旧半径")
	await _drag_to(_card(), spear_point, true, "长枪与上半身落点")
	# 目标附近另一单位的脚底更近时，优先选择鼠标下实际可见的身体。
	soldier.global_position = spear_point + Vector2(0, -60)
	check(runtime.pick_target(definition, spear_point) == ally, "可见身体优先于邻兵脚底的容错圈")
	soldier.global_position = Vector2(450, 500)
	var enemy := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamB").add_child(enemy)
	enemy.global_position = Vector2(1400, 500)
	enemy.set_physics_process(false)
	rounds.start_auto_battle()
	await _drag_to(_card(), spear_point, true, "交锋中的身体落点")
	ally = soldier
	# 多行状态和受伤血条也属于其单位的可见落点。
	ally.current_health -= 1
	ally.get_node("HealthBar").update_hp_bar(ally.current_health)
	var health_panel: Control = ally.get_node("HealthBar/PanelContainer")
	var health_point := health_panel.get_global_transform() * (health_panel.size * 0.5)
	await _drag_to(_card(), health_point, true, "血条落点")
	var status: Control = ally.get_node("HealthBar/StatusDisplay")
	var entries: Array[Dictionary] = []
	for i in 16:
		entries.append({"icon": "fixture_%d" % i, "tooltip": "测试状态"})
	status.set_statuses(entries)
	var icon_point: Vector2 = status.get_global_transform() * status.icon_rect(15).get_center()
	check(icon_point.distance_to(ally.global_position) > 65, "多行状态测试点超出旧半径")
	await _drag_to(_card(), icon_point, true, "多行状态图标落点")
	# 正常的地图位置型效果仍应执行其范围限制。
	var position_card := _card(CardDefinition.Target.POSITION)
	check(not runtime.try_play(position_card, Vector2(700, 950)) and hand.hand.has(position_card), "位置型牌仍受战场范围限制")
	hand.hand.erase(position_card)
	hand.hand_changed.emit(hand.hand)
	ally.current_state = UnitBase.State.DEATH
	check(runtime.pick_target(definition, ally.global_position) == null, "死亡单位不能成为强化目标")
	ally.current_state = UnitBase.State.IDLE
	# 被拖起的原牌可以穿透，其他真实按钮和面板仍应阻止施放。
	var blocker := Panel.new()
	blocker.position = battle.get_canvas_transform() * ally.global_position - Vector2(50, 50)
	blocker.size = Vector2(100, 100)
	battle.card_ui.add_child(blocker)
	await _drag_to(_card(), ally.global_position, false, "真实界面面板遮挡")
	blocker.free()
	await _drag_to(_card(CardDefinition.Target.ENEMY), ally.global_position, false, "敌方专用牌不能强化友军")
	rounds.current_energy = 0
	rounds.energy_changed.emit(0, rounds.final_energy_max)
	await _drag_to(_card(), ally.global_position, false, "能量不足不能吞牌")
	check(battle.card_ui.get_node("CardFeedback").text == "能量不足。", "失败提示显示具体原因")
	battle.battle_finished = true
	battle.queue_free()
	await get_tree().process_frame
	print("CARD_TARGETING_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
