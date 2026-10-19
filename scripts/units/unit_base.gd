# 这玩意儿是干嘛的（核心逻辑）：管理单位生命与战斗，生成后播放待机动画，提供命中、死亡等卡牌效果接口。
# 数据是咋流动的（数据流向）：生成时复制属性与动画资源并启动 idle；独立属性 → 命中与死亡信号；拖牌预览 → 临时颜色。
# 为啥这么写（选型决策）：每个单位复制资源，替换动画资源后显式恢复播放；登记战场的弱引用阻止结束后残留伤害。
# 性能咋样（复杂度）：生成时复制一次资源并启动待机；动画按固定物理步推进，命中与死亡时才通知效果系统。
extends CharacterBody2D
class_name UnitBase

# 单位数据导入
## 此单位的基础属性、阵营、卡面和技能配置资源。出场时读取并建立独立运行数据；场景应绑定与实际单位动画和技能相匹配的 UnitData。
@export var unit_data: UnitData

## 单位当前逻辑楼层，1~4 对应地图 Layer01~Layer04；地面单位通过楼梯切层，飞行单位跨越地形时自动切层。
@export_range(1, 4, 1) var floor_id: int = 1:
	set(value):
		var next := clampi(value, 1, 4)
		if floor_id == next:
			return
		floor_id = next
		if is_node_ready():
			_refresh_floor()
var floor_map: Node
var move_floor_id: int = 1

# 移动相关参数
var target_position
var target_vector

# 自动索敌参数
@onready var navigation_agent_2d: NavigationAgent2D = get_node_or_null("NavigationAgent2D")
@onready var skill_manager: Node2D = get_node_or_null("SkillManager")
@onready var animated_sprite_2d: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
# 用 Node 接口取得服务，避免单位/技能资源与 autoload 脚本形成编译引用环。
@onready var combat_audio: Node = get_node("/root/CombatAudio")

signal unit_died(unit: UnitBase)
signal hit_received(unit: UnitBase, attacker: UnitBase)
signal attack_resolved(unit: UnitBase, attacker: UnitBase, actual_damage: int)
signal kill_confirmed(unit: UnitBase, killer: UnitBase)
signal attack_target_selected(target: UnitBase)
signal attack_landed(target: UnitBase)
signal attack_damage_dealt(target: UnitBase, amount: int)
signal health_changed()
signal actions_interrupted()
var is_stunned := false
var _stun_sources: Dictionary = {}
var status_runtime: Node
var soldier_runtime: Node
var knight_runtime: Node
var taunt_runtime: Node2D
var taunt_defence_bonus := 0
var taunt_attackers := 0
var soldier_attack_bonus := 0
var shield_amount := 0
var shield_visual: Node2D
var cast_preview_highlight := false
var original_sprite_tint := Color.WHITE
var protection_attack_bonus := 0
var _protection_sources: Dictionary = {}
var consecutive_attack_bonus := 0
var consecutive_attack_hits := 0
var consecutive_attack_target_name := ""
var is_stealthed := false
var stealth_seconds_left := 0.0


# 作用：切换施放预览颜色；enabled 表示是否高亮，没有返回值。
func set_cast_preview(enabled: bool) -> void:
	cast_preview_highlight = enabled
	refresh_unit_tint()


# 作用：统一决定当前颜色，预览优先于普通选中；没有参数，没有返回值。
func refresh_unit_tint() -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null:
		sprite.modulate = Color(0.35, 1.0, 0.45) if cast_preview_highlight else normal_unit_tint()
		if is_stealthed:
			sprite.modulate.a *= 0.28


# 作用：提供无预览时的颜色，己方可覆盖为选中黄色；没有参数，返回颜色。
func normal_unit_tint() -> Color:
	return original_sprite_tint

# 属性相关参数
var current_health: int = 0
var _health_initialized := false
var _combat_initialized := false
var _initialization_rejected := false

# 状态参数
enum State {
	IDLE,
	WALK,
	ATTACK,
	DEATH
}
var current_state: State = State.IDLE


# 可在入树前校验；旧主堡兼容壳主动不参与战斗初始化。
func configuration_error() -> String:
	if unit_data == null:
		return "缺少 UnitData。"
	if unit_data.max_hp <= 0:
		return "最大生命必须大于零。"
	if unit_data.unit_team not in ["team_a", "team_b"]:
		return "阵营必须是 team_a 或 team_b。"
	var required := {"AnimatedSprite2D": "AnimatedSprite2D", "HealthBar": "Control",
		"SkillManager": "Node2D", "NavigationAgent2D": "NavigationAgent2D"}
	for path: String in required:
		var node := get_node_or_null(NodePath(path))
		if node == null or not node.is_class(required[path]):
			return "缺少必需子节点或类型错误：" + path
	return ""


func is_initialization_rejected() -> bool:
	return _initialization_rejected


func is_combat_initialized() -> bool:
	return _combat_initialized and not _initialization_rejected


func is_alive() -> bool:
	return is_combat_initialized() and is_node_ready() and is_inside_tree() \
		and not is_queued_for_deletion() and unit_data != null \
		and current_state != State.DEATH and current_health > 0


# 无效单位退出，不作为一次战斗死亡；父子 ready 和重复登记只报告一次。
func reject_initialization(reason: String) -> void:
	if _initialization_rejected:
		return
	_initialization_rejected = true
	current_health = 0
	process_mode = Node.PROCESS_MODE_DISABLED
	push_error("UNIT_INITIALIZATION_FAILED: %s：%s" % [name, reason])
	queue_free()


# 作用：Godot 在单位首次进入树时隔离属性并建立初始生命；换队时保留已有运行状态。
func _enter_tree() -> void:
	# 外层按单位脚底位置排序；关闭内部 Y 排序，让精灵和血条作为整体参与遮挡。
	# 否则血条的向下偏移会成为独立排序位置，盖住站在前面的单位。
	y_sort_enabled = false
	if is_in_group("player_base") or _initialization_rejected:
		return
	var error := configuration_error()
	if not error.is_empty():
		reject_initialization(error)
		return
	if not _health_initialized:
		unit_data = unit_data.duplicate()
		current_health = unit_data.max_hp
		_health_initialized = true

# 作用：完成单位可视初始化和初始待机，标记为可登记的战斗单位。
func _ready() -> void:
	if _initialization_rejected:
		return
	var ancestor := get_parent()
	while ancestor != null:
		var terrain := ancestor.get_node_or_null("Level/NavigationRegion2D")
		if terrain != null and terrain.has_method("apply_unit_floor"):
			floor_map = terrain
			break
		ancestor = ancestor.get_parent()
	move_floor_id = floor_id
	_refresh_floor()
	# 每个单位持有自己的闪白材质和动画配置，避免一个单位修改资源时影响整队。
	original_sprite_tint = $AnimatedSprite2D.modulate
	$AnimatedSprite2D.material = $AnimatedSprite2D.material.duplicate()
	$AnimatedSprite2D.sprite_frames = $AnimatedSprite2D.sprite_frames.duplicate()
	preload("res://scripts/combat/fixed_sprite_clock.gd").attach($AnimatedSprite2D)
	# 替换动画资源会停止场景的自动播放；准备阶段不执行战斗行为，所以这里必须重新启动待机。
	$AnimatedSprite2D.play("idle")
	$HealthBar.setup(unit_data.max_hp)
	status_runtime = preload("res://scripts/units/unit_status_runtime.gd").new()
	status_runtime.name = "StatusRuntime"
	add_child(status_runtime)
	SignalBus.phase_change.connect(_on_shield_phase_changed)
	if unit_data.unit_english_name == "soldier":
		soldier_runtime = load("res://scripts/units/soldier_runtime.gd").new()
		soldier_runtime.name = "SoldierRuntime"
		add_child(soldier_runtime)
	if unit_data.unit_english_name == "knight":
		knight_runtime = load("res://scripts/units/knight_blood_runtime.gd").new()
		knight_runtime.name = "KnightBloodRuntime"
		add_child(knight_runtime)
	_play_spawn_smoke()
	_combat_initialized = true


# 楼梯、出生配置和脚本统一通过此接口切层。
func set_floor(value: int) -> void:
	floor_id = value


func _refresh_floor() -> void:
	if is_instance_valid(floor_map) and current_state != State.DEATH:
		floor_map.apply_unit_floor(self)
		if skill_manager != null:
			skill_manager.clear_target_cache()
	elif current_state != State.DEATH:
		# 旧测试场也分开阵营查询位和身体位，使地面单位不会被空中单位挡住。
		collision_layer = (collision_layer & ~0b11110000000) | (0 if unit_data.is_flying else 128)
		collision_mask = 0 if unit_data.is_flying else (collision_mask & ~0b11) | 128
		if navigation_agent_2d != null:
			navigation_agent_2d.reset_after_teleport()


# 准备阶段移动与落点提示共用；飞行落点不投影到导航边缘。
func resolve_move_destination(point: Vector2, floor_step: int = 0) -> Dictionary:
	var destination_floor := floor_id
	if unit_data.is_flying:
		if is_instance_valid(floor_map):
			destination_floor = floor_map.flight_destination_floor(point, floor_id, floor_step)
		return {"position": point, "floor": destination_floor}
	var map := navigation_agent_2d.get_navigation_map()
	if is_instance_valid(floor_map):
		destination_floor = floor_map.floor_at(point, floor_id, floor_step)
		map = floor_map.get_floor_map(destination_floor)
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return {}
	return {"position": NavigationServer2D.map_get_closest_point(map, point), "floor": destination_floor}


func is_on_same_floor(other: UnitBase) -> bool:
	return is_instance_valid(other) and floor_id == other.floor_id


func _physics_process(delta: float) -> void:
	if skill_manager.is_forced_moving:
		return
	if is_action_blocked():
		navigation_agent_2d.stop_navigation()
		return
	if Global.game_phase == Global.GamePhase.AUTO_BATTLE:
		if has_status(&"confusion") and not is_potion_confused():
			status_runtime.wander(delta)
			return
		_battle_behavior()

# 战斗方法
func _battle_behavior():
	if not can_use_skills() or skill_manager.is_reacting or skill_manager.is_forced_moving:
		return
	
	navigation_agent_2d.fight_auto_move()
	if navigation_agent_2d.is_flight_transitioning():
		return
	skill_manager.check_attack()
	match current_state:
		State.IDLE:
			$AnimatedSprite2D.play('idle')
		State.WALK:
			$AnimatedSprite2D.play('walk')
		State.ATTACK:
			skill_manager.attack()
		State.DEATH:
			set_physics_process(false)

# 作用：结算攻击并通知命中效果；attack_damage 为伤害、attacker 为来源、
# can_trigger_counter 表示是否允许反击；sound_profile 可保留远程弹的命中音色。
# attack_floor 供投射物保留发射楼层，默认读取攻击者当前楼层。
# fixed_damage 用于霜暴等固定数值命中，跳过防御和伤害倍率，仍保留受击、击杀和攻击信号。
# 返回是否命中（闪避时返回 false）。
func get_hurt(attack_damage: int, attacker: UnitBase = null, can_trigger_counter: bool = true, sound_profile: StringName = &"", attack_floor: int = -1, fixed_damage: bool = false, damage_kind: StringName = &"normal", defence_segments: int = 1) -> bool:
	if current_state == State.DEATH or _encounter_finished():
		return false
	if is_instance_valid(attacker) and attacker.unit_data.unit_team == unit_data.unit_team and not attacker.is_potion_confused():
		return false
	var dodge_relics := relic_runtime()
	var extra_dodge: float = dodge_relics.dodge_bonus(self, attacker) if dodge_relics != null else 0.0
	if is_instance_valid(attacker) and can_trigger_counter and can_use_skills() and (unit_data.is_skill_unlocked(unit_data.dodge_skill) or extra_dodge > 0):
		var dodge_rate := clampf((unit_data.dodge_rate if unit_data.is_skill_unlocked(unit_data.dodge_skill) else 0.0) + extra_dodge, 0.0, 1.0)
		if randf() < dodge_rate:
			combat_audio.play_block(self)
			if unit_data.is_skill_unlocked(unit_data.dodge_skill):
				unit_data.dodge_skill.execute(self, attacker)
			return false
	var tactics := _tactical_runtime()
	var relics := relic_runtime()
	var defence_per_hit := ceili(float(unit_data.defence) / maxi(1, defence_segments))
	var damage: int = maxi(attack_damage, 0) if fixed_damage else (tactics.attack_damage(self, attacker, attack_damage, defence_segments) if tactics != null else maxi(attack_damage - defence_per_hit, 1))
	# 高打低每层增加最终伤害的 10%，层差相加；低打高不减伤。
	var source_floor := attack_floor if attack_floor >= 1 else (attacker.floor_id if is_instance_valid(attacker) else floor_id)
	if not fixed_damage:
		damage += roundi(damage * maxi(source_floor - floor_id, 0) / 10.0)
	if relics != null and not fixed_damage:
		damage = relics.incoming_damage(self, attacker, damage, damage_kind, true)
	var shield_before := shield_amount
	damage = _absorb_with_shield(damage)
	var actual_damage := mini(maxi(int(current_health), 0), damage)
	preload("res://scripts/effects/combat_numbers.gd").show_number(self, actual_damage + shield_before - shield_amount, damage_kind)
	# 持续伤害不唤醒；只有通过攻击入口且真正命中的攻击解除全部睡眠来源。
	remove_status(&"sleep")
	current_health -= damage
	$HealthBar.update_hp_bar(current_health)
	health_changed.emit()
	combat_audio.play_hit(self, attacker, &"lightning" if sound_profile == &"" and damage_kind == &"lightning" else sound_profile)
	preload("res://scripts/effects/combat_vfx.gd").hit(self)
	hit_received.emit(self, attacker)
	var tween = create_tween()
	tween.tween_property($AnimatedSprite2D.material, 'shader_parameter/flash_intensity', 0.8,0.2)
	tween.tween_property($AnimatedSprite2D.material, 'shader_parameter/flash_intensity', 0.0,0.2)
	if current_health <= 0:
		die(attacker)
	attack_resolved.emit(self, attacker, actual_damage)
	# 直接效果伤害不会发出此信号；闪避和友军拒绝命中也不叠连击。
	if is_instance_valid(attacker):
		if actual_damage > 0:
			attacker.attack_damage_dealt.emit(self, actual_damage)
		attacker.attack_landed.emit(self)
	return true


# 作用：毒和区域等环境伤害，绕过防御与反击、不触发攻击上毒；amount 为伤害，没有返回值。
func take_effect_damage(amount: int, source: UnitBase = null, damage_kind: StringName = &"skill") -> void:
	if current_state == State.DEATH or amount <= 0 or _encounter_finished():
		return
	var relics := relic_runtime()
	if relics != null:
		amount = relics.incoming_damage(self, source, amount, damage_kind, false)
	# 药水催眠受任何伤害唤醒；原技能睡眠的攻击唤醒规则保留。
	if has_meta("potion_sleep"):
		remove_status(&"sleep")
		remove_meta("potion_sleep")
	var shield_before := shield_amount
	amount = _absorb_with_shield(amount)
	var actual_damage := mini(maxi(int(current_health), 0), amount)
	preload("res://scripts/effects/combat_numbers.gd").show_number(self, actual_damage + shield_before - shield_amount, damage_kind)
	current_health -= amount
	$HealthBar.update_hp_bar(current_health)
	health_changed.emit()
	# 雷云与链式落雷按实际命中发声；毒、流血等连续跳字不逐跳制造噪声。
	if damage_kind == &"lightning":
		combat_audio.play_hit(self, source, &"lightning")
	if current_health <= 0:
		die(source)
	if is_instance_valid(source):
		attack_resolved.emit(self, source, actual_damage)
	if relics != null and damage_kind in [&"poison", &"bleed"]:
		relics.dot_tick(self, actual_damage)


func _tactical_runtime() -> Node:
	if not has_meta("battle_owner"):
		return null
	var reference: WeakRef = get_meta("battle_owner", null)
	var owner_battle = reference.get_ref() if reference != null else null
	return owner_battle.card_runtime.tactics if is_instance_valid(owner_battle) else null


func relic_runtime() -> Node:
	if not has_meta("battle_owner"):
		return null
	var reference: WeakRef = get_meta("battle_owner", null)
	var owner_battle = reference.get_ref() if reference != null else null
	return owner_battle.get_node_or_null("RelicRuntime") if is_instance_valid(owner_battle) else null


func shares_encounter(other: UnitBase) -> bool:
	if has_meta("battle_owner") or other.has_meta("battle_owner"):
		var a: WeakRef = get_meta("battle_owner") if has_meta("battle_owner") else null
		var b: WeakRef = other.get_meta("battle_owner") if other.has_meta("battle_owner") else null
		return a != null and b != null and a.get_ref() != null and a.get_ref() == b.get_ref()
	return get_parent() != null and other.get_parent() != null and get_parent().get_parent() == other.get_parent().get_parent()


func set_taunt_defence_bonus(amount: int, attackers: int) -> void:
	var delta := amount - taunt_defence_bonus
	var changed := attackers != taunt_attackers or delta != 0
	taunt_defence_bonus = amount
	taunt_attackers = attackers
	if delta != 0:
		adjust_combat_defence(delta)
	if changed:
		_refresh_passive_status()


func adjust_combat_defence(delta: int) -> void:
	var tactics := _tactical_runtime()
	if tactics != null:
		tactics.adjust_base_defence(self, delta)
	else:
		unit_data.defence += delta


# 按光环来源记录临时庇护；同类重叠取最高值，反复刷新不会反复增加属性。
func set_protection_source(source_id: int, amount: int, label: String, radius: float) -> void:
	var entry := {"amount": maxi(0, amount), "label": label, "radius": radius}
	if _protection_sources.get(source_id) == entry:
		return
	_protection_sources[source_id] = entry
	_update_protection_bonus()


func remove_protection_source(source_id: int) -> void:
	if _protection_sources.erase(source_id):
		_update_protection_bonus()


func _update_protection_bonus() -> void:
	var amount := 0
	for entry: Dictionary in _protection_sources.values():
		amount = maxi(amount, int(entry.amount))
	var delta := amount - protection_attack_bonus
	protection_attack_bonus = amount
	if delta != 0 and unit_data != null:
		var tactics := _tactical_runtime()
		if tactics != null:
			# 先撤销战术乘数贡献，再改变基础加法，狂化等效果才能按新攻击正确重算。
			tactics.adjust_base_attack(self, delta)
		else:
			unit_data.attack += delta
	_refresh_passive_status()


func protection_statuses() -> Array[Dictionary]:
	if protection_attack_bonus <= 0 or current_state == State.DEATH:
		return []
	var lines: Array[String] = []
	for entry: Dictionary in _protection_sources.values():
		lines.append("%s：攻击+%d · 半径%.0f" % [entry.label, entry.amount, entry.radius])
	return [{"icon": "protection", "tooltip": "庇护：攻击力提升%d\n%s\n位于存活光环内时生效，同类重叠取最高加成。" % [protection_attack_bonus, "\n".join(lines)]}]


func notify_attack_target(target: UnitBase) -> void:
	if is_instance_valid(target) and target.unit_data.unit_team != unit_data.unit_team:
		attack_target_selected.emit(target)


func set_soldier_attack_bonus(amount: int) -> void:
	var delta := amount - soldier_attack_bonus
	soldier_attack_bonus = amount
	if delta != 0:
		var tactics := _tactical_runtime()
		if tactics != null:
			tactics.adjust_base_attack(self, delta)
		else:
			unit_data.attack += delta
	_refresh_passive_status()


func set_consecutive_attack_bonus(amount: int, hits: int, target_name: String) -> void:
	amount = maxi(0, amount)
	if amount == consecutive_attack_bonus and hits == consecutive_attack_hits and target_name == consecutive_attack_target_name:
		return
	var delta := amount - consecutive_attack_bonus
	consecutive_attack_bonus = amount
	consecutive_attack_hits = hits
	consecutive_attack_target_name = target_name
	if delta != 0 and unit_data != null:
		var tactics := _tactical_runtime()
		if tactics != null:
			tactics.adjust_base_attack(self, delta)
		else:
			unit_data.attack += delta
	_refresh_passive_status()


func consecutive_attack_statuses() -> Array[Dictionary]:
	if consecutive_attack_bonus <= 0 or current_state == State.DEATH:
		return []
	return [{"icon": "consecutive_attack", "count": consecutive_attack_hits, "tooltip": "愈战愈勇：连续命中%d次，攻击力提升%d\n当前目标：%s\n下一击生效，切换目标时清除增益。" % [consecutive_attack_hits, consecutive_attack_bonus, consecutive_attack_target_name]}]


func can_be_targeted_by(observer: UnitBase) -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and current_state != State.DEATH \
		and int(current_health) > 0 and (not is_stealthed or (is_instance_valid(observer) \
		and observer.unit_data.unit_team == unit_data.unit_team))


func set_stealthed(enabled: bool) -> void:
	if is_stealthed == enabled:
		return
	is_stealthed = enabled
	refresh_unit_tint()
	_refresh_passive_status()
	if not enabled or not is_inside_tree():
		return
	# 入隐身即撤销敌人的旧缓存与锁定，避免已选中的五连击继续追击。
	var enemy_group := "team_b" if unit_data.unit_team == "team_a" else "team_a"
	for node in get_tree().get_nodes_in_group(enemy_group):
		var enemy := node as UnitBase
		if not is_instance_valid(enemy) or not enemy.is_node_ready():
			continue
		var manager = enemy.skill_manager
		manager.clear_target_cache()
		if manager.current_target == self or manager.cast_target == self or manager._reaction_target == self:
			manager.interrupt_actions()


func stealth_statuses() -> Array[Dictionary]:
	if not is_stealthed or current_state == State.DEATH:
		return []
	return [{"icon": "stealth", "tooltip": "隐身：无法被敌方索敌选中\n剩余%d秒；攻击不会解除隐身，每次部署只触发一次。" % ceili(stealth_seconds_left)}]


func _refresh_passive_status() -> void:
	var health_bar := get_node_or_null("HealthBar")
	if health_bar == null:
		return
	if has_meta("battle_owner"):
		var reference: WeakRef = get_meta("battle_owner", null)
		var owner_battle = reference.get_ref() if reference != null else null
		if is_instance_valid(owner_battle):
			owner_battle.card_runtime._refresh_unit_status(self)
			return
	# 独立怪物测试场没有卡牌运行器，也显示驻场被动状态。
	var entries: Array[Dictionary] = []
	for entry: Dictionary in health_bar.pending_statuses:
		if entry.icon not in ["protection", "consecutive_attack", "seventh_strike", "stealth", "bleed", "confusion", "mortal_wounds", "sleep", "stun", "weakness", "slow", "shield", "soldier_growth", "missile_mark", "taunt", "taunt_guard", "armor_break"]:
			entries.append(entry)
	entries.append_array(protection_statuses())
	entries.append_array(consecutive_attack_statuses())
	entries.append_array(stealth_statuses())
	entries.append_array(active_statuses())
	health_bar.set_statuses(entries)


func _exit_tree() -> void:
	set_stealthed(false)
	set_consecutive_attack_bonus(0, 0, "")
	_protection_sources.clear()
	_update_protection_bonus()


func set_stunned(enabled: bool, source: StringName = &"legacy") -> void:
	if enabled:
		_stun_sources[source] = true
	else:
		_stun_sources.erase(source)
	var active := not _stun_sources.is_empty()
	if status_runtime != null:
		status_runtime.set_visual(&"stun", active, &"stun_sources")
	if is_stunned == active:
		return
	is_stunned = active
	if not is_node_ready() or current_state == State.DEATH:
		return
	if active:
		stop_status_actions()
	elif not is_action_blocked():
		animated_sprite_2d.play("idle")
	_refresh_passive_status()


func has_status(id: StringName) -> bool:
	return status_runtime != null and status_runtime.has_status(id)


func apply_status(id: StringName, duration: float = 0.0, amount: int = 0, source: Node = null, source_key: String = "") -> bool:
	return status_runtime != null and status_runtime.apply_status(id, duration, amount, source, source_key)


func remove_status(id: StringName, source_key: String = "") -> void:
	if status_runtime != null:
		status_runtime.remove_status(id, source_key)


func active_statuses() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if status_runtime != null:
		entries.assign(status_runtime.status_entries())
	var seventh: Node = skill_manager.get_node_or_null("SeventhStrike") if is_instance_valid(skill_manager) else null
	if seventh != null:
		entries.append(seventh.status_entry())
	if is_stunned and not has_status(&"stun"):
		entries.append({"icon": "stun", "tooltip": "晕眩：无法移动、攻击、施法或反击。"})
	if shield_amount > 0:
		entries.append({"icon": "shield", "count": shield_amount, "tooltip": "护盾：剩余%d点，先于生命抵扣受到的伤害。\n溢出治疗按1:1累加，交锋结束后清除。" % shield_amount})
	if soldier_runtime != null:
		entries.append_array(soldier_runtime.statuses())
	if taunt_runtime != null and taunt_runtime.left > 0:
		entries.append({"icon": "taunt_guard", "count": taunt_defence_bonus, "tooltip": "嘲讽释放中：剩余%.1f秒\n当前%d名敌人瞄准自身，防御+%d。" % [taunt_runtime.left, taunt_attackers, taunt_defence_bonus]})
	var mark := get_node_or_null("SoldierMissileMark")
	if mark != null and mark.active:
		entries.append(mark.status_entry())
	return entries


func is_action_blocked() -> bool:
	return is_stunned or has_status(&"sleep")


func can_use_skills() -> bool:
	return current_state != State.DEATH and not is_action_blocked() and (not has_status(&"confusion") or is_potion_confused())


func is_potion_confused() -> bool:
	return has_meta("potion_confusion") and has_status(&"confusion")


func enemy_team() -> String:
	return unit_data.unit_team if is_potion_confused() else ("team_b" if unit_data.unit_team == "team_a" else "team_a")


func stop_status_actions() -> void:
	if not is_node_ready() or current_state == State.DEATH:
		return
	navigation_agent_2d.stop_navigation()
	target_position = null
	skill_manager.interrupt_actions()
	current_state = State.IDLE
	animated_sprite_2d.play("idle")
	if is_action_blocked():
		animated_sprite_2d.pause()


func get_movement_speed() -> float:
	var penalty: int = status_runtime.strongest_amount(&"slow") if status_runtime != null else 0
	var relics := relic_runtime()
	return maxf(1.0, unit_data.speed - penalty) * (relics.movement_multiplier(self) if relics != null else 1.0)


func clear_combat_statuses() -> void:
	var seventh: Node = skill_manager.get_node_or_null("SeventhStrike") if is_instance_valid(skill_manager) else null
	if seventh != null:
		seventh.clear()
	if taunt_runtime != null:
		taunt_runtime.clear()
	if knight_runtime != null:
		knight_runtime.clear()
	if soldier_runtime != null:
		soldier_runtime.clear()
	var mark := get_node_or_null("SoldierMissileMark")
	if mark != null:
		mark.clear_mark()
	clear_shield()
	if status_runtime != null:
		status_runtime.clear()
	set_stunned(false)


# 作用：拦截本战场结束后的旧伤害；没有参数，返回是否已结束，独立练兵场没有登记则照常工作。
func _encounter_finished() -> bool:
	if not has_meta("battle_owner"):
		return false
	var reference: WeakRef = get_meta("battle_owner", null)
	if reference == null:
		return false
	var owner_battle = reference.get_ref()
	return not is_instance_valid(owner_battle) or owner_battle.battle_finished

# 治愈函数
func get_heal(heal_damage: int, _healer: UnitBase = null) -> bool:
	return receive_healing(heal_damage, _healer, false)


func receive_healing(amount: int, _healer: UnitBase = null, overflow_to_shield: bool = false) -> bool:
	if current_state == State.DEATH or is_queued_for_deletion() or _encounter_finished() \
		or has_status(&"mortal_wounds") or amount <= 0:
		return false
	var relics := relic_runtime()
	if relics != null:
		amount = relics.healing_amount(self, amount)
		overflow_to_shield = overflow_to_shield or (unit_data.unit_team == "team_a" and relics.has_relic(&"blood_bank"))
	var missing := maxi(0, unit_data.max_hp - int(current_health))
	var healing := mini(missing, amount)
	var overflow := amount - healing if overflow_to_shield or has_status(&"overflow_shield") else 0
	if healing == 0 and overflow == 0:
		return false
	current_health += healing
	preload("res://scripts/effects/combat_numbers.gd").show_number(self, healing, &"heal")
	if overflow > 0:
		add_shield(overflow)
	$HealthBar.update_hp_bar(current_health)
	health_changed.emit()
	return true


func add_shield(amount: int) -> void:
	if amount <= 0 or current_state == State.DEATH or _encounter_finished():
		return
	shield_amount += amount
	preload("res://scripts/effects/combat_numbers.gd").show_number(self, amount, &"shield")
	if not is_instance_valid(shield_visual):
		shield_visual = preload("res://scripts/effects/combat_vfx.gd").spawn(self, "ShieldBubbleVFX", 0.0)
	_refresh_passive_status()


func _absorb_with_shield(damage: int) -> int:
	var absorbed := mini(maxi(0, damage), shield_amount)
	if absorbed > 0:
		shield_amount -= absorbed
		if shield_amount == 0:
			clear_shield()
		else:
			_refresh_passive_status()
	return damage - absorbed


func clear_shield() -> void:
	shield_amount = 0
	if is_instance_valid(shield_visual):
		shield_visual.hide()
		shield_visual.queue_free()
	shield_visual = null
	_refresh_passive_status()


func _on_shield_phase_changed(phase: int) -> void:
	if phase != Global.GamePhase.AUTO_BATTLE and shield_amount > 0:
		clear_shield()

# 死亡函数
func die(killer: UnitBase = null):
	if current_state == State.DEATH:
		return
	combat_audio.play_death(self)
	switch_state(State.DEATH)
	clear_combat_statuses()
	var spawn_smoke := get_node_or_null("SpawnSmoke")
	if spawn_smoke != null:
		spawn_smoke.queue_free()
	set_physics_process(false)
	skill_manager.interrupt_actions()
	animated_sprite_2d.pause()
	# 后续光环撤销仍会刷新状态，清除受伤显条标记，避免烟中重新冒出空血条。
	$HealthBar.hp_revealed = false
	$HealthBar.set_statuses([])
	set_cast_preview(false)
	unit_died.emit(self)
	if is_instance_valid(killer):
		kill_confirmed.emit(self, killer)
	# 死亡通知会刷新光环与卡牌状态，须在这些刷新之后隐藏血条。
	$HealthBar.hide()
	_play_death_effects()


# 死亡立即结算，退场表现独立推进；有 death 时播完一次，没有则直接起烟。
func _play_death_effects() -> void:
	var frames := animated_sprite_2d.sprite_frames
	if frames.has_animation(&"death") and frames.get_frame_count(&"death") > 0:
		# 动画资源已按单位复制；强制单次播放，避免循环配置阻止退场。
		frames.set_animation_loop(&"death", false)
		animated_sprite_2d.stop()
		animated_sprite_2d.animation_finished.connect(_spawn_death_smoke, CONNECT_ONE_SHOT)
		animated_sprite_2d.play(&"death")
		return
	_spawn_death_smoke()


# 出生烟雾只负责显示并自行释放，不隐藏单位或延迟战斗行为。
func _play_spawn_smoke() -> void:
	var smoke := preload("res://scenes/effects/unit_death_smoke.tscn").instantiate()
	smoke.name = "SpawnSmoke"
	smoke.configure(_smoke_body_rect())
	add_child(smoke)


func _spawn_death_smoke() -> void:
	var smoke := preload("res://scenes/effects/unit_death_smoke.tscn").instantiate()
	smoke.configure(_smoke_body_rect())
	smoke.covered.connect(animated_sprite_2d.hide, CONNECT_ONE_SHOT)
	smoke.finished.connect(queue_free, CONNECT_ONE_SHOT)
	add_child(smoke)


# 按待机的可见像素计算出生/死亡烟雾范围，兼容旧单位缩放和大体型怪物。
func _smoke_body_rect() -> Rect2:
	var sprite := animated_sprite_2d
	var texture := sprite.sprite_frames.get_frame_texture(&"idle", 0)
	var image := texture.get_image()
	var bounds := Rect2(image.get_used_rect())
	var origin := bounds.position - texture.get_size() * 0.5 + sprite.offset
	if sprite.flip_h:
		origin.x = -origin.x - bounds.size.x
	if sprite.flip_v:
		origin.y = -origin.y - bounds.size.y
	return Rect2(sprite.position + origin * sprite.scale, bounds.size * sprite.scale)

# 状态切换函数
func switch_state(new_state:State):
	if current_state == State.DEATH:
		return
	if is_action_blocked() and new_state != State.DEATH:
		return
	current_state = new_state
