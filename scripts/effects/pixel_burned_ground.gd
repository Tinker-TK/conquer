@tool
extends Node2D
## 焦草、程序化沿面燃烧和实验室「灼烧 · 地面」火星，共用物理时钟与区域期限。

const SHADER := preload("res://shaders/pixel_burned_ground.gdshader")
const SPARKS := preload("res://scripts/effects/burn_ground_sparks.gd")
const BURNING := preload("res://scripts/effects/ground_burning_layer.gd")

@export_range(1.0, 2000.0, 1.0) var radius := 200.0:
	set(value):
		radius = maxf(value, 1.0)
		_sync()
@export_range(1.0, 6.0, 0.5) var pixel_size := 2.0:
	set(value):
		pixel_size = maxf(value, 1.0)
		_sync()
@export_range(0.0, 1.0, 0.01) var burn_amount := 0.86:
	set(value):
		burn_amount = clampf(value, 0.0, 1.0)
		_sync()
@export_range(0.0, 2.0, 0.05) var spark_density := 1.0:
	set(value):
		spark_density = clampf(value, 0.0, 2.0)
		_sync()
@export_range(0.0, 2.0, 0.05) var flame_density := 0.85:
	set(value):
		flame_density = clampf(value, 0.0, 2.0)
		_sync()
@export_range(0.0, 1.0, 0.01) var flame_opacity := 0.42:
	set(value):
		flame_opacity = clampf(value, 0.0, 1.0)
		_sync()
@export var pattern_seed := 1.0:
	set(value):
		pattern_seed = value
		_sync()
@export var playing := true

var _elapsed := 0.0
var _surface: ColorRect
var _material: ShaderMaterial
var _sparks: Node2D
var _burning: Node2D


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_surface = ColorRect.new()
	_surface.name = "ScorchedGrass"
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.material = _material
	add_child(_surface)
	_burning = BURNING.new()
	_burning.name = "BurningFlames"
	# 火焰从焦草上燃起，位于单位脚下；原有火星仍保留在上方。
	add_child(_burning)
	_sparks = SPARKS.new()
	_sparks.name = "Sparks"
	_sparks.z_index = 2
	add_child(_sparks)
	_sync()
	seek(_elapsed)


func _physics_process(delta: float) -> void:
	if playing:
		_elapsed += delta
		_material.set_shader_parameter("clock_time", _elapsed)
		_burning.seek(_elapsed)
		_sparks.advance(delta)


func seek(seconds: float) -> void:
	_elapsed = maxf(seconds, 0.0)
	if _material != null:
		_material.set_shader_parameter("clock_time", _elapsed)
		_burning.seek(_elapsed)
		_sparks.seek(_elapsed)


func _sync() -> void:
	if _material == null:
		return
	_surface.position = -Vector2.ONE * radius
	_surface.size = Vector2.ONE * radius * 2.0
	for parameter in ["radius", "pixel_size", "burn_amount", "pattern_seed"]:
		_material.set_shader_parameter(parameter, get(parameter))
	_burning.configure(radius, flame_density, pattern_seed, pixel_size)
	_burning.modulate.a = flame_opacity
	_burning.seek(_elapsed)
	_sparks.configure(radius, spark_density, pattern_seed)
	_sparks.seek(_elapsed)
