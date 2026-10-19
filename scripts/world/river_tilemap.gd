@tool
extends TileMapLayer
class_name RiverTileMap

signal water_level_changed(value: float)

## 此河流瓦片层的动态水面配置资源，控制水位、水色、流水与泡沫；河道形状和配套高度图由 TileSet 图块提供，关卡配置可覆盖预设。
@export var settings: RiverSettings = preload("res://data/water/river_default.tres")
## 相对本河流瓦片层的 RainWeather 路径，用于共享单位倒影、落雨和脚步波纹。独立河流可留空；需与河流位于同一世界画布。
@export var weather_path: NodePath = NodePath("../../RainWeather")
## 按地图坐标覆盖单格水位；不在字典中的格子跟随 Settings 水位/潮汐。
@export var cell_water_levels: Dictionary[Vector2i, float] = {}

# 布局只来自 TileMapLayer 保存的图块。内部画布用于共享连续水纹与天气纹理。
var surface: DynamicRiver
var _dirty := true
var _building := false
var _settings_signature := 0
var _level_signature := 0
var _layout_signature := 0
var _timer := 0.0
var _bound_tileset: TileSet
var _map_bounds := Rect2()
var _cell_rect := Rect2i()
var _atlas_images: Dictionary = {}


func _ready() -> void:
	if not Engine.is_editor_hint():
		settings = settings.duplicate(true) if settings != null else RiverSettings.new()
		cell_water_levels = cell_water_levels.duplicate()
	if settings == null:
		settings = RiverSettings.new()
	# Self Modulate 仅隐藏原生静态预览图，不影响内部动态画布或 TileSet 面板。
	self_modulate = Color(1, 1, 1, 0)
	changed.connect(_queue_rebuild)
	_bind_tileset()
	rebuild()


func configure(value: RiverSettings) -> void:
	if value == null:
		return
	settings = value if Engine.is_editor_hint() else value.duplicate(true)
	if is_node_ready():
		apply_settings()


func _bind_tileset() -> void:
	if _bound_tileset == tile_set:
		return
	if _bound_tileset != null and _bound_tileset.changed.is_connected(_queue_rebuild):
		_bound_tileset.changed.disconnect(_queue_rebuild)
	_bound_tileset = tile_set
	if _bound_tileset != null:
		_bound_tileset.changed.connect(_queue_rebuild)


func _queue_rebuild() -> void:
	_dirty = true
	if is_node_ready() and not _building:
		_rebuild_if_dirty.call_deferred()


func _rebuild_if_dirty() -> void:
	if _dirty and not _building and is_inside_tree():
		rebuild()


func _settings_hash() -> int:
	var values: Array = [weather_path, enabled, tile_set]
	if settings != null:
		for property in settings.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				values.append(settings.get(property.name))
	return hash(values)


func apply_settings() -> void:
	if not is_node_ready():
		return
	rebuild()


func _new_surface() -> void:
	if is_instance_valid(surface):
		return
	surface = DynamicRiver.new()
	surface.name = "TileWaterSurface"
	surface.z_index = 0
	# 内部生成节点不写入 .tscn；地图布局始终保存在原生 tile_map_data。
	surface.weather_path = _surface_weather_path()
	surface.settings = settings.duplicate(true)
	add_child(surface, false, Node.INTERNAL_MODE_BACK)
	surface.water_level_changed.connect(func(value: float): water_level_changed.emit(value))


func _surface_weather_path() -> NodePath:
	if weather_path.is_empty() or weather_path.is_absolute():
		return weather_path
	return NodePath("../" + str(weather_path))


func rebuild() -> void:
	if _building or settings == null:
		return
	_building = true
	_dirty = false
	_bind_tileset()
	_new_surface()
	_atlas_images.clear()
	_cell_rect = get_used_rect()
	_layout_signature = hash(tile_map_data)
	var records := _tile_records()
	if records.is_empty():
		_map_bounds = Rect2()
		surface.polygon = PackedVector2Array()
		surface.settings.enabled = false
		surface.apply_settings()
		_settings_signature = _settings_hash()
		_building = false
		return
	_map_bounds = records[0].bounds
	for record in records:
		_map_bounds = _map_bounds.merge(record.bounds)
	var end := _map_bounds.end.ceil()
	_map_bounds.position = _map_bounds.position.floor()
	_map_bounds.size = (end - _map_bounds.position).max(Vector2.ONE)
	var ratio := minf(1.0, float(settings.height_resolution) / maxf(_map_bounds.size.x, _map_bounds.size.y))
	var size := Vector2i((_map_bounds.size * ratio).ceil()).max(Vector2i(2, 2))
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var image_scale := Vector2(size) / _map_bounds.size
	var original_slope := float(tile_set.get_meta("river_bank_slope", 40.0))
	for record in records:
		var bounds: Rect2 = record.bounds
		var inverse: Transform2D = record.inverse
		var rect: Rect2i = record.rect
		var atlas: Image = record.image
		var start := Vector2i(((bounds.position - _map_bounds.position) * image_scale).floor())
		var stop := Vector2i(((bounds.end - _map_bounds.position) * image_scale).ceil())
		for y in range(clampi(start.y, 0, size.y), clampi(stop.y, 0, size.y)):
			for x in range(clampi(start.x, 0, size.x), clampi(stop.x, 0, size.x)):
				var point := _map_bounds.position + (Vector2(x, y) + Vector2.ONE * 0.5) / image_scale
				var pixel := Vector2i((inverse * point + Vector2(rect.size) * 0.5).floor())
				if not Rect2i(Vector2i.ZERO, rect.size).has_point(pixel):
					continue
				var sample := atlas.get_pixelv(rect.position + pixel)
				if sample.a <= 0.0:
					continue
				var height := clampf(1.0 - (1.0 - sample.r) * original_slope / maxf(settings.bank_slope, 1.0), 0.0, 1.0)
				image.set_pixel(x, y, Color(height, height, height, sample.a))
	surface.weather_path = _surface_weather_path()
	surface.polygon = PackedVector2Array([_map_bounds.position, Vector2(_map_bounds.end.x, _map_bounds.position.y),
		_map_bounds.end, Vector2(_map_bounds.position.x, _map_bounds.end.y)])
	var runtime_settings := settings.duplicate(true) as RiverSettings
	runtime_settings.enabled = settings.enabled and enabled
	runtime_settings.height_texture = ImageTexture.create_from_image(image)
	surface.configure(runtime_settings)
	_update_cell_levels()
	_settings_signature = _settings_hash()
	_building = false


func _tile_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if tile_set == null:
		return records
	var heights: Dictionary = tile_set.get_meta("river_height_atlases", {})
	var custom := tile_set.get_custom_data_layer_by_name("river_tile")
	for cell in get_used_cells():
		var source_id := get_cell_source_id(cell)
		if not heights.has(source_id) or not tile_set.has_source(source_id):
			continue
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		var data := get_cell_tile_data(cell)
		if source == null or data == null or (custom >= 0 and not bool(data.get_custom_data_by_layer_id(custom))):
			continue
		var height_texture: Texture2D = heights[source_id]
		if height_texture == null:
			continue
		if not _atlas_images.has(source_id):
			var atlas_image := height_texture.get_image()
			if atlas_image.is_compressed():
				atlas_image.decompress()
			_atlas_images[source_id] = atlas_image
		var alternative := get_cell_alternative_tile(cell)
		var tile_transform := _texture_transform(data.transpose, data.flip_h, data.flip_v)
		tile_transform.origin = -Vector2(data.texture_origin)
		var cell_transform := _texture_transform(bool(alternative & TileSetAtlasSource.TRANSFORM_TRANSPOSE),
			bool(alternative & TileSetAtlasSource.TRANSFORM_FLIP_H), bool(alternative & TileSetAtlasSource.TRANSFORM_FLIP_V))
		cell_transform.origin = map_to_local(cell)
		var sprite_transform := cell_transform * tile_transform
		var rect := source.get_tile_texture_region(get_cell_atlas_coords(cell))
		records.append({"image": _atlas_images[source_id], "rect": rect, "inverse": sprite_transform.affine_inverse(),
			"bounds": sprite_transform * Rect2(-Vector2(rect.size) * 0.5, Vector2(rect.size))})
	return records


func _texture_transform(transpose: bool, flip_h: bool, flip_v: bool) -> Transform2D:
	var h := -1.0 if flip_h else 1.0
	var v := -1.0 if flip_v else 1.0
	return Transform2D(Vector2(0, v), Vector2(h, 0), Vector2.ZERO) if transpose else Transform2D(Vector2(h, 0), Vector2(0, v), Vector2.ZERO)


func _update_cell_levels() -> void:
	if not is_instance_valid(surface) or not _cell_rect.has_area() or tile_set == null:
		return
	# 与高度图共享包围盒坐标；TileMap 使用单元中心，首格左上角需减半格。
	var grid_origin := map_to_local(_cell_rect.position) - Vector2(tile_set.tile_size) * 0.5
	var image := Image.create(_cell_rect.size.x, _cell_rect.size.y, false, Image.FORMAT_RGBA8)
	for cell in cell_water_levels:
		if _cell_rect.has_point(cell) and get_cell_source_id(cell) >= 0:
			image.set_pixelv(cell - _cell_rect.position, Color(clampf(cell_water_levels[cell], 0.0, 1.0), 1, 0, 1))
	surface.set_cell_level_map(image, Rect2(grid_origin, Vector2(_cell_rect.size * tile_set.tile_size)))
	_level_signature = hash(cell_water_levels)


func set_cell_water_level(cell: Vector2i, value: float) -> void:
	cell_water_levels[cell] = clampf(value, 0.0, 1.0)
	if is_node_ready():
		_update_cell_levels()


func clear_cell_water_level(cell: Vector2i) -> void:
	cell_water_levels.erase(cell)
	if is_node_ready():
		_update_cell_levels()


func set_water_level(value: float, duration: float = 0.0) -> void:
	if not is_node_ready():
		settings = settings.duplicate(true) if settings != null else RiverSettings.new()
	settings.water_level = clampf(value, 0.0, 1.0)
	if is_instance_valid(surface):
		surface.set_water_level(value, duration)
	_settings_signature = _settings_hash()


func get_water_level() -> float:
	return surface.get_water_level() if is_instance_valid(surface) else settings.water_level


func set_river_enabled(value: bool) -> void:
	if not is_node_ready():
		settings = settings.duplicate(true) if settings != null else RiverSettings.new()
	settings.enabled = value
	if is_node_ready():
		apply_settings()


func is_water_point(point: Vector2) -> bool:
	return is_instance_valid(surface) and surface.is_water_point(point)


func is_bed_point(point: Vector2) -> bool:
	return is_instance_valid(surface) and surface.is_bed_point(point)


func get_world_bounds() -> Rect2:
	return global_transform * _map_bounds


func _process(delta: float) -> void:
	_timer += delta
	if _timer < 0.25:
		return
	_timer = 0.0
	_bind_tileset()
	# 部分运行时原生 set_cell/erase_cell 调用不会发 changed；同时检查保存数据。
	if _settings_hash() != _settings_signature or hash(tile_map_data) != _layout_signature:
		_dirty = true
	_rebuild_if_dirty()
	if hash(cell_water_levels) != _level_signature:
		_update_cell_levels()
