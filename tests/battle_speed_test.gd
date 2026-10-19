# 真正运行寻路、攻击动画、冷却、弹道、召唤与持续效果；同一输入比较三档和途中切档。
extends Node

var checks := 0
var failures: Array[String] = []
var battle
var _events: Array = []
var _result: Dictionary = {}
var _serial := 0
var _origin := 0
var _measuring := false
var _bad_delta := false
var comparisons: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func _physics_process(delta: float) -> void:
	if _measuring and not is_equal_approx(delta, 1.0 / 60.0):
		_bad_delta = true


func _click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await get_tree().process_frame
	await get_tree().process_frame


func _ui() -> void:
	RunManager.start_new_run()
	RunManager.starting_reward_pending = false # 开局奖励已由balance-ui验证，本组操作顶部倍速。
	var session = load("res://scenes/app/game_session.tscn").instantiate()
	get_tree().root.add_child(session)
	get_tree().current_scene = session
	await get_tree().process_frame
	var controls: HBoxContainer = session.get_node("HUDLayer/RunHUD/TopButtons/SpeedControls")
	check(controls.get_child(0).button_pressed, "默认选择原速")
	check(controls.get_global_rect().end.x < session.map_button.get_global_rect().position.x, "倍速按钮位于章节与地图按钮之间")
	for speed in [2, 3, 1, 3]:
		await _click(controls.get_child(speed - 1))
		check(BattleSpeed.multiplier == speed and controls.get_child(speed - 1).button_pressed, "真实点击选择 %d 倍速" % speed)
		check(Engine.time_scale == 1.0 and Engine.physics_ticks_per_second == 60, "地图预选倍速不加速地图")
	BattleSpeed.set_multiplier(9)
	check(BattleSpeed.multiplier == 3, "拒绝无效速度")
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.maintenance/battle-speed-buttons.png")
	session.free()
	check(BattleSpeed.multiplier == 1 and Engine.time_scale == 1.0, "退出本局恢复原速")
	await get_tree().process_frame


func _observe(unit: Node) -> void:
	if not unit is UnitBase:
		return
	_serial += 1
	unit.set_meta("speed_test_id", _serial)
	unit.unit_died.connect(_death)
	unit.attack_resolved.connect(_hit)
	if _measuring:
		_events.append(["spawn", _serial, unit.unit_data.unit_english_name])


func _id(unit: UnitBase) -> int:
	return int(unit.get_meta("speed_test_id", 0)) if is_instance_valid(unit) else 0


func _death(unit: UnitBase) -> void:
	_events.append(["death", _id(unit)])


func _hit(unit: UnitBase, attacker: UnitBase, damage: int) -> void:
	_events.append(["hit", _id(unit), _id(attacker), damage])


func _settled(result: StringName, damage: int, base_damage: int, unit_damage: int) -> void:
	var survivors: Array = []
	for unit in battle.card_runtime.living_units():
		survivors.append([_id(unit), unit.unit_data.unit_team, int(unit.current_health)])
	_result = {"result": String(result), "damage": damage, "base": base_damage, "units": unit_damage,
		"player_hp": RunManager.hp, "enemy_hp": battle.battle_round_manager.enemy_hp, "survivors": survivors}


func _unit(scene_name: String, team: String, point: Vector2, hp: int = 100) -> UnitBase:
	var unit := load("res://scenes/units/%s.tscn" % scene_name).instantiate() as UnitBase
	unit.unit_data = unit.unit_data.duplicate()
	unit.unit_data.unit_team = team
	unit.unit_data.max_hp = hp
	unit.unit_data.attack = 24
	unit.unit_data.defence = 2
	unit.unit_data.speed = 120
	unit.remove_from_group("team_b" if team == "team_a" else "team_a")
	unit.add_to_group(team)
	unit.set_collision_layer_value(1, team == "team_a")
	unit.set_collision_layer_value(2, team == "team_b")
	var parent: Node2D = battle.get_node("Entities/TeamA" if team == "team_a" else "Entities/TeamB")
	unit.position = parent.to_local(point)
	parent.add_child(unit)
	return unit


func _effect(kind: CardEffect.Kind, amount: float, target: UnitBase) -> void:
	var effect := CardEffect.new()
	effect.kind = kind
	effect.amount = amount
	effect.radius = 175
	effect.interval = 0.4
	if kind == CardEffect.Kind.PARALYSIS:
		effect.lifetime = CardEffect.Lifetime.ROUNDS
		effect.lasting_rounds = 1
	var definition := CardDefinition.new()
	definition.card_name = "倍速测试效果"
	definition.effects.append(effect)
	definition.target = CardDefinition.Target.ALLY if target.unit_data.unit_team == "team_a" else CardDefinition.Target.ENEMY
	if kind == CardEffect.Kind.DAMAGE_ZONE:
		definition.target = CardDefinition.Target.POSITION
		definition.category = CardDefinition.Category.ABILITY
		definition.effects[0].affected_team = CardEffect.AffectedTeam.BOTH
	var card := CardInstance.new(definition)
	battle.hand_manager.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(card, target.global_position), "倍速夹具通过正式施放入口")


func _fight(kind: String, speed: int, switch_during: bool = false) -> Dictionary:
	BattleSpeed.reset()
	var start := RunStartData.new()
	start.max_hp = 200
	RunManager.start_new_run(start)
	seed(731291)
	_events.clear()
	_result.clear()
	_serial = 0
	_bad_delta = false
	_measuring = false
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.enemy_max_hp = 1
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	for team in ["TeamA", "TeamB"]:
		battle.get_node("Entities/" + team).child_entered_tree.connect(_observe)
	var ally: UnitBase
	var enemy: UnitBase
	match kind:
		"melee":
			ally = _unit("soldier", "team_a", Vector2(600, 500))
			enemy = _unit("orc", "team_b", Vector2(820, 500))
		"ranged", "effects":
			ally = _unit("archer", "team_a", Vector2(540, 550), 150)
			_unit("soldier", "team_a", Vector2(620, 440), 150)
			enemy = _unit("skeleton_archer", "team_b", Vector2(880, 550), 150)
			_unit("orc", "team_b", Vector2(800, 440), 150)
		"dash":
			ally = _unit("knight", "team_a", Vector2(550, 500), 180)
			ally.unit_data.dodge_rate = 0.4
			enemy = _unit("orc", "team_b", Vector2(820, 500), 150)
			_unit("bat", "team_b", Vector2(830, 600))
		"summon":
			ally = _unit("soldier", "team_a", Vector2(540, 490), 180)
			_unit("archer", "team_a", Vector2(510, 610), 180)
			enemy = _unit("necromancer", "team_b", Vector2(840, 490), 240)
	if kind == "effects":
		_effect(CardEffect.Kind.POISON_ON_HIT, 2, ally)
		_effect(CardEffect.Kind.DEATH_EXPLOSION, 25, enemy)
		_effect(CardEffect.Kind.PARALYSIS, 0.15, enemy)
		_effect(CardEffect.Kind.FRENZY, 20, ally)
		_effect(CardEffect.Kind.DAMAGE_ZONE, 2, enemy)
	# 同样数量的准备物理步让导航同步；每场以相同 RNG 状态开始，不依赖渲染帧数。
	for step in 3:
		await get_tree().physics_frame
	BattleSpeed.set_multiplier(speed)
	battle.battle_round_manager.round_settled.connect(_settled)
	_origin = Engine.get_physics_frames()
	_measuring = true
	var render_start := Engine.get_process_frames()
	battle.battle_round_manager.start_auto_battle()
	if kind == "effects":
		var potion := load("res://data/potions/thunder_cloud.tres") as PotionDefinition
		RunManager.add_potion(potion)
		var items = battle.get_node("BattleItems")
		check(items.select_potion(RunManager.potions[0]) and items.try_cast(Vector2(820, 500)), "比较战斗包含真实雷云药水")
	var changed := false
	var paused := false
	while _result.is_empty() and Engine.get_physics_frames() - _origin < 3600:
		await get_tree().physics_frame
		var step := Engine.get_physics_frames() - _origin
		if switch_during and step >= 90 and not changed:
			changed = true
			BattleSpeed.set_multiplier(3)
		if switch_during and step >= 180 and not paused:
			paused = true
			get_tree().paused = true
			var point := ally.global_position if is_instance_valid(ally) else Vector2.ZERO
			await get_tree().create_timer(0.15, true, false, true).timeout
			check(not is_instance_valid(ally) or ally.global_position == point, "倍速暂停期间单位不移动")
			get_tree().paused = false
			BattleSpeed.set_multiplier(2)
	_measuring = false
	check(not _bad_delta, "%s %d倍每步保持 1/60 秒" % [kind, speed])
	check(not _result.is_empty(), "%s %d倍实际完成回合" % [kind, speed])
	var output := {"result": _result.duplicate(true), "events": _events.duplicate(true), "frames": Engine.get_process_frames() - render_start}
	comparisons.append({"kind": kind, "speed": speed, "switch": switch_during, "result": output.result,
		"events": output.events.size(), "event_hash": JSON.stringify(output.events).sha256_text(), "render_frames": output.frames})
	print("SPEED_COMPARE: %s %dx switch=%s result=%s events=%d frames=%d" % [kind, speed, switch_during, output.result.get("result", "unfinished"), output.events.size(), output.frames])
	battle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(Engine.time_scale == 1.0 and Engine.physics_ticks_per_second == 60, "离开战场恢复引擎原速")
	return output


func _run() -> void:
	await _ui()
	for kind in ["melee", "ranged", "dash", "summon", "effects"]:
		var normal := await _fight(kind, 1)
		for speed in [2, 3]:
			var accelerated := await _fight(kind, speed)
			check(accelerated.result == normal.result, "%s %d倍胜负、幸存生命和回合扣血与原速一致" % [kind, speed])
			check(accelerated.events == normal.events, "%s %d倍全部命中、死亡及召唤顺序与原速一致" % [kind, speed])
			check(accelerated.frames < normal.frames, "%s %d倍实际加快播放" % [kind, speed])
		var switched := await _fight(kind, 1, true)
		check(switched.result == normal.result and switched.events == normal.events, "%s 战斗途中切档和暂停不改变结果" % kind)
	var file := FileAccess.open("res://.maintenance/battle-speed-comparison.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(comparisons, "\t"))
	BattleSpeed.reset()
	print("BATTLE_SPEED_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
