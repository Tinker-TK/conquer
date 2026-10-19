extends Node

var failures: Array[String] = []
const TILESET = preload("res://data/water/river_tileset.tres")
const DIRECTIONS = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const SIDES = [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE]

func _ready() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error("RIVER_TILEMAP: " + label)

func _new_map() -> RiverTileMap:
	var map := RiverTileMap.new()
	map.tile_set = TILESET
	map.weather_path = NodePath()
	map.settings = RiverSettings.new()
	map.settings.height_resolution = 1024
	return map

func _run() -> void:
	get_tree().create_timer(50.0).timeout.connect(func(): get_tree().quit(2))
	_check(TILESET.get_source(0).get_tiles_count() == 16 and TILESET.get_source(1).get_tiles_count() == 47,
		"native atlas must include all 16 channel and 47 water variants")
	var map := _new_map()
	var cells: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(-1, 0), Vector2i.ZERO,
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)]
	map.set_cells_terrain_connect(cells, 0, 0, false)
	add_child(map)
	await get_tree().process_frame
	for cell in cells:
		var data := map.get_cell_tile_data(cell)
		for side in 4:
			_check((data.get_terrain_peering_bit(SIDES[side]) == 0) == cells.has(cell + DIRECTIONS[side]),
				"native terrain brush must choose correct channel edge %s side %d" % [cell, side])
		_check(map.is_water_point(map.to_global(map.map_to_local(cell))), "painted channel center must flood " + str(cell))
	_check(not map.is_bed_point(map.to_global(map.map_to_local(Vector2i(3, 0)))), "unpainted cells retain ground")
	# Per-cell levels remain independent of global level, and fallback follows the global value.
	map.set_cell_water_level(Vector2i.ZERO, 0.0)
	_check(not map.is_water_point(map.to_global(map.map_to_local(Vector2i.ZERO))), "single cell may be dry")
	_check(map.is_water_point(map.to_global(map.map_to_local(Vector2i(1, 0)))), "neighbor cell retains its level")
	map.set_water_level(0.0)
	map.set_cell_water_level(Vector2i.ZERO, 0.8)
	_check(map.is_water_point(map.to_global(map.map_to_local(Vector2i.ZERO))), "cell override works when global level is zero")
	map.clear_cell_water_level(Vector2i.ZERO)
	_check(not map.is_water_point(map.to_global(map.map_to_local(Vector2i.ZERO))), "clearing override restores global level")
	map.set_water_level(0.66)
	# Editing native cells must immediately change the surface; no baked layout is reinstated.
	map.erase_cell(Vector2i(1, 0))
	await get_tree().create_timer(0.3).timeout
	_check(not map.is_bed_point(map.to_global(map.map_to_local(Vector2i(1, 0)))), "erasing a tile must remove bed and water")
	map.set_cell(Vector2i(4, 0), 0, Vector2i(2, 2), TileSetAtlasSource.TRANSFORM_TRANSPOSE)
	await get_tree().create_timer(0.3).timeout
	var center := map.map_to_local(Vector2i(4, 0))
	_check(map.is_bed_point(map.to_global(center + Vector2(0, 55))), "transposed horizontal tile opens vertically")
	_check(not map.is_bed_point(map.to_global(center + Vector2(55, 0))), "transposed tile closes horizontal banks")
	map.set_cell_water_level(Vector2i(4, 0), 0.4)
	var packed := PackedScene.new()
	_check(packed.pack(map) == OK and ResourceSaver.save(packed, "res://.maintenance/river-cells-roundtrip.tscn") == OK,
		"native tile layout must save as a normal scene")
	var restored := (load("res://.maintenance/river-cells-roundtrip.tscn") as PackedScene).instantiate() as RiverTileMap
	_check(restored.tile_map_data == map.tile_map_data and restored.cell_water_levels == map.cell_water_levels,
		"scene reload must preserve tiles and per-cell overrides")
	_check(restored.get_child_count(true) == 0, "generated surface must never be serialized into user layout")
	restored.free()
	map.queue_free()
	await get_tree().process_frame
	var lake := _new_map()
	var lake_cells: Array[Vector2i] = []
	for y in 3:
		for x in 3:
			if Vector2i(x, y) != Vector2i(1, 1):
				lake_cells.append(Vector2i(x, y))
	lake.set_cells_terrain_connect(lake_cells, 1, 0, false)
	add_child(lake)
	_check(not lake.is_bed_point(lake.to_global(lake.map_to_local(Vector2i(1, 1)))), "empty lake cell must remain an island")
	for cell in lake_cells:
		_check(lake.is_water_point(lake.to_global(lake.map_to_local(cell))), "painted lake cell must contain water " + str(cell))
	# Adjacent connected edges have matching heights and no transparent strip.
	var seam_errors := 0
	for x in range(119, 138):
		for y in range(44, 85, 2):
			if not lake.is_bed_point(Vector2(x, y)):
				seam_errors += 1
	_check(seam_errors == 0, "connected lake tiles must join without alpha gaps")
	lake.queue_free()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await _check_render()
	print("RIVER_TILEMAP_PASS: failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture(surface: DynamicRiver, time: float) -> Image:
	surface._water_material.set_shader_parameter("clock_time", time)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_tree().root.get_texture().get_image()

func _check_render() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(768, 512)
	RenderingServer.set_default_clear_color(Color.BLACK)
	var map := _new_map()
	map.position = Vector2(64, 64)
	var cells: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 0),
		Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)]
	map.set_cells_terrain_connect(cells, 0, 0, false)
	add_child(map)
	map.surface.set_process(false)
	map.set_cell_water_level(Vector2i(2, 1), 0.0)
	var a := await _capture(map.surface, 0.0)
	var b := await _capture(map.surface, 3.0)
	var moving := 0
	var dry_errors := 0
	for y in range(0, 512, 4):
		for x in range(0, 768, 4):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				moving += 1
				if not map.is_water_point(Vector2(x, y)):
					dry_errors += 1
	_check(moving > 200 and dry_errors == 0, "tile animation must affect only wet pixels, including per-cell levels")
	var material := map.surface._water_material
	material.set_shader_parameter("bed_color", Color.BLACK)
	material.set_shader_parameter("bank_color", Color.BLACK)
	material.set_shader_parameter("shallow_color", Color(0, 1, 1))
	material.set_shader_parameter("deep_color", Color(0, 1, 1))
	material.set_shader_parameter("shallow_opacity", 1.0)
	material.set_shader_parameter("deep_opacity", 1.0)
	material.set_shader_parameter("foam_width", 0.0)
	material.set_shader_parameter("caustics_strength", 0.0)
	var frame := await _capture(map.surface, 0.0)
	var mismatch := 0
	for y in range(0, 512, 4):
		for x in range(0, 768, 4):
			if (frame.get_pixel(x, y).g > 0.9) != map.is_water_point(Vector2(x, y)):
				mismatch += 1
	_check(mismatch == 0, "GPU/CPU per-cell water coverage must agree; mismatches=%d" % mismatch)
	map.queue_free()
	await get_tree().process_frame
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	var demo := preload("res://scenes/testing/river_tiles_demo.tscn").instantiate()
	add_child(demo)
	await get_tree().process_frame
	demo.river.surface.set_process(false)
	demo.weather.set_process(false)
	for i in 12:
		demo.river.set_water_level(0.58 + sin(float(i) * TAU / 12.0) * 0.32)
		var frame_preview := await _capture(demo.river.surface, float(i) * 0.3)
		frame_preview.save_png("res://.maintenance/river-tiles-demo-%02d.png" % i)
	demo.river.set_water_level(0.66)
	var preview := await _capture(demo.river.surface, 0.0)
	preview.save_png("res://.maintenance/river-tiles-preview.png")
	print("RIVER_TILEMAP_RENDER: moving=", moving, "; dry_errors=", dry_errors, "; gpu_mismatches=", mismatch)
	demo.queue_free()
	await get_tree().process_frame
	root.content_scale_size = Vector2i(1920, 1080)
	RunManager.start_new_run()
	var config := preload("res://data/levels/level_001.tres")
	var battle := config.battle_scene.instantiate()
	battle.configure_level(config)
	add_child(battle)
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.maintenance/river-tiles-battle-preview.png")
	battle.queue_free()
	await get_tree().process_frame
