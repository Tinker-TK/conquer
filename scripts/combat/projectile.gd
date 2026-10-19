# 这玩意儿是干嘛的（核心逻辑）：推动远程弹飞向目标，命中后结算伤害与特效。
# 数据是咋流动的（数据流向）：技能把目标、伤害和特效传进来 → 飞行 → 命中目标播放特效。
# 为啥这么写（选型决策）：投射物负责撞击时刻；离开交锋阶段立即作废，旧箭不能伤害下一轮单位。
# 性能咋样（复杂度）：普通弹每帧只跟踪目标；穿透弹只扫描对应阵营，特效仅命中时创建。
class_name Projectile
extends Node2D

## 弹道类型
enum Trajectory {
	STRAIGHT,   # 直线：每帧朝目标当前位置飞（自动追踪移动目标）
	PARABOLIC,  # 抛物线：弧线飞行；默认追踪目标，也可锁定发射时落点
}

## 投射物的默认弹道类型：STRAIGHT 沿直线飞行，PARABOLIC 沿弧线飞行。技能调用 fire 发射时会覆盖此值；抛物线追踪由 Track Target 控制。
@export var trajectory: Trajectory = Trajectory.STRAIGHT
## 投射物飞行速度，单位为世界像素/秒；直线弹每帧按此速度前进，抛物线按目标距离估算飞行时间。越大则更快命中。
@export var speed: float = 500.0          # 飞行速度（像素/秒）
## 抛物线弹道中点相对直线路径向上抬起的高度，单位为世界像素；越大则弧线越高，直线弹道不使用此值。
@export var max_height: float = 100.0     # 抛物线最高点高度
## 投射物与目标中心之间的命中距离，单位为世界像素；越大越容易判定命中。穿透直线弹也用此半径检查不同敌人。
@export var hit_radius: float = 24.0      # 命中判定半径
## 投射物最多存活的秒数，超时后自动销毁；用于限制未命中或持续穿透的弹。离开交锋阶段时也会立即清理。
@export var max_lifetime: float = 3.0     # 最长存活时间（秒），防止无限飞
## 投射物图片相对飞行切线的朝向修正，单位为弧度；用于让不同贴图的箭头或弹头朝向正确，不改变飞行方向。
@export_range(-PI, PI, 0.01) var sprite_angle_offset: float = 0.0  # 贴图朝向修正（弧度）
## 抛物线是否持续更新移动目标的落点。开启会追踪目标当前位置，关闭锁定发射时落点，目标走开可能射空；不控制直线弹的追踪规则。
@export var track_target: bool = true     # 抛物线是否追踪移动目标；false = 锁定发射时的落点

var _is_piercing: bool = false          # 新增：这颗箭是否是穿透弹（fire 时定死）
var _owner: UnitBase
var _target: Node2D
var _target_pos: Vector2 = Vector2.ZERO   # 锁定/最后已知的目标位置
var _damage: int = 0
var _start_pos: Vector2 = Vector2.ZERO
var _t: float = 0.0                       # 抛物线进度 0~1
var _duration: float = 1.0                # 抛物线总飞行时间（秒）
var pierce_count: int = 1
var pierce_all := false
var _hit_list: Array = []        # 已命中的敌人（防同一敌人重复结算）
var _enemy_group: String = ""
var _fly_dir: Vector2 = Vector2.ZERO
var _on_hit_effect: PackedScene
var _owner_team := ""
var _owner_identity := 0
var _attack_floor := 1
var hit_sound_profile: StringName = &""
var damage_kind: StringName = &"normal"
var defence_segments: int = 1
var status_skill: Resource
var status_effects: Array[UnitStatusEffect] = []


# 作用：Godot 入树时监听交锋结束；没有参数，没有返回值。
func _ready() -> void:
	SignalBus.phase_change.connect(_on_phase_changed)


# 作用：离开交锋就释放旧弹；phase 是新阶段，没有返回值。
func _on_phase_changed(phase: int) -> void:
	if phase != Global.GamePhase.AUTO_BATTLE:
		queue_free()

# 发射者死亡后返回 null，避免把已经释放的对象传给 get_hurt。
func _get_safe_owner() -> UnitBase:
	if is_instance_valid(_owner):
		return _owner

	return null

# 发射初始化：由攻击单位在命中帧调用
# 作用：初始化本次飞行；参数依次为发射者、目标、伤害、弹道、穿透数、敌方组和命中特效，没有返回值。
func fire(owner_unit: UnitBase, target_unit: Node2D, damage: int, traj: Trajectory = Trajectory.STRAIGHT, pierce: int = 1, enemy_group: String = "", hit_effect: PackedScene = null) -> void:
	_owner = owner_unit
	_owner_identity = owner_unit.get_instance_id()
	_owner_team = owner_unit.unit_data.unit_team
	# 发射后切层或退场不改变这颗弹的高地来源；每个受击者按命中时楼层结算。
	_attack_floor = owner_unit.floor_id
	z_index = maxi(owner_unit.z_index, target_unit.z_index) if is_instance_valid(target_unit) else owner_unit.z_index
	_target = target_unit
	_damage = damage
	trajectory = traj
	pierce_count = pierce
	_enemy_group = enemy_group
	_on_hit_effect = hit_effect
	_hit_list.clear()
	_start_pos = global_position
	if is_instance_valid(_target):
		_target_pos = _target.global_position
	_is_piercing = pierce_all or pierce > 1
	if _is_piercing:
		_fly_dir = (_target_pos - global_position).normalized()
	_duration = _start_pos.distance_to(_target_pos) / maxf(speed, 1.0)
	_duration = maxf(_duration, 0.01)

func _physics_process(delta: float) -> void:
	if is_instance_valid(_owner) and _owner.unit_data.unit_team != _owner_team:
		queue_free()
		return
	if is_queued_for_deletion() or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		queue_free()
		return
	max_lifetime -= delta
	if max_lifetime <= 0.0:
		queue_free()
		return
	match trajectory:
		Trajectory.STRAIGHT:
			_move_straight(delta)
		Trajectory.PARABOLIC:
			_move_parabolic(delta)

# 直线：每帧朝目标当前位置飞（目标死亡则飞向最后位置后消失）
func _move_straight(delta: float) -> void:
	if _is_piercing:                    # 只要这颗箭是穿透弹，就一直走这里
		var from := global_position
		global_position += _fly_dir * speed * delta
		rotation = _fly_dir.angle() + sprite_angle_offset
		var contacts: Array[Dictionary] = []
		for node in get_tree().get_nodes_in_group(_enemy_group):
			var enemy := node as UnitBase
			if not is_instance_valid(enemy) or enemy in _hit_list or enemy.is_queued_for_deletion() \
				or enemy.current_state == UnitBase.State.DEATH or enemy.current_health <= 0 \
				or enemy.unit_data.unit_team != _enemy_group or enemy.get_instance_id() == _owner_identity or enemy.is_in_group("player_base"):
				continue
			# 检查整段飞行轨迹，避免快箭跨过敌人；同帧按路径顺序消耗穿透次数。
			var point := Geometry2D.get_closest_point_to_segment(enemy.global_position, from, global_position)
			if point.distance_squared_to(enemy.global_position) <= hit_radius * hit_radius:
				contacts.append({"enemy": enemy, "distance": from.distance_squared_to(point)})
		contacts.sort_custom(func(a: Dictionary, b: Dictionary): return a.distance < b.distance)
		for contact: Dictionary in contacts:
			var enemy := contact.enemy as UnitBase
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.current_state == UnitBase.State.DEATH:
				continue
			_hit_list.append(enemy)
			var hit_position := enemy.global_position
			if enemy.get_hurt(_damage, _get_safe_owner(), false, hit_sound_profile, _attack_floor, false, damage_kind, defence_segments):
				_apply_statuses(enemy)
				_spawn_hit_effect(hit_position)
			if not pierce_all:
				pierce_count -= 1
				if pierce_count <= 0:
					queue_free()        # 穿透次数耗尽才销毁
					return
		return
	if is_instance_valid(_target):
		_target_pos = _target.global_position
	var dir := global_position.direction_to(_target_pos)
	global_position += dir * speed * delta
	rotation = dir.angle() + sprite_angle_offset
	if is_instance_valid(_target):
		if global_position.distance_to(_target.global_position) <= hit_radius:
			_deal_damage()
	else:
		if global_position.distance_to(_target_pos) <= hit_radius:
			queue_free()

# 抛物线：track_target=true 时每帧朝目标当前位置飞（弧线跟随移动目标）；
# track_target=false 时锁定发射时的落点，按 y = 4h*t*(1-t) 的弧线飞过去
func _move_parabolic(delta: float) -> void:
	if track_target and is_instance_valid(_target):
		_target_pos = _target.global_position
	# 按当前距离动态更新飞行时长，保证飞行速度恒定（目标走远则追得更久）
	_duration = _start_pos.distance_to(_target_pos) / maxf(speed, 1.0)
	_duration = maxf(_duration, 0.01)
	_t += delta / _duration
	var t := clampf(_t, 0.0, 1.0)
	var base := _start_pos.lerp(_target_pos, t)
	var height := 4.0 * max_height * t * (1.0 - t)
	global_position = base + Vector2(0.0, -height)
	# 沿飞行切线方向旋转箭头
	var tangent := (_target_pos - _start_pos) + Vector2(0.0, -4.0 * max_height * (1.0 - 2.0 * t))
	rotation = tangent.angle() + sprite_angle_offset
	if _t >= 1.0:
		# 追踪模式：落点即目标当前位置；锁定模式：目标走远了就会射空
		if is_instance_valid(_target) and global_position.distance_to(_target.global_position) <= hit_radius:
			_deal_damage()
		else:
			queue_free()

func _deal_damage() -> void:
	if is_instance_valid(_target) and _target.has_method("get_hurt"):
		var hit_position := _target.global_position
		if _target.get_hurt(_damage, _get_safe_owner(), false, hit_sound_profile, _attack_floor, false, damage_kind, defence_segments):
			_apply_statuses(_target)
			_spawn_hit_effect(hit_position)
	queue_free()

# 与伤害同时抵达；落空、友军拒绝命中和致死伤害不会留下状态。
func _apply_statuses(target: Node) -> void:
	if status_skill == null or target.current_state == UnitBase.State.DEATH:
		return
	for effect: UnitStatusEffect in status_effects:
		if effect != null:
			effect.apply_to(target, _get_safe_owner(), status_skill, _owner_identity)

# 作用：在 position 播放技能配置的命中特效；没有返回值。
func _spawn_hit_effect(world_position: Vector2) -> void:
	if _on_hit_effect == null:
		return
	var instance := _on_hit_effect.instantiate()
	var effect := instance as AnimatedSprite2D
	if effect == null:
		instance.free()
		push_warning("投射物命中特效的根节点必须是 AnimatedSprite2D")
		return
	# 兼容通用 effect 动画，以及像特殊魔法那样在场景里单独命名的动画。
	var animation_name: StringName = &"effect" if effect.sprite_frames != null and effect.sprite_frames.has_animation(&"effect") else effect.animation
	if effect.sprite_frames == null or not effect.sprite_frames.has_animation(animation_name):
		effect.free()
		push_warning("投射物命中特效缺少可播放的动画")
		return
	get_parent().add_child(effect)
	effect.global_position = world_position
	effect.animation_finished.connect(effect.queue_free, CONNECT_ONE_SHOT)
	effect.stop()
	effect.play(animation_name)
