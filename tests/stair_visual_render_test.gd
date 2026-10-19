# 使用完整 level_107_1 首波和真实 GPU 画面，比较行进中的身体与强制前景参考，捕获“脚底入区前半身被盖住”。
extends Node2D

var failures: Array[String] = []
var comparisons := 0
var checked_units: Dictionary = {}
var output := "res://.maintenance/stair-visual-render"


func _ready() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)


# 直接从当前动画帧读取可见像素，独立于正式寻路脚本的整段动画包围框。
func _screen_body_rect(unit: UnitBase) -> Rect2i:
	var sprite: AnimatedSprite2D = unit.get_node("AnimatedSprite2D")
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	var rect := Rect2(texture.get_image().get_used_rect())
	var size := texture.get_size()
	if sprite.flip_h:
		rect.position.x = size.x - rect.end.x
	if sprite.flip_v:
		rect.position.y = size.y - rect.end.y
	rect.position += sprite.offset - (size * 0.5 if sprite.centered else Vector2.ZERO)
	var screen := sprite.get_global_transform_with_canvas() * rect
	return Rect2i(screen.grow(1.0)).intersection(Rect2i(Vector2i.ZERO, get_viewport().get_visible_rect().size))


func _capture() -> Image:
	await get_tree().process_frame
	# 暂停帧或隐藏窗口可能没有自动重绘，直接提交绘制，避免等待一个不会触发的信号。
	RenderingServer.force_draw(false)
	return get_viewport().get_texture().get_image()


# 暂停同一帧，强制身体放到前景作为参考；两次截图中的身体像素必须完全一致。
func _compare(units: Array[UnitBase], frame: int) -> void:
	get_tree().paused = true
	var actual: Image = await _capture()
	var old_z: Array[int] = []
	for unit in units:
		old_z.append(unit.z_index)
		unit.z_index = 64
	var reference: Image = await _capture()
	for index in units.size():
		var unit := units[index]
		var rect := _screen_body_rect(unit)
		var same := actual.get_region(rect).get_data() == reference.get_region(rect).get_data()
		comparisons += 1
		checked_units[unit.name] = true
		check(same, "第%d帧%s身体被坡道盖住：位置%s" % [frame, unit.name, unit.global_position])
		unit.z_index = old_z[index]
		if not same and failures.size() <= 4:
			actual.save_png("%s/frame-%03d-actual.png" % [output, frame])
			reference.save_png("%s/frame-%03d-reference.png" % [output, frame])
	get_tree().paused = false


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("坡道遮挡像素回归需要图形模式运行")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	# 使用独立完整战场，关闭随时间变化的天气以便同一动画帧逐像素比较。
	get_node("/root/CombatAudio").settings.enabled = false
	RunManager.start_new_run()
	var config: BattleLevelConfig = load("res://data/levels/level_107_1.tres")
	var battle: Node2D = config.battle_scene.instantiate()
	battle.configure_level(config)
	add_child(battle)
	for path in ["RainWeather", "SnowWeather"]:
		var weather := battle.get_node_or_null(path)
		if weather != null:
			weather.set_enabled(false)
	var terrain: Node = battle.get_node("Level/NavigationRegion2D")
	for frame in 30:
		await get_tree().physics_frame
	battle.card_ui.hide()
	battle.get_node("Camera2D").enabled = false
	var camera := Camera2D.new()
	camera.position = Vector2(1660, 507)
	camera.zoom = Vector2(2, 2)
	add_child(camera)
	camera.make_current()
	var ally: UnitBase = load("res://scenes/units/soldier.tscn").instantiate()
	ally.position = NavigationServer2D.map_get_closest_point(terrain.get_floor_map(1), Vector2(400, 700))
	battle.get_node("Entities/TeamA").add_child(ally)
	ally.current_health = 1000000
	ally.set_physics_process(false)
	var enemies: Array[UnitBase] = []
	for unit in battle.get_node("Entities/TeamB").get_children():
		enemies.append(unit)
		unit.current_health = 1000000
	var link: Node2D = terrain.transitions[2]
	battle.battle_round_manager.start_auto_battle()
	for frame in 480:
		await get_tree().physics_frame
		if frame % 6 != 0:
			continue
		var near: Array[UnitBase] = []
		for unit in enemies:
			if unit.floor_id == 1 and unit.global_position.distance_to(link.entry_point(1)) < 130.0 \
				and unit.navigation_agent_2d._floor_route.get("transition") == link:
				near.append(unit)
		if not near.is_empty():
			await _compare(near, frame)
	check(comparisons >= 12 and checked_units.size() == 4, "必须覆盖首波四只怪物接近坡道的实际画面")
	var report := {"comparisons": comparisons, "units": checked_units.keys(), "failures": failures}
	var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("STAIR_VISUAL_RENDER_TEST: ", comparisons, " comparisons; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
