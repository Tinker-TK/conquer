# 参考视频：随机像素雪花 → 固定噪声阈值积雪 → 覆雪层 → 覆盖度变化。
# 只绘制天气，不复制单位逻辑，也不更改导航/碰撞/战斗数值。
extends Node2D
class_name SnowWeather

const GROUND_MASK = preload("res://scripts/world/weather_ground_mask.gd")
const GROUND_SHADER = preload("res://shaders/snow_ground.gdshader")
const SCENERY_SHADER = preload("res://shaders/snow_scenery.gdshader")
const FLAKE_SHADER = preload("res://shaders/snow_flake.gdshader")

## 此节点使用的雪天天气配置资源，展开可调整雪花、积雪和物体覆雪。运行时会复制资源，关卡 Snow Weather Settings 可覆盖场景预设。
@export var settings: SnowWeatherSettings = preload("res://data/weather/snow_default.tres")
@export_group("地面与物体来源")
## 相对本雪天节点的地形根节点路径，向下查找 TileMapLayer 以生成实际地表积雪遮罩；不使用导航烘焙多边形。
@export var terrain_root_path := NodePath("../Level/NavigationRegion2D")
## 相对本雪天节点的场景物体根路径，向下查找树木等可覆雪精灵。战斗单位、瓦片层、UI 和标记排除的物体会跳过。
@export var scenery_path := NodePath("../Level")
## 相对本雪天节点的 RainWeather 路径，用于共用整体场景色调，并在启用雪天时关闭雨天效果；需指向同一战场的雨天节点。
@export var rain_weather_path := NodePath("../RainWeather")
## 是否按地形图块的实际可见像素限定积雪。开启可排除悬崖立面、透明洞和非地面 terrain；关闭则在 Ground Rect 矩形内铺雪。
@export var use_terrain_mask := true
## 可积雪地面的 TileSet 地形集编号，从 0 开始；仅在启用地表遮罩且没有 snow_ground 或 rain_ground 自定义标记时作为筛选条件。
@export var ground_terrain_set := 0
## 可积雪地面的 terrain 编号，从 0 开始，与 Ground Terrain Set 配合筛选；图块的 snow_ground 或 rain_ground 自定义标记优先。
@export var ground_terrain_id := 0
## 地表遮罩的备用世界坐标矩形。启用遮罩并找到有效地表时会使用实际图块范围；关闭遮罩时整个矩形都可积雪。
@export var ground_rect := Rect2(170, 170, 1580, 685)

var _runtime: Node2D
var _surface: Polygon2D
var _back_buffer: BackBufferCopy
var _material: ShaderMaterial
var _floor_passes: Dictionary = {}
var _tint: CanvasModulate
var _flakes: Array[GPUParticles2D] = []
var _scenery: Dictionary = {}
var _ground = GROUND_MASK.new()
var _noise_image: Image
var _noise_texture: ImageTexture
var _intensity := 0.0
var _coverage := 0.0
var _elapsed := 0.0
var _scan_time := 0.0
var _built := false
var _intensity_tween: Tween
var _coverage_tween: Tween


func _ready() -> void:
	settings = settings.duplicate(true) if settings != null else SnowWeatherSettings.new()
	_runtime = Node2D.new()
	_runtime.name = "SnowRuntime"
	add_child(_runtime)
	_runtime.top_level = true
	_runtime.global_transform = Transform2D.IDENTITY
	# 同一世界 Canvas 只保留一个 CanvasModulate，避免雨雪同时争夺色调。
	var rain := get_node_or_null(rain_weather_path) as RainWeather
	if rain != null:
		_tint = rain._tint
	if _tint == null:
		_tint = CanvasModulate.new()
		_runtime.add_child(_tint)
	_back_buffer = BackBufferCopy.new()
	_back_buffer.name = "GroundBeforeSnow"
	_back_buffer.z_index = -17
	_back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_runtime.add_child(_back_buffer)
	_surface = Polygon2D.new()
	_surface.name = "GroundSnow"
	# 地面 -20 → 积雪 -16 → 河流 -14 → 单位；河水始终在雪地之上。
	_surface.z_index = -16
	_material = ShaderMaterial.new()
	_material.shader = GROUND_SHADER
	_surface.material = _material
	_runtime.add_child(_surface)
	_floor_passes[1] = {"surface": _surface, "back_buffer": _back_buffer, "material": _material}
	for i in 2:
		var particles := GPUParticles2D.new()
		particles.name = "DistantSnow" if i == 0 else "NearSnow"
		particles.z_index = -5 if i == 0 else 8
		particles.local_coords = false
		particles.process_material = ParticleProcessMaterial.new()
		var mat := ShaderMaterial.new()
		mat.shader = FLAKE_SHADER
		particles.material = mat
		particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_runtime.add_child(particles)
		_flakes.append(particles)
	if settings.enabled:
		apply_settings()
	else:
		_update_active()


func configure(value: SnowWeatherSettings) -> void:
	if value == null:
		return
	settings = value.duplicate(true)
	if is_node_ready():
		apply_settings()


func set_enabled(value: bool) -> void:
	if not is_node_ready():
		settings = settings.duplicate(true) if settings != null else SnowWeatherSettings.new()
	settings.enabled = value
	if is_node_ready():
		if value and not _built:
			apply_settings()
		else:
			_update_active()


func set_snow_intensity(amount: float, duration: float = 0.0) -> void:
	if not is_node_ready():
		settings = settings.duplicate(true) if settings != null else SnowWeatherSettings.new()
	settings.intensity = clampf(amount, 0.0, 1.0)
	if is_instance_valid(_intensity_tween):
		_intensity_tween.kill()
	if not is_node_ready():
		return
	if duration <= 0.0:
		_set_intensity(settings.intensity)
	else:
		_intensity_tween = create_tween()
		_intensity_tween.tween_method(_set_intensity, _intensity, settings.intensity, duration)


# 自动堆积开启时，过渡完成后继续按雪量堆积/融化。
func set_snow_cover(amount: float, duration: float = 0.0) -> void:
	if not is_node_ready():
		settings = settings.duplicate(true) if settings != null else SnowWeatherSettings.new()
	settings.initial_coverage = clampf(amount, 0.0, 1.0)
	if is_instance_valid(_coverage_tween):
		_coverage_tween.kill()
	if not is_node_ready():
		return
	if duration <= 0.0:
		_set_coverage(settings.initial_coverage)
	else:
		_coverage_tween = create_tween()
		_coverage_tween.tween_method(_set_coverage, _coverage, settings.initial_coverage, duration)


func apply_settings() -> void:
	if not is_node_ready():
		return
	for tween in [_intensity_tween, _coverage_tween]:
		if is_instance_valid(tween):
			tween.kill()
	_ground.build(get_node_or_null(terrain_root_path), ground_rect, use_terrain_mask, ground_terrain_set, ground_terrain_id)
	_build_floor_passes()
	var noise := FastNoiseLite.new()
	noise.seed = settings.random_seed
	noise.frequency = 1.0 / maxf(settings.patch_scale, 1.0)
	noise.fractal_octaves = 3
	_noise_image = noise.get_seamless_image(1024, 1024)
	_noise_texture = ImageTexture.create_from_image(_noise_image)
	for pass_data in _floor_passes.values():
		pass_data.material.set_shader_parameter("noise_map", _noise_texture)
		pass_data.material.set_shader_parameter("pixel_size", maxf(settings.pixel_size, 1.0))
		pass_data.material.set_shader_parameter("ground_detail", settings.ground_detail)
		pass_data.material.set_shader_parameter("snow_tint", settings.snow_tint)
		pass_data.material.set_shader_parameter("snow_shadow", settings.snow_shadow)
	var atlas := _make_flake_atlas()
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.1, 0.85, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	for i in _flakes.size():
		var particles := _flakes[i]
		particles.texture = atlas
		particles.amount = maxi(8, int(settings.snow_amount * (0.7 if i == 0 else 0.3)))
		var mat := particles.material as ShaderMaterial
		mat.set_shader_parameter("flake_scale", settings.flake_scale * (0.7 if i == 0 else 1.0))
		var process := particles.process_material as ParticleProcessMaterial
		var velocity := Vector2(settings.wind, maxf(settings.fall_speed, 10.0)) * (0.65 if i == 0 else 1.0)
		process.direction = Vector3(velocity.x, velocity.y, 0).normalized()
		process.spread = 8.0
		process.gravity = Vector3.ZERO
		process.particle_flag_disable_z = true
		process.initial_velocity_min = velocity.length() * 0.75
		process.initial_velocity_max = velocity.length() * 1.25
		process.angle_min = 0.0
		process.angle_max = 360.0
		process.angular_velocity_min = -20.0
		process.angular_velocity_max = 20.0
		process.anim_offset_min = 0.0
		process.anim_offset_max = 1.0
		process.scale_min = 0.8
		process.scale_max = 1.35
		process.color = settings.snow_color
		process.color.a *= settings.snow_opacity * (0.65 if i == 0 else 1.0)
		process.color_ramp = ramp
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_built = true
	_scan_scenery()
	_set_coverage(settings.initial_coverage)
	_set_intensity(settings.intensity)
	_update_emitters()
	_sync_scenery()


# 每层积雪只合成本层地表，在本层单位之下；上层地形仍可遮住桥下积雪。
func _build_floor_passes() -> void:
	var terrain_root := get_node_or_null(terrain_root_path)
	var bounds: Rect2 = _ground.bounds
	for floor_id in _ground.floor_images:
		if not _floor_passes.has(floor_id):
			var back_buffer := BackBufferCopy.new()
			back_buffer.name = "GroundBeforeSnowFloor%d" % floor_id
			back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
			_runtime.add_child(back_buffer)
			var surface := Polygon2D.new()
			surface.name = "GroundSnowFloor%d" % floor_id
			var effect_material := ShaderMaterial.new()
			effect_material.shader = GROUND_SHADER
			surface.material = effect_material
			_runtime.add_child(surface)
			_floor_passes[floor_id] = {"surface": surface, "back_buffer": back_buffer, "material": effect_material}
		var pass_data: Dictionary = _floor_passes[floor_id]
		var z := int(terrain_root.get_floor_z_index(floor_id)) if terrain_root != null and terrain_root.has_method("get_floor_z_index") else 0
		pass_data.back_buffer.z_as_relative = false
		pass_data.back_buffer.z_index = z - 17
		pass_data.surface.z_as_relative = false
		pass_data.surface.z_index = z - 16
		pass_data.surface.polygon = PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
		pass_data.material.set_shader_parameter("ground_mask", ImageTexture.create_from_image(_ground.floor_images[floor_id]))
		pass_data.material.set_shader_parameter("world_rect", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))


func _make_flake_atlas() -> ImageTexture:
	# 原创 9 种三像素形状；对应视频的随机 3×3 图集方法。
	var shapes := ["010111010", "000010000", "100010001", "001010100", "000110010", "010010000", "010101010", "110010000", "000011011"]
	var atlas := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	for i in shapes.size():
		for y in 3:
			for x in 3:
				if shapes[i][y * 3 + x] == "1":
					atlas.set_pixel((i % 3) * 3 + x, floori(float(i) / 3.0) * 3 + y, Color.WHITE)
	return ImageTexture.create_from_image(atlas)


func _set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	_update_active()


func _set_coverage(value: float) -> void:
	_coverage = clampf(value, 0.0, 1.0)
	for pass_data in _floor_passes.values():
		pass_data.material.set_shader_parameter("coverage", _coverage)
	for record in _scenery.values():
		if is_instance_valid(record.copy):
			record.copy.material.set_shader_parameter("coverage", _coverage * settings.scenery_coverage)


func _update_active() -> void:
	var active := settings.enabled
	set_process(active)
	_runtime.visible = active
	for floor_id in _floor_passes:
		var pass_data: Dictionary = _floor_passes[floor_id]
		pass_data.surface.visible = active and settings.ground_snow_enabled and _ground.floor_images.has(floor_id)
		pass_data.back_buffer.visible = pass_data.surface.visible
	var rain := get_node_or_null(rain_weather_path) as RainWeather
	if active:
		if rain != null and rain.settings.enabled:
			rain.set_enabled(false)
		_tint.color = Color.WHITE.lerp(settings.atmosphere_tint, maxf(_intensity, _coverage * 0.5))
	elif rain == null or not rain.settings.enabled:
		_tint.color = Color.WHITE
	for particles in _flakes:
		particles.amount_ratio = maxf(_intensity, 0.001)
		particles.emitting = active and _intensity > 0.0
		particles.visible = active and _intensity > 0.0
	_sync_scenery()


func _process(delta: float) -> void:
	_elapsed += delta
	_scan_time += delta
	if _scan_time >= 0.5:
		_scan_time = 0.0
		_scan_scenery()
	if settings.automatic_accumulation and not (is_instance_valid(_coverage_tween) and _coverage_tween.is_running()):
		var rate := settings.accumulation_rate * _intensity if _intensity > 0.0 else -settings.melt_rate
		_set_coverage(_coverage + delta * rate)
		_tint.color = Color.WHITE.lerp(settings.atmosphere_tint, maxf(_intensity, _coverage * 0.5))
	_update_emitters()
	_sync_scenery()
	for particles in _flakes:
		particles.material.set_shader_parameter("clock_time", _elapsed)


func _camera_rect() -> Rect2:
	return get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()


func _update_emitters() -> void:
	var view := _camera_rect()
	for i in _flakes.size():
		var particles := _flakes[i]
		var factor := 0.65 if i == 0 else 1.0
		var speed := maxf(settings.fall_speed, 10.0) * factor
		var lifetime := (view.size.y + 160.0) / (speed * 0.6)
		if not is_equal_approx(particles.lifetime, lifetime):
			particles.lifetime = lifetime
			particles.preprocess = lifetime
		# 在整个镜头范围预填，移动/缩放后不会因雪速慢出现长时间空白。
		var drift := settings.wind * factor * lifetime
		var half := Vector2(view.size.x * 0.5 + absf(drift) + 80.0, view.size.y * 0.5 + 80.0)
		particles.global_position = view.get_center() - Vector2(drift * 0.25, view.size.y * 0.35)
		var process := particles.process_material as ParticleProcessMaterial
		process.emission_box_extents = Vector3(half.x, half.y, 0)
		particles.visibility_rect = Rect2(-half - Vector2(absf(drift), 100.0), half * 2.0 + Vector2(absf(drift) * 2.0, speed * 1.25 * lifetime + 200.0))


func is_ground_point(point: Vector2, floor_id: int = 0) -> bool:
	return _ground.contains(point, floor_id)


func _scan_scenery() -> void:
	var sources: Dictionary = {}
	var scenery := get_node_or_null(scenery_path)
	if scenery != null and settings.scenery_snow_enabled:
		_collect_scenery(scenery, sources)
	for key in _scenery.keys():
		if not sources.has(key):
			if is_instance_valid(_scenery[key].copy):
				_scenery[key].copy.queue_free()
			_scenery.erase(key)
	for key in sources:
		if not _scenery.has(key):
			var cover := Sprite2D.new()
			cover.name = "SnowCover"
			cover.set_meta("snow_overlay", true)
			var scenery_material := ShaderMaterial.new()
			scenery_material.shader = SCENERY_SHADER
			cover.material = scenery_material
			sources[key].add_child(cover)
			_scenery[key] = {"source": sources[key], "copy": cover}
		var mat: ShaderMaterial = _scenery[key].copy.material
		mat.set_shader_parameter("noise_map", _noise_texture)
		mat.set_shader_parameter("coverage", _coverage * settings.scenery_coverage)
		mat.set_shader_parameter("snowline", settings.scenery_snowline)
		mat.set_shader_parameter("snow_tint", settings.snow_tint)
		mat.set_shader_parameter("snow_shadow", settings.snow_shadow)


func _collect_scenery(node: Node, sources: Dictionary) -> void:
	if node is Parallax2D or node is TileMapLayer or node is CanvasLayer or node is Control or node is UnitBase or node.has_meta("snow_overlay") or bool(node.get_meta("snow_exclude", false)):
		return
	if sources.size() >= settings.max_scenery:
		return
	if node is Sprite2D or node is AnimatedSprite2D:
		sources[node.get_instance_id()] = node
	for child in node.get_children():
		_collect_scenery(child, sources)


func _sync_scenery() -> void:
	for record in _scenery.values():
		var source = record.source
		var cover: Sprite2D = record.copy
		if not is_instance_valid(source) or not is_instance_valid(cover):
			continue
		cover.visible = settings.enabled and settings.scenery_snow_enabled and source.is_visible_in_tree()
		cover.centered = source.centered
		cover.offset = source.offset
		cover.flip_h = source.flip_h
		cover.flip_v = source.flip_v
		# modulate 从父精灵继承；self_modulate 则显式同步，支持遮挡透明。
		cover.self_modulate = source.self_modulate
		if source is AnimatedSprite2D:
			if source.sprite_frames == null or not source.sprite_frames.has_animation(source.animation):
				cover.hide()
				continue
			cover.texture = source.sprite_frames.get_frame_texture(source.animation, source.frame)
		else:
			cover.frame = 0
			cover.texture = source.texture
			cover.hframes = source.hframes
			cover.vframes = source.vframes
			cover.frame = source.frame
			cover.region_enabled = source.region_enabled
			cover.region_rect = source.region_rect
		var uv_rect := Rect2(0, 0, 1, 1)
		if cover.texture is AtlasTexture and cover.texture.atlas != null:
			var texture: AtlasTexture = cover.texture
			uv_rect = Rect2(texture.region.position / texture.atlas.get_size(), texture.region.size / texture.atlas.get_size())
		elif cover.texture != null:
			if cover.region_enabled:
				uv_rect = Rect2(cover.region_rect.position / cover.texture.get_size(), cover.region_rect.size / cover.texture.get_size())
			else:
				var size := Vector2(1.0 / cover.hframes, 1.0 / cover.vframes)
				uv_rect = Rect2(Vector2(cover.frame_coords) * size, size)
		cover.material.set_shader_parameter("source_uv_rect", Vector4(uv_rect.position.x, uv_rect.position.y, uv_rect.size.x, uv_rect.size.y))


func _exit_tree() -> void:
	# 覆雪层挂在场景精灵上；独立删除天气节点时也必须回收。
	for record in _scenery.values():
		if is_instance_valid(record.copy):
			record.copy.hide()
			record.copy.queue_free()
	_scenery.clear()
	var rain := get_node_or_null(rain_weather_path) as RainWeather
	if is_instance_valid(_tint) and (rain == null or not rain.settings.enabled):
		_tint.color = Color.WHITE
