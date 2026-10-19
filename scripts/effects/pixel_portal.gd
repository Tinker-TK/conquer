@tool
class_name PixelPortal
extends Node2D
## 原点位于地面中心。四层纯显示效果，不依赖角色、传送逻辑或自动加载节点。

const PALETTES: Array = [
	[Color("111827"), Color("243e50"), Color("397582"), Color("70b9c0"), Color("b4e5df")],
	[Color("1b142b"), Color("493359"), Color("78548f"), Color("bc8dd1"), Color("eccef7")],
	[Color("251720"), Color("61343b"), Color("ad6248"), Color("edb16b"), Color("fff0bc")],
	[Color("121e23"), Color("2e4d44"), Color("4f8a64"), Color("96cc91"), Color("dceec2")],
]

@export_group("形态")
@export var draw_size := Vector2(32, 48):
	set(value):
		draw_size = value.max(Vector2(24, 32))
		_sync()
@export var portal_size := Vector2(19, 34):
	set(value):
		portal_size = value.max(Vector2(8, 12))
		_sync()
@export_range(0.5, 4.0, 0.5) var pixel_size := 1.0:
	set(value):
		pixel_size = maxf(value, 0.5)
		_sync()
@export_range(0.5, 4.0, 0.1) var ring_width := 2.3:
	set(value):
		ring_width = maxf(value, 0.5)
		_sync()
@export_range(0.0, 2.0, 0.05) var distortion := 0.7:
	set(value):
		distortion = clampf(value, 0, 2)
		_sync()
@export_range(0.0, 2.0, 0.05) var swirl_strength := 1.0:
	set(value):
		swirl_strength = clampf(value, 0, 2)
		_sync()
@export_range(0, 20, 1) var fragment_count := 10:
	set(value):
		fragment_count = clampi(value, 0, 20)
		_sync()
@export var random_seed := 1.0:
	set(value):
		random_seed = value
		_sync()

@export_group("循环动画")
@export_range(1.0, 12.0, 0.1) var loop_duration := 6.0:
	set(value):
		loop_duration = maxf(value, 0.1)
		seek(_elapsed)
@export_range(1.0, 60.0, 1.0) var animation_fps := 14.0:
	set(value):
		animation_fps = maxf(value, 1)
		seek(_elapsed)
@export_range(0.0, 3.0, 0.05) var playback_speed := 1.0
@export var playing := true

@export_group("分层")
@export var ring_enabled := true:
	set(value):
		ring_enabled = value
		_sync()
@export var interior_enabled := true:
	set(value):
		interior_enabled = value
		_sync()
@export var fragments_enabled := true:
	set(value):
		fragments_enabled = value
		_sync()
@export var ground_enabled := true:
	set(value):
		ground_enabled = value
		_sync()
@export var halo_enabled := false:
	set(value):
		halo_enabled = value
		_sync()

@export_group("配色")
@export_enum("青蓝传送门", "紫色奥术", "金色余烬", "绿色秘境") var palette_preset := 0:
	set(value):
		palette_preset = clampi(value, 0, 3)
		_sync()
@export_range(0.0, 2.0, 0.05) var brightness := 1.0:
	set(value):
		brightness = clampf(value, 0, 2)
		_sync()
@export var use_custom_palette := false:
	set(value):
		use_custom_palette = value
		_sync()
@export var custom_palette := PackedColorArray([
	Color("111827"), Color("243e50"), Color("397582"), Color("70b9c0"), Color("b4e5df")]):
	set(value):
		custom_palette = value
		_sync()

var _elapsed := 0.0
var _material: ShaderMaterial


func _ready() -> void:
	_material = ($Portal.material as ShaderMaterial).duplicate() as ShaderMaterial
	$Portal.material = _material
	_sync()
	seek(_elapsed)


func _process(delta: float) -> void:
	if playing and playback_speed > 0:
		seek(_elapsed + delta * playback_speed)


## 输入效果内部秒数，支持确定性截图。循环帧数取整，任意时长都不会出现末帧跳变。
func seek(seconds: float) -> void:
	_elapsed = maxf(seconds, 0)
	if _material != null:
		var frames := maxi(1, roundi(loop_duration * animation_fps))
		var phase := fposmod(_elapsed, loop_duration) / loop_duration
		var frame := floori(phase * frames + 0.00001) % frames
		_material.set_shader_parameter("cycle_phase", float(frame) / frames)


func restart() -> void:
	seek(0)


func get_cycle_position() -> float:
	return fposmod(_elapsed, loop_duration) / loop_duration


func get_palette() -> PackedColorArray:
	if use_custom_palette and custom_palette.size() == 5:
		return custom_palette
	return PackedColorArray(PALETTES[palette_preset])


func _sync() -> void:
	if not is_inside_tree() or _material == null:
		return
	var sprite := $Portal as Sprite2D
	sprite.position = Vector2(0, -draw_size.y * 0.5 + 5.5)
	sprite.scale = draw_size / Vector2(32, 48)
	var parameters := {
		"draw_size": draw_size, "portal_size": portal_size, "pixel_size": pixel_size,
		"ring_width": ring_width, "distortion": distortion, "swirl_strength": swirl_strength,
		"fragment_count": fragment_count, "random_seed": random_seed, "brightness": brightness,
		"ring_enabled": ring_enabled, "interior_enabled": interior_enabled,
		"fragments_enabled": fragments_enabled, "ground_enabled": ground_enabled,
		"halo_enabled": halo_enabled,
	}
	for key in parameters:
		_material.set_shader_parameter(key, parameters[key])
	var colors := get_palette()
	for i in 5:
		_material.set_shader_parameter("color_%d" % i, colors[i])
