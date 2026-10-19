@tool
class_name PixelFlame
extends Node2D
## 独立像素火焰。原点在脚下，材质与时钟逐实例隔离；不依赖战斗或全局节点。

const PALETTES: Array = [
	[Color("203d47"), Color("346b70"), Color("559e9e"), Color("89cfca"), Color("c3efdf")],
	[Color("672c35"), Color("a34432"), Color("dc7034"), Color("efb84b"), Color("fff1a0")],
	[Color("293e31"), Color("486d37"), Color("80a845"), Color("b6d76a"), Color("e7f6a9")],
	[Color("392e53"), Color("644781"), Color("9764b2"), Color("c492d5"), Color("efd0f0")],
]

@export_group("外形")
@export var flame_size := Vector2(64, 80):
	set(value):
		flame_size = value.max(Vector2(8, 8))
		_sync()
@export_range(0.5, 8.0, 0.5) var pixel_size := 1.0:
	set(value):
		pixel_size = maxf(value, 0.5)
		_sync()
@export_enum("圆润灵魂火", "修长火苗") var shape: int = 0:
	set(value):
		shape = value
		_sync()
## 可选白色/灰度火焰 PNG，透明背景；未设置时使用程序轮廓。
@export var shape_mask: Texture2D:
	set(value):
		shape_mask = value
		_sync()

@export_group("动画")
@export_range(0.0, 1.5, 0.01) var intensity := 1.0:
	set(value):
		intensity = clampf(value, 0.0, 1.5)
		_sync()
@export_range(0.0, 4.0, 0.05) var flow_speed := 1.0:
	set(value):
		flow_speed = maxf(value, 0.0)
		_sync()
@export_range(0.0, 0.75, 0.01) var distortion := 0.28:
	set(value):
		distortion = value
		_sync()
@export_range(0.0, 0.85, 0.01) var erosion := 0.30:
	set(value):
		erosion = value
		_sync()
@export_range(-1.0, 1.0, 0.01) var wind := 0.0:
	set(value):
		wind = value
		_sync()
@export_range(1.0, 60.0, 1.0) var animation_fps := 18.0:
	set(value):
		animation_fps = maxf(value, 1.0)
		_sync()
@export var random_seed := 1.0:
	set(value):
		random_seed = value
		_sync()
@export var playing := true
@export var embers_enabled := true:
	set(value):
		embers_enabled = value
		_sync()
@export var glow_enabled := false:
	set(value):
		glow_enabled = value
		_sync()

@export_group("配色")
@export_enum("青色灵魂火", "橙色火焰", "绿色毒焰", "紫色奥术") var palette_preset: int = 0:
	set(value):
		palette_preset = clampi(value, 0, 3)
		_sync()
@export var use_custom_palette := false:
	set(value):
		use_custom_palette = value
		_sync()
@export var custom_palette := PackedColorArray([
	Color("203d47"), Color("346b70"), Color("559e9e"), Color("89cfca"), Color("c3efdf")]):
	set(value):
		custom_palette = value
		_sync()

@export_group("分层查看")
@export_enum("完整效果", "火焰遮罩", "摆动噪声", "侵蚀噪声", "热度分层") var debug_view: int = 0:
	set(value):
		debug_view = value
		_sync()

var _elapsed := 0.0
var _material: ShaderMaterial


func _ready() -> void:
	# Each scene instance needs its own material, including dynamically instantiated previews.
	_material = ($Flame.material as ShaderMaterial).duplicate() as ShaderMaterial
	$Flame.material = _material
	_sync()
	seek(_elapsed)


func _process(delta: float) -> void:
	if playing:
		seek(_elapsed + delta)


## 用本地时间驱动 Shader，暂停、重播、单帧预览不受全局 TIME 影响。
func seek(seconds: float) -> void:
	_elapsed = maxf(seconds, 0.0)
	if _material != null:
		_material.set_shader_parameter("clock_time", _elapsed)


func restart() -> void:
	seek(0.0)


func get_palette() -> PackedColorArray:
	if use_custom_palette and custom_palette.size() == 5:
		return custom_palette
	return PackedColorArray(PALETTES[palette_preset])


func _sync() -> void:
	if not is_inside_tree() or _material == null:
		return
	var sprite := $Flame as Sprite2D
	sprite.position = Vector2(0, -flame_size.y * 0.5)
	sprite.scale = flame_size / Vector2(64, 80)
	var parameters := {
		"draw_size": flame_size, "pixel_size": pixel_size, "intensity": intensity,
		"flow_speed": flow_speed, "distortion": distortion, "erosion": erosion,
		"wind": wind, "animation_fps": animation_fps, "tall_shape": float(shape),
		"random_seed": random_seed, "embers_enabled": embers_enabled,
		"glow_enabled": glow_enabled, "debug_view": debug_view,
		"use_shape_mask": shape_mask != null,
	}
	for key in parameters:
		_material.set_shader_parameter(key, parameters[key])
	if shape_mask != null:
		_material.set_shader_parameter("shape_mask", shape_mask)
	var colors := get_palette()
	for i in 5:
		_material.set_shader_parameter("color_%d" % i, colors[i])
