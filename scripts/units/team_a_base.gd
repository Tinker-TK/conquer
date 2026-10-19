# 这玩意儿是干嘛的（核心逻辑）：己方单位在准备阶段听从右键部署指令，自动战斗时交给索敌逻辑。
# 数据是咋流动的（数据流向）：右键位置投影到导航 → 共用寻路避让 → 各自到达后停止；阶段切换清除旧指令。
# 为啥这么写（选型决策）：部署也需要绕墙，不能沿鼠标方向直冲；一人到达不能让整队提前停下。
# 性能咋样（复杂度）：每个物理帧只检查自身目标；切换阶段时清理一次移动状态。
extends UnitBase

# 移动相关参数
## 准备阶段右键部署移动的到达距离，单位为世界像素。距目标不超过此值时停止移动；越大则更早停下，不改变技能施法范围。
@export var arrival_distance: = 40.0
# 是否被选中
var is_selected: bool = false :
	set(value):
		is_selected = value
		refresh_unit_tint()


# 作用：无施放预览时显示当前选中状态；没有参数，返回黄色或原始颜色。
func normal_unit_tint() -> Color:
	return Color(1, 0.8, 0.3) if is_selected else super.normal_unit_tint()

# 作用：Godot 在单位入树时初始化并监听阶段切换；没有参数，没有返回值。
func _ready() -> void:
	super()
	if not is_combat_initialized():
		return
	SignalBus.phase_change.connect(_on_phase_changed)
	_on_phase_changed(Global.game_phase)

# 作用：Godot 每个物理帧按阶段分配行为；delta 为帧间隔秒数，没有返回值。
func _physics_process(delta: float) -> void:
	if current_state == State.DEATH or is_action_blocked():
		return
	if Global.game_phase == Global.GamePhase.AUTO_BATTLE:
		super._physics_process(delta)
	elif Global.game_phase == Global.GamePhase.CARD_PLAY:
		mouse_move()

# 作用：Godot 在界面未消费右键时下达移动；event 为输入，没有返回值。
func _unhandled_input(event: InputEvent) -> void:
	# 单位详情由双击显示；右键仍可向单位所在位置下达移动命令。
	if Global.game_phase != Global.GamePhase.CARD_PLAY or current_state == State.DEATH or is_action_blocked() or has_status(&"confusion") or is_in_group("converted_enemy"):
		return
	if event is InputEventMouseButton and event.is_action_pressed('move') and is_selected:
		# 与落点提示共用本次事件的坐标，镜头刚移动时也不读取滞后的鼠标位置。
		var world_point: Vector2 = get_canvas_transform().affine_inverse() * event.position
		var floor_step := 1 if event.alt_pressed else (-1 if event.ctrl_pressed else 0)
		var destination := resolve_move_destination(world_point, floor_step)
		if destination.is_empty():
			return
		navigation_agent_2d.stop_navigation()
		move_floor_id = destination.floor
		target_position = destination.position
		
# 作用：只沿玩家本阶段下达的目标移动；没有参数，没有返回值。
func mouse_move():
	if Global.game_phase != Global.GamePhase.CARD_PLAY or current_state == State.DEATH or is_action_blocked() or has_status(&"confusion") or is_in_group("converted_enemy"):
		return
	# 没有部署目标就不执行 move_and_slide，不能沿上一轮战斗速度滑动。
	if target_position == null:
		navigation_agent_2d.stop_navigation()
		return
	if (not is_instance_valid(floor_map) or move_floor_id == floor_id) \
		and (target_position.distance_to(global_position) <= arrival_distance \
			or navigation_agent_2d.has_reached_stair_destination(target_position, arrival_distance)) \
		and not navigation_agent_2d.has_pending_stair_exit():
		_stop_move()
		return
	
	# 与战斗共用导航及避让，物理移动在安全速度回调里统一执行一次。
	navigation_agent_2d.move_to(target_position, move_floor_id if is_instance_valid(floor_map) else -1)


# 作用：停止部署移动；没有参数，没有返回值。死亡时保留死亡动画。
func _stop_move() -> void:
	navigation_agent_2d.stop_navigation()
	target_position = null
	target_vector = Vector2.ZERO
	velocity = Vector2.ZERO
	if is_action_blocked():
		animated_sprite_2d.pause()
		return
	if current_state != State.DEATH:
		# 反击和冲刺有自己的收尾流程，不能用 idle 替换它们正在等待的动画。
		if skill_manager.is_reacting or skill_manager.is_forced_moving:
			return
		if skill_manager.is_casting and skill_manager.current_skill != null:
			if skill_manager.current_skill.manual_finish:
				return
			# 回合结束打断普通攻击时，先解除施法锁，再改为待机。
			# 否则下一轮寻路发现 is_casting 为 true，就会永远站在原地。
			skill_manager.finish_skill(skill_manager.current_skill)
		switch_state(State.IDLE)
		$AnimatedSprite2D.play("idle")


# 作用：全局阶段切换时清除旧指令；phase 是新阶段，没有返回值。
func _on_phase_changed(phase: Global.GamePhase) -> void:
	# 开始自动战斗只清理速度，让战斗逻辑自行决定动画，避免打断攻击。
	target_position = null
	target_vector = Vector2.ZERO
	velocity = Vector2.ZERO
	if phase != Global.GamePhase.AUTO_BATTLE:
		_stop_move()
