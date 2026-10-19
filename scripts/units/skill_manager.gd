# 这玩意儿是干嘛的（核心逻辑）：按路径、血量或生命比例选择目标，管理技能冷却和施法状态。
# 数据是咋流动的（数据流向）：导航与敌军位置 → 稳定的追击目标 → 普攻或防守反击 → 动画结束后解锁。
# 为啥这么写（选型决策）：湖泊会让直线最近的敌人实际很远；保留目标并按导航路径比较，避免每帧掉头。
# 性能咋样（复杂度）：普通索敌每隔约三分之一秒查路径；剑矢士兵额外扫描射程内敌军，不查路径，动画只连接一次信号。
extends Node2D

@onready var player_entity: CharacterBody2D = $".."
@onready var animated_sprite_2d: AnimatedSprite2D = get_node_or_null("../AnimatedSprite2D")

var current_target: UnitBase = null:
	set(value):
		current_target = value
		# 技能收尾的 null 不算换目标，选中另一个敌人时先撤销连击增益。
		if is_instance_valid(player_entity) and is_instance_valid(value):
			player_entity.notify_attack_target(value)
var _nearest_enemy_target: UnitBase = null
var _next_enemy_scan_frame: int = 0
const ENEMY_SCAN_FRAMES := 20
const RETARGET_MARGIN := 32.0
const RETARGET_RATIO := 0.8
var cast_target: UnitBase = null
var group_skills: Array[SkillBase] = []
var _skill_time_cd: Dictionary = {}

var current_skill: SkillBase = null
var is_casting: bool = false          # 技能使用中
# 一次施法独有的快照；技能资源由多个单位共享，不能在资源上保存护盾等运行值。
var cast_data: Dictionary = {}
var is_chanting := false
var chant_elapsed := 0.0
var chant_bar: Node2D
var is_reacting: bool = false         # 防守反击中
var _reaction_skill: SkillBase = null
var _reaction_target: UnitBase = null
var _reaction_stage: StringName = &""
var _reaction_hits: Dictionary = {}
var _reaction_has_hit := false
var is_forced_moving: bool = false    # 强制位移中
var forced_movement_tween: Tween
var cooldown_multiplier := 1.0
const SWORD_ARROW_RANGE := 300.0
const SWORD_ARROW_ANIMATION := &"attack_03"
const SWORD_ARROW_HIT_FRAME := 7
var _cast_sword_arrow := false
var _sword_arrow_attack: SkillBase


func has_sword_arrow() -> bool:
	return player_entity.unit_data.has_sword_arrow()


# 只扩大普通攻击的可施放距离，技能资源和计时器保持原样。
func get_attack_range(skill: SkillBase) -> float:
	if skill.is_global_cast():
		return INF
	return SWORD_ARROW_RANGE if player_entity.unit_data.is_basic_attack(skill) and has_sword_arrow() else skill.cast_range


func _cast_animation_for(skill: SkillBase) -> StringName:
	return SWORD_ARROW_ANIMATION if _cast_sword_arrow and skill == current_skill else StringName(skill.cast_animation)


# 强化士兵优先处理射程内的近处敌人，避免路径目标缓存忽略已经贴身的敌人。
func _find_sword_arrow_enemy() -> UnitBase:
	var nearest: UnitBase
	var distance_squared := SWORD_ARROW_RANGE * SWORD_ARROW_RANGE
	for candidate in get_tree().get_nodes_in_group(player_entity.enemy_team()):
		var enemy := candidate as UnitBase
		if not _can_target_enemy(enemy) or enemy.is_in_group("player_base"):
			continue
		var distance: float = player_entity.global_position.distance_squared_to(enemy.global_position)
		if distance <= distance_squared:
			nearest = enemy
			distance_squared = distance
	return nearest


func set_cooldown_multiplier(value: float) -> void:
	value = maxf(value, 0.01)
	if is_equal_approx(value, cooldown_multiplier):
		return
	var previous := cooldown_multiplier
	cooldown_multiplier = value
	for skill: SkillBase in _skill_time_cd:
		var timer := _skill_time_cd[skill] as Timer
		var remaining := timer.time_left / previous * value
		if not timer.is_stopped():
			timer.start(maxf(remaining, 0.001))
		timer.wait_time = maxf(0.001, skill.cooldown * value)


func clear_target_cache() -> void:
	_nearest_enemy_target = null
	_next_enemy_scan_frame = 0


# 眩晕与策反时中断所有动作，保留真实冷却进度；直接位移 Tween 也必须停止。
func interrupt_actions() -> void:
	if forced_movement_tween != null and forced_movement_tween.is_valid():
		forced_movement_tween.kill()
	forced_movement_tween = null
	is_forced_moving = false
	var collision := player_entity.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		collision.set_deferred("disabled", false)
	var area := player_entity.get_node_or_null("AttackArea") as Area2D
	if area != null:
		area.set_deferred("monitoring", false)
	if is_reacting:
		_finish_reaction()
	finish_skill(current_skill)
	clear_target_cache()
	player_entity.velocity = Vector2.ZERO
	player_entity.actions_interrupted.emit()

# 作用：让详情面板读取技能实际剩余冷却；skill 是要查询的技能，返回秒数。
func get_cooldown_left(skill: SkillBase) -> float:
	var timer := _skill_time_cd.get(skill) as Timer
	return timer.time_left if is_instance_valid(timer) else 0.0


# 技能的击杀刷新仅清空该单位、该技能的计时器，不改动共享资源或其它技能。
func reset_cooldown(skill: SkillBase) -> void:
	var timer := _skill_time_cd.get(skill) as Timer
	if is_instance_valid(timer):
		timer.stop()


# 当前一次冷却的比例；start(seconds) 可覆盖基础 CD，因此读取 Timer 的实际时长。
func get_cooldown_fraction(skill: SkillBase) -> float:
	var timer := _skill_time_cd.get(skill) as Timer
	if not is_instance_valid(timer) or timer.is_stopped() or timer.wait_time <= 0.0:
		return 0.0
	return clampf(timer.time_left / timer.wait_time, 0.0, 1.0)

# 作用：Godot 初始化节点时安装技能，并连接命中帧与动画结束信号。
func _ready() -> void:
	if player_entity.is_initialization_rejected():
		return
	setup(player_entity.unit_data.skills)
	# 兼容已有场景连线，新场景也不会因漏连命中帧而静默失效。
	if not animated_sprite_2d.frame_changed.is_connected(_on_animated_sprite_2d_frame_changed):
		animated_sprite_2d.frame_changed.connect(_on_animated_sprite_2d_frame_changed)
	animated_sprite_2d.animation_finished.connect(_on_cast_animation_finished)
	animated_sprite_2d.animation_changed.connect(_on_reaction_animation_changed)
	SignalBus.phase_change.connect(_on_reaction_phase_changed)
	player_entity.unit_died.connect(_on_reaction_unit_died)

# 初始化角色技能包  每个技能对应一个timer节点，用来计时技能cd
func setup(skills: Array[SkillBase]):
	var list: Array[SkillBase] = skills.duplicate()
	for skill in list:
		if not player_entity.unit_data.is_skill_unlocked(skill):
			continue
		group_skills.append(skill)
		if skill.is_passive():
			var passive := skill.create_passive(player_entity)
			if passive != null:
				add_child(passive)
			continue
		var t: = Timer.new()
		# 冷却与命中动画共用物理时钟，倍速或低画面帧率不会改变出手顺序。
		t.process_callback = Timer.TIMER_PROCESS_PHYSICS
		t.one_shot = true
		t.wait_time = maxf(0.001, skill.cooldown * cooldown_multiplier)
		add_child(t)
		_skill_time_cd[skill] = t
	group_skills.sort_custom(func(a, b): return a.priority > b.priority)

# 检查是否可以攻击
func check_attack():
	if not is_instance_valid(player_entity) or not player_entity.can_use_skills():
		return
	var attack_judge: Array[bool] = [
		not is_reacting,
		not is_casting,
		not is_forced_moving,
	]
	# 对自己施法（例如召唤）没有左右方向，保留施法前的朝向。
	if is_instance_valid(cast_target) and cast_target != player_entity:
		animated_sprite_2d.flip_h = player_entity.global_position.x > cast_target.global_position.x
	if attack_judge.has(false):
		return
	if player_entity.current_state == player_entity.State.DEATH:
		return
	if not pick_skill():
		return
	if current_skill == null or not is_instance_valid(current_target):
		return
	if player_entity.global_position.distance_to(current_target.global_position) <= get_attack_range(current_skill) + 0.001:
		player_entity.switch_state(player_entity.State.ATTACK)

# 作用：开始已选中的技能，命中由动画帧触发；没有参数，没有返回值。
func attack():
	if not player_entity.can_use_skills():
		return
	if is_casting:
		return
	if is_instance_valid(current_target) and current_target.unit_data.unit_team != player_entity.unit_data.unit_team \
		and not _can_target_enemy(current_target):
		finish_skill(current_skill)
		return
	if not player_entity.unit_data.is_skill_unlocked(current_skill) or current_skill.is_passive() or not is_instance_valid(current_target):
		current_skill = null
		current_target = null
		player_entity.switch_state(player_entity.State.IDLE)
		return
	is_casting = true
	cast_data.clear()
	cast_target = current_target
	var skill := current_skill
	_cast_sword_arrow = has_sword_arrow() and player_entity.unit_data.is_basic_attack(skill) \
		and player_entity.global_position.distance_to(cast_target.global_position) > skill.cast_range
	if skill.chant_duration > 0.0:
		is_chanting = true
		chant_elapsed = 0.0
		player_entity.navigation_agent_2d.stop_navigation()
		animated_sprite_2d.play("idle")
		if chant_bar == null:
			chant_bar = preload("res://scripts/ui/chant_bar.gd").new()
			chant_bar.name = "ChantBar"
			player_entity.add_child(chant_bar)
		var bounds: Rect2 = player_entity._smoke_body_rect()
		chant_bar.position = Vector2(bounds.get_center().x, bounds.position.y - 12.0)
		chant_bar.z_index = 10
		chant_bar.set_progress(0.0)
		chant_bar.show()
		return
	_begin_skill_action(skill)


func _start_skill_cooldown(skill: SkillBase) -> void:
	var timer := _skill_time_cd.get(skill) as Timer
	if is_instance_valid(timer):
		timer.start(maxf(0.001, skill.cooldown * cooldown_multiplier))


func _begin_skill_action(skill: SkillBase) -> void:
	_start_skill_cooldown(skill)
	if not skill.begin_cast(player_entity, cast_target):
		finish_skill(skill)
		return
	if not skill.owns_cast_animation():
		animated_sprite_2d.play(_cast_animation_for(skill))
	# 普通攻击由统一信号收尾；冲刺等 manual_finish 技能仍自行调用 finish_skill。


func _end_chant() -> void:
	is_chanting = false
	chant_elapsed = 0.0
	if is_instance_valid(chant_bar):
		chant_bar.hide()


func interrupt_chant() -> void:
	if is_chanting:
		interrupt_actions()


func _physics_process(delta: float) -> void:
	if not is_chanting:
		return
	if Global.game_phase != Global.GamePhase.AUTO_BATTLE or not player_entity.can_use_skills() \
		or player_entity._encounter_finished() or not is_instance_valid(cast_target) \
		or cast_target.is_queued_for_deletion() or cast_target.current_state == UnitBase.State.DEATH \
		or not player_entity.unit_data.is_skill_unlocked(current_skill):
		interrupt_actions()
		return
	if current_skill.target_type != SkillBase.TargetType.SELF:
		var allied := current_skill.target_type == SkillBase.TargetType.ALLY_LOWEST_HP
		if allied != (cast_target.unit_data.unit_team == player_entity.unit_data.unit_team) and not player_entity.is_potion_confused():
			interrupt_actions()
			return
	chant_elapsed = minf(current_skill.chant_duration, chant_elapsed + delta)
	chant_bar.set_progress(chant_elapsed / current_skill.chant_duration)
	if chant_elapsed + 0.000001 >= current_skill.chant_duration:
		var skill := current_skill
		_end_chant()
		_begin_skill_action(skill)


# 作用：Godot 播完非循环动画时解除当前普通攻击的锁；没有参数，没有返回值。
func _on_cast_animation_finished() -> void:
	# 防守结束接反击；反击结束统一解锁，不依赖最后一个命中帧是否存在。
	if is_reacting:
		if _reaction_stage == &"defend" and _reaction_target_alive():
			_reaction_stage = &"counter"
			animated_sprite_2d.stop()
			animated_sprite_2d.play(_reaction_skill.cast_animation)
			if is_reacting:
				_apply_reaction_frame()
		else:
			_finish_reaction()
		return
	if not is_casting or is_chanting or current_skill == null or current_skill.manual_finish:
		return
	# 死亡、受击或反击动画结束不能冒充本次攻击完成。
	if is_reacting or animated_sprite_2d.animation != _cast_animation_for(current_skill):
		return
	finish_skill(current_skill)

# 选择角色使用的技能
func pick_skill() -> bool:
	var enhanced := has_sword_arrow()
	var forced: UnitBase = player_entity.status_runtime.taunt_target() if player_entity.status_runtime != null else null
	var nearby_enemy := forced if forced != null else (_find_sword_arrow_enemy() if enhanced else null)
	var approach_skill: SkillBase = null
	var approach_target: UnitBase
	for skill in group_skills:
		if player_entity.is_potion_confused() and not player_entity.unit_data.is_basic_attack(skill):
			continue
		if skill.is_passive():
			continue
		if not player_entity.unit_data.is_skill_unlocked(skill):
			continue
		if not _skill_time_cd[skill].is_stopped():
			continue
		var target = find_target_for_skill(skill)
		if enhanced and skill.target_type == SkillBase.TargetType.ENEMY_NEAREST and is_instance_valid(nearby_enemy):
			target = nearby_enemy
		if not is_instance_valid(target):  # 当前技能的目标是否存在，不存在就跳过
			continue
		# 跨层、剑矢或允许范围回退的近战技能，先尝试能立刻释放的技能；都够不到仍按原优先级寻路。
		if (enhanced or skill.try_other_skills_when_out_of_range() or not player_entity.is_on_same_floor(target)) \
			and player_entity.global_position.distance_to(target.global_position) > get_attack_range(skill) + 0.001:
			if approach_skill == null:
				approach_skill = skill
				approach_target = target
			continue
		current_skill = skill
		current_target = target
		return true
	if approach_skill != null:
		current_skill = approach_skill
		current_target = approach_target
		return true
	current_skill = null
	current_target = null
	return false

# 主动结束技能的方法
func finish_skill(skill: SkillBase) -> void:
	if current_skill != skill:
		return
	if is_chanting:
		_start_skill_cooldown(current_skill)
	_end_chant()

	cast_data.clear()
	cast_target = null
	current_target = null
	current_skill = null
	is_casting = false
	_cast_sword_arrow = false

	if player_entity.current_state != player_entity.State.DEATH:
		player_entity.switch_state(player_entity.State.IDLE)
		animated_sprite_2d.play("idle")

# 发动攻击，有发射物就发射，没有发射物直接攻击受伤
func fire_projectile(skill: SkillBase) -> void:
	if is_chanting:
		return
	if not player_entity.unit_data.is_skill_unlocked(skill) or skill.is_passive():
		return
	# 旧攻击动画可能仍在播，但回合结束或死亡后不能再次结算命中。
	if Global.game_phase != Global.GamePhase.AUTO_BATTLE or player_entity.current_state == UnitBase.State.DEATH or not player_entity.can_use_skills():
		return
	var safe_target: UnitBase = null
	if is_instance_valid(cast_target):
		safe_target = cast_target
	if skill.requires_live_target_on_hit() and safe_target != null and safe_target.unit_data.unit_team != player_entity.unit_data.unit_team \
		and not _can_target_enemy(safe_target):
		return
	var attack_skill := skill
	if _cast_sword_arrow and skill == current_skill:
		if not has_sword_arrow() or not is_instance_valid(safe_target):
			return
		# 命中帧之前敌人已经近身时，本次也改用近战；冷却早已由普攻启动。
		if player_entity.global_position.distance_to(safe_target.global_position) > skill.cast_range:
			if _sword_arrow_attack == null:
				_sword_arrow_attack = preload("res://data/skills/archer_arrow_attack.tres").duplicate() as SkillBase
			_sword_arrow_attack.attack_rate = skill.attack_rate
			_sword_arrow_attack.status_effects = skill.status_effects
			attack_skill = _sword_arrow_attack
	player_entity.combat_audio.play_attack(player_entity, attack_skill, safe_target)
	attack_skill.execute(player_entity, safe_target)

# 根据帧数判定攻击对象受伤
func _on_animated_sprite_2d_frame_changed() -> void:
	if not is_instance_valid(player_entity) or not player_entity.can_use_skills():
		return
	# 反击期间只能结算反击，不能重复触发被打断的普通攻击。
	if is_reacting:
		if _reaction_stage == &"counter":
			_apply_reaction_frame()
		return
	if current_skill == null or not is_casting or is_chanting:
		return
	# 敌人近身后切回原近战动作和命中帧，已经启动的普攻冷却继续计时。
	if _cast_sword_arrow and animated_sprite_2d.animation == SWORD_ARROW_ANIMATION and is_instance_valid(cast_target) \
		and player_entity.global_position.distance_to(cast_target.global_position) <= current_skill.cast_range:
		_cast_sword_arrow = false
		animated_sprite_2d.play(current_skill.cast_animation)
		return
	var is_hit_frame: bool = animated_sprite_2d.frame == SWORD_ARROW_HIT_FRAME if _cast_sword_arrow else animated_sprite_2d.frame in current_skill.hit_frame
	if animated_sprite_2d.animation == _cast_animation_for(current_skill) and is_hit_frame and player_entity.current_state == player_entity.State.ATTACK:
		fire_projectile(current_skill)

# 作用：按技能配置选择目标；skill 是待释放技能，返回目标或空。
func find_target_for_skill(skill: SkillBase):
	if player_entity.is_potion_confused():
		return find_nearest_enemy()
	if skill.target_type not in [SkillBase.TargetType.SELF, SkillBase.TargetType.ALLY_LOWEST_HP] and player_entity.status_runtime != null:
		var forced: UnitBase = player_entity.status_runtime.taunt_target()
		if forced != null:
			return forced if skill.accepts_forced_target(player_entity, forced) else null
	if skill.has_custom_targeting():
		return skill.select_target(player_entity)
	match skill.target_type:
		SkillBase.TargetType.ENEMY_NEAREST:
			return find_nearest_enemy()
			
		SkillBase.TargetType.ALLY_LOWEST_HP:
			return find_ally_lowest_hp(skill)
			
		SkillBase.TargetType.SELF:
			return player_entity
		SkillBase.TargetType.ENEMY_LOWEST_HP:
			return find_lowest_health_enemy(false)
		SkillBase.TargetType.ENEMY_LOWEST_HP_PERCENT:
			return find_lowest_health_enemy(true)
		SkillBase.TargetType.ENEMY_FARTHEST:
			return find_farthest_enemy()
	return null


func attack_target() -> UnitBase:
	if is_reacting:
		return _reaction_target
	var skill := current_skill
	if skill == null or skill.target_type in [SkillBase.TargetType.SELF, SkillBase.TargetType.ALLY_LOWEST_HP]:
		return null
	return cast_target if is_casting else current_target


# 嘲讽更换当前攻击对象，已经进入冷却的旧动作不退款；眩晕、睡眠、混乱和强制位移优先。
func redirect_to_taunt(target: UnitBase) -> void:
	if not player_entity.can_use_skills() or is_forced_moving or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		return
	if is_casting and current_skill != null and current_skill.target_type in [SkillBase.TargetType.SELF, SkillBase.TargetType.ALLY_LOWEST_HP]:
		return
	if attack_target() == target:
		return
	if is_casting or is_reacting:
		interrupt_actions()
	clear_target_cache()
	player_entity.navigation_agent_2d.stop_navigation()
	pick_skill()


# 作用：寻找最虚弱的敌军；use_percent 为真时比较当前生命/最大生命，否则比较剩余生命值。
# 返回存活目标或空；敌军清空后不再寻找建筑目标。
func find_lowest_health_enemy(use_percent: bool) -> UnitBase:
	var enemy_group: String = player_entity.enemy_team()
	var best: UnitBase = null
	var best_health := INF
	var best_distance := INF
	# 与最近敌人索敌一样扫描全体敌军，距离只用于同血量时择近；施法范围仍由 check_attack 判断。
	for candidate in get_tree().get_nodes_in_group(enemy_group):
		var enemy := candidate as UnitBase
		if not _can_target_enemy(enemy):
			continue
		# 非法的最大生命不能参与比例计算，避免除零；满血敌人仍是合法攻击目标。
		if enemy.unit_data == null or enemy.unit_data.max_hp <= 0:
			continue
		var health := float(enemy.current_health)
		if use_percent:
			health /= float(enemy.unit_data.max_hp)
		var distance := player_entity.global_position.distance_squared_to(enemy.global_position)
		if best == null or health < best_health or (health == best_health and distance < best_distance):
			best = enemy
			best_health = health
			best_distance = distance
	if best != null:
		return best
	return null

# 作用：确认敌人还在场上且能被攻击；enemy 是候选值，返回能否继续追击。
func _can_target_enemy(enemy: Variant) -> bool:
	# 缓存里的单位可能已经 queue_free；先接收原始值再验证，避免类型检查在函数入口就报错。
	if not is_instance_valid(enemy) or not enemy is UnitBase:
		return false
	var unit := enemy as UnitBase
	return unit != player_entity and not unit.is_queued_for_deletion() \
		and unit.unit_data != null and unit.can_be_targeted_by(player_entity) \
		and unit.unit_data.unit_team == player_entity.enemy_team() \
		and not unit.is_in_group("player_base") and unit.current_state != UnitBase.State.DEATH and unit.current_health > 0

# 作用：计算走到敌人身边需要的距离；enemy 是候选单位，返回路径长度，无导航时退回直线距离。
func find_farthest_enemy() -> UnitBase:
	var enemy_group: String = player_entity.enemy_team()
	var farthest: UnitBase
	var distance := -1.0
	for candidate in get_tree().get_nodes_in_group(enemy_group):
		if not _can_target_enemy(candidate):
			continue
		var next: float = player_entity.global_position.distance_squared_to(candidate.global_position)
		if next > distance:
			farthest = candidate
			distance = next
	return farthest


func _enemy_travel_distance(enemy: UnitBase) -> float:
	var start: Vector2 = player_entity.global_position
	var finish: Vector2 = enemy.global_position
	if player_entity.unit_data.is_flying:
		return start.distance_to(finish)
	# 射程内可直接跨层攻击，无需存在楼梯；射程外仍按真实楼梯路线接敌。
	if not player_entity.is_on_same_floor(enemy):
		var direct_distance := start.distance_to(finish)
		for skill in group_skills:
			if skill.is_passive() or not player_entity.unit_data.is_skill_unlocked(skill) \
				or skill.target_type in [SkillBase.TargetType.SELF, SkillBase.TargetType.ALLY_LOWEST_HP]:
				continue
			if direct_distance <= get_attack_range(skill):
				return direct_distance
	if is_instance_valid(player_entity.floor_map):
		var route: Dictionary = player_entity.floor_map.route(start, player_entity.floor_id, finish, enemy.floor_id)
		return route.get("distance", INF)
	var map: RID = player_entity.navigation_agent_2d.get_navigation_map()
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return start.distance_to(finish)
	# 这里读取现成导航图，不修改追击代理的当前路径；水面和墙因此计入真实绕行距离。
	var path: PackedVector2Array = NavigationServer2D.map_get_path(map, start, finish, true)
	if path.is_empty():
		return INF
	# 单位可能站在导航边缘外几像素；起终点到路径的距离也要算进去，不能把隔墙投影当作近路。
	var distance := start.distance_to(path[0]) + path[path.size() - 1].distance_to(finish)
	for index in range(1, path.size()):
		distance += path[index - 1].distance_to(path[index])
	return distance

# 作用：选出路径最近的存活敌军；没有参数，返回追击目标或空，敌军清空后交给回合管理器。
func find_nearest_enemy() -> UnitBase:
	var enemy_group: String = player_entity.enemy_team()
	# 活目标保持到下次定期复查；死亡、退场或切阶段时立刻重新选，避免追着空位置跑。
	var frame := Engine.get_physics_frames()
	if Global.game_phase == Global.GamePhase.AUTO_BATTLE and frame < _next_enemy_scan_frame \
		and _can_target_enemy(_nearest_enemy_target):
		return _nearest_enemy_target
	_next_enemy_scan_frame = frame + ENEMY_SCAN_FRAMES
	var best: UnitBase = null
	var best_distance := INF
	var locked_distance := INF
	for candidate in get_tree().get_nodes_in_group(enemy_group):
		var enemy := candidate as UnitBase
		# 只追踪正式活单位，死者、待删除者和旧建筑不能占住目标锁。
		if not _can_target_enemy(enemy) or enemy.is_in_group("player_base"):
			continue
		var distance := _enemy_travel_distance(enemy)
		if distance == INF:
			continue
		if enemy == _nearest_enemy_target:
			locked_distance = distance
		if best == null or distance < best_distance:
			best = enemy
			best_distance = distance
	if best != null:
		# 两人绕行距离相近时继续追原目标；只有明显更近才掉头，避免路口来回横跳。
		if _can_target_enemy(_nearest_enemy_target) and not _nearest_enemy_target.is_in_group("player_base") \
			and locked_distance < INF and (best_distance >= locked_distance * RETARGET_RATIO \
			or best_distance + RETARGET_MARGIN >= locked_distance):
			best = _nearest_enemy_target
		_nearest_enemy_target = best
		return best
	_nearest_enemy_target = null
	return null

# 找血量百分比最低的友军
func find_ally_lowest_hp(skill: SkillBase = null) -> UnitBase:
	var lowest: UnitBase
	var highest: UnitBase
	var lowest_ratio := 1.0
	var nearest_distance := INF
	var highest_health := -1
	var highest_distance := INF
	var battle_ref: WeakRef = player_entity.get_meta("battle_owner") if player_entity.has_meta("battle_owner") else null
	var owner_battle = battle_ref.get_ref() if battle_ref != null else null
	for node in get_tree().get_nodes_in_group(player_entity.unit_data.unit_team):
		var ally := node as UnitBase
		if not is_instance_valid(ally) or ally.is_queued_for_deletion() or ally.is_in_group("player_base") \
			or ally.current_state == UnitBase.State.DEATH or ally.current_health <= 0 \
			or ally.unit_data.max_hp <= 0 or ally.unit_data.unit_team != player_entity.unit_data.unit_team:
			continue
		var ally_ref: WeakRef = ally.get_meta("battle_owner") if ally.has_meta("battle_owner") else null
		if (ally_ref.get_ref() if ally_ref != null else null) != owner_battle:
			continue
		# 独立练兵场没有正式战场标记，只在同一队伍容器中寻找友军。
		if owner_battle == null and ally.get_parent() != player_entity.get_parent():
			continue
		var ratio := float(ally.current_health) / float(ally.unit_data.max_hp)
		var distance: float = player_entity.global_position.distance_squared_to(ally.global_position)
		if ratio < 1.0 and (lowest == null or ratio < lowest_ratio or (is_equal_approx(ratio, lowest_ratio) and distance < nearest_distance)):
			lowest = ally
			lowest_ratio = ratio
			nearest_distance = distance
		if ally.current_health > highest_health or (ally.current_health == highest_health and distance < highest_distance):
			highest = ally
			highest_health = int(ally.current_health)
			highest_distance = distance
	if lowest != null:
		return lowest
	return highest if skill != null and "overflow_to_shield" in skill and skill.overflow_to_shield else null
	

# 作用：开始 skill 对 target 的防守反击；没有返回值。
func start_reaction(skill: SkillBase, target: UnitBase) -> void:
	if not player_entity.unit_data.is_skill_unlocked(skill):
		return
	if not _can_target_enemy(target):
		return
	if player_entity.global_position.distance_to(target.global_position) > get_attack_range(skill):
		return
	# 强制位移的技能仍由自身收尾，避免反击与冲刺同时控制角色。
	if not player_entity.can_use_skills() or is_reacting or is_forced_moving or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		return
	var frames := animated_sprite_2d.sprite_frames
	for animation in [&"defend", skill.cast_animation]:
		if not frames.has_animation(animation) or frames.get_animation_loop(animation):
			push_warning("防守反击需要非循环动画：" + str(animation))
			return
	# 防守会替换普通攻击动画，因此同时解除旧施法锁；已经消耗的冷却保持不变。
	if is_chanting:
		finish_skill(current_skill)
	cast_data.clear()
	current_skill = null
	current_target = null
	cast_target = null
	is_casting = false
	player_entity.navigation_agent_2d.stop_navigation()
	is_reacting = true
	_reaction_skill = skill
	_reaction_target = target
	_reaction_stage = &"defend"
	_reaction_hits.clear()
	_reaction_has_hit = false
	animated_sprite_2d.stop()
	animated_sprite_2d.play("defend")

# 作用：判断反击目标是否仍然存活；没有参数，返回能否继续反击。
func _reaction_target_alive() -> bool:
	return _can_target_enemy(_reaction_target) \
		and player_entity.global_position.distance_to(_reaction_target.global_position) <= get_attack_range(_reaction_skill)

# 作用：结算当前反击命中帧；没有参数，没有返回值。
func _apply_reaction_frame() -> void:
	# 切换动画时 stop 也会重置帧；防守动画的重置不能算成反击命中。
	if animated_sprite_2d.animation != _reaction_skill.cast_animation:
		return
	if not _reaction_target_alive():
		_finish_reaction()
		return
	# 同一帧只命中一次；禁止反击再次触发对方反击，避免两人无限互相反击。
	var frame := animated_sprite_2d.frame
	if frame in _reaction_skill.hit_frame and not _reaction_hits.has(frame):
		_reaction_hits[frame] = true
		player_entity.combat_audio.play_attack(player_entity, _reaction_skill, _reaction_target)
		var reaction := _reaction_skill
		var target := _reaction_target
		var relics: Node = player_entity.relic_runtime()
		var amount := int(player_entity.unit_data.attack * reaction.attack_rate)
		if relics != null:
			amount = relics.counter_damage(player_entity, amount)
		if target.get_hurt(amount, player_entity, false, &"", -1, false, reaction.combat_number_kind()):
			if relics != null:
				relics.countered(player_entity)
			var first_hit := not _reaction_has_hit
			_reaction_has_hit = true
			reaction.apply_reaction_hit_statuses(player_entity, target, first_hit)

# 作用：结束或取消反击，恢复待机；没有参数，没有返回值。
func _finish_reaction() -> void:
	is_reacting = false
	_reaction_skill = null
	_reaction_target = null
	_reaction_stage = &""
	_reaction_hits.clear()
	_reaction_has_hit = false
	# 死亡时只清理锁，不播放待机，防止覆盖死亡动画。
	if player_entity.current_state != UnitBase.State.DEATH:
		player_entity.switch_state(UnitBase.State.IDLE)
		animated_sprite_2d.play("idle")

# 作用：引擎切换动画时检查反击是否被打断；没有参数，没有返回值。
func _on_reaction_animation_changed() -> void:
	if is_chanting and animated_sprite_2d.animation != &"idle":
		interrupt_actions()
		return
	if not is_reacting:
		return
	var expected: StringName = &"defend" if _reaction_stage == &"defend" else StringName(_reaction_skill.cast_animation)
	if animated_sprite_2d.animation != expected:
		_finish_reaction()

# 作用：phase 是新的游戏阶段；离开战斗时取消反击与追击目标，没有返回值。
func _on_reaction_phase_changed(phase: Global.GamePhase) -> void:
	if phase != Global.GamePhase.AUTO_BATTLE:
		if is_chanting:
			interrupt_actions()
		# 下一轮可能出现新的近处敌人，旧目标不能跨回合占住索敌缓存。
		_nearest_enemy_target = null
		_next_enemy_scan_frame = 0
		if is_reacting:
			_finish_reaction()

# 作用：unit 是死亡的施法者；死亡信号触发时清理反击，没有返回值。
func _on_reaction_unit_died(_unit: UnitBase) -> void:
	if is_reacting:
		_finish_reaction()
