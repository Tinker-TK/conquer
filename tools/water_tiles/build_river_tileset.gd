# Rebuild the native TileSet after atlas import. Never run automatically on user maps.
extends SceneTree

const SIDES = [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE]
const EIGHT = [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER]

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tilemap/river/river_tiles_manifest.json"))
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(128, 128)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(0, "river_tile")
	tiles.set_custom_data_layer_type(0, TYPE_BOOL)
	var heights: Dictionary = {}
	for kind in 2:
		var label := "channel" if kind == 0 else "water"
		var masks: Array = manifest.channel_masks if kind == 0 else manifest.water_masks
		var columns := 4 if kind == 0 else 8
		tiles.add_terrain_set()
		tiles.set_terrain_set_mode(kind, TileSet.TERRAIN_MODE_MATCH_SIDES if kind == 0 else TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
		tiles.add_terrain(kind)
		tiles.set_terrain_name(kind, 0, "河道（细河）" if kind == 0 else "水域（湖泊与宽河）")
		tiles.set_terrain_color(kind, 0, Color(0.19, 0.55, 0.77) if kind == 0 else Color(0.25, 0.72, 0.60))
		var source := TileSetAtlasSource.new()
		source.resource_name = "河道 · 16 种连接" if kind == 0 else "水域 · 47 种岸边"
		source.texture_region_size = tiles.tile_size
		source.texture = load("res://assets/tilemap/river/river_%s.png" % label)
		tiles.add_source(source, kind)
		heights[kind] = load("res://assets/tilemap/river/river_%s_height.png" % label)
		for i in masks.size():
			var atlas := Vector2i(i % columns, i / columns)
			source.create_tile(atlas)
			var data := source.get_tile_data(atlas, 0)
			data.terrain_set = kind
			data.terrain = 0
			data.set_custom_data("river_tile", true)
			var bits: Array = SIDES if kind == 0 else EIGHT
			for bit in bits.size():
				data.set_terrain_peering_bit(bits[bit], 0 if int(masks[i]) & (1 << bit) else -1)
	tiles.set_meta("river_height_atlases", heights)
	tiles.set_meta("river_bank_slope", 40.0)
	tiles.resource_name = "可绘制河流 · 河道与水域"
	var saved := ResourceSaver.save(tiles, "res://data/water/river_tileset.tres")
	if saved != OK:
		push_error("TileSet save failed: " + str(saved))
		quit(1)
		return
	print("RIVER_TILESET_BUILT: sources=2; channel=16; water=47")
	quit()
