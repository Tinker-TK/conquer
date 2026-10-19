# 真实场景验证 ready 前隔离、登记、命中帧连线和换父节点时的生命保持。
extends Node

var checks := 0
var failures: Array[String] = []
var battle
var fresh: UnitBase
var observed_early := false


func _ready() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func _observe_entry(node: Node) -> void:
	if node != fresh:
		return
	observed_early = true
	check(not fresh.is_node_ready() and not fresh.is_alive(), "ready 前不能作为活单位查询")
	check(fresh.current_health == fresh.unit_data.max_hp, "登记信号前已建立非空的初始生命")
	check(not battle.card_runtime.states.has(fresh.get_instance_id()), "ready 前不登记战术/卡牌状态")
	check(not battle.card_runtime.living_units().has(fresh), "同步登记回调查询也不能读到半初始化单位")


func _run() -> void:
	var empty := UnitBase.new()
	check(empty.current_health == 0 and not empty.is_alive(), "未入树单位的生命为零且不存活")
	check(not empty.configuration_error().is_empty(), "无数据单位可在入树前被拒绝")
	empty.free()
	for filename in DirAccess.get_files_at("res://scenes/units"):
		if not filename.ends_with(".tscn") or filename == "player_base.tscn":
			continue
		var unit: UnitBase = load("res://scenes/units/" + filename).instantiate()
		check(unit.configuration_error().is_empty(), "正式单位场景契约：" + filename)
		unit.free()
	RunManager.start_new_run(RunStartData.new())
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	var team: Node = battle.get_node("Entities/TeamA")
	team.child_entered_tree.connect(_observe_entry)
	fresh = load("res://scenes/units/soldier.tscn").instantiate()
	# 模拟作者漏连帧信号；SkillManager 应自行补接，保留正常场景时则不得重复。
	var sprite := fresh.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var manager := fresh.get_node("SkillManager")
	for connection: Dictionary in sprite.frame_changed.get_connections():
		if connection.callable.get_object() == manager:
			sprite.frame_changed.disconnect(connection.callable)
	team.add_child(fresh)
	check(observed_early and fresh.is_alive(), "add_child 返回后完成生命初始化")
	check(battle.card_runtime.living_units().has(fresh), "ready 后立即可作为正式目标")
	check(battle.card_runtime.tactics.ally_count == 1, "新单位立即计入战术阵容")
	var frames := sprite.frame_changed.get_connections().filter(func(c: Dictionary): return c.callable.get_object() == manager)
	check(frames.size() == 1, "漏连的命中帧信号只补接一次")
	battle.card_runtime._register_unit(fresh)
	battle.card_runtime._register_unit(fresh)
	check(fresh.hit_received.get_connections().size() == 1, "重复登记不重复连接命中事件")
	fresh.current_health = 0
	check(not fresh.is_alive() and not battle.card_runtime.living_units().has(fresh), "零生命单位从所有存活查询排除")
	var survivors: Array[UnitBase] = [fresh]
	check(battle.battle_round_manager.calculate_round_hp_damage(3, survivors) == 3, "零生命不贡献回合 HP 伤害")
	fresh.current_health = 50
	fresh.current_state = UnitBase.State.DEATH
	check(not fresh.is_alive(), "死亡标记优先于正生命")
	fresh.current_state = UnitBase.State.IDLE
	fresh.queue_free()
	check(not fresh.is_alive(), "待删除单位不参与结算")
	await get_tree().process_frame
	check(battle.card_runtime.tactics.ally_count == 0, "退场立即移除阵容贡献")
	var left := Node2D.new()
	var right := Node2D.new()
	get_tree().root.add_child(left)
	get_tree().root.add_child(right)
	var moved: UnitBase = load("res://scenes/units/soldier.tscn").instantiate()
	left.add_child(moved)
	moved.current_health = 37
	var runtime_data := moved.unit_data
	moved.reparent(right)
	check(moved.current_health == 37 and moved.unit_data == runtime_data, "换父节点不重置生命或重复制运行数据")
	check(moved.is_alive(), "换父节点后仍正常存活")
	left.queue_free()
	right.queue_free()
	battle.battle_finished = true
	battle.queue_free()
	await get_tree().process_frame
	print("UNIT_LIFECYCLE_TEST: %d checks; failures=%s" % [checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
