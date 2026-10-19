# Explicitly rebuild the example scene and emit first-stage native cell data.
# This helper is never run by the game or editor, so hand-painted layouts persist.
extends Node

func _ready() -> void:
	_build.call_deferred()

func _build() -> void:
	var scene := Node2D.new()
	scene.name = "RiverTilesDemo"
	scene.set_script(load("res://scripts/world/river_tiles_demo.gd"))
	var river := preload("res://scenes/effects/river_tilemap.tscn").instantiate() as RiverTileMap
	river.position = Vector2(64, 64)
	river.weather_path = NodePath("../RainWeather")
	scene.add_child(river)
	river.owner = scene
	var channel: Array[Vector2i] = []
	for x in 5:
		channel.append(Vector2i(x, 3))
	channel.append_array([Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 1), Vector2i(1, 4)])
	river.set_cells_terrain_connect(channel, 0, 0, false)
	var lake: Array[Vector2i] = []
	for y in range(2, 5):
		for x in range(6, 9):
			if Vector2i(x, y) != Vector2i(7, 3):
				lake.append(Vector2i(x, y))
	river.set_cells_terrain_connect(lake, 1, 0, false)
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed, "res://scenes/testing/river_tiles_demo.tscn") == OK)
	scene.free()
	var stage := TileMapLayer.new()
	stage.tile_set = preload("res://data/water/river_tileset.tres")
	var cells: Array[Vector2i] = []
	for x in range(2, 13):
		cells.append(Vector2i(x, 6))
	cells.append_array([Vector2i(4, 5), Vector2i(5, 5), Vector2i(9, 5), Vector2i(10, 5)])
	stage.set_cells_terrain_connect(cells, 0, 0, false)
	var output := FileAccess.open("res://.maintenance/stage-river-cells.txt", FileAccess.WRITE)
	output.store_string("PackedByteArray(\"" + Marshalls.raw_to_base64(stage.tile_map_data) + "\")")
	stage.free()
	print("RIVER_EXAMPLES_BUILT: native saved cells; demo=17; stage=15")
	get_tree().quit()
