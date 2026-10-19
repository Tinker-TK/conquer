# 真实战场输入：九宫格框选不能吞掉松开事件，右键提示必须与整队实际导航落点一致。
extends Node

var checks := 0
var failures: Array[String] = []
var battle
var selection
var camera: Camera2D
var mouse := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(30.0, true, false, true).timeout.connect(func(): get_tree().quit(1))
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


func _button(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	get_viewport().push_input(event, true)


func _right_click(world_point: Vector2) -> void:
	var screen_point: Vector2 = battle.get_canvas_transform() * world_point
	_motion(screen_point)
	_button(screen_point, MOUSE_BUTTON_RIGHT, true)
	_button(screen_point, MOUSE_BUTTON_RIGHT, false)


func _unit(scene_name: String, point: Vector2) -> UnitBase:
	var unit := load("res://scenes/units/%s.tscn" % scene_name).instantiate() as UnitBase
	unit.unit_data = unit.unit_data.duplicate()
	unit.unit_data.max_hp = 1000
	battle.get_node("Entities/TeamA" if unit.unit_data.unit_team == "team_a" else "Entities/TeamB").add_child(unit)
	unit.global_position = point
	unit.set_physics_process(false)
	return unit


func _shot(resource_name: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.maintenance/pointer-%s.png" % resource_name)


func _run() -> void:
	RunManager.start_new_run()
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	selection = battle.get_node("MouseSlectionController")
	camera = battle.get_node("Camera2D")
	camera._on_window_focus_entered()
	var ally := _unit("soldier", Vector2(450, 450))
	var second := _unit("soldier", Vector2(550, 500))
	var enemy := _unit("orc", Vector2(600, 500))
	for i in 5:
		await get_tree().physics_frame
	check(get_tree().root.has_node("GamePointer") and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "全局像素光标在战场启动且鼠标保持可见")
	# 投影变化时选框四角仍为原图大小，选择仍以世界矩形为准。
	for zoom_value in [1.0, 0.75, 2.0]:
		camera.zoom = Vector2.ONE * zoom_value
		camera.global_position = Vector2(700, 500)
		camera.force_update_scroll()
		var start: Vector2 = battle.get_canvas_transform() * Vector2(400, 400)
		var finish: Vector2 = battle.get_canvas_transform() * Vector2(640, 550)
		_motion(start)
		_button(start, MOUSE_BUTTON_LEFT, true)
		_motion(finish, true)
		check(selection.control.visible and selection.control.get_global_rect().is_equal_approx(Rect2(start, finish - start)), "%s倍缩放后的框选投影正确" % zoom_value)
		if zoom_value == 1.0:
			await _shot("selection")
		_button(finish, MOUSE_BUTTON_LEFT, false)
		check(not selection.control.visible and not selection.is_dragging, "真实松开事件隐藏九宫格选框")
		check(selection.selected_units.has(ally) and selection.selected_units.has(second) and not selection.selected_units.has(enemy), "框选只选择己方单位")
	# 点击不可走的树边：反馈对准导航投影后的落点，一次整队指令只生成一个动画。
	camera.zoom = Vector2.ONE
	camera.global_position = Vector2(960, 540)
	camera.force_update_scroll()
	var map: RID = ally.navigation_agent_2d.get_navigation_map()
	var requested := Vector2(1500, 120)
	var expected := NavigationServer2D.map_get_closest_point(map, requested)
	_right_click(requested)
	var indicator = selection.click_indicator
	check(is_instance_valid(indicator), "右键部署生成提示")
	if not is_instance_valid(indicator):
		get_tree().quit(1)
		return
	check(indicator.global_position.is_equal_approx(expected) and expected.distance_to(requested) > 1.0, "提示显示实际可走落点")
	check(ally.target_position == expected and second.target_position == expected, "整队实际移动目标与提示一致")
	indicator.set_process(false)
	# 相机缩放与平移只改变屏幕投影，动画仍钉在落点，线宽保持可读。
	for zoom_value in [0.75, 2.0]:
		camera.zoom = Vector2.ONE * zoom_value
		camera.global_position += Vector2(50, 30)
		camera.force_update_scroll()
		indicator._update_scale()
		check(indicator.global_position.is_equal_approx(expected) and indicator.get_global_transform_with_canvas().get_scale().is_equal_approx(Vector2.ONE), "镜头变化保持落点和提示屏幕尺寸")
	camera.zoom = Vector2.ONE
	camera.global_position = Vector2(960, 540)
	camera.force_update_scroll()
	_right_click(Vector2(800, 500))
	check(not is_instance_valid(indicator) and is_instance_valid(selection.click_indicator), "重复右键替换旧提示")
	indicator = selection.click_indicator
	indicator.set_process(false)
	await _shot("click-start")
	indicator._process(indicator.DURATION * 0.5)
	await _shot("click-mid")
	# 界面消耗右键后，单位和提示均不能接收移动指令。
	var blocker := Panel.new()
	blocker.position = Vector2(700, 400)
	blocker.size = Vector2(200, 200)
	battle.card_ui.add_child(blocker)
	await get_tree().process_frame
	_right_click(Vector2(760, 450))
	check(selection.click_indicator == indicator and ally.target_position == Vector2(800, 500), "UI 上的右键不生成落点提示或移动单位")
	# 从战场开始的拖框在 UI 上松开也必须清理。
	_motion(Vector2(400, 400))
	_button(Vector2(400, 400), MOUSE_BUTTON_LEFT, true)
	_motion(Vector2(760, 450), true)
	_button(Vector2(760, 450), MOUSE_BUTTON_LEFT, false)
	check(not selection.is_dragging and not selection.control.visible, "UI 上松开不会留下选框")
	blocker.free()
	indicator._process(indicator.DURATION)
	await get_tree().process_frame
	check(not is_instance_valid(indicator), "收束动画按时清理")
	selection.clear_selection()
	_right_click(Vector2(800, 500))
	check(not is_instance_valid(selection.click_indicator), "未选中单位时不显示移动指令提示")
	selection._add_seleted(ally)
	ally.is_stunned = true
	_right_click(Vector2(800, 500))
	check(not is_instance_valid(selection.click_indicator), "无法移动的单位不产生误导提示")
	ally.is_stunned = false
	_right_click(Vector2(800, 500))
	_motion(Vector2(400, 400))
	_button(Vector2(400, 400), MOUSE_BUTTON_LEFT, true)
	_motion(Vector2(500, 500), true)
	get_tree().paused = true
	check(not selection.control.visible and not selection.is_dragging, "暂停时清理拖框")
	get_tree().paused = false
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await get_tree().process_frame
	check(not is_instance_valid(selection.click_indicator), "离开部署阶段清理落点动画")
	battle.queue_free()
	await get_tree().process_frame
	print("POINTER_INTERACTION_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
