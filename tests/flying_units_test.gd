# 真实单位飞越无导航区域、墙、水面及四层地形，逐帧验证 64 像素升降与自动接敌。
extends Node2D

const FLOORS = preload("res://scripts/world/battle_floor_map.gd")
const FLYERS := ["bumblebee", "imp", "giant_bat", "bat"]
var terrain: Node2D
var units: Array[UnitBase] = []
var checks := 0
var failures: Array[String] = []
var visual_preview := false
var visual_samples := 0
const VISUAL_OUTPUT := "res://.maintenance/checks/flying-visual"


func _ready() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func _unit(id: String, point: Vector2, floor_id: int = 1) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/%s.tscn" % id).instantiate()
	unit.position = point
	unit.floor_id = floor_id
	add_child(unit)
	units.append(unit)
	return unit


func _clear() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	for unit in units:
		if is_instance_valid(unit):
			unit.queue_free()
	units.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _travel(unit: UnitBase, goal: Vector2, goal_floor: int, limit: int = 900) -> Dictionary:
	var vertical_steps: Array[float] = []
	var step_frames: Array[int] = []
	var step := 0.0
	var frames := 0
	var visited: Array[int] = [unit.floor_id]
	var backwards := 0
	var direction := signf(goal.x - unit.global_position.x)
	for frame in limit:
		await get_tree().physics_frame
		var before := unit.global_position
		unit.navigation_agent_2d.move_to(goal, goal_floor)
		var motion := unit.global_position - before
		if motion.x * direction < -0.01:
			backwards += 1
		if absf(motion.y) > 0.01 and absf(motion.x) < 0.01:
			step += motion.y
			frames += 1
			if visual_preview and frames in [1, 3, 6]:
				await _render_flight_frame(unit)
		if unit.floor_id != visited.back():
			visited.append(unit.floor_id)
			vertical_steps.append(step)
			step_frames.append(frames)
			step = 0.0
			frames = 0
		if unit.floor_id == goal_floor and unit.global_position.distance_to(goal) <= 2.0 \
			and not unit.navigation_agent_2d.is_flight_transitioning():
			break
	unit.navigation_agent_2d.stop_navigation()
	return {"visited": visited, "steps": vertical_steps, "frames": step_frames, "backwards": backwards}


# 同一物理帧比较真实绘制与强制前景，防止爬升/下降的身体被岩壁遮住。
func _render_flight_frame(unit: UnitBase) -> void:
	get_tree().paused = true
	var paused_at := unit.global_position
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var actual := get_viewport().get_texture().get_image()
	var old_z := unit.z_index
	unit.z_index = 1000
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var reference := get_viewport().get_texture().get_image()
	unit.z_index = old_z
	var world_bounds: Rect2 = unit.navigation_agent_2d.get_visual_body_bounds()
	var rect := Rect2i(get_canvas_transform() * world_bounds).grow(1)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, get_viewport().get_visible_rect().size))
	check(rect.has_area() and actual.get_region(rect).get_data() == reference.get_region(rect).get_data(),
		unit.unit_data.unit_name + " 升降时身体不被地形遮住")
	check(unit.global_position == paused_at, "暂停冻结飞行位置")
	visual_samples += 1
	actual.save_png("%s/%s-%02d.png" % [VISUAL_OUTPUT, unit.unit_data.unit_english_name, visual_samples])
	get_tree().paused = false


func _test_without_navigation() -> void:
	var obstacles := Node2D.new()
	add_child(obstacles)
	for index in 5:
		var wall := StaticBody2D.new()
		wall.position = Vector2(-120 + index * 50, 700)
		wall.collision_layer = 1 << (index + 2)
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(16, 160)
		collision.shape = shape
		wall.add_child(collision)
		obstacles.add_child(wall)
	for id in FLYERS:
		var flyer := _unit(id, Vector2(-220, 700))
		check(flyer.unit_data.is_flying and load("res://data/units/%s.tres" % id).is_flying, id + " 正式配置为飞行单位")
		check(flyer.collision_mask == 0 and not flyer.navigation_agent_2d.avoidance_enabled, id + " 不受地面碰撞和避让限制")
		check((flyer.collision_layer & 2) != 0 and (flyer.collision_layer & FLOORS.UNIT_MASK) == 0, id + " 保留敌军命中查询且不挡住地面身体")
		var destination := flyer.resolve_move_destination(Vector2(220, 700))
		check(destination.position == Vector2(220, 700), id + " 无导航时保留原始移动落点")
		var result := await _travel(flyer, destination.position, 1)
		check(flyer.global_position.distance_to(Vector2(220, 700)) < 2.1 and result.backwards == 0 \
			and is_equal_approx(flyer.global_position.y, 700.0), id + " 直线穿过实体及四种楼层墙，不依赖导航")
		await _clear()
	obstacles.queue_free()
	await get_tree().physics_frame
	var ground := _unit("orc", Vector2(100, 700))
	var air := _unit("bat", Vector2(160, 700))
	await get_tree().physics_frame
	check(not ground.unit_data.is_flying and not ground.test_move(ground.global_transform, Vector2(100, 0)), "旧单层地图地面单位可从飞行单位下方通行")
	check(air.can_be_targeted_by(_unit("soldier", Vector2(280, 700))), "飞行单位仍可正常被敌军选中")
	await _clear()


func _build_terrain() -> void:
	var level := Node2D.new()
	level.name = "Level"
	add_child(level)
	terrain = FLOORS.new()
	terrain.name = "NavigationRegion2D"
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color("79a875"))
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(64, 64)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(64, 64)
	atlas.create_tile(Vector2i.ZERO)
	tiles.add_source(atlas, 0)
	for floor_id in range(1, 5):
		var layer := TileMapLayer.new()
		layer.name = "Layer%02d" % floor_id
		layer.tile_set = tiles
		# 上层在屏幕上每层高 64 像素；地面平面投影后的边界分别为 x=256、448、640。
		layer.position.y = -(floor_id - 1) * 64
		layer.modulate = [Color.WHITE, Color("c3d291"), Color("d6b36e"), Color("bf886e")][floor_id - 1]
		var start_x := 0 if floor_id == 1 else 4 + (floor_id - 2) * 3
		var finish_x := 16 if floor_id == 1 else start_x + 3
		for x in range(start_x, finish_x):
			for y in range(2, 7):
				# 一层中间留出无导航水面；飞行应仍照直穿越。
				if floor_id != 1 or x < 2 or x >= 4:
					layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
		terrain.add_child(layer)
	level.add_child(terrain)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _test_four_floors() -> void:
	check(terrain.transitions.is_empty() and terrain.route(Vector2(128, 256), 1, Vector2(750, 64), 4).is_empty(), "四层地形没有任何可用楼梯")
	check(terrain.flight_floor_at_ground(Vector2(260, 256)) == 2 and not terrain.is_walkable(Vector2(260, 192), 2), "飞行以真实瓦片边缘认层，不等到导航留白内才跨层")
	for id in FLYERS:
		var tested_flyer := _unit(id, Vector2(128, 256))
		var travel_result := await _travel(tested_flyer, Vector2(960, 256), 1)
		check(tested_flyer.global_position.distance_to(Vector2(960, 256)) <= 2.0 and travel_result.backwards == 0, id + " 飞过水面和三层高地后到达目标，无折返")
		check(travel_result.visited == [1, 2, 3, 4, 3, 2, 1], id + " 连跨三层高地再逐层下降，楼层不来回抖动")
		check(travel_result.steps.size() == 6, id + " 共执行六次跨层动作")
		for index in travel_result.steps.size():
			check(is_equal_approx(travel_result.steps[index], -64.0 if index < 3 else 64.0), id + " 第%d次跨层向正确方向恰好移动64像素" % (index + 1))
			check(travel_result.frames[index] >= 5 and travel_result.frames[index] <= 7, id + " 第%d次跨层约0.1秒完成" % (index + 1))
		check(tested_flyer.z_index == 0 and tested_flyer.collision_mask == 0 and not tested_flyer.navigation_agent_2d.avoidance_enabled, id + " 跨层后保持飞行碰撞和正确绘制层")
		await _clear()
	var flyer := _unit("bumblebee", Vector2(720, 64), 4)
	var result := await _travel(flyer, Vector2(750, 256), 1)
	check(flyer.floor_id == 1 and flyer.global_position.distance_to(Vector2(750, 256)) <= 2.0, "重叠地形可到达明确指定的桥下落点")
	check(result.visited == [4, 3, 2, 1], "桥下落点不触发重复升降")
	flyer.set_floor(4)
	flyer.global_position = Vector2(700, 64)
	await _travel(flyer, Vector2(750, 64), 4)
	check(flyer.global_position.distance_to(Vector2(750, 64)) <= 2.0, "外部切层和瞬移后正确重置飞行高度")
	await _clear()


func _test_interruptions() -> void:
	var flyer := _unit("bumblebee", Vector2(254, 256))
	var origin := flyer.global_position
	flyer.navigation_agent_2d.move_to(Vector2(400, 192), 2)
	check(flyer.navigation_agent_2d.is_flight_transitioning(), "接触高层边缘立即开始快速上升")
	flyer.set_stunned(true)
	var stopped := flyer.global_position
	for frame in 12:
		await get_tree().physics_frame
	check(flyer.global_position == stopped and not flyer.navigation_agent_2d.is_flight_transitioning(), "眩晕立即停止跨层且没有残余移动")
	flyer.set_stunned(false)
	for frame in 12:
		await get_tree().physics_frame
		flyer.navigation_agent_2d.move_to(Vector2(400, 192), 2)
		if flyer.floor_id == 2:
			break
	check(flyer.floor_id == 2 and is_equal_approx(flyer.global_position.y - origin.y, -64.0), "恢复后补完剩余升幅，总升高仍为64像素")
	var phase_stop := flyer.global_position
	Global.game_phase = Global.GamePhase.ROUND_RESOLVE
	for frame in 12:
		await get_tree().physics_frame
	check(flyer.global_position == phase_stop, "阶段切换不残留飞行移动")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	flyer.global_position = Vector2(254, 256)
	flyer.set_floor(1)
	flyer.navigation_agent_2d.move_to(Vector2(400, 192), 2)
	flyer.set_floor(4)
	check(flyer.floor_id == 4 and not flyer.navigation_agent_2d.is_flight_transitioning() and flyer.z_index == 192,
		"跨层中外部改层立即清除旧升降和绘制状态")
	flyer.global_position = Vector2(700, 64)
	await _travel(flyer, Vector2(750, 64), 4)
	check(flyer.floor_id == 4 and flyer.global_position.distance_to(Vector2(750, 64)) <= 2.0,
		"跨层中瞬移后不会被旧动作拉回原楼层")
	flyer.global_position = Vector2(254, 256)
	flyer.set_floor(1)
	flyer.navigation_agent_2d.move_to(Vector2(400, 192), 2)
	flyer.die()
	stopped = flyer.global_position
	for frame in 8:
		await get_tree().physics_frame
	check(is_instance_valid(flyer) and flyer.global_position == stopped and flyer.collision_layer == 0 \
		and flyer.collision_mask == 0, "跨层时死亡立即停飞并释放碰撞")
	await _clear()


func _test_targeting_and_combat() -> void:
	var flyer := _unit("bumblebee", Vector2(128, 256))
	var upper := _unit("soldier", Vector2(700, 64), 4)
	var distant := _unit("soldier", Vector2(980, 256))
	var ground := _unit("orc", Vector2(300, 256))
	check(flyer.skill_manager.find_nearest_enemy() == upper, "飞行索敌按直线距离选择无楼梯高层目标")
	check(ground.skill_manager.find_nearest_enemy() == distant, "地面单位仍按导航可达性选择一层目标")
	await _clear()
	for id in FLYERS:
		flyer = _unit(id, Vector2(128, 256))
		upper = _unit("soldier", Vector2(750, 64), 4)
		upper.current_health = 10000
		upper.set_physics_process(false)
		Global.game_phase = Global.GamePhase.AUTO_BATTLE
		for frame in 720:
			await get_tree().physics_frame
			if upper.current_health < 10000:
				break
		check(upper.current_health < 10000, id + " 自动飞越无楼梯高地并以真实动画命中目标")
		check(not flyer.navigation_agent_2d.is_flight_transitioning() and flyer.skill_manager.is_casting, id + " 完成升降后才发动攻击")
		await _clear()


func _test_authored_map() -> void:
	if has_node("Level"):
		get_node("Level").free()
	var battle: Node2D = load("res://scenes/levels/battles/battle_005.tscn").instantiate()
	var level: Node2D = battle.get_node("Level")
	battle.remove_child(level)
	level.owner = null
	add_child(level)
	battle.free()
	terrain = level.get_node("NavigationRegion2D")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var link: Node2D = terrain.transitions[0]
	var start: Vector2 = link.entry_point(1) - Vector2(128, 0)
	var finish: Vector2 = link.entry_point(2) + Vector2(128, 0)
	if visual_preview:
		var camera := Camera2D.new()
		camera.position = (start + finish) * 0.5 - Vector2(0, 48)
		camera.zoom = Vector2(2, 2)
		add_child(camera)
		camera.make_current()
	for stairs in terrain.transitions:
		stairs.enabled = false
	for id in FLYERS:
		var flyer := _unit(id, start)
		await _travel(flyer, finish, 2)
		check(flyer.floor_id == 2 and flyer.global_position.distance_to(finish) <= 2.0, id + " 正式第5关关闭全部楼梯后仍可飞上高地")
		await _travel(flyer, start, 1)
		check(flyer.floor_id == 1 and flyer.global_position.distance_to(start) <= 2.0, id + " 正式第5关可反向飞下高地")
		await _clear()


func _run() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	visual_preview = "--flying-preview" in OS.get_cmdline_user_args()
	if visual_preview:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VISUAL_OUTPUT))
		await _test_authored_map()
		check(visual_samples >= 12, "图形验收覆盖四种单位的实际升降动画")
		print("FLYING_VISUAL_TEST: %d samples; failures=%s" % [visual_samples, failures])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	await _test_without_navigation()
	await _build_terrain()
	await _test_four_floors()
	await _test_interruptions()
	await _test_targeting_and_combat()
	await _test_authored_map()
	print("FLYING_UNITS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
