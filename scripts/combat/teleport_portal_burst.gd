# 包装演示中的原传送门特效，给循环特效补上短暂播放和阶段清理。
extends Node2D

var effect: PackedScene
var effect_scale := 3.0
var remaining := 0.8
var visual: Node2D


func _ready() -> void:
	add_to_group("teleport_portal_burst")
	# 与单位共用脚底排序；生成时排在单位分支之前，不盖住落点的狼人。
	z_index = 0
	if effect != null:
		visual = effect.instantiate() as Node2D
		if visual != null:
			visual.scale = Vector2.ONE * effect_scale
			add_child(visual)
	SignalBus.phase_change.connect(_on_phase_changed)


func _on_phase_changed(phase: Global.GamePhase) -> void:
	if phase != Global.GamePhase.AUTO_BATTLE:
		queue_free()


func _physics_process(delta: float) -> void:
	remaining -= delta
	if remaining <= 0:
		queue_free()
