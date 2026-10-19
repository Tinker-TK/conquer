# 用 battle_006 的真实坡口、身体碰撞和准备阶段指令回归多人切层，包含同帧落点竞争。
extends Node2D

var terrain: NavigationRegion2D
var units: Array[UnitBase] = []
var goals: Dictionary = {}
var failures: Array[String] = []
var checks := 0
var overlaps: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _physics_process(_delta: float) -> void:
	for unit: UnitBase in goals:
		var task: Dictionary = goals[unit]
		if task.get("native", false):
			continue
		if unit.floor_id == task.floor and unit.global_position.distance_to(task.point) < 8.0:
			unit.navigation_agent_2d.stop_navigation()
		else:
			unit.navigation_agent_2d.move_to(task.point, task.floor)
	for i in units.size():
		for j in range(i + 1, units.size()):
			var first := units[i]
			var second := units[j]
			if first.floor_id == second.floor_id and first.global_position.distance_to(second.global_position) \
				< first.navigation_agent_2d.radius + second.navigation_agent_2d.radius - 0.5:
				overlaps[Vector2i(i, j)] = true

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _unit(point: Vector2, floor_id: int, scene_name: String = "orc") -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/%s.tscn" % scene_name).instantiate()
	unit.position = point
	unit.floor_id = floor_id
	add_child(unit)
	units.append(unit)
	return unit

func _clear() -> void:
	check(overlaps.is_empty(), "全过程同层身体不重叠：%s" % [overlaps.keys()])
	goals.clear()
	for unit in units:
		unit.queue_free()
	units.clear()
	overlaps.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame

func _wait(frames: int) -> void:
	for frame in frames:
		await get_tree().physics_frame

func _done() -> int:
	var count := 0
	for unit: UnitBase in goals:
		var task: Dictionary = goals[unit]
		if unit.floor_id != task.floor:
			continue
		if task.get("native", false):
			count += 1 if unit.target_position == null else 0
		elif unit.global_position.distance_to(task.point) < 8.0:
			count += 1
	return count

func _until_done(limit: int = 1200) -> void:
	for frame in limit:
		await get_tree().physics_frame
		if _done() == goals.size():
			return

func _spot_list(anchor: Vector2, floor_id: int, count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var offsets: Array[Vector2] = []
	for y in range(-4, 5):
		for x in range(-4, 5):
			offsets.append(Vector2(x, y) * 48.0)
	offsets.sort_custom(func(a: Vector2, b: Vector2): return a.length_squared() < b.length_squared())
	for offset in offsets:
		var point := anchor + offset
		if terrain.is_walkable(point, floor_id) and terrain.path_distance(anchor, point, floor_id) < INF:
			result.append(point)
		if result.size() == count:
			break
	return result

func _passage(link: Node2D, fixture: Dictionary) -> void:
	for other in terrain.transitions:
		other.enabled = other == link
	terrain._route_cache.clear()
	var low: Vector2 = link.entry_point(1)
	var high: Vector2 = link.entry_point(2)
	var lower_goal := Vector2(fixture.lower_start[0], fixture.lower_start[1])
	var upper_goal := Vector2(fixture.upper_goal[0], fixture.upper_goal[1])
	var upper := _unit(high, 2)
	var lower := _unit(low, 1)
	goals[upper] = {"point": lower_goal, "floor": 1}
	goals[lower] = {"point": upper_goal, "floor": 2}
	await _until_done(600)
	check(_done() == 2, "%s双向对冲均可通过" % link.name)
	await _clear()

	upper = _unit(high, 2)
	lower = _unit(low + Vector2(0, 24), 1)
	lower.navigation_agent_2d.stop_navigation()
	var stationary := lower.global_position
	goals[upper] = {"point": lower_goal, "floor": 1}
	await _until_done(600)
	check(_done() == 1, "%s出口旁站人仍可下楼" % link.name)
	check(lower.global_position.is_equal_approx(stationary), "不会强制移动出口旁站定的单位")
	await _clear()

	for scene_name in ["soldier", "knight"]:
		var starts := _spot_list(upper_goal, 2, 6)
		var destination := low + (low - high).normalized() * 20.0
		for start in starts:
			var unit := _unit(start, 2, scene_name)
			unit.move_floor_id = 1
			unit.target_position = destination
			goals[unit] = {"point": destination, "floor": 1, "native": true}
		await _until_done(1800)
		var positions := []
		for unit in units:
			positions.append("%s:%s" % [unit.floor_id, unit.global_position])
		check(units.size() == 6 and _done() == 6, "%s六名%s点击近处出口后均下楼并站定：%s" % [link.name, scene_name, positions])
		for unit in units:
			check(unit.global_position.distance_to(low) >= link.exit_clearance(unit) - 0.5,
				"%s让开楼梯出口后才停止" % scene_name)
		await _clear()

	# 同一帧连续提交两个切层，物理服务器尚未同步时也不得分配同一个落点。
	upper = _unit(high, 2)
	lower = _unit(high + Vector2(48, 0), 2)
	await _wait(2)
	check(link.transfer(upper), "第一个同帧请求获得安全落点")
	lower.global_position = high
	check(link.transfer(lower), "第二个同帧请求选择另一个落点")
	check(upper.global_position.distance_to(lower.global_position) >= 30.0, "同帧落点预留避免重叠")
	await _clear()

	# 整个局部出口都被身体占住时只能等待，不能通过扩大搜索范围把人送往远处。
	upper = _unit(high, 2)
	lower = _unit(low, 1)
	var occupied := CircleShape2D.new()
	occupied.radius = link.landing_search_radius + 30.0
	lower.get_node("CollisionShape2D").shape = occupied
	await _wait(2)
	for attempt in 3:
		check(not link.transfer(upper) and upper.floor_id == 2 and upper.global_position.is_equal_approx(high),
			"出口无空位时留在入口等待，不重叠或远距离跳过拥堵")
	units.erase(lower)
	lower.queue_free()
	await _wait(2)
	check(link.transfer(upper) and upper.floor_id == 1, "出口腾空后等待单位恢复下楼")
	await _clear()

	# 即使导航图仍显示原地可走，动态增加的实心地形也不能被候选落点跳过去。
	var wall := StaticBody2D.new()
	wall.position = low
	wall.collision_layer = 8
	wall.collision_mask = 0
	var body := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	body.shape = circle
	wall.add_child(body)
	add_child(wall)
	upper = _unit(high, 2)
	await _wait(2)
	check(not link.transfer(upper) and upper.floor_id == 2, "地形封住出口时保持原楼层，不穿墙")
	wall.queue_free()
	await _wait(2)
	check(link.transfer(upper), "地形移除后出口恢复通行")
	await _clear()

	upper = _unit(high, 2)
	link.bidirectional = false
	check(not link.transfer(upper) and upper.floor_id == 2, "单向楼梯仍禁止反向切层")
	link.bidirectional = true
	link.enabled = false
	check(not link.transfer(upper) and upper.floor_id == 2, "关闭楼梯仍禁止切层")
	link.enabled = true
	await _clear()

func _run() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/battle_006_movement.json"))
	var battle: Node = load(fixtures.scene).instantiate()
	var level: Node2D = battle.get_node("Level")
	terrain = level.get_node("NavigationRegion2D")
	battle.remove_child(level)
	level.owner = null
	add_child(level)
	battle.free()
	await _wait(30)
	for fixture: Dictionary in fixtures.passages:
		await _passage(terrain.get_node(fixture.path), fixture)
	print("STAIR_CROWD_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
