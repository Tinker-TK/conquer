@tool
extends Node
## 跟随父 AnimatedSprite2D 的实际图集帧更新像素网格，不参与动画或战斗计时。

const Palette = preload("res://scripts/units/enemy_pixel_palette.gd")
@export var palette: Palette
var sprite: AnimatedSprite2D


func _ready() -> void:
	sprite = get_parent() as AnimatedSprite2D
	assert(sprite != null and palette != null)
	assert(palette.source_colors.size() == palette.target_colors.size())
	assert(palette.source_colors.size() > 0 and palette.source_colors.size() <= 32)
	var material := sprite.material as ShaderMaterial
	material.set_shader_parameter("pixel_step", 2.0)
	material.set_shader_parameter("match_palette", true)
	material.set_shader_parameter("source_palette_texture", palette.source_texture())
	material.set_shader_parameter("palette_texture", palette.target_texture())
	material.set_shader_parameter("palette_count", palette.source_colors.size())
	sprite.frame_changed.connect(_sync_frame)
	sprite.animation_changed.connect(_sync_frame)
	_sync_frame()


func _sync_frame() -> void:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(sprite.animation):
		return
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	# UnitBase 会复制材质以隔离受击闪红；每次读取当前材质，避免更新复制前的旧实例。
	var material := sprite.material as ShaderMaterial
	if texture is AtlasTexture:
		material.set_shader_parameter("frame_origin", texture.region.position)
		material.set_shader_parameter("frame_size", texture.region.size)
	elif texture != null:
		material.set_shader_parameter("frame_origin", Vector2.ZERO)
		material.set_shader_parameter("frame_size", texture.get_size())
