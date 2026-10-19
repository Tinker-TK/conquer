@tool
extends Node2D
## 直接复用实验室「灼烧 · 地面」的 Particles 节点，不带地面多边形、伤害或秒数期限。

const SOURCE := preload("res://assets/effect/eslabong_vfx/source/Scenes/VFX/BurnGroundVFX.tscn")
var particles: CPUParticles2D
var _source_amount := 30
var _radius_ratio := 35.0 / 45.0
var _request_frame := -1
var _pending_time := 0.0


func configure(area_radius: float, density: float, pattern_seed: float) -> void:
	if particles == null:
		var authored := SOURCE.instantiate() as Area2D
		particles = authored.get_node("Particles") as CPUParticles2D
		var shape := authored.get_node("CollisionShape2D").shape as CircleShape2D
		_source_amount = particles.amount
		_radius_ratio = particles.emission_sphere_radius / shape.radius
		particles.owner = null
		authored.remove_child(particles)
		authored.free()
		particles.set_meta("source_scene", SOURCE.resource_path)
		particles.local_coords = true
		particles.use_fixed_seed = true
		particles.fixed_fps = 60
		# 原粒子由区域物理时钟驱动，暂停、倍速和定格时不会独立向前播放。
		particles.speed_scale = 0.0
		particles.preprocess = 0.0
		add_child(particles)
	particles.seed = absi(int(pattern_seed * 1009.0) + 7919)
	particles.amount = maxi(1, roundi(_source_amount * density))
	particles.emission_sphere_radius = area_radius * _radius_ratio
	particles.emitting = density > 0.0
	particles.visible = density > 0.0


func seek(seconds: float) -> void:
	if particles == null:
		return
	# restart() 会立即执行一次原生更新；先清空未消费的预热请求，避免重复定格多走一段。
	particles.request_particles_process(0.0)
	if not particles.visible:
		particles.emitting = false
		_pending_time = 0.0
		return
	particles.restart(true)
	_request_frame = Engine.get_process_frames()
	# 先预热一个原始寿命，使刚落地的区域已有零散火星。
	_pending_time = particles.lifetime + maxf(seconds, 0.0)
	_request()


func advance(delta: float) -> void:
	if particles == null:
		return
	var frame := Engine.get_process_frames()
	if frame != _request_frame:
		_request_frame = frame
		_pending_time = 0.0
	# 倍速下同一画面可能包含多个物理步，需要累加后交给原粒子模拟。
	_pending_time += delta
	_request()


func _request() -> void:
	# 原模拟向上取整到 fixed_fps，去掉浮点边界误差，避免多走一帧。
	particles.request_particles_process(maxf(0.0, _pending_time - 0.000001))
