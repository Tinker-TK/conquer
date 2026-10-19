# 这玩意儿是干嘛的（核心逻辑）：管理一次召唤，魔法阵播完出兵，施法者死亡或回合结束就取消。
# 数据是咋流动的（数据流向）：技能传入施法者与场景 → 特效结束信号 → 队伍容器新增单位。
# 为啥这么写（选型决策）：等待属于独立节点，节点随战场销毁，避免资源里的异步等待残留。
# 性能咋样（复杂度）：特效动画按固定物理步推进，生成与取消响应动画、死亡和阶段信号。
extends AnimatedSprite2D

var caster: UnitBase
var summon_scene: PackedScene
var effect_animation: StringName
var resolved := false
var summon_floor: int = 1


# 作用：入树前接收本次召唤的数据；source 是召唤师，scene 是单位场景，animation_name 是特效动画，没有返回值。
func configure(source: UnitBase, scene: PackedScene, animation_name: StringName) -> void:
	caster = source
	summon_floor = source.floor_id
	z_index = source.z_index
	summon_scene = scene
	effect_animation = animation_name


# 作用：Godot 在特效入树时连接中断与完成信号并播放；没有参数，没有返回值。
func _ready() -> void:
	preload("res://scripts/combat/fixed_sprite_clock.gd").attach(self)
	if not is_instance_valid(caster):
		_cancel()
		return
	# 信号接收者是本特效，特效删除后 Godot 会自动解除连接。
	SignalBus.phase_change.connect(_on_phase_changed)
	caster.unit_died.connect(_on_caster_died)
	caster.actions_interrupted.connect(_cancel)
	caster.tree_exiting.connect(_cancel)
	animation_finished.connect(_on_animation_finished)
	stop()
	play(effect_animation)


# 作用：动画播放结束时生成一个怪物；没有参数，没有返回值。
func _on_animation_finished() -> void:
	if resolved or animation != effect_animation:
		return
	if not is_instance_valid(caster) or caster.is_queued_for_deletion():
		_cancel()
		return
	if not caster.can_use_skills() or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		_cancel()
		return

	# 先锁住完成状态，防止重复通知让一次召唤生成多只怪物。
	resolved = true
	var instance := summon_scene.instantiate()
	var unit := instance as UnitBase
	if unit == null or unit.unit_data == null:
		instance.free()
		queue_free()
		push_warning("召唤场景必须是带有 UnitData 的 UnitBase")
		return

	# 本技能要求场景阵营与施法者一致，避免数据、分组和碰撞层彼此矛盾。
	if unit.unit_data.unit_team != caster.unit_data.unit_team:
		unit.free()
		queue_free()
		push_warning("召唤物和施法者的阵营必须一致")
		return
	var team := get_parent() as Node2D
	unit.position = team.to_local(global_position)
	unit.floor_id = summon_floor
	team.add_child(unit)
	queue_free()


# 作用：游戏阶段变化时取消尚未完成的召唤；phase 是新阶段，没有返回值。
func _on_phase_changed(phase: Global.GamePhase) -> void:
	if phase != Global.GamePhase.AUTO_BATTLE:
		_cancel()


# 作用：召唤师死亡立即取消魔法阵；_unit 是死亡的召唤师，没有返回值。
func _on_caster_died(_unit: UnitBase) -> void:
	_cancel()


# 作用：让这次召唤失效并释放魔法阵；没有参数，没有返回值。
func _cancel() -> void:
	resolved = true
	queue_free()
