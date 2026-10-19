@tool
extends Node2D
## 程序化沿面燃烧：不规则燃烧前沿、贴地卷焰；火星继续使用实验室原粒子。

const SHADER := preload("res://shaders/ground_surface_burn.gdshader")
var _surface: ColorRect
var _material: ShaderMaterial


func configure(area_radius: float, density: float, pattern_seed: float, pixel_size: float = 2.0) -> void:
	if _surface == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_surface = ColorRect.new()
		_surface.name = "BurningSurface"
		_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_surface.material = _material
		add_child(_surface)
	_surface.position = -Vector2.ONE * area_radius
	_surface.size = Vector2.ONE * area_radius * 2.0
	_surface.visible = density > 0.0
	_material.set_shader_parameter("radius", area_radius)
	_material.set_shader_parameter("density", density)
	_material.set_shader_parameter("pattern_seed", pattern_seed)
	_material.set_shader_parameter("pixel_size", pixel_size)


func seek(seconds: float) -> void:
	if _material != null:
		_material.set_shader_parameter("clock_time", maxf(seconds, 0.0))
