# 用 eslabong_vfx_demo 的 SmokeVFX 烟团遮盖出生/死亡，保留现有退场信号接口。
extends Node2D

signal covered
signal finished

@export_range(0.4, 2.0, 0.05) var duration: float = 0.85
var elapsed := 0.0
var body_rect := Rect2(-36, -80, 72, 80)
var _covered := false


func configure(rect: Rect2) -> void:
	body_rect = rect


func _ready() -> void:
	var effect := preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd").spawn(
		self, "SmokeVFX", body_rect.get_center(), {
			"unit_height": maxf(body_rect.size.y, body_rect.size.x),
			"scale": 3.5, "max_lifetime": 0.0,
		})
	if effect != null:
		preload("res://scripts/effects/combat_vfx.gd").use_physics_clock(effect)
		var root: Node = effect.get_meta("visual_root")
		var sprite := root.get_node("AnimatedSprite2D") as AnimatedSprite2D
		var frames := sprite.sprite_frames
		var seconds := 0.0
		for frame in frames.get_frame_count(sprite.animation):
			seconds += frames.get_frame_duration(sprite.animation, frame) / frames.get_animation_speed(sprite.animation)
		sprite.speed_scale = seconds / duration
		sprite.frame = mini(2, frames.get_frame_count(sprite.animation) - 1)


func _physics_process(delta: float) -> void:
	elapsed += delta
	if not _covered and elapsed >= 0.14:
		_covered = true
		covered.emit()
	if elapsed >= duration:
		finished.emit()
		queue_free()
