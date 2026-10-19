# 视频思路的项目适配：地面噪声遮罩 → 独立倒影/水波视口 → 折射合成；雨滴跟随镜头。
# 按楼层合成地面效果；只复制精灵绘制数据，水花与倒影总数均有上限。
extends Node2D
class_name RainWeather

const RIPPLE_CANVAS = preload("res://scripts/world/rain_ripple_canvas.gd")
const WATER_SHADER = preload("res://shaders/rain_puddles.gdshader")
const REFLECTION_SHADER = preload("res://shaders/rain_reflection.gdshader")
const RAIN_SHADER = preload("res://shaders/rain_streak.gdshader")
const SPLASH_SHADER = preload("res://shaders/rain_splash.gdshader")

## 此节点使用的雨天天气配置资源，展开可调整雨滴、积水、倒影和水花。运行时复制资源，关卡 Weather Settings 可覆盖场景预设。
@export var settings: RainWeatherSettings = preload("res://data/weather/rain_default.tres")
@export_group("地面与倒影来源")
# 此节点只作为图块容器查找；不读取烘焙导航或 agent_radius。
## 相对本雨天节点的地形根路径，向下查找实际 TileMapLayer 图块以建立积水遮罩；不读取导航烘焙范围或导航代理半径。
@export var terrain_root_path: NodePath = NodePath("../Level/NavigationRegion2D")
## 相对本雨天节点的战斗实体根路径，用于收集单位的动画精灵作为倒影来源，并追踪脚底行走距离产生积水脚步水花。
@export var entities_path: NodePath = NodePath("../Entities")
## 相对本雨天节点的静态场景物体根路径，向下查找树木等精灵作为倒影来源；与实体倒影共用 Max Reflections 上限。
@export var scenery_path: NodePath = NodePath("../Level")
## 独立水面云层的图片来源，默认读取此容器后代中的 Clouds 精灵；仅复制图片，不改变场景精灵的位置、材质、可见性和动画。
@export var cloud_source_path: NodePath = NodePath("../Level/decrition")
# 只接收指定的地表 terrain，透明洞/无 terrain 的立面不会生成积水。
## 是否按实际地表图块限定积水；开启时透明洞、未标记的立面和非地面 terrain 不积水。关闭时使用 Ground Rect 作为矩形地表。
@export var use_terrain_mask := true
## 可积水地表的 TileSet 地形集编号，从 0 开始；与 Ground Terrain Id 配合筛选，图块 rain_ground 自定义数据可优先指定地表。
@export var ground_terrain_set: int = 0
## 可积水地表的 terrain 编号，从 0 开始；启用地表遮罩时与地形集编号共同筛选，图块自定义地表标记优先。
@export var ground_terrain_id: int = 0
## 积水地表的备用世界坐标矩形。存在有效图块遮罩时使用实际地表范围，关联河流可扩大离屏画布；关闭遮罩时该矩形作为地面范围。
@export var ground_rect := Rect2(170, 170, 1580, 685)

var _runtime: Node2D
var _surface: Polygon2D
var _back_buffer: BackBufferCopy
var _water_material: ShaderMaterial
var _reflection_view: SubViewport
var _ripple_view: SubViewport
var _ripple_canvas: Node2D
var _splash_canvas: Node2D
var _tint: CanvasModulate
var _rain: Array[GPUParticles2D] = []
var _reflectors: Dictionary = {}
var _terrain_layers: Array[TileMapLayer] = []
var _ground_tiles: Array[Dictionary] = []
var _atlas_images: Dictionary = {}
var _ground_mask_image: Image
var _floor_masks: Dictionary = {}
var _floor_passes: Dictionary = {}
var _bounds := Rect2()
var _noise_image: Image
var _edge_noise_image: Image
var _rng := RandomNumberGenerator.new()
var _events: Array[Dictionary] = []
var _elapsed := 0.0
var _sky_scroll_offset := Vector2.ZERO
var _sky_cloud_image: Image
var _sky_cloud_choices: Array[String] = []
var _sky_cloud_source_ids: Dictionary = {}
var _scan_time := 0.0
var _splash_accumulator := 0.0
var _intensity := 0.0
var _intensity_tween: Tween
var _rivers: Array[DynamicRiver] = []


func _ready() -> void:
	# 场景共享预设只读；运行中改变天气不会污染其他关卡或磁盘资源。
	settings = settings.duplicate(true) if settings != null else RainWeatherSettings.new()
	_runtime = Node2D.new()
	_runtime.name = "WeatherRuntime"
	add_child(_runtime)
	_runtime.top_level = true
	_runtime.global_transform = Transform2D.IDENTITY
	_tint = CanvasModulate.new()
	_tint.name = "WeatherTint"
	_runtime.add_child(_tint)
	_back_buffer = BackBufferCopy.new()
	_back_buffer.name = "GroundBeforeWater"
	_back_buffer.z_index = -11
	# 完整复制保证缩放、屏幕边缘及折射偏移不会采到未复制的像素。
	_back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_runtime.add_child(_back_buffer)
	_surface = Polygon2D.new()
	_surface.name = "Puddles"
	_surface.z_index = -10
	_water_material = ShaderMaterial.new()
	_water_material.shader = WATER_SHADER
	_surface.material = _water_material
	_runtime.add_child(_surface)
	_reflection_view = _new_viewport("ReflectionViewport")
	_ripple_view = _new_viewport("RippleViewport")
	_ripple_canvas = RIPPLE_CANVAS.new()
	_ripple_canvas.distortion_pass = true
	var ripple_material := CanvasItemMaterial.new()
	ripple_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_ripple_canvas.material = ripple_material
	_ripple_view.add_child(_ripple_canvas)
	_splash_canvas = RIPPLE_CANVAS.new()
	_splash_canvas.name = "GroundSplashes"
	_splash_canvas.z_index = -8
	var splash_material := ShaderMaterial.new()
	splash_material.shader = SPLASH_SHADER
	_splash_canvas.material = splash_material
	_runtime.add_child(_splash_canvas)
	for i in 2:
		var particles := GPUParticles2D.new()
		particles.name = "DistantRain" if i == 0 else "NearRain"
		particles.z_index = -5 if i == 0 else 8
		particles.local_coords = false
		particles.fixed_fps = 0
		particles.lifetime = 1.2
		particles.preprocess = 1.2
		particles.process_material = ParticleProcessMaterial.new()
		var rain_material := ShaderMaterial.new()
		rain_material.shader = RAIN_SHADER
		particles.material = rain_material
		particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_runtime.add_child(particles)
		_rain.append(particles)
	_floor_passes[1] = {"surface": _surface, "back_buffer": _back_buffer, "material": _water_material,
		"reflection_view": _reflection_view, "ripple_view": _ripple_view,
		"ripple_canvas": _ripple_canvas, "splash_canvas": _splash_canvas}
	apply_settings()


# 入树前可注入关卡预设，运行中也可调用；输入资源始终保持只读。
func configure(value: RainWeatherSettings) -> void:
	if value == null:
		return
	settings = value.duplicate(true)
	if is_node_ready():
		apply_settings()


func set_enabled(value: bool) -> void:
	if not is_node_ready():
		settings = settings.duplicate(true) if settings != null else RainWeatherSettings.new()
	settings.enabled = value
	if is_node_ready():
		_update_active()


# amount 为 0~1；duration 为过渡秒数，暂停时过渡也暂停。
func set_rain_intensity(amount: float, duration: float = 0.0) -> void:
	if not is_node_ready():
		settings = settings.duplicate(true) if settings != null else RainWeatherSettings.new()
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


# 改过 settings 外观字段或地表图块后调用一次，刷新显示遮罩。
func apply_settings() -> void:
	if not is_node_ready():
		return
	if is_instance_valid(_intensity_tween):
		_intensity_tween.kill()
	_rng.seed = settings.random_seed
	_build_ground()
	_build_scene_clouds()
	var noise := FastNoiseLite.new()
	noise.seed = settings.random_seed
	noise.frequency = 1.0 / maxf(settings.puddle_scale, 1.0)
	noise.fractal_octaves = 3
	_noise_image = noise.get_seamless_image(1024, 1024)
	_water_material.set_shader_parameter("noise_map", ImageTexture.create_from_image(_noise_image))
	var edge_noise := FastNoiseLite.new()
	edge_noise.seed = settings.random_seed ^ 0x5F3759DF
	edge_noise.frequency = 1.0 / maxf(settings.edge_noise_scale, 1.0)
	edge_noise.fractal_octaves = 2
	_edge_noise_image = edge_noise.get_seamless_image(256, 256)
	_water_material.set_shader_parameter("edge_noise_map", ImageTexture.create_from_image(_edge_noise_image))
	_water_material.set_shader_parameter("edge_noise_strength", settings.edge_noise_strength)
	_water_material.set_shader_parameter("edge_noise_speed", settings.edge_noise_speed)
	_water_material.set_shader_parameter("edge_width", settings.edge_width)
	_water_material.set_shader_parameter("edge_color", settings.edge_color)
	_water_material.set_shader_parameter("world_rect", Vector4(_bounds.position.x, _bounds.position.y, _bounds.size.x, _bounds.size.y))
	_water_material.set_shader_parameter("coverage", settings.puddle_coverage)
	_water_material.set_shader_parameter("edge_softness", maxf(settings.edge_softness, 0.001))
	_water_material.set_shader_parameter("wetness", settings.wetness)
	_water_material.set_shader_parameter("depth_opacity", settings.depth_opacity)
	_water_material.set_shader_parameter("water_tint", settings.water_tint)
	_water_material.set_shader_parameter("sky_strength", settings.sky_strength)
	_water_material.set_shader_parameter("sky_cloud_strength", settings.sky_cloud_strength)
	_water_material.set_shader_parameter("sky_map", settings.sky_texture)
	_water_material.set_shader_parameter("sky_scale", maxf(settings.sky_scale, 1.0))
	_water_material.set_shader_parameter("sky_scroll_offset", _sky_scroll_offset)
	_water_material.set_shader_parameter("has_sky_texture", settings.sky_texture != null)
	_water_material.set_shader_parameter("distortion", settings.distortion)
	_water_material.set_shader_parameter("reflection_opacity", settings.reflection_opacity if settings.reflections_enabled else 0.0)
	_water_material.set_shader_parameter("reflection_map", _reflection_view.get_texture())
	_water_material.set_shader_parameter("ripple_map", _ripple_view.get_texture())
	_sync_floor_materials()
	_resize_water_views()
	for canvas in _water_canvases():
		canvas.lifetime = maxf(settings.ripple_lifetime, 0.15)
		canvas.radius = settings.ripple_radius
		canvas.events = _events
		canvas.splash_size = settings.splash_size
		canvas.splash_opacity = settings.splash_opacity
		canvas.splash_lifetime = settings.splash_lifetime
		canvas.rain_color = settings.rain_color
		canvas.rain_color.a *= settings.rain_opacity
		canvas.streak_width = settings.streak_width
		canvas.streak_length = settings.streak_length
	for i in _rain.size():
		var particles := _rain[i]
		particles.amount = maxi(8, int(settings.rain_amount * (0.7 if i == 0 else 0.3)))
		var length := maxi(4, int(settings.streak_length * (0.65 if i == 0 else 1.0)))
		var width := maxi(1, roundi(settings.streak_width * (0.7 if i == 0 else 1.0)))
		var streak := Image.create(width, length, false, Image.FORMAT_RGBA8)
		for y in length:
			# 只淡出两端，保留明亮的核心，避免整条雨丝都因渐变而过淡。
			var t := (float(y) + 0.5) / float(length)
			var alpha := smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.8, 1.0, t))
			streak.fill_rect(Rect2i(0, y, width, 1), Color(1, 1, 1, alpha))
		particles.texture = ImageTexture.create_from_image(streak)
		var effect_material := particles.process_material as ParticleProcessMaterial
		effect_material.spread = 0.0
		effect_material.gravity = Vector3.ZERO
		effect_material.particle_flag_disable_z = true
		# Godot 粒子 Angle 的旋转符号与 Node2D 不同；直接沿实际速度对齐长轴。
		effect_material.particle_flag_align_y = true
		effect_material.angle_min = 0.0
		effect_material.angle_max = 0.0
		effect_material.color = settings.rain_color
		effect_material.color.a *= settings.rain_opacity * (0.75 if i == 0 else 1.0)
		effect_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_events.clear()
	_splash_accumulator = 0.0
	_scan_reflectors()
	_set_intensity(settings.intensity)
	_update_rain_emitters()


# 仅加工水面专用副本：尊重精灵取帧/翻转，去掉贴图暗影，再按镜面上下反转。
func _cloud_reflection_image(source: Sprite2D) -> Image:
	if source.texture == null:
		return null
	var image := source.texture.get_image()
	if image == null or image.is_empty():
		return null
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if source.region_enabled:
		image = image.get_region(Rect2i(source.region_rect))
	elif source.hframes > 1 or source.vframes > 1:
		@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
		var frame_size := image.get_size() / Vector2i(source.hframes, source.vframes)
		image = image.get_region(Rect2i(source.frame_coords * frame_size, frame_size))
	if source.flip_h:
		image.flip_x()
	if source.flip_v:
		image.flip_y()
	# 当前 Clouds 的暗影为 RGB(36,42,59)、Alpha85；云体最暗色仍为浅米灰。
	# 按颜色遮掉暗影，保留原云体的亮度层次和边缘 Alpha，不改动原纹理。
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a > 0.0 and maxf(color.r, maxf(color.g, color.b)) < 0.4:
				image.set_pixel(x, y, Color.TRANSPARENT)
	image.flip_y()
	return image


func _build_scene_clouds() -> void:
	_sky_cloud_image = null
	_sky_cloud_choices.clear()
	_sky_cloud_source_ids.clear()
	var images: Array[Image] = []
	var names: Array[String] = []
	var seen: Dictionary = {}
	var source_root := get_node_or_null(cloud_source_path)
	if source_root != null:
		for source: Sprite2D in source_root.find_children("Clouds*", "Sprite2D", true, false):
			_sky_cloud_source_ids[source.get_instance_id()] = true
			if not settings.sky_use_scene_clouds or source.texture == null:
				continue
			var key := "%d:%d:%s:%s:%s" % [source.texture.get_instance_id(), source.frame, source.region_rect if source.region_enabled else Rect2(), source.flip_h, source.flip_v]
			if seen.has(key):
				continue
			seen[key] = true
			var image := _cloud_reflection_image(source)
			if image == null:
				continue
			images.append(image)
			names.append(source.texture.resource_path)
	if not images.is_empty():
		const TILE_SIZE := 1024
		var atlas := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		var cloud_rng := RandomNumberGenerator.new()
		cloud_rng.seed = settings.random_seed ^ 0x434C4F55
		var count := clampi(settings.sky_cloud_count, 1, 24)
		var columns := ceili(sqrt(float(count)))
		var rows := ceili(float(count) / float(columns))
		var bag: Array[int] = []
		for i in count:
			# 先随机用完一轮不同云形，再允许重复，避免同一贴图反复占满画面。
			if bag.is_empty():
				for index in images.size():
					bag.append(index)
			var selected: int = bag.pop_at(cloud_rng.randi_range(0, bag.size() - 1))
			var image := images[selected].duplicate() as Image
			var cloud_scale := settings.sky_cloud_size * cloud_rng.randf_range(0.8, 1.15)
			cloud_scale = minf(cloud_scale, float(TILE_SIZE) * 0.8 / maxf(image.get_width(), image.get_height()))
			image.resize(maxi(1, roundi(image.get_width() * cloud_scale)), maxi(1, roundi(image.get_height() * cloud_scale)), Image.INTERPOLATE_NEAREST)
			@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
			var center := Vector2((float(i % columns) + cloud_rng.randf_range(0.15, 0.85)) / float(columns), (float(i / columns) + cloud_rng.randf_range(0.15, 0.85)) / float(rows)) * TILE_SIZE
			var draw_position := Vector2i((center - Vector2(image.get_size()) * 0.5).round())
			# 把跨边缘的部分卷回另一侧，循环移动时不会出现直线切口。
			for y in range(-1, 2):
				for x in range(-1, 2):
					atlas.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), draw_position + Vector2i(x, y) * TILE_SIZE)
			_sky_cloud_choices.append(names[selected])
		_sky_cloud_image = atlas
	_water_material.set_shader_parameter("has_scene_clouds", _sky_cloud_image != null)
	_water_material.set_shader_parameter("scene_cloud_map", ImageTexture.create_from_image(_sky_cloud_image) if _sky_cloud_image != null else null)


func _new_viewport(node_name: String) -> SubViewport:
	var view := SubViewport.new()
	view.name = node_name
	view.disable_3d = true
	view.transparent_bg = true
	view.gui_disable_input = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_runtime.add_child(view)
	return view


# 每层水面夹在本层地形和单位之间；上层悬崖自然遮住下层水面与倒影。
func _ensure_floor_pass(floor_id: int) -> void:
	if _floor_passes.has(floor_id):
		return
	var surface := Polygon2D.new()
	surface.name = "PuddlesFloor%d" % floor_id
	var effect_material := ShaderMaterial.new()
	effect_material.shader = WATER_SHADER
	surface.material = effect_material
	_runtime.add_child(surface)
	var back_buffer := BackBufferCopy.new()
	back_buffer.name = "GroundBeforeWaterFloor%d" % floor_id
	back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_runtime.add_child(back_buffer)
	var reflection_view := _new_viewport("ReflectionViewportFloor%d" % floor_id)
	var ripple_view := _new_viewport("RippleViewportFloor%d" % floor_id)
	var ripple_canvas := RIPPLE_CANVAS.new()
	ripple_canvas.floor_id = floor_id
	ripple_canvas.distortion_pass = true
	ripple_canvas.material = _ripple_canvas.material
	ripple_view.add_child(ripple_canvas)
	var splash_canvas := RIPPLE_CANVAS.new()
	splash_canvas.name = "GroundSplashesFloor%d" % floor_id
	splash_canvas.floor_id = floor_id
	splash_canvas.material = _splash_canvas.material
	_runtime.add_child(splash_canvas)
	_floor_passes[floor_id] = {"surface": surface, "back_buffer": back_buffer, "material": effect_material,
		"reflection_view": reflection_view, "ripple_view": ripple_view,
		"ripple_canvas": ripple_canvas, "splash_canvas": splash_canvas}


func _water_canvases() -> Array[Node2D]:
	var canvases: Array[Node2D] = []
	for pass_data in _floor_passes.values():
		canvases.append(pass_data.ripple_canvas)
		canvases.append(pass_data.splash_canvas)
	return canvases


func _sync_floor_materials() -> void:
	for floor_id in _floor_passes:
		var pass_data: Dictionary = _floor_passes[floor_id]
		var effect_material: ShaderMaterial = pass_data.material
		if floor_id != 1:
			for uniform_data in WATER_SHADER.get_shader_uniform_list():
				effect_material.set_shader_parameter(uniform_data.name, _water_material.get_shader_parameter(uniform_data.name))
		if _floor_masks.has(floor_id):
			effect_material.set_shader_parameter("ground_mask", ImageTexture.create_from_image(_floor_masks[floor_id]))
		effect_material.set_shader_parameter("reflection_map", pass_data.reflection_view.get_texture())
		effect_material.set_shader_parameter("ripple_map", pass_data.ripple_view.get_texture())


func _resize_water_views() -> void:
	var resolution := clampf(settings.reflection_resolution, 0.25, 1.0)
	for pass_data in _floor_passes.values():
		for view: SubViewport in [pass_data.reflection_view, pass_data.ripple_view]:
			view.size = Vector2i(maxi(2, ceili(_bounds.size.x * resolution)), maxi(2, ceili(_bounds.size.y * resolution)))
			var ratio := Vector2(view.size) / _bounds.size
			view.canvas_transform = Transform2D(Vector2(ratio.x, 0), Vector2(0, ratio.y), -_bounds.position * ratio)


# 河流改变轮廓/位置/开关时，只刷新地表范围，不重置天气随机序列和已有波纹。
func refresh_river_surfaces() -> void:
	if not is_node_ready():
		return
	_build_ground()
	_water_material.set_shader_parameter("world_rect", Vector4(_bounds.position.x, _bounds.position.y, _bounds.size.x, _bounds.size.y))
	_sync_floor_materials()
	_resize_water_views()
	_update_active()


# 从地表图块的实际绘制像素生成一次显示遮罩，完全独立于导航烘焙。
func _build_ground() -> void:
	_rivers.clear()
	for node in get_tree().get_nodes_in_group("dynamic_river"):
		if node is DynamicRiver and node.get_node_or_null(node.weather_path) == self:
			_rivers.append(node)
	_terrain_layers.clear()
	_ground_tiles.clear()
	_atlas_images.clear()
	_bounds = ground_rect.abs()
	var terrain_root := get_node_or_null(terrain_root_path)
	if use_terrain_mask and terrain_root != null:
		_find_terrain(terrain_root)
		_cache_ground_tiles()
		if not _ground_tiles.is_empty():
			_bounds = _ground_tiles[0].bounds
			for tile in _ground_tiles:
				_bounds = _bounds.merge(tile.bounds)
	for river in _rivers:
		if river.settings.enabled:
			_bounds = _bounds.merge(river.get_world_bounds())
	_bounds.size = _bounds.size.max(Vector2(2, 2))
	var end := _bounds.end.ceil()
	_bounds.position = _bounds.position.floor()
	_bounds.size = end - _bounds.position
	# 地表保留原图 1px 轮廓；水洼噪声的 2px 风格化网格不用于裁切地形。
	var mask_scale := minf(1.0, 4096.0 / maxf(_bounds.size.x, _bounds.size.y))
	var size := Vector2i((_bounds.size * mask_scale).ceil())
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	mask.fill(Color.BLACK if use_terrain_mask else Color.WHITE)
	_floor_masks.clear()
	_floor_masks[1] = mask.duplicate()
	for tile in _ground_tiles:
		if not _floor_masks.has(tile.floor_id):
			var floor_mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			floor_mask.fill(Color.BLACK)
			_floor_masks[tile.floor_id] = floor_mask
	var ratio := Vector2(size) / _bounds.size
	for tile in _ground_tiles:
		var floor_mask: Image = _floor_masks[tile.floor_id]
		var rect: Rect2i = tile.rect
		var image: Image = tile.image
		var inverse: Transform2D = tile.inverse
		var draw_bounds: Rect2 = tile.bounds
		var start := Vector2i(((draw_bounds.position - _bounds.position) * ratio).floor())
		var stop := Vector2i(((draw_bounds.end - _bounds.position) * ratio).ceil())
		for y in range(clampi(start.y, 0, size.y), clampi(stop.y, 0, size.y)):
			for x in range(clampi(start.x, 0, size.x), clampi(stop.x, 0, size.x)):
				var point := _bounds.position + (Vector2(x, y) + Vector2.ONE * 0.5) / ratio
				var pixel := Vector2i((inverse * point + Vector2(rect.size) * 0.5).floor())
				if Rect2i(Vector2i.ZERO, rect.size).has_point(pixel) and image.get_pixelv(rect.position + pixel).a > 0.2:
					mask.set_pixel(x, y, Color.WHITE)
					floor_mask.set_pixel(x, y, Color.WHITE)
	# 河床包括露出的浅滩；避免原积水在河流之上重复着色。
	for river in _rivers:
		var river_bounds := river.get_world_bounds().intersection(_bounds)
		var start := Vector2i(((river_bounds.position - _bounds.position) * ratio).floor())
		var stop := Vector2i(((river_bounds.end - _bounds.position) * ratio).ceil())
		for y in range(clampi(start.y, 0, size.y), clampi(stop.y, 0, size.y)):
			for x in range(clampi(start.x, 0, size.x), clampi(stop.x, 0, size.x)):
				var point := _bounds.position + (Vector2(x, y) + Vector2.ONE * 0.5) / ratio
				if river.is_bed_point(point):
					# 当前河流位于第一层，不应从桥面或更高地面挖掉积水。
					_floor_masks[1].set_pixel(x, y, Color.BLACK)
					var upper_ground := false
					for floor_id in _floor_masks:
						if floor_id != 1 and _floor_masks[floor_id].get_pixel(x, y).r > 0.5:
							upper_ground = true
					mask.set_pixel(x, y, Color.WHITE if upper_ground else Color.BLACK)
	_ground_mask_image = mask
	for floor_id in _floor_masks:
		_ensure_floor_pass(floor_id)
		var pass_data: Dictionary = _floor_passes[floor_id]
		var z := int(terrain_root.get_floor_z_index(floor_id)) if terrain_root != null and terrain_root.has_method("get_floor_z_index") else 0
		pass_data.surface.z_as_relative = false
		pass_data.surface.z_index = z - 10
		pass_data.back_buffer.z_as_relative = false
		pass_data.back_buffer.z_index = z - 11
		pass_data.splash_canvas.z_as_relative = false
		pass_data.splash_canvas.z_index = z - 8
		pass_data.surface.polygon = PackedVector2Array([_bounds.position, Vector2(_bounds.end.x, _bounds.position.y), _bounds.end, Vector2(_bounds.position.x, _bounds.end.y)])
		pass_data.material.set_shader_parameter("ground_mask", ImageTexture.create_from_image(_floor_masks[floor_id]))


func _find_terrain(node: Node) -> void:
	if node is TileMapLayer and node.enabled and node.is_visible_in_tree():
		_terrain_layers.append(node)
	for child in node.get_children():
		_find_terrain(child)


func _cache_ground_tiles() -> void:
	var terrain_root := get_node_or_null(terrain_root_path)
	for layer in _terrain_layers:
		if layer.tile_set == null:
			continue
		var custom_layer := layer.tile_set.get_custom_data_layer_by_name("rain_ground")
		var floor_id := int(terrain_root.get_tile_layer_floor(layer)) if terrain_root != null and terrain_root.has_method("get_tile_layer_floor") else 1
		for cell in layer.get_used_cells():
			var source_id := layer.get_cell_source_id(cell)
			if not layer.tile_set.has_source(source_id):
				continue
			var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
			var atlas_coords := layer.get_cell_atlas_coords(cell)
			var alternative := layer.get_cell_alternative_tile(cell)
			var flags := TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V | TileSetAtlasSource.TRANSFORM_TRANSPOSE
			if source == null or not source.has_tile(atlas_coords) or not source.has_alternative_tile(atlas_coords, alternative & ~flags):
				continue
			var data := layer.get_cell_tile_data(cell)
			if source == null or source.texture == null or data == null:
				continue
			# 自定义 bool 可指定桥/新地表；当前 main terrain 自动排除悬崖图块。
			var ground := bool(data.get_custom_data_by_layer_id(custom_layer)) if custom_layer >= 0 else data.terrain_set == ground_terrain_set and data.terrain == ground_terrain_id
			if not ground:
				continue
			var texture := source.texture
			if not _atlas_images.has(texture.get_instance_id()):
				var image := texture.get_image()
				if image.is_compressed():
					image.decompress()
				_atlas_images[texture.get_instance_id()] = image
			# 与 Godot 4.6 的绘制顺序相同：图块转置/翻转 → -texture_origin → 单元转置/翻转 → 单元中心。
			var tile_transform := _texture_transform(data.transpose, data.flip_h, data.flip_v)
			tile_transform.origin = -Vector2(data.texture_origin)
			var cell_transform := _texture_transform(bool(alternative & TileSetAtlasSource.TRANSFORM_TRANSPOSE), bool(alternative & TileSetAtlasSource.TRANSFORM_FLIP_H), bool(alternative & TileSetAtlasSource.TRANSFORM_FLIP_V))
			cell_transform.origin = layer.map_to_local(cell)
			var draw_transform := layer.global_transform * cell_transform * tile_transform
			var rect := source.get_tile_texture_region(atlas_coords)
			_ground_tiles.append({"floor_id": floor_id, "image": _atlas_images[texture.get_instance_id()], "rect": rect, "inverse": draw_transform.affine_inverse(), "bounds": draw_transform * Rect2(-Vector2(rect.size) * 0.5, Vector2(rect.size))})


func _texture_transform(transpose: bool, flip_h: bool, flip_v: bool) -> Transform2D:
	var h := -1.0 if flip_h else 1.0
	var v := -1.0 if flip_v else 1.0
	return Transform2D(Vector2(0, v), Vector2(h, 0), Vector2.ZERO) if transpose else Transform2D(Vector2(h, 0), Vector2(0, v), Vector2.ZERO)


func is_ground_point(point: Vector2, floor_id: int = 0) -> bool:
	var mask: Image = _ground_mask_image if floor_id == 0 else _floor_masks.get(floor_id)
	if mask == null or not _bounds.has_point(point):
		return false
	var ratio := Vector2(mask.get_size()) / _bounds.size
	return mask.get_pixelv(Vector2i(((point - _bounds.position) * ratio).floor())).r > 0.5


func _is_wet(point: Vector2, floor_id: int = 0) -> bool:
	if floor_id == 0:
		floor_id = _surface_floor_at(point)
	if floor_id == 1:
		for river in _rivers:
			if is_instance_valid(river) and river.is_bed_point(point):
				return river.is_water_point(point)
	if not settings.puddles_enabled or settings.puddle_coverage <= 0.0 or settings.wetness <= 0.0 or not is_ground_point(point, floor_id):
		return false
	var p := (point / 2.0).floor() * 2.0
	var base := _sample_noise_repeat(_noise_image, p)
	return base > lerpf(0.72, 0.28, settings.puddle_coverage)


func _surface_floor_at(point: Vector2) -> int:
	var result := 1
	for floor_id in _floor_masks:
		if floor_id > result and is_ground_point(point, floor_id):
			result = floor_id
	return result


func _is_splash_surface(point: Vector2, floor_id: int = 0) -> bool:
	if is_ground_point(point, floor_id):
		return true
	if floor_id > 1:
		return false
	for river in _rivers:
		if is_instance_valid(river) and river.is_bed_point(point):
			return true
	return false


# 河流共用第一层的两张纹理；高层地面单独合成，避免桥上/桥下倒影串层。
func get_shared_water_maps() -> Dictionary:
	return {"reflection": _reflection_view.get_texture(), "ripple": _ripple_view.get_texture(),
		"bounds": Vector4(_bounds.position.x, _bounds.position.y, _bounds.size.x, _bounds.size.y)}


func _has_active_river() -> bool:
	for river in _rivers:
		if is_instance_valid(river) and river.settings.enabled and river.is_visible_in_tree():
			return true
	return false


# 与 filter_linear/repeat_enable 的 GPU 主体采样对齐；移动亮边不改变干湿。
func _sample_noise_repeat(image: Image, point: Vector2) -> float:
	var q := point - Vector2(0.5, 0.5)
	var ix := floori(q.x)
	var iy := floori(q.y)
	var tx := q.x - ix
	var ty := q.y - iy
	var width := image.get_width()
	var height := image.get_height()
	var a := image.get_pixel(posmod(ix, width), posmod(iy, height)).r
	var b := image.get_pixel(posmod(ix + 1, width), posmod(iy, height)).r
	var c := image.get_pixel(posmod(ix, width), posmod(iy + 1, height)).r
	var d := image.get_pixel(posmod(ix + 1, width), posmod(iy + 1, height)).r
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func _set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	_update_active()


func _update_active() -> void:
	var active := settings.enabled
	# 运行中切回雨天时关闭雪天；入树顺序不覆盖尚未 ready 的雪天配置。
	var snow := get_node_or_null("../SnowWeather")
	if active and snow != null and snow.is_node_ready() and snow.has_method("set_enabled"):
		snow.set_enabled(false)
	set_process(active)
	_runtime.visible = active
	_tint.color = Color.WHITE.lerp(settings.atmosphere_tint, _intensity) if active else Color.WHITE
	for floor_id in _floor_passes:
		var pass_data: Dictionary = _floor_passes[floor_id]
		var present := _floor_masks.has(floor_id)
		pass_data.surface.visible = active and present and settings.puddles_enabled and settings.wetness > 0.0
		pass_data.back_buffer.visible = pass_data.surface.visible
		pass_data.splash_canvas.visible = active and present
		var water_visible: bool = pass_data.surface.visible or (floor_id == 1 and _has_active_river())
		pass_data.reflection_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if active and settings.reflections_enabled and water_visible else SubViewport.UPDATE_DISABLED
		pass_data.ripple_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if active and water_visible else SubViewport.UPDATE_DISABLED
	for particles in _rain:
		particles.amount_ratio = maxf(_intensity, 0.001)
		particles.emitting = active and _intensity > 0.0
		particles.visible = active and _intensity > 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	_advance_sky(delta)
	for pass_data in _floor_passes.values():
		pass_data.material.set_shader_parameter("clock_time", _elapsed)
		pass_data.material.set_shader_parameter("screen_zoom", get_viewport().get_canvas_transform().get_scale().abs())
	_update_rain_emitters()
	_scan_time += delta
	if _scan_time >= 0.25:
		_scan_time = 0.0
		_scan_reflectors()
	_sync_reflectors()
	for i in range(_events.size() - 1, -1, -1):
		_events[i].age += delta
		var event_lifetime := maxf(settings.ripple_lifetime, settings.splash_lifetime) if bool(_events[i].wet) else settings.splash_lifetime
		if float(_events[i].age) >= event_lifetime:
			_events.remove_at(i)
	_splash_accumulator += delta * settings.splash_rate * _intensity
	var count := mini(12, int(_splash_accumulator))
	_splash_accumulator -= count
	var visible_ground := _bounds.intersection(_camera_rect())
	if visible_ground.has_area():
		for i in count:
			for attempt in 6:
				var point := visible_ground.position + Vector2(_rng.randf(), _rng.randf()) * visible_ground.size
				if _is_splash_surface(point):
					_add_splash(point, _rng.randf_range(0.7, 1.1), true)
					break
	for canvas in _water_canvases():
		canvas.queue_redraw()


func _camera_rect() -> Rect2:
	var inverse := get_viewport().get_canvas_transform().affine_inverse()
	return inverse * get_viewport_rect()


func _rain_velocity() -> Vector2:
	# 只转换速度的基向量，落点依旧固定在世界中；支持镜头缩放和窗口拉伸。
	var screen_to_world := (get_viewport().get_stretch_transform() * get_viewport().get_canvas_transform()).affine_inverse()
	return screen_to_world * Vector2(settings.wind, settings.fall_speed) - screen_to_world.origin


func _sky_velocity() -> Vector2:
	if not settings.sky_follow_wind:
		return settings.sky_scroll_speed
	# 云层只沿画面左右移动；风决定方向和慢速倍率，不混入雨滴下落速度。
	var screen_to_world := (get_viewport().get_stretch_transform() * get_viewport().get_canvas_transform()).affine_inverse()
	var horizontal := (screen_to_world * Vector2.RIGHT - screen_to_world.origin).normalized()
	return horizontal * settings.wind * settings.sky_wind_speed_scale


func _advance_sky(delta: float) -> void:
	# 累积位移，改变风向/速度不会重算从开局开始的相位，也不会突然跳动。
	_sky_scroll_offset += _sky_velocity() * delta
	for pass_data in _floor_passes.values():
		pass_data.material.set_shader_parameter("sky_scroll_offset", _sky_scroll_offset)


func _update_rain_emitters() -> void:
	var view := _camera_rect()
	var near_velocity := _rain_velocity()
	for i in _rain.size():
		var particles := _rain[i]
		var speed_factor := 0.82 if i == 0 else 1.0
		var velocity := near_velocity * speed_factor
		var fall_speed := maxf(velocity.y, 1.0)
		var effect_material := particles.process_material as ParticleProcessMaterial
		effect_material.direction = Vector3(velocity.x, velocity.y, 0).normalized()
		effect_material.initial_velocity_min = velocity.length()
		effect_material.initial_velocity_max = velocity.length()
		# 无随机偏角、重力或横向摆动，雨滴沿长轴匀速直线落下。
		var lifetime := maxf(0.05, (view.size.y + 120.0) / fall_speed)
		if not is_equal_approx(particles.lifetime, lifetime):
			particles.lifetime = lifetime
			particles.preprocess = lifetime
		var drift := velocity.x * lifetime
		var half_width := view.size.x * 0.5 + absf(drift) * 0.5 + 64.0
		particles.global_position = Vector2(view.get_center().x - drift * 0.5, view.position.y - 40.0)
		effect_material.emission_box_extents = Vector3(half_width, 24.0, 0.0)
		particles.visibility_rect = Rect2(Vector2(-half_width + minf(drift, 0.0) - 64.0, -80.0), Vector2(half_width * 2.0 + absf(drift) + 128.0, fall_speed * 1.1 * lifetime + 160.0))


func _add_splash(point: Vector2, strength: float, falling_drop: bool = false, floor_id: int = 0) -> void:
	if floor_id == 0:
		floor_id = _surface_floor_at(point)
	if _events.size() >= settings.max_ripples or not _is_splash_surface(point, floor_id):
		return
	# 落雨先绘制抵达此落点的最后一段直线，再在同一位置溅起；脚步即时触发。
	_events.append({"point": point, "age": -0.05 if falling_drop else 0.0,
		"strength": strength, "wet": _is_wet(point, floor_id), "floor_id": floor_id,
		"velocity": Vector2(settings.wind, settings.fall_speed)})


func _scan_reflectors() -> void:
	var sources: Dictionary = {}
	var entities := get_node_or_null(entities_path)
	if entities != null:
		for team in entities.get_children():
			for unit in team.get_children():
				if unit is UnitBase:
					_collect_source(unit.get_node_or_null("AnimatedSprite2D"), unit, sources)
	var scenery := get_node_or_null(scenery_path)
	if scenery != null:
		_collect_scenery(scenery, sources)
	for key in _reflectors.keys():
		if not sources.has(key):
			_reflectors[key].copy.queue_free()
			_reflectors.erase(key)
	for key in sources:
		if _reflectors.has(key):
			continue
		var sprite := Sprite2D.new()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var mat := ShaderMaterial.new()
		mat.shader = REFLECTION_SHADER
		sprite.material = mat
		_reflection_view.add_child(sprite)
		var record: Dictionary = sources[key]
		record.copy = sprite
		record.last_point = _foot_point(record.anchor)
		record.distance = 0.0
		_reflectors[key] = record


func _collect_source(source: Node, anchor: Node2D, sources: Dictionary) -> void:
	if source == null or anchor == null or sources.size() >= settings.max_reflections:
		return
	if source is Sprite2D or source is AnimatedSprite2D:
		sources[source.get_instance_id()] = {"source": source, "anchor": anchor}


func _collect_scenery(node: Node, sources: Dictionary) -> void:
	# 天空、地面图块、UI 和技能特效都不进入物体倒影。
	if node is Parallax2D or node is TileMapLayer or node is CanvasLayer or node is Control or node.has_meta("snow_overlay"):
		return
	if bool(node.get_meta("rain_reflection_exclude", false)) or node.is_in_group("rain_reflection_exclude"):
		return
	if _sky_cloud_source_ids.has(node.get_instance_id()):
		return
	# 背景云是普通 Sprite2D，不能按地面物体围绕父节点脚底镜像。
	# 只排除倒影副本，保留场景节点、位置、材质和原有动画。
	if node is Sprite2D:
		var texture: Texture2D = node.texture
		while texture is AtlasTexture:
			texture = texture.atlas
		if texture != null and texture.resource_path.to_lower().begins_with("res://assets/tilemap/clouds/"):
			return
	if node is Sprite2D or node is AnimatedSprite2D:
		_collect_source(node, node.get_parent() as Node2D, sources)
	for child in node.get_children():
		_collect_scenery(child, sources)


func _foot_point(anchor: Node2D) -> Vector2:
	var offset := float(anchor.get_meta("rain_foot_offset", settings.foot_offset))
	return anchor.to_global(Vector2(0, offset))


func _sync_reflectors() -> void:
	for key in _reflectors:
		var record: Dictionary = _reflectors[key]
		var source = record.source
		var anchor = record.anchor
		var sprite: Sprite2D = record.copy
		if not is_instance_valid(source) or not is_instance_valid(anchor) or not source.is_inside_tree():
			sprite.visible = false
			continue
		var foot := _foot_point(anchor)
		var floor_id := _reflector_floor(anchor)
		var reflection_view: SubViewport = _floor_passes.get(floor_id, _floor_passes[1]).reflection_view
		if sprite.get_parent() != reflection_view:
			sprite.reparent(reflection_view, false)
		sprite.visible = settings.reflections_enabled and _floor_masks.has(floor_id) and source.is_visible_in_tree()
		if source is AnimatedSprite2D:
			if source.sprite_frames == null or not source.sprite_frames.has_animation(source.animation):
				sprite.visible = false
				continue
			sprite.texture = source.sprite_frames.get_frame_texture(source.animation, source.frame)
		else:
			sprite.frame = 0
			sprite.texture = source.texture
			sprite.hframes = source.hframes
			sprite.vframes = source.vframes
			sprite.frame = source.frame
			sprite.region_enabled = source.region_enabled
			sprite.region_rect = source.region_rect
			sprite.region_filter_clip_enabled = source.region_filter_clip_enabled
		sprite.centered = source.centered
		sprite.offset = source.offset
		sprite.flip_h = source.flip_h
		sprite.flip_v = source.flip_v
		sprite.modulate = source.modulate * source.self_modulate * anchor.modulate
		var height := clampf(settings.reflection_height, 0.2, 1.0)
		var mirror := Transform2D(Vector2(1, 0), Vector2(0, -height), Vector2(0, foot.y * (1.0 + height)))
		sprite.transform = mirror * source.global_transform
		# 倒影只在所属楼层的地面合成，内部保持脚底的 Y 排序。
		sprite.z_index = clampi(int(foot.y - _bounds.position.y), -4096, 4096)
		var rect: Rect2
		if source is AnimatedSprite2D:
			var texture_size := sprite.texture.get_size() if sprite.texture != null else Vector2.ONE
			rect = Rect2(source.offset - (texture_size * 0.5 if source.centered else Vector2.ZERO), texture_size)
		else:
			rect = source.get_rect()
		var mat := sprite.material as ShaderMaterial
		mat.set_shader_parameter("source_top", rect.position.y)
		mat.set_shader_parameter("source_height", rect.size.y)
		mat.set_shader_parameter("foot_y", foot.y)
		mat.set_shader_parameter("gap", settings.reflection_gap)
		mat.set_shader_parameter("fade", settings.reflection_fade)
		var travel: float = foot.distance_to(record.last_point)
		record.last_point = foot
		if not anchor is UnitBase or not settings.footsteps_enabled or not source.is_visible_in_tree():
			continue
		if travel > maxf(settings.step_distance * 6.0, 180.0) or anchor.current_state == UnitBase.State.DEATH:
			record.distance = 0.0
			continue
		record.distance += travel
		if float(record.distance) >= settings.step_distance:
			record.distance = 0.0
			if _is_wet(foot, floor_id) and _camera_rect().has_point(foot):
				_add_splash(foot, 1.25, false, floor_id)


func _reflector_floor(anchor: Node2D) -> int:
	if anchor is UnitBase:
		return anchor.floor_id
	return int(anchor.get_meta("floor_id", 1))
