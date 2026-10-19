# 验证四层征召、统一左右分界、相机落点转换，以及正式第5关的高层地形。
extends Node

const FLOORS = preload("res://scripts/world/battle_floor_map.gd")
var battle: Node2D
var checks := 0
var failures: Array[String] = []
var source: Control


func _ready() -> void:
	_run.call_deferred()


func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures.append(label)
		push_error(label)


func _mesh(rectangles: Array[Rect2]) -> NavigationPolygon:
	var mesh := NavigationPolygon.new()
	var vertices := PackedVector2Array()
	for rect in rectangles:
		var start := vertices.size()
		vertices.append_array(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
			rect.end, Vector2(rect.position.x, rect.end.y)]))
		mesh.add_polygon(PackedInt32Array([start, start + 1, start + 2, start + 3]))
	mesh.vertices = vertices
	return mesh


func _open_battle(path: String) -> void:
	battle = load(path).instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	battle.card_runtime.set_physics_process(false)
	source = Control.new()
	add_child(source)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _close_battle() -> void:
	battle.battle_finished = true
	battle.queue_free()
	source.queue_free()
	await get_tree().process_frame


func _drop(point: Vector2, expected_floor: int, label: String) -> void:
	var card := CardInstance.new(load("res://data/units/soldier.tres"))
	var hand: Node = battle.hand_manager
	hand.hand.append(card)
	var rounds: BattleRoundManager = battle.battle_round_manager
	rounds.current_energy = 99
	var team := battle.get_node("Entities/TeamA")
	var before := team.get_child_count()
	var receiver: Control = battle.card_ui.get_node("PlayerDeployDropZone")
	var screen := battle.get_canvas_transform() * point
	var local := receiver.get_global_transform_with_canvas().affine_inverse() * screen
	receiver._drop_data(local, {"kind": &"unit_card", "card_instance": card, "source_card": source})
	check(team.get_child_count() == before + 1, label + "：拖放成功生成单位")
	if team.get_child_count() != before + 1:
		return
	var unit := team.get_children().back() as UnitBase
	unit.set_physics_process(false)
	check(unit.floor_id == expected_floor and unit.move_floor_id == expected_floor, label + "：单位初始化到正确楼层")
	check(unit.global_position.is_equal_approx(point), label + "：相机转换后落点一致")
	check(unit.navigation_agent_2d.get_navigation_map() == unit.floor_map.get_floor_map(expected_floor), label + "：使用对应楼层导航")
	check(unit.z_index == unit.floor_map.get_floor_z_index(expected_floor), label + "：使用对应楼层绘制高度")
	check((unit.collision_layer & FLOORS.UNIT_MASK) == FLOORS.unit_bit(expected_floor)
		and (unit.collision_mask & FLOORS.TERRAIN_MASK) == FLOORS.terrain_bit(expected_floor), label + "：使用对应楼层碰撞")
	check(hand.board_cards.get(unit.get_instance_id()) == card and not hand.hand.has(card)
		and rounds.current_energy == 99 - card.get_cost(), label + "：原牌绑定和扣费正确")


func _run() -> void:
	RunManager.start_new_run(RunStartData.new())
	RunManager.deck.clear()
	await _open_battle("res://scenes/battle/battle_scene.tscn")
	var terrain: NavigationRegion2D = battle.get_node("Level/NavigationRegion2D")
	terrain.global_transform = Transform2D(0.0, Vector2(1.3, 0.8), 0.0, Vector2(180, 60))
	terrain.floor_regions[0].navigation_polygon = _mesh([Rect2(0, 0, 50, 160), Rect2(100, 0, 300, 160)])
	terrain.floor_regions[1].navigation_polygon = _mesh([Rect2(100, 220, 45, 160), Rect2(165, 220, 185, 160)])
	terrain.floor_regions[2].navigation_polygon = _mesh([Rect2(100, 440, 300, 160)])
	terrain.floor_regions[3].navigation_polygon = _mesh([Rect2(100, 660, 250, 160), Rect2(110, 60, 80, 80)])
	await get_tree().physics_frame
	await get_tree().physics_frame
	var camera := battle.get_node("Camera2D") as Camera2D
	for floor_id in range(1, 5):
		var point := terrain.to_global(Vector2(25, 80) if floor_id == 1 else Vector2(190, 80 + (floor_id - 1) * 220))
		check(battle.get_deployment_floor(point) == floor_id, "第%d层左侧导航可部署" % floor_id)
		camera.zoom = Vector2.ONE * (0.75 if floor_id % 2 == 0 else 1.5)
		camera.global_position = point
		camera.force_update_scroll()
		_drop(point, floor_id, "第%d层" % floor_id)
		check(not battle.is_deployment_position(terrain.to_global(Vector2(210, 80 + (floor_id - 1) * 220))),
			"第%d层沿用全图中线，右侧不能部署" % floor_id)
	var overlap := terrain.to_global(Vector2(150, 100))
	check(battle.get_deployment_floor(overlap) == 4, "重叠地形选择最上方可走楼层")
	_drop(overlap, 4, "重叠地形")
	check(not battle.is_deployment_position(terrain.to_global(Vector2(155, 300))), "高层导航缺口不能部署")
	check(not battle.is_deployment_position(terrain.to_global(Vector2(75, 80))), "底层导航缺口不能部署")
	var rejected := CardInstance.new(load("res://data/units/soldier.tres"))
	battle.hand_manager.hand.append(rejected)
	check(not battle.card_runtime.try_play(rejected, terrain.to_global(Vector2(155, 300)))
		and battle.hand_manager.hand.has(rejected) and battle.battle_round_manager.current_energy == 99 - rejected.get_cost(),
		"无效高层落点不吞牌和能量")
	terrain.floor_regions[3].enabled = false
	check(battle.get_deployment_floor(overlap) == 1, "关闭高层导航后落点使用下方可走层")
	check(not battle.is_deployment_position(terrain.to_global(Vector2(190, 740))), "禁用的楼层不能部署")
	terrain.floor_regions[3].enabled = true
	var sampled_floors: Dictionary = {}
	seed(4071)
	for i in 200:
		var point: Vector2 = battle.random_deployment_position()
		var floor_id: int = battle.get_deployment_floor(point)
		check(floor_id > 0, "随机征召落点在合法导航内")
		sampled_floors[floor_id] = true
	check(sampled_floors.size() == 4, "随机征召覆盖四层可走地形")
	# 随机免费征召也必须采用采样点的真实楼层。
	for region: NavigationRegion2D in terrain.floor_regions:
		if region != terrain.floor_regions[2]:
			region.navigation_polygon = null
	var random_card := CardInstance.new(load("res://data/units/soldier.tres"))
	battle.hand_manager.draw_pile.assign([random_card])
	battle.card_runtime._random_play(1, 1)
	var random_unit := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	check(random_unit.floor_id == 3 and battle.hand_manager.board_cards.get(random_unit.get_instance_id()) == random_card,
		"仅第三层有导航时随机征召正确设置楼层和原牌")
	for region: NavigationRegion2D in terrain.floor_regions:
		region.navigation_polygon = null
	check(not battle.is_deployment_position(overlap) and battle.random_deployment_position() == null, "所有楼层无导航时禁止征召")
	await _close_battle()
	await _open_battle("res://scenes/levels/battles/battle_005.tscn")
	terrain = battle.get_node("Level/NavigationRegion2D")
	var upper_polygons := 0
	for polygon: PackedVector2Array in battle.get_deployment_polygons():
		var indices := Geometry2D.triangulate_polygon(polygon)
		if indices.size() < 3:
			continue
		var point := (polygon[indices[0]] + polygon[indices[1]] + polygon[indices[2]]) / 3.0
		if battle.get_deployment_floor(point) != 2:
			continue
		upper_polygons += 1
		if upper_polygons <= 3:
			_drop(point, 2, "正式第5关左侧高地%d" % upper_polygons)
	check(upper_polygons > 0, "正式第5关左侧第二层包含可部署地面")
	await _close_battle()
	print("DEPLOYMENT_FLOORS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
