# 这玩意儿是干嘛的（核心逻辑）：触发开局遗物，管理药水瞄准、即时结算及单个场地生效槽。
# 数据是咋流动的（数据流向）：HUD 选药 → 鼠标落点验证 → 消耗一瓶 → 范围伤害和配置特效 → 期限结束清理；雷云跨回合保留。
# 为啥这么写（选型决策）：药水不走手牌、不消耗能量；与战场一起暂停和销毁，避免跨关卡遗留伤害。
# 性能咋样（复杂度）：场地/多段药水占一个槽，即时药水按需结算；空闲时不扫描单位。
extends Node2D

const THUNDER_CLOUD_SCENE := preload("res://scenes/effects/pixel_thunder_cloud.tscn")
const THUNDER_BOLT_SCENE := preload("res://scenes/effects/pixel_lightning.tscn")
const THUNDER_CLOUD_SIZE_MULTIPLIER := 2.0

var battle: Node2D
var potion: PotionDefinition
var committed := false
var remaining_casts := 0
var cooldown := 0.0
var effect_position := Vector2.ZERO
var direction := Vector2.RIGHT
var remaining_time := 0.0
var damage_clock := 0.0
var animation_clock := 0.0
var opening_applied := false
var remaining_rounds := 0
var _cloud_end_round := 0
var _thunder_elapsed := 0.0
var _thunder_next_cast := 0.0
var _thunder_interval := 0.4
var _thunder_last_target_id := 0
var _thunder_sequence := 0
var _thunder_bolts: Array[Dictionary] = []
var _thunder_visual: PixelThunderCloud
var _persistent_visual: AnimatedSprite2D
var _flash_visuals: Array[AnimatedSprite2D] = []
var _cast_has_visual := false
var potion_runtime: Node2D
var aiming_potion: PotionDefinition
var last_error := ""
var _potion_preview: UnitBase


# 作用：Godot 入树时注册当前战场药水入口；没有参数，没有返回值。
func _ready() -> void:
	z_index = 5
	potion_runtime = preload("res://scripts/items/potion_runtime.gd").new()
	potion_runtime.name = "PotionRuntime"
	add_child(potion_runtime)
	potion_runtime.setup(self)
	RunManager.item_battle = self
	SignalBus.phase_change.connect(_on_phase_changed)
	battle.battle_round_manager.battle_round_ended.connect(_on_battle_round_ended)
	RunManager.items_changed.emit()
	# F6 单独测试战斗没有整局 HUD，也提供相同的物品入口。
	if get_tree().get_nodes_in_group("run_items_hud").is_empty():
		var layer := CanvasLayer.new()
		layer.name = "RunItemsLayer"
		layer.layer = 30
		battle.add_child(layer)
		layer.add_child(load("res://scenes/ui/run_items_hud.tscn").instantiate())


# 作用：判断当前是否允许战场技能；没有参数，返回可用与否。
func can_use(selected: PotionDefinition = null) -> bool:
	return is_instance_valid(battle) and not battle.battle_finished and not get_tree().paused and (
		Global.game_phase == Global.GamePhase.AUTO_BATTLE or (selected != null and selected.prep_usable and Global.game_phase == Global.GamePhase.CARD_PLAY))


func can_select(selected: PotionDefinition) -> bool:
	if selected == null or selected.target_mode == PotionDefinition.TargetMode.PASSIVE or not can_use(selected) or aiming_potion != null:
		return false
	if potion != null and (not committed or selected.occupies_slot()):
		return false
	return RunManager.potions.has(selected)


# 作用：选中一瓶药水进入瞄准；selected 是背包实例，返回是否接受，选中本身不扣瓶。
func select_potion(selected: PotionDefinition) -> bool:
	if not can_select(selected):
		return false
	last_error = ""
	if selected.kind == PotionDefinition.Kind.EFFECTS:
		aiming_potion = selected
		if not selected.needs_aim():
			return _try_cast_effects(battle.battlefield_rect.get_center())
		RunManager.items_changed.emit()
		return true
	potion = selected
	committed = false
	remaining_casts = maxi(selected.casts, 1) if selected.kind == PotionDefinition.Kind.LIGHTNING else 1
	cooldown = 0.0
	RunManager.items_changed.emit()
	return true


# 作用：给 HUD 返回当前提示；没有参数，返回说明文字。
func status_text() -> String:
	if aiming_potion != null:
		return "%s：左键选择%s，右键/Esc取消" % [aiming_potion.display_name,
			"敌方单位" if aiming_potion.target_mode == PotionDefinition.TargetMode.ENEMY_UNIT else ("友军" if aiming_potion.target_mode == PotionDefinition.TargetMode.ALLY_UNIT else "战场落点")]
	if potion == null:
		return last_error
	if not committed:
		return "%s：左键选择战场落点，右键/Esc取消" % potion.display_name
	if potion.kind == PotionDefinition.Kind.LIGHTNING:
		return "闪电剩余 %d 次 · 等待间隔后左键释放" % remaining_casts
	if potion.kind == PotionDefinition.Kind.THUNDER_CLOUD:
		return "雷云 · 剩余 %d 回合 · %s" % [remaining_rounds,
			"索敌中" if can_use() else "暂停"]
	if potion.kind == PotionDefinition.Kind.EFFECTS and not potion_runtime.field.is_empty() and potion_runtime.field.effect.rounds > 0:
		var left: int = maxi(0, int(potion_runtime.field.end_round) - battle.battle_round_manager.current_round + 1)
		return "%s · 剩余%d回合 · 仍可使用即时药水" % [potion.display_name, left]
	return "%s生效中 · 场地槽已占用，仍可使用即时药水" % potion.display_name


# 作用：读取未被 UI 消费的战场左键；event 是鼠标/键盘输入，没有返回值。
func _unhandled_input(event: InputEvent) -> void:
	var selected := aiming_potion if aiming_potion != null else potion
	if selected == null or not can_use(selected):
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		# 已经消耗的四连闪电不能通过取消返还；回合结束会清除剩余次数。
		if aiming_potion != null:
			_cancel_aim()
		elif not committed:
			clear_effect()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 使用这次事件的坐标，不依赖可能尚未刷新的全局鼠标位置；相机移动后仍准确。
		try_cast(battle.get_canvas_transform().affine_inverse() * event.position)
		get_viewport().set_input_as_handled()


# 作用：在合法位置施放一次；point 是世界坐标，返回是否成功；无效点击不扣次数或药水。
func try_cast(point: Vector2) -> bool:
	if aiming_potion != null:
		return _try_cast_effects(point)
	if potion == null or not can_use() or cooldown > 0.0 or remaining_casts <= 0:
		return false
	if not battle.battlefield_rect.has_point(point):
		return false
	var recipe := potion
	if not committed:
		# 扣瓶前先锁定状态，背包刷新信号不能让 HUD 在这一瞬间重新开放使用。
		committed = true
		if not RunManager.consume_potion(recipe):
			clear_effect()
			return false
	recipe = relic_recipe(recipe)
	effect_position = point
	remaining_casts -= 1
	damage_clock = 0.0
	animation_clock = 0.0
	cooldown = maxf(recipe.cast_delay, 0.1)
	if recipe.kind == PotionDefinition.Kind.TORNADO:
		# 主堡移除后，从战场左侧中央确定向外施放方向，不依赖建筑节点。
		var origin := Vector2(battle.battlefield_rect.position.x, battle.battlefield_rect.get_center().y)
		direction = origin.direction_to(point)
		if direction.is_zero_approx():
			direction = Vector2.RIGHT
		remaining_time = maxf(recipe.duration, 0.1)
	# 伤害可能同步结束战斗；先创建视觉，阶段切换才能同时清理它。
	if recipe.kind == PotionDefinition.Kind.THUNDER_CLOUD:
		remaining_rounds = maxi(recipe.rounds, 1)
		_cloud_end_round = battle.battle_round_manager.current_round + remaining_rounds - 1
		_cast_has_visual = _spawn_thunder_cloud(point, recipe)
	else:
		_cast_has_visual = _spawn_visual(point, recipe)
		# 普通药水落地先命中一次；雷云等待主干触地，与画面同步。
		_damage_at(point, recipe)
	RunManager.items_changed.emit()
	queue_redraw()
	return true


# 作用：暂停之外按固定物理步推进当前药水；delta 为秒数，没有返回值。
func _physics_process(delta: float) -> void:
	if aiming_potion != null:
		_update_potion_preview()
		queue_redraw()
	if potion != null and potion.kind == PotionDefinition.Kind.EFFECTS:
		return
	if potion == null:
		return
	if not can_use():
		return
	animation_clock += delta
	cooldown = maxf(0.0, cooldown - delta)
	if not committed:
		queue_redraw()
		return
	var recipe := potion
	if recipe.kind == PotionDefinition.Kind.THUNDER_CLOUD:
		_advance_thunder_cloud(delta, recipe)
	elif recipe.kind == PotionDefinition.Kind.LIGHTNING:
		if remaining_casts == 0 and cooldown <= 0.0:
			clear_effect()
	else:
		if recipe.kind == PotionDefinition.Kind.TORNADO:
			# 到战场边缘反弹，始终留在战场内；法术可穿过地形，不修改单位导航。
			effect_position += direction * recipe.speed * delta
			var bounds: Rect2 = battle.battlefield_rect
			if effect_position.x < bounds.position.x or effect_position.x > bounds.end.x:
				direction.x *= -1.0
			if effect_position.y < bounds.position.y or effect_position.y > bounds.end.y:
				direction.y *= -1.0
			effect_position = effect_position.clamp(bounds.position, bounds.end)
			if is_instance_valid(_persistent_visual):
				_persistent_visual.global_position = effect_position + recipe.effect_offset
			remaining_time -= delta
			if remaining_time <= 0.0:
				clear_effect()
				return
		damage_clock += delta
		while damage_clock >= maxf(recipe.interval, 0.05):
			damage_clock -= maxf(recipe.interval, 0.05)
			_damage_at(effect_position, recipe)
			# 伤害可能同步触发胜负和清理，不能继续使用已结束的效果。
			if potion == null or not can_use():
				return
	queue_redraw()


func _try_cast_effects(point: Vector2) -> bool:
	var recipe := aiming_potion
	if recipe == null or not can_use(recipe):
		return false
	if not battle.battlefield_rect.has_point(point):
		last_error = "请选择战场内的落点。"
		battle.card_runtime.feedback.emit(last_error)
		return false
	var context: Dictionary = potion_runtime.prepare(recipe, point)
	if context.is_empty():
		last_error = potion_runtime.error
		battle.card_runtime.feedback.emit(last_error)
		if not recipe.needs_aim():
			_cancel_aim()
		return false
	_cancel_aim()
	if recipe.occupies_slot():
		potion = recipe
		committed = true
		effect_position = point
	if not RunManager.consume_potion(recipe):
		potion_runtime.free_prepared(context)
		if potion == recipe:
			clear_effect()
		return false
	last_error = ""
	battle.card_runtime.feedback.emit("")
	var effective := relic_recipe(recipe)
	potion_runtime.cast(effective, context)
	RunManager.items_changed.emit()
	queue_redraw()
	return true


func _cancel_aim() -> void:
	aiming_potion = null
	if is_instance_valid(_potion_preview):
		_potion_preview.set_cast_preview(false)
	_potion_preview = null
	queue_redraw()


func _update_potion_preview() -> void:
	var target: UnitBase
	if aiming_potion != null and can_use(aiming_potion) and aiming_potion.target_mode in [PotionDefinition.TargetMode.ENEMY_UNIT, PotionDefinition.TargetMode.ALLY_UNIT]:
		target = potion_runtime.target_at(aiming_potion, battle.get_global_mouse_position())
	if target == _potion_preview:
		return
	if is_instance_valid(_potion_preview):
		_potion_preview.set_cast_preview(false)
	_potion_preview = target
	if is_instance_valid(target):
		target.set_cast_preview(true)


# 雷云由药水统一驱动时钟，暂停/准备时既不推进画面，也不积累待补发的伤害。
func _spawn_thunder_cloud(point: Vector2, recipe: PotionDefinition) -> bool:
	var scene := recipe.effect_scene if recipe.effect_scene != null else THUNDER_CLOUD_SCENE
	var instance := scene.instantiate()
	_thunder_visual = instance as PixelThunderCloud
	if _thunder_visual == null:
		instance.free()
		push_warning("雷云药水需要 PixelThunderCloud 根节点，已回退到默认雷云：%s" % recipe.display_name)
		_thunder_visual = THUNDER_CLOUD_SCENE.instantiate() as PixelThunderCloud
	_thunder_interval = maxf(recipe.interval, 0.05)
	_thunder_visual.auto_start = false
	_thunder_visual.playing = false
	# 云团始终在原处翻滚；雷电使用独立实例连接锁定目标，不播放固定落点的循环雷。
	_thunder_visual.loop = false
	_thunder_visual.lightning_enabled = false
	_thunder_visual.flash_enabled = false
	_thunder_visual.cloud_size *= THUNDER_CLOUD_SIZE_MULTIPLIER
	_thunder_visual.process_mode = Node.PROCESS_MODE_PAUSABLE
	_thunder_visual.scale *= recipe.effect_scale
	add_child(_thunder_visual)
	_thunder_visual.global_position = point + recipe.effect_offset
	_thunder_visual.restart()
	_thunder_elapsed = 0.0
	_thunder_next_cast = _thunder_interval
	_thunder_last_target_id = 0
	_thunder_sequence = 0
	return true


func _advance_thunder_cloud(delta: float, recipe: PotionDefinition) -> void:
	var end_time := _thunder_elapsed + delta
	# 按时间先完成上一击再选择下一人，低帧率也不会把多次攻击合成范围群伤。
	while _thunder_next_cast <= end_time + 0.000001:
		_thunder_elapsed = _thunder_next_cast
		_update_thunder_bolts(recipe)
		if not _has_committed_cloud() or not can_use():
			return
		_thunder_next_cast += _thunder_interval
		var target := _next_thunder_target(recipe)
		if target != null:
			_launch_thunder_bolt(target)
	_thunder_elapsed = end_time
	_update_thunder_bolts(recipe)
	if not _has_committed_cloud() or not is_instance_valid(_thunder_visual):
		return
	_thunder_visual.seek(_thunder_elapsed)
	# 无目标时 flash 为零。闪光来自实际放出的雷，而非云场景自身的固定周期。
	var flash := 0.0
	var flash_position := Vector2.ZERO
	for shot in _thunder_bolts:
		var bolt: PixelLightning = shot.visual
		var age := _thunder_elapsed - float(shot.started)
		var bright_end := bolt.strike_duration + bolt.flash_duration
		var amount := 1.0 if age < bright_end else clampf(1.0 - (age - bright_end) / 0.11, 0.0, 1.0)
		if amount > flash:
			flash = amount
			flash_position = shot.flash_position
	var effect_material := _thunder_visual.get_node("Cloud").material as ShaderMaterial
	if flash > 0.0:
		effect_material.set_shader_parameter("flash_position", flash_position)
	effect_material.set_shader_parameter("flash_amount", flash * _thunder_visual.flash_strength)


func _is_thunder_target(unit: UnitBase, recipe: PotionDefinition) -> bool:
	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion() or unit.current_state == UnitBase.State.DEATH or unit.current_health <= 0:
		return false
	var ally := unit.unit_data.unit_team == "team_a"
	if (recipe.targets == PotionDefinition.Targets.ENEMIES and ally) or (recipe.targets == PotionDefinition.Targets.ALLIES and not ally):
		return false
	return unit.global_position.distance_to(effect_position) <= recipe.radius + 0.0001


# 以稳定的实例编号轮流选择，离开/死亡/新增目标都不会留下失效索引。
func _next_thunder_target(recipe: PotionDefinition) -> UnitBase:
	var candidates: Array[UnitBase] = []
	for unit in battle.card_runtime.living_units():
		if _is_thunder_target(unit, recipe):
			candidates.append(unit)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a: UnitBase, b: UnitBase): return a.get_instance_id() < b.get_instance_id())
	for unit in candidates:
		if unit.get_instance_id() > _thunder_last_target_id:
			return unit
	return candidates[0]


func _launch_thunder_bolt(target: UnitBase) -> void:
	_thunder_sequence += 1
	_thunder_last_target_id = target.get_instance_id()
	var bolt := THUNDER_BOLT_SCENE.instantiate() as PixelLightning
	bolt.auto_start = false
	bolt.playing = false
	bolt.loop = false
	bolt.lightning_type = 0
	bolt.core_width = 2
	bolt.random_seed = _thunder_visual.random_seed + _thunder_sequence * 104729
	bolt.core_color = _thunder_visual.flash_core
	bolt.branch_color = _thunder_visual.flash_color
	bolt.dim_color = _thunder_visual.flash_color.darkened(0.62)
	add_child(bolt)
	# 每道雷独立从底部四块云团中随机选一块，不沿用组合场景初始化时的固定出雷点。
	var source_rng := RandomNumberGenerator.new()
	source_rng.seed = bolt.random_seed
	var source_index := source_rng.randi_range(0, PixelThunderCloud.SOURCE_POINTS.size() - 1)
	var source_point: Vector2 = PixelThunderCloud.SOURCE_POINTS[source_index]
	var cloud_point := Vector2(0, -_thunder_visual.cloud_altitude) + source_point * _thunder_visual.cloud_size / Vector2(112, 58)
	var source := _thunder_visual.to_global(cloud_point)
	var shot := {"target": weakref(target), "visual": bolt, "source": source,
		"source_index": source_index, "flash_position": source_point,
		"started": _thunder_elapsed, "impacted": false}
	_thunder_bolts.append(shot)
	_set_thunder_path(shot, target)
	bolt.restart()


# 支持美术显式放置命中点；默认连到精灵的身体中心，不连单位脚下的固定区域中心。
func _thunder_hit_position(unit: UnitBase) -> Vector2:
	var marker := unit.get_node_or_null("ThunderHitPoint") as Node2D
	if marker != null:
		return marker.global_position
	if is_instance_valid(unit.animated_sprite_2d):
		return unit.animated_sprite_2d.global_position
	return unit.global_position


func _set_thunder_path(shot: Dictionary, target: UnitBase) -> void:
	var bolt: PixelLightning = shot.visual
	var end := to_local(_thunder_hit_position(target))
	var vector := to_local(shot.source) - end
	# 原落雷的像素端点会取整，Y倍率补偿长度，保证实际绘制的两端精确对接。
	var height := maxf(roundf(vector.length()), 32.0)
	if not is_equal_approx(bolt.bolt_height, height):
		bolt.bolt_height = height
	bolt.position = end
	bolt.rotation = vector.angle() + PI * 0.5
	bolt.scale = Vector2(1.0, vector.length() / height)


func _update_thunder_bolts(recipe: PotionDefinition) -> void:
	for shot in _thunder_bolts.duplicate():
		var target := (shot.target as WeakRef).get_ref() as UnitBase
		if not _is_thunder_target(target, recipe):
			_remove_thunder_bolt(shot)
			continue
		var bolt: PixelLightning = shot.visual
		_set_thunder_path(shot, target)
		var age := maxf(_thunder_elapsed - float(shot.started), 0.0)
		bolt.seek(age)
		if not shot.impacted and age + 0.000001 >= bolt.strike_duration:
			shot.impacted = true
			target.take_effect_damage(recipe.damage, null, &"lightning")
			if not _has_committed_cloud() or not can_use():
				return
		if age >= bolt.get_duration():
			_remove_thunder_bolt(shot)


func _remove_thunder_bolt(shot: Dictionary) -> void:
	var bolt: PixelLightning = shot.visual
	if is_instance_valid(bolt):
		bolt.queue_free()
	_thunder_bolts.erase(shot)


func _clear_thunder_bolts() -> void:
	for shot in _thunder_bolts.duplicate():
		_remove_thunder_bolt(shot)
	if is_instance_valid(_thunder_visual):
		var effect_material := _thunder_visual.get_node("Cloud").material as ShaderMaterial
		effect_material.set_shader_parameter("flash_amount", 0.0)


func _has_committed_cloud() -> bool:
	return potion != null and committed and potion.kind == PotionDefinition.Kind.THUNDER_CLOUD


# 使用真实回合编号计算剩余期限，同一轮重复通知不会多扣一回合。
func _on_battle_round_ended() -> void:
	if not _has_committed_cloud():
		return
	remaining_rounds = maxi(0, _cloud_end_round - battle.battle_round_manager.current_round)
	if remaining_rounds == 0:
		clear_effect()
	else:
		RunManager.items_changed.emit()
		queue_redraw()


# 作用：按药水配置生成纯视觉动画；point 为世界落点，recipe 为配方，返回是否成功创建。
func _spawn_visual(point: Vector2, recipe: PotionDefinition) -> bool:
	if recipe.effect_scene == null:
		return false
	var instance := recipe.effect_scene.instantiate()
	var visual := instance as AnimatedSprite2D
	if visual == null:
		instance.free()
		push_warning("药水使用特效的根节点必须是 AnimatedSprite2D：%s" % recipe.display_name)
		return false
	var animation_name := visual.animation
	# 场景决定播放内容，药水无需再保存名字；兼容导入后仍选中空 default 的场景。
	if visual.sprite_frames != null and (not visual.sprite_frames.has_animation(animation_name) or visual.sprite_frames.get_frame_count(animation_name) == 0):
		for candidate in visual.sprite_frames.get_animation_names():
			if visual.sprite_frames.get_frame_count(candidate) > 0:
				animation_name = candidate
				break
	if visual.sprite_frames == null or not visual.sprite_frames.has_animation(animation_name) or visual.sprite_frames.get_frame_count(animation_name) == 0:
		var available := "、".join(visual.sprite_frames.get_animation_names()) if visual.sprite_frames != null else "无"
		visual.free()
		push_warning("药水使用特效没有可播放的动画帧：%s；场景：%s；动画列表：%s。请在特效场景中添加动画帧。" % [recipe.display_name, recipe.effect_scene.resource_path, available])
		return false
	# 每个实例独立设置循环模式，避免不同药水共用场景时互相修改。
	visual.sprite_frames = visual.sprite_frames.duplicate() as SpriteFrames
	var persistent := recipe.kind != PotionDefinition.Kind.LIGHTNING
	visual.sprite_frames.set_animation_loop(animation_name, persistent)
	visual.process_mode = Node.PROCESS_MODE_PAUSABLE
	visual.scale *= recipe.effect_scale
	visual.stop()
	if persistent:
		_persistent_visual = visual
	else:
		_flash_visuals.append(visual)
		visual.animation_finished.connect(visual.queue_free, CONNECT_ONE_SHOT)
		visual.tree_exiting.connect(_forget_flash_visual.bind(visual), CONNECT_ONE_SHOT)
	add_child(visual)
	visual.global_position = point + recipe.effect_offset
	visual.play(animation_name)
	return true


# 作用：单次动画出树时移除引用；visual 为结束的闪电视觉，没有返回值。
func _forget_flash_visual(visual: AnimatedSprite2D) -> void:
	_flash_visuals.erase(visual)


# 作用：离开交锋时终止所有尚未播完的闪电动画；没有参数，没有返回值。
func _clear_flash_visuals() -> void:
	for visual in _flash_visuals:
		if is_instance_valid(visual):
			visual.queue_free()
	_flash_visuals.clear()


# 作用：结算指定圆内的直接法术伤害；point 为中心，recipe 为配方，没有返回值。
func _damage_at(point: Vector2, recipe: PotionDefinition) -> void:
	recipe = relic_recipe(recipe)
	for unit in battle.card_runtime.living_units():
		if battle.battle_finished:
			break
		var ally: bool = unit.unit_data.unit_team == "team_a"
		if (recipe.targets == PotionDefinition.Targets.ENEMIES and ally) or (recipe.targets == PotionDefinition.Targets.ALLIES and not ally):
			continue
		if unit.global_position.distance_to(point) <= recipe.radius:
			var kind: StringName = &"lightning" if recipe.kind == PotionDefinition.Kind.LIGHTNING else (&"burn" if recipe.kind == PotionDefinition.Kind.FIRE else &"skill")
			unit.take_effect_damage(recipe.damage, null, kind)


## 每次施放建立独立快照，原库存实例和共享配方保持可判重、可消耗。
func relic_recipe(recipe: PotionDefinition) -> PotionDefinition:
	if recipe.has_meta("relic_scaled"):
		return recipe
	var alchemy := RunManager.has_relic(&"alchemy_pack")
	var ember := RunManager.has_relic(&"ember")
	if not alchemy and not ember:
		return recipe
	var copy := recipe.duplicate(true) as PotionDefinition
	copy.set_meta("relic_scaled", true)
	if alchemy:
		copy.damage = ceili(copy.damage * 1.25)
		copy.duration *= 1.25
		if copy.rounds > 0: copy.rounds = ceili(copy.rounds * 1.25)
	if ember and copy.kind == PotionDefinition.Kind.FIRE:
		copy.damage += 2
		copy.radius += 30
	for effect: PotionEffect in copy.effects:
		if alchemy:
			if effect.kind in [PotionEffect.Kind.DAMAGE, PotionEffect.Kind.CHAIN_LIGHTNING, PotionEffect.Kind.DELAYED_BLAST]:
				effect.amount = ceili(effect.amount * 1.25)
			if effect.kind == PotionEffect.Kind.DELAYED_BLAST: effect.count = ceili(effect.count * 1.25)
			effect.duration *= 1.25
			if effect.rounds > 0: effect.rounds = ceili(effect.rounds * 1.25)
		if ember and effect.kind == PotionEffect.Kind.DELAYED_BLAST:
			effect.count += 2
			effect.radius += 30
	return copy


# 作用：阶段变化时施加一次开局护甲，并终止离开战斗阶段的药水；phase 为新阶段，没有返回值。
func _on_phase_changed(phase: Global.GamePhase) -> void:
	_cancel_aim()
	if phase != Global.GamePhase.AUTO_BATTLE:
		# 结算后的单位即将清场，取消旧锁定，下一轮重新索敌；整局暂停则原样冻结。
		_clear_thunder_bolts()
		# 已放出的雷云留在同一战场；未施放的选中状态与普通药水仍按原规则回收。
		var persistent_field: bool = potion_runtime != null and potion_runtime.persists_between_rounds() and not battle.battle_finished and phase in [Global.GamePhase.CARD_PLAY, Global.GamePhase.ROUND_RESOLVE]
		if not persistent_field and not (_has_committed_cloud() and not battle.battle_finished and phase in [Global.GamePhase.CARD_PLAY, Global.GamePhase.ROUND_RESOLVE]):
			clear_effect()
		_clear_flash_visuals()
		queue_redraw()
		return
	if _has_committed_cloud():
		remaining_rounds = maxi(0, _cloud_end_round - battle.battle_round_manager.current_round + 1)
		if remaining_rounds == 0:
			clear_effect()
	if opening_applied:
		return
	opening_applied = true
	for relic in RunManager.relics:
		if relic.kind != RelicDefinition.Kind.OPENING_DEFENCE:
			continue
		for unit in battle.card_runtime.living_units():
			if unit.unit_data.unit_team != "team_a":
				continue
			var effect := CardEffect.new()
			effect.kind = CardEffect.Kind.DEFENCE_UP
			effect.amount = relic.amount
			effect.lifetime = CardEffect.Lifetime.ROUNDS
			effect.lasting_rounds = relic.rounds
			battle.card_runtime._add_buff(unit, effect, relic.display_name)


# 作用：清理药水状态与持续视觉；闪电残影独立播完，离开交锋时统一清除，不返还已消耗的瓶子。
func clear_effect() -> void:
	_cancel_aim()
	if potion_runtime != null and not potion_runtime.field.is_empty():
		# 先断开占槽引用，结束区域不会递归回本入口。
		potion = null
		potion_runtime.finish_field()
	_clear_thunder_bolts()
	if is_instance_valid(_thunder_visual):
		_thunder_visual.queue_free()
	_thunder_visual = null
	remaining_rounds = 0
	_cloud_end_round = 0
	_thunder_elapsed = 0.0
	_thunder_next_cast = 0.0
	_thunder_last_target_id = 0
	_thunder_sequence = 0
	if is_instance_valid(_persistent_visual):
		_persistent_visual.queue_free()
	_persistent_visual = null
	_cast_has_visual = false
	potion = null
	committed = false
	remaining_casts = 0
	cooldown = 0.0
	damage_clock = 0.0
	RunManager.items_changed.emit()
	queue_redraw()


# 作用：Godot 重绘时展示瞄准圈和简单法术效果；没有参数，没有返回值。
func _draw() -> void:
	if aiming_potion != null:
		var aim := to_local(battle.get_global_mouse_position())
		draw_arc(aim, aiming_potion.radius, 0, TAU, 48, aiming_potion.tint, 2, true)
		return
	if potion == null:
		return
	if potion.kind == PotionDefinition.Kind.EFFECTS:
		return
	var point := to_local(effect_position if committed else battle.get_global_mouse_position())
	var color := Color(0.4, 0.85, 1.0, 0.65)
	if potion.kind == PotionDefinition.Kind.FIRE:
		color = Color(1.0, 0.32, 0.06, 0.65)
	elif potion.kind == PotionDefinition.Kind.LIGHTNING:
		color = Color(0.85, 0.8, 1.0, 0.8)
	if not committed or (potion.kind == PotionDefinition.Kind.LIGHTNING and cooldown <= 0.0):
		point = to_local(battle.get_global_mouse_position())
		draw_arc(point, potion.radius, 0, TAU, 48, color, 3.0, true)
		return
	if _cast_has_visual:
		if potion.kind == PotionDefinition.Kind.THUNDER_CLOUD:
			draw_circle(point, potion.radius, Color(color, 0.045))
			draw_arc(point, potion.radius, 0, TAU, 64, Color(color, 0.4), 1.5, true)
			var label := "雷云 · %d 回合" % remaining_rounds
			var font := ThemeDB.fallback_font
			var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
			draw_string(font, point + Vector2(-label_size.x * 0.5, potion.radius + 22), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("c1e4eb"))
		return
	draw_circle(point, potion.radius, Color(color, 0.15))
	if potion.kind == PotionDefinition.Kind.TORNADO:
		for index in 5:
			var radius: float = potion.radius * (0.35 + index * 0.12)
			var angle := animation_clock * 5.0 + index * 0.8
			draw_arc(point + Vector2(0, -index * 8), radius, angle, angle + PI * 1.5, 32, color, 4.0, true)
	elif potion.kind == PotionDefinition.Kind.LIGHTNING:
		draw_polyline(PackedVector2Array([point + Vector2(0, -180), point + Vector2(-18, -100), point + Vector2(15, -110), point]), color, 7.0, true)
	else:
		for index in 7:
			var flame := point + Vector2.from_angle(index * TAU / 7.0) * potion.radius * 0.5
			draw_circle(flame, 12.0 + sin(animation_clock * 9.0 + index) * 5.0, color)


# 作用：退出战场时撤销全局入口；没有参数，没有返回值。
func _exit_tree() -> void:
	if RunManager.item_battle == self:
		RunManager.item_battle = null
		RunManager.items_changed.emit()
