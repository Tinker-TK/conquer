# AnimatedSprite2D 原生按画面帧播放；战斗动画改按物理步推进，保留原节点、帧事件和播放接口。
# 每个命中帧都逐一触发，支持帧独立时长、循环、反播、暂停和完成回调中的动画切换。
extends Node

var sprite: AnimatedSprite2D


static func attach(target: AnimatedSprite2D) -> void:
	if target.has_node("FixedSpriteClock"):
		return
	var clock := load("res://scripts/combat/fixed_sprite_clock.gd").new() as Node
	clock.name = "FixedSpriteClock"
	clock.sprite = target
	target.add_child(clock)


func _ready() -> void:
	process_priority = -10000
	process_physics_priority = 1000
	sprite.set_process_internal(false)


# play() 会重新开启原生播放；在原生画面帧更新之前关闭，防止双重推进。
func _process(_delta: float) -> void:
	sprite.set_process_internal(false)


func _physics_process(delta: float) -> void:
	sprite.set_process_internal(false)
	var remaining := delta
	var transitions := 0
	while remaining > 0.000000001 and sprite.is_playing() and not sprite.is_queued_for_deletion():
		var frames := sprite.sprite_frames
		var animation := sprite.animation
		if frames == null or not frames.has_animation(animation) or frames.get_frame_count(animation) == 0:
			return
		var speed := sprite.get_playing_speed()
		var fps := frames.get_animation_speed(animation)
		if is_zero_approx(speed) or fps <= 0.0:
			return
		var forward := speed > 0.0
		var duration := maxf(frames.get_frame_duration(animation, sprite.frame) / (fps * absf(speed)), 0.000001)
		var fraction := 1.0 - sprite.frame_progress if forward else sprite.frame_progress
		var until_next := maxf(0.0, fraction * duration)
		if remaining + 0.000000001 < until_next:
			sprite.set_frame_and_progress(sprite.frame, sprite.frame_progress + remaining / duration * (1.0 if forward else -1.0))
			break
		remaining = maxf(0.0, remaining - until_next)
		var next := sprite.frame + (1 if forward else -1)
		var count := frames.get_frame_count(animation)
		if next < 0 or next >= count:
			if not frames.get_animation_loop(animation):
				sprite.set_frame_and_progress(sprite.frame, 1.0 if forward else 0.0)
				sprite.pause()
				sprite.animation_finished.emit()
				break
			sprite.set_frame_and_progress(0 if forward else count - 1, 0.0 if forward else 1.0)
			sprite.animation_looped.emit()
		else:
			sprite.set_frame_and_progress(next, 0.0 if forward else 1.0)
		# 命中可能触发死亡、眩晕或反击，回调切动画后从下一物理步推进新动作。
		if sprite.animation != animation or not sprite.is_playing():
			break
		transitions += 1
		if transitions >= 1024:
			break
	sprite.set_process_internal(false)
