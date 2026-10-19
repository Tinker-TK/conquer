# 按 TileMapLayer 真正绘制的 alpha 合并地表；不读取导航多边形。
# 支持 texture_origin、单元及图块翻转/转置、跨单元的纹理。
extends RefCounted

var bounds := Rect2()
var image: Image
var floor_images: Dictionary = {}
var tiles: Array[Dictionary] = []
var _layers: Array[TileMapLayer] = []
var _atlas_images: Dictionary = {}


func build(root: Node, fallback: Rect2, use_mask: bool, terrain_set: int, terrain_id: int) -> void:
	bounds = fallback.abs()
	tiles.clear()
	floor_images.clear()
	_layers.clear()
	_atlas_images.clear()
	if use_mask and root != null:
		_find_layers(root)
		_cache_tiles(root, terrain_set, terrain_id)
		if not tiles.is_empty():
			bounds = tiles[0].bounds
			for tile in tiles:
				bounds = bounds.merge(tile.bounds)
	bounds.size = bounds.size.max(Vector2(2, 2))
	var end := bounds.end.ceil()
	bounds.position = bounds.position.floor()
	bounds.size = end - bounds.position
	var mask_scale := minf(1.0, 4096.0 / maxf(bounds.size.x, bounds.size.y))
	var size := Vector2i((bounds.size * mask_scale).ceil())
	image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK if use_mask else Color.WHITE)
	floor_images[1] = image.duplicate()
	for tile in tiles:
		if not floor_images.has(tile.floor_id):
			var floor_image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			floor_image.fill(Color.BLACK)
			floor_images[tile.floor_id] = floor_image
	var ratio := Vector2(size) / bounds.size
	for tile in tiles:
		var floor_image: Image = floor_images[tile.floor_id]
		var rect: Rect2i = tile.rect
		var atlas: Image = tile.image
		var inverse: Transform2D = tile.inverse
		var draw_bounds: Rect2 = tile.bounds
		var start := Vector2i(((draw_bounds.position - bounds.position) * ratio).floor())
		var stop := Vector2i(((draw_bounds.end - bounds.position) * ratio).ceil())
		for y in range(clampi(start.y, 0, size.y), clampi(stop.y, 0, size.y)):
			for x in range(clampi(start.x, 0, size.x), clampi(stop.x, 0, size.x)):
				var point := bounds.position + (Vector2(x, y) + Vector2.ONE * 0.5) / ratio
				var pixel := Vector2i((inverse * point + Vector2(rect.size) * 0.5).floor())
				if Rect2i(Vector2i.ZERO, rect.size).has_point(pixel) and atlas.get_pixelv(rect.position + pixel).a > 0.2:
					image.set_pixel(x, y, Color.WHITE)
					floor_image.set_pixel(x, y, Color.WHITE)


func contains(point: Vector2, floor_id: int = 0) -> bool:
	var mask: Image = image if floor_id == 0 else floor_images.get(floor_id)
	if mask == null or not bounds.has_point(point):
		return false
	var ratio := Vector2(mask.get_size()) / bounds.size
	return mask.get_pixelv(Vector2i(((point - bounds.position) * ratio).floor())).r > 0.5


func _find_layers(node: Node) -> void:
	if node is TileMapLayer and node.enabled and node.is_visible_in_tree():
		_layers.append(node)
	for child in node.get_children():
		_find_layers(child)


func _cache_tiles(root: Node, terrain_set: int, terrain_id: int) -> void:
	for layer in _layers:
		if layer.tile_set == null:
			continue
		var custom := layer.tile_set.get_custom_data_layer_by_name("snow_ground")
		if custom < 0:
			custom = layer.tile_set.get_custom_data_layer_by_name("rain_ground")
		var floor_id := int(root.get_tile_layer_floor(layer)) if root.has_method("get_tile_layer_floor") else 1
		for cell in layer.get_used_cells():
			var source_id := layer.get_cell_source_id(cell)
			if not layer.tile_set.has_source(source_id):
				continue
			var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
			var coords := layer.get_cell_atlas_coords(cell)
			var alternative := layer.get_cell_alternative_tile(cell)
			var flags := TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V | TileSetAtlasSource.TRANSFORM_TRANSPOSE
			if source == null or not source.has_tile(coords) or not source.has_alternative_tile(coords, alternative & ~flags):
				continue
			var data := layer.get_cell_tile_data(cell)
			if source.texture == null or data == null:
				continue
			var ground := bool(data.get_custom_data_by_layer_id(custom)) if custom >= 0 else data.terrain_set == terrain_set and data.terrain == terrain_id
			if not ground:
				continue
			var texture := source.texture
			if not _atlas_images.has(texture.get_instance_id()):
				var atlas := texture.get_image()
				if atlas.is_compressed():
					atlas.decompress()
				_atlas_images[texture.get_instance_id()] = atlas
			var tile_transform := _texture_transform(data.transpose, data.flip_h, data.flip_v)
			tile_transform.origin = -Vector2(data.texture_origin)
			var cell_transform := _texture_transform(bool(alternative & TileSetAtlasSource.TRANSFORM_TRANSPOSE), bool(alternative & TileSetAtlasSource.TRANSFORM_FLIP_H), bool(alternative & TileSetAtlasSource.TRANSFORM_FLIP_V))
			cell_transform.origin = layer.map_to_local(cell)
			var draw_transform := layer.global_transform * cell_transform * tile_transform
			var rect := source.get_tile_texture_region(coords)
			tiles.append({"floor_id": floor_id, "image": _atlas_images[texture.get_instance_id()], "rect": rect, "inverse": draw_transform.affine_inverse(), "bounds": draw_transform * Rect2(-Vector2(rect.size) * 0.5, Vector2(rect.size))})


func _texture_transform(transpose: bool, flip_h: bool, flip_v: bool) -> Transform2D:
	var h := -1.0 if flip_h else 1.0
	var v := -1.0 if flip_v else 1.0
	return Transform2D(Vector2(0, v), Vector2(h, 0), Vector2.ZERO) if transpose else Transform2D(Vector2(h, 0), Vector2(0, v), Vector2.ZERO)
