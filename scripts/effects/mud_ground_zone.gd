# 泥沼复用实验室「Leap · 地面 · 印记」的贴图与入场参数，由区域管理期限。
extends Node2D

const SOURCE := preload("res://assets/effect/eslabong_vfx/source/Scenes/VFX/LeapGroundDecal.tscn")
static var _texture_bounds := Rect2()
var _fade_duration := 0.1
var _target_alpha := 0.85
var _pulse_scale := 1.04
var _decal_tint := Color.WHITE


func _init(radius: float = 150.0) -> void:
	name = "MudGroundZone"
	set_meta("effect_id", "scenes_vfx_leapgrounddecal")
	var authored := SOURCE.instantiate() as Node2D
	_fade_duration = authored.fade_in_duration
	_target_alpha = authored.target_alpha
	_pulse_scale = authored.pulse_scale
	_decal_tint = authored.decal_modulate
	var sprite := authored.get_node("Sprite2D") as Sprite2D
	# 按贴图实际可见范围居中和缩放，忽略透明边距，保持原图透视比例。
	if not _texture_bounds.has_area():
		_texture_bounds = Rect2(sprite.texture.get_image().get_used_rect())
	sprite.offset = sprite.texture.get_size() * 0.5 - _texture_bounds.get_center()
	sprite.scale = Vector2.ONE * radius * 2.0 / _texture_bounds.size.x
	sprite.owner = null
	authored.remove_child(sprite)
	add_child(sprite)
	authored.free()


func _ready() -> void:
	# 沿用素材的淡入与轻微扩张；不执行原脚本按秒淡出和删除的阶段。
	modulate = Color(_decal_tint, 0.0)
	scale = Vector2.ONE / _pulse_scale
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", _target_alpha, _fade_duration)
	tween.tween_property(self, "scale", Vector2.ONE, _fade_duration)
