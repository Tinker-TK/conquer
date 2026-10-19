@tool
class_name PixelThunderCloud
extends Node2D
## 原点是固定落点。新增乌云与同步时钟，通过实例参数复用原 PixelLightning。
## 不修改落雷源文件，不读取战斗状态，不产生伤害或镜头效果。

signal struck
signal finished

const SOURCE_POINTS := [Vector2(-29, 11), Vector2(-9, 13), Vector2(9, 14), Vector2(26, 16)]

@export_group("乌云形态")
@export var cloud_size := Vector2(112, 58):
	set(value):
		cloud_size = value.max(Vector2(40, 24))
		_sync()
@export_range(70.0, 280.0, 1.0) var cloud_altitude := 156.0:
	set(value):
		cloud_altitude = maxf(value, 70.0)
		_sync()
@export_range(1.0, 4.0, 1.0) var pixel_size := 1.0:
	set(value):
		pixel_size = maxf(value, 1.0)
		_sync()
@export_range(0.0, 4.0, 0.05) var edge_noise := 1.8:
	set(value):
		edge_noise = maxf(value, 0.0)
		_sync()
@export_range(0.0, 2.5, 0.05) var shade_noise := 1.0:
	set(value):
		shade_noise = maxf(value, 0.0)
		_sync()

@export_group("翻滚动画")
@export_range(0.0, 2.0, 0.05) var roll_speed := 0.65:
	set(value):
		roll_speed = maxf(value, 0.0)
		_sync()
@export_range(0.0, 2.0, 0.05) var roll_amount := 1.0:
	set(value):
		roll_amount = maxf(value, 0.0)
		_sync()
@export_range(1.0, 60.0, 1.0) var animation_fps := 16.0:
	set(value):
		animation_fps = maxf(value, 1.0)
		_sync()
@export_range(0.0, 3.0, 0.05) var playback_speed := 1.0
@export var playing := true
@export var auto_start := true
@export var loop := true
@export var random_seed: int = 11:
	set(value):
		random_seed = value
		_prepare_discharge()
		_sync()

@export_group("云内闪光与落雷")
@export var lightning_enabled := true:
	set(value):
		lightning_enabled = value
		_sync()
@export_enum("单雷", "树状落雷") var lightning_type: int = 0:
	set(value):
		lightning_type = clampi(value, 0, 1)
		_sync()
@export_range(1.2, 6.0, 0.05) var cycle_duration := 2.4:
	set(value):
		cycle_duration = maxf(value, 1.2)
		_sync()
@export_range(0.25, 1.0, 0.01) var strike_delay := 0.65:
	set(value):
		strike_delay = clampf(value, 0.25, 1.0)
		_sync()
@export var flash_enabled := true:
	set(value):
		flash_enabled = value
		_sync()
@export_range(0.0, 2.0, 0.05) var flash_strength := 1.0:
	set(value):
		flash_strength = maxf(value, 0.0)
		_sync()
@export var sparks_enabled := true:
	set(value):
		sparks_enabled = value
		_sync()

@export_group("颜色")
@export var dark_color := Color("242c36"):
	set(value):
		dark_color = value
		_sync()
@export var body_color := Color("404957"):
	set(value):
		body_color = value
		_sync()
@export var light_color := Color("606976"):
	set(value):
		light_color = value
		_sync()
@export var flash_color := Color("88c9ce"):
	set(value):
		flash_color = value
		_sync()
@export var flash_core := Color("dcebdd"):
	set(value):
		flash_core = value
		_sync()

@export_group("分层查看")
@export_enum("完整效果", "椭圆结构", "像素遮罩", "三色明暗", "云内闪光", "流动噪声") var debug_view: int = 0:
	set(value):
		debug_view = clampi(value, 0, 5)
		_sync()

var _material: ShaderMaterial
var _lightning: PixelLightning
var _elapsed := 0.0
var _active := false
var _has_frame := false
var _sequence_offset := 0
var _cycle_index := 0
var _source_point := Vector2(-9, 13)
var _impact_emitted := false
var _finished_emitted := false


func _ready() -> void:
	_material = ($Cloud.material as ShaderMaterial).duplicate() as ShaderMaterial
	$Cloud.material = _material
	_lightning = $Lightning as PixelLightning
	_lightning.playing = false
	_lightning.loop = false
	_prepare_discharge()
	_sync()
	if auto_start:
		restart()
	else:
		_update_frame()


func _process(delta: float) -> void:
	if not playing or playback_speed <= 0.0:
		return
	var previous := get_cycle_time()
	var previous_cycle := _cycle_index
	_elapsed += delta * playback_speed
	if _active:
		_update_cycle()
		var phase := get_cycle_time()
		if _cycle_index != previous_cycle:
			previous = 0.0
			_impact_emitted = false
			_finished_emitted = false
		var impact := strike_delay + _lightning.strike_duration
		if not _impact_emitted and previous < impact and phase >= impact:
			_impact_emitted = true
			if lightning_enabled and not Engine.is_editor_hint():
				struck.emit()
		if not _finished_emitted and phase >= get_strike_end():
			_finished_emitted = true
			if not Engine.is_editor_hint():
				finished.emit()
			if not loop:
				_active = false
				_has_frame = false
	_update_frame()


## 定位画面；不发送伤害或结束信号。循环模式下形状由周期编号确定。
func seek(seconds: float) -> void:
	_elapsed = maxf(seconds, 0.0)
	_has_frame = true
	_update_cycle()
	_update_frame()


## 重播当前随机序列，从第一周期开始。
func restart() -> void:
	_cycle_index = 0
	_prepare_discharge()
	_active = true
	_impact_emitted = false
	_finished_emitted = false
	seek(0.0)


## 生成新的出雷点与雷线，固定原点作为落点。
func trigger() -> void:
	_sequence_offset += 1
	restart()


func reset_sequence() -> void:
	_sequence_offset = 0
	restart()


func get_elapsed() -> float:
	return _elapsed


func get_cycle_time() -> float:
	return fposmod(_elapsed, cycle_duration) if loop else _elapsed


func get_strike_end() -> float:
	return strike_delay + (_lightning.get_duration() if _lightning != null else 0.34)


func get_discharge_position() -> Vector2:
	return Vector2(0, -cloud_altitude) + _source_point * cloud_size / Vector2(112, 58)


func get_lightning() -> PixelLightning:
	return _lightning


func _update_cycle() -> void:
	var index := int(floor(_elapsed / cycle_duration)) if loop else 0
	if index != _cycle_index:
		_cycle_index = index
		_prepare_discharge()


func _prepare_discharge() -> void:
	if _lightning == null:
		return
	var seed_value := random_seed + (_cycle_index + _sequence_offset) * 104729
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_source_point = SOURCE_POINTS[rng.randi_range(0, SOURCE_POINTS.size() - 1)]
	_source_point.x += rng.randf_range(-3.0, 3.0)
	_lightning.random_seed = seed_value
	_lightning.reset_sequence()
	_sync()


func _sync() -> void:
	if not is_inside_tree() or _material == null or _lightning == null:
		return
	var draw_size := cloud_size + Vector2(24, 22)
	var cloud := $Cloud as Sprite2D
	cloud.position = Vector2(0, -cloud_altitude)
	cloud.scale = draw_size / Vector2(136, 80)
	var parameters := {"draw_size": draw_size, "cloud_size": cloud_size, "pixel_size": pixel_size,
		"animation_fps": animation_fps, "roll_speed": roll_speed, "roll_amount": roll_amount,
		"edge_noise": edge_noise, "shade_noise": shade_noise, "random_seed": float(random_seed),
		"dark_color": dark_color, "body_color": body_color, "light_color": light_color,
		"flash_color": flash_color, "flash_core": flash_core, "flash_position": _source_point,
		"debug_view": debug_view}
	for key in parameters:
		_material.set_shader_parameter(key, parameters[key])
	# 转动独立实例，使它的起点落在云内、末端仍然落在 (0, 0)。
	var source := get_discharge_position()
	_lightning.position = Vector2.ZERO
	_lightning.bolt_height = source.length()
	_lightning.rotation = source.angle() + PI * 0.5
	_lightning.lightning_type = lightning_type
	_lightning.pixel_size = pixel_size
	_lightning.sparks_enabled = sparks_enabled
	_lightning.core_color = flash_core
	_lightning.branch_color = flash_color
	_lightning.dim_color = flash_color.darkened(0.62)
	_update_frame()


func _update_frame() -> void:
	if _material == null or _lightning == null:
		return
	_material.set_shader_parameter("clock_time", _elapsed)
	var phase := get_cycle_time()
	var bolt_time := phase - strike_delay
	var flash := 0.0
	if _has_frame and flash_enabled:
		if bolt_time >= -0.18 and bolt_time < 0.0:
			var charge := (bolt_time + 0.18) / 0.18
			flash = pow(maxf(sin(charge * PI * 3.0), 0.0), 2.0) * lerpf(0.15, 0.55, charge)
		elif bolt_time >= 0.0 and bolt_time < _lightning.strike_duration + _lightning.flash_duration:
			flash = 0.80 + 0.20 * sin(clampf(bolt_time / _lightning.strike_duration, 0, 1) * PI * 0.5)
		elif bolt_time >= 0.0:
			var tail := (bolt_time - _lightning.strike_duration - _lightning.flash_duration) / 0.11
			flash = pow(clampf(1.0 - tail, 0, 1), 2.0) * 0.75
	_material.set_shader_parameter("flash_amount", flash * flash_strength)
	_lightning.visible = _has_frame and lightning_enabled and debug_view == 0 and bolt_time >= 0 and bolt_time < _lightning.get_duration()
	if _lightning.visible:
		_lightning.seek(bolt_time)
