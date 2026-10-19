@tool
extends Polygon2D
class_name DynamicRiver

signal water_level_changed(value: float)

const WATER_SHADER = preload("res://shaders/dynamic_river.gdshader")

## 此多边形河流的水位、河床、水色、流水和泡沫配置资源。运行时复制共享预设；关卡 River Settings 可统一覆盖，编辑器可直接预览。
@export var settings: RiverSettings = preload("res://data/water/river_default.tres")
## 同画布的 RainWeather，可共享单位倒影、雨滴与脚步波纹；独立河流可留空。
@export var weather_path: NodePath = NodePath("../../RainWeather")
## 指向子 Polygon2D，定义保留原地面的干燥岛；岛节点只作为编辑轮廓。
@export var dry_islands: Array[NodePath] = []

var _water_material: ShaderMaterial
var _height_image: Image
var _bounds := Rect2()
var _elapsed := 0.0
var _water_level := 0.0
var _base_level := 0.0
var _level_tween: Tween
var _editor_timer := 0.0
var _editor_signature := 0
var _height_signature := 0
var _surface_signature := 0
var _cell_level_image: Image
var _cell_level_rect := Rect2()
var _island_polygons: Array[PackedVector2Array] = []


func _ready() -> void:
	if not Engine.is_editor_hint():
		settings = settings.duplicate(true) if settings != null else RiverSettings.new()
		add_to_group("dynamic_river")
	if settings == null:
		settings = RiverSettings.new()
	_water_material = ShaderMaterial.new()
	_water_material.shader = WATER_SHADER
	material = _water_material
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	apply_settings()
	_editor_signature = _configuration_signature()


func configure(value: RiverSettings) -> void:
	if value == null:
		return
	settings = value if Engine.is_editor_hint() else value.duplicate(true)
	if is_node_ready():
		apply_settings()


func set_enabled(value: bool) -> void:
	if not is_node_ready():
		settings = settings.duplicate(true) if settings != null else RiverSettings.new()
	settings.enabled = value
	if is_node_ready():
		apply_settings()


## 平滑改变水位；时间由本战场控制，随战斗暂停。原始共享 .tres 不会改变。
func set_water_level(value: float, duration: float = 0.0) -> void:
	if not is_node_ready():
		settings = settings.duplicate(true) if settings != null else RiverSettings.new()
	settings.water_level = clampf(value, 0.0, 1.0)
	_base_level = settings.water_level
	if is_instance_valid(_level_tween):
		_level_tween.kill()
	if duration <= 0.0 or not is_node_ready():
		_set_level(_base_level)
	else:
		_level_tween = create_tween()
		_level_tween.tween_method(_set_level, _water_level, _base_level, duration)


func get_water_level() -> float:
	return _water_level


func _set_level(value: float) -> void:
	_water_level = clampf(value, 0.0, 1.0)
	if _water_material != null:
		_water_material.set_shader_parameter("water_level", _water_level)
	water_level_changed.emit(_water_level)


func apply_settings() -> void:
	if _water_material == null or settings == null:
		return
	if is_instance_valid(_level_tween):
		_level_tween.kill()
	_build_height_map()
	for key in ["pixel_size", "bank_slope", "bed_color", "bank_color", "shallow_color", "deep_color",
		"shallow_opacity", "deep_opacity", "flow_velocity", "wave_scale", "refraction", "caustics_strength",
		"foam_color", "foam_width", "shore_motion", "reflection_opacity"]:
		_water_material.set_shader_parameter(key, settings.get(key))
	_water_material.set_shader_parameter("random_seed", float(settings.random_seed))
	_water_material.set_shader_parameter("bed_map", settings.bed_texture)
	_water_material.set_shader_parameter("has_bed_texture", settings.bed_texture != null)
	_water_material.set_shader_parameter("bed_scale", maxf(1.0, settings.bed_texture_scale))
	_base_level = clampf(settings.water_level, 0.0, 1.0)
	_set_level(_base_level)
	visible = settings.enabled and polygon.size() >= 3
	_update_weather_maps()
	_refresh_weather_surface()


func _refresh_weather_surface() -> void:
	if Engine.is_editor_hint():
		return
	var signature := hash([_height_signature, global_transform, visible, settings.enabled])
	if signature == _surface_signature:
		return
	_surface_signature = signature
	var weather := get_node_or_null(weather_path) as RainWeather if not weather_path.is_empty() else null
	if weather != null and weather.is_node_ready():
		weather.refresh_river_surfaces.call_deferred()


func _collect_islands() -> void:
	_island_polygons.clear()
	for path in dry_islands:
		var island := get_node_or_null(path) as Polygon2D
		if island == null or island.polygon.size() < 3:
			continue
		var points := PackedVector2Array()
		var local := global_transform.affine_inverse() * island.global_transform
		for point in island.polygon:
			points.append(local * point)
		_island_polygons.append(points)
		# 留下可编辑的轮廓，游戏中不额外绘制岛的辅助多边形。
		island.visible = Engine.is_editor_hint()
		if Engine.is_editor_hint():
			island.color = Color(0.8, 0.7, 0.3, 0.15)


func _configuration_signature() -> int:
	var values: Array = [polygon, dry_islands, weather_path]
	if settings != null:
		for property in settings.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				values.append(settings.get(property.name))
	for path in dry_islands:
		var island := get_node_or_null(path) as Polygon2D
		if island != null:
			values.append(island.polygon)
			values.append(global_transform.affine_inverse() * island.global_transform)
	return hash(values)


# 最多 512^2 纹素，只有几何/高度图/坡度修改时重建；水位和时间不参与。
func _build_height_map() -> void:
	_collect_islands()
	var signature := hash([polygon, _island_polygons, settings.height_texture, settings.bank_slope,
		settings.random_seed, settings.height_resolution])
	if _height_image != null and signature == _height_signature:
		return
	_height_signature = signature
	_bounds = Rect2()
	if polygon.size() < 3:
		_height_image = null
		return
	_bounds = Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		_bounds = _bounds.expand(point)
	_bounds.size = _bounds.size.max(Vector2(1.0, 1.0))
	var ratio := minf(1.0, float(settings.height_resolution) / maxf(_bounds.size.x, _bounds.size.y))
	var size := Vector2i((_bounds.size * ratio).ceil()).max(Vector2i(2, 2))
	_height_image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var supplied: Image
	if settings.height_texture != null:
		supplied = settings.height_texture.get_image()
		if supplied != null and supplied.is_compressed():
			supplied.decompress()
	var detail := FastNoiseLite.new()
	detail.seed = settings.random_seed
	detail.frequency = 0.055
	detail.fractal_octaves = 2
	for y in size.y:
		for x in size.x:
			var normalized_point := (Vector2(x, y) + Vector2.ONE * 0.5) / Vector2(size)
			var point := _bounds.position + normalized_point * _bounds.size
			if not Geometry2D.is_point_in_polygon(point, polygon) or _inside_island(point):
				continue
			var height := 0.0
			var alpha := 1.0
			if supplied != null:
				var source := supplied.get_pixelv(Vector2i((normalized_point * Vector2(supplied.get_size())).floor()).min(supplied.get_size() - Vector2i.ONE))
				height = source.r
				alpha = source.a
			else:
				var distance := _distance_to_bank(point, polygon)
				for island in _island_polygons:
					distance = minf(distance, _distance_to_bank(point, island))
				# 岸最高、河心最低；低河床增加小范围起伏，退水时显露小浅滩。
				height = clampf(1.0 - distance / maxf(settings.bank_slope, 1.0) + detail.get_noise_2dv(point) * 0.08, 0.0, 1.0)
			_height_image.set_pixel(x, y, Color(height, height, height, alpha))
	_water_material.set_shader_parameter("height_map", ImageTexture.create_from_image(_height_image))
	_water_material.set_shader_parameter("local_rect", Vector4(_bounds.position.x, _bounds.position.y, _bounds.size.x, _bounds.size.y))


func _inside_island(point: Vector2) -> bool:
	for island in _island_polygons:
		if Geometry2D.is_point_in_polygon(point, island):
			return true
	return false


func _distance_to_bank(point: Vector2, points: PackedVector2Array) -> float:
	var distance := INF
	for i in points.size():
		distance = minf(distance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, points[i], points[(i + 1) % points.size()])))
	return distance


func get_world_bounds() -> Rect2:
	return global_transform * _bounds


func _sample_height(world_point: Vector2) -> Color:
	if _height_image == null or not is_visible_in_tree() or settings == null or not settings.enabled:
		return Color(1, 1, 1, 0)
	var point := to_local(world_point)
	# 逆变换的浮点误差不能把精确网格边界推到前一个纹素。
	point = (point / maxf(settings.pixel_size, 1.0) + Vector2.ONE * 0.0001).floor() * maxf(settings.pixel_size, 1.0)
	if not _bounds.has_point(point) or not Geometry2D.is_point_in_polygon(point, polygon):
		return Color(1, 1, 1, 0)
	var normalized_point := (point - _bounds.position) / _bounds.size
	var pixel := Vector2i((normalized_point * Vector2(_height_image.get_size()) + Vector2.ONE * 0.0001).floor()).min(_height_image.get_size() - Vector2i.ONE)
	return _height_image.get_pixelv(pixel)


func is_bed_point(world_point: Vector2) -> bool:
	return _sample_height(world_point).a > 0.5


func is_water_point(world_point: Vector2) -> bool:
	var sample := _sample_height(world_point)
	var level := _level_at(world_point)
	return sample.a > 0.5 and level > 0.0 and sample.r <= level


func set_cell_level_map(image: Image, rect: Rect2) -> void:
	_cell_level_image = image
	_cell_level_rect = rect
	if _water_material == null:
		return
	_water_material.set_shader_parameter("use_cell_levels", image != null)
	if image != null:
		_water_material.set_shader_parameter("cell_level_map", ImageTexture.create_from_image(image))
		_water_material.set_shader_parameter("cell_level_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))


func _level_at(world_point: Vector2) -> float:
	if _cell_level_image == null or not _cell_level_rect.has_area():
		return _water_level
	var point := to_local(world_point)
	point = (point / maxf(settings.pixel_size, 1.0) + Vector2.ONE * 0.0001).floor() * maxf(settings.pixel_size, 1.0)
	if not _cell_level_rect.has_point(point):
		return _water_level
	var normalized_point := (point - _cell_level_rect.position) / _cell_level_rect.size
	var pixel := Vector2i((normalized_point * Vector2(_cell_level_image.get_size()) + Vector2.ONE * 0.0001).floor()).min(_cell_level_image.get_size() - Vector2i.ONE)
	var value := _cell_level_image.get_pixelv(pixel)
	return value.r if value.g > 0.5 else _water_level


func _update_weather_maps() -> void:
	var weather := get_node_or_null(weather_path) as RainWeather if not weather_path.is_empty() else null
	var available := weather != null and weather.is_node_ready() and not Engine.is_editor_hint()
	_water_material.set_shader_parameter("has_weather", available and weather.settings.enabled if available else false)
	if not available:
		return
	var maps := weather.get_shared_water_maps()
	_water_material.set_shader_parameter("reflection_map", maps.reflection)
	_water_material.set_shader_parameter("ripple_map", maps.ripple)
	_water_material.set_shader_parameter("reflection_rect", maps.bounds)
	_water_material.set_shader_parameter("reflection_opacity", settings.reflection_opacity if weather.settings.reflections_enabled else 0.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_editor_timer += delta
		if _editor_timer >= 0.3:
			_editor_timer = 0.0
			var signature := _configuration_signature()
			if signature != _editor_signature:
				_editor_signature = signature
				apply_settings()
	if settings == null or not settings.enabled or _water_material == null:
		return
	_elapsed += delta
	_water_material.set_shader_parameter("clock_time", _elapsed)
	if settings.tide_enabled and not (is_instance_valid(_level_tween) and _level_tween.is_running()):
		_set_level(_base_level + sin(_elapsed * TAU / maxf(settings.tide_period, 0.1)) * settings.tide_amplitude)
	_update_weather_maps()
	_refresh_weather_surface()
