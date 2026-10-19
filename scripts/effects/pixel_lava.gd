@tool
extends Node2D
## 像素熔岩地面：独立材质、局部像素网格和物理时钟；不参与伤害与随机数结算。

const SHADER := preload("res://shaders/pixel_lava.gdshader")

@export_range(1.0, 2000.0, 1.0) var radius := 200.0:
	set(value):
		radius = maxf(value, 1.0)
		_sync()
@export_range(1.0, 8.0, 0.5) var pixel_size := 3.0:
	set(value):
		pixel_size = maxf(value, 1.0)
		_sync()
@export_range(0.0, 4.0, 0.05) var flow_speed := 1.0:
	set(value):
		flow_speed = maxf(value, 0.0)
		_sync()
@export_range(12.0, 100.0, 1.0) var plate_size := 38.0:
	set(value):
		plate_size = maxf(value, 12.0)
		_sync()
@export_range(0.05, 0.4, 0.01) var channel_width := 0.18:
	set(value):
		channel_width = clampf(value, 0.05, 0.4)
		_sync()
@export_range(1.0, 30.0, 1.0) var animation_fps := 12.0:
	set(value):
		animation_fps = maxf(value, 1.0)
		_sync()
@export var pattern_seed := 1.0:
	set(value):
		pattern_seed = value
		_sync()
@export var playing := true

var _elapsed := 0.0
var _surface: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_surface = ColorRect.new()
	_surface.name = "LavaSurface"
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.material = _material
	add_child(_surface)
	_sync()
	seek(_elapsed)


func _physics_process(delta: float) -> void:
	if playing:
		seek(_elapsed + delta)


func seek(seconds: float) -> void:
	_elapsed = maxf(seconds, 0.0)
	if _material != null:
		_material.set_shader_parameter("clock_time", _elapsed)


func _sync() -> void:
	if _material == null:
		return
	_surface.position = -Vector2.ONE * radius
	_surface.size = Vector2.ONE * radius * 2.0
	for parameter in ["radius", "pixel_size", "flow_speed", "plate_size", "channel_width", "animation_fps", "pattern_seed"]:
		_material.set_shader_parameter(parameter, get(parameter))
