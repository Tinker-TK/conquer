# 战斗只调用素材库的视觉接口；伤害和状态始终由单位系统结算。
extends RefCounted

const Library = preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd")
const SpriteClock = preload("res://scripts/combat/fixed_sprite_clock.gd")
const UnitScale = preload("res://assets/effect/eslabong_vfx/runtime/unit_scale.gd")
const HIT_FRAMES := {
	"BloodImpactVFX": preload("res://assets/effect/eslabong_vfx/combat_baked/BloodImpactVFX.res"),
	"FireSparks": preload("res://assets/effect/eslabong_vfx/combat_baked/FireSparks.res"),
}
const STATUS_EFFECTS := {
	&"bleed": "BleedVFX", &"converted": "CharmVFX", &"confusion": "ConfusionVFX",
	&"mortal_wounds": "MortalWoundsVFX", &"sleep": "SleepVFX",
	&"stun": "StunVFX", &"weakness": "WeakenVFX", &"slow": "SlowVFX",
	&"poison": "PoisonVFX",
}


static func spawn(unit: Node2D, effect: String, lifetime: float = 1.5, multiplier: float = 1.0) -> Node2D:
	var bounds: Rect2 = unit._smoke_body_rect()
	if effect in ["BloodImpactVFX", "FireSparks"]:
		return _baked_hit(unit, effect, bounds, lifetime, multiplier)
	var holder := Library.spawn(unit, effect, bounds.get_center(), {
		"unit": unit, "max_lifetime": lifetime, "scale": multiplier,
		"ground_position": unit.global_position,
	})
	if holder != null:
		# 库中状态动画与命中素材随游戏暂停、倍速和固定物理时钟推进。
		use_physics_clock(holder)
	return holder


# Godot 粒子构造也会消耗全局 RNG。运行时播放同一 demo 素材的烘焙帧，
# 保留其标定尺寸及锚点，并且不会改变闪避、抽牌或不同倍速下的战斗结果。
static func _baked_hit(unit: Node2D, effect: String, bounds: Rect2, _lifetime: float, multiplier: float) -> Node2D:
	var holder := Node2D.new()
	holder.name = "Eslabong_" + effect
	holder.z_index = 1
	holder.position = bounds.get_center()
	holder.set_meta("effect_id", Library.find(effect).id)
	holder.set_meta("eslabong_scope", true)
	holder.scale = Vector2.ONE * UnitScale.factor(Library.find(effect), multiplier, bounds.size.y)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = HIT_FRAMES[effect]
	holder.add_child(sprite)
	unit.add_child(holder)
	SpriteClock.attach(sprite)
	sprite.animation_finished.connect(holder.queue_free, CONNECT_ONE_SHOT)
	sprite.play(&"default")
	return holder


static func hit(unit: Node2D) -> void:
	spawn(unit, "BloodImpactVFX")
	spawn(unit, "FireSparks", 0.7, 0.45)


static func use_physics_clock(node: Node) -> void:
	if node is AnimatedSprite2D:
		SpriteClock.attach(node)
	if node is AnimationPlayer:
		node.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	if node is Timer:
		node.process_callback = Timer.TIMER_PROCESS_PHYSICS
	for child in node.get_children():
		use_physics_clock(child)
