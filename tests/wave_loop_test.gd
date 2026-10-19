# 这玩意儿是干嘛的（核心逻辑）：验证区间循环、逐单位成长，以及编辑器与实战一致。
# 数据是咋流动的（数据流向）：临时六波夹具 → 3–5 循环 → 第 3/6/9/12 回合属性核对。
# 为啥这么写（选型决策）：所有保存都写测试目录，不修改玩家的正式关卡和怪物资源。
# 性能咋样（复杂度）：手动执行一次，几十条断言后退出。
extends SceneTree

var failures: Array[String] = []
var checks := 0
var temporary := "user://wave_loop_fixture.tres"
var recovery := "user://wave_loop_recovery.tres"

# 作用：引擎初始化后执行测试；没有参数，没有返回值。
func _initialize() -> void:
	_run.call_deferred()

# 作用：记录检查结果；value 为是否符合预期，message 为失败说明，没有返回值。
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

# 作用：构造单波两怪；scene 为怪物场景、index 为波号，返回独立打包场景。
func make_wave(scene: PackedScene, index: int) -> PackedScene:
	var wave := Node2D.new()
	wave.name = "Wave%d" % index
	for i in 2:
		var unit := scene.instantiate()
		unit.position = Vector2(index * 10, i * 100)
		wave.add_child(unit, true)
		unit.owner = wave
	var packed := PackedScene.new()
	packed.pack(wave)
	wave.free()
	return packed

# 作用：执行模型、界面与真实刷怪的回归；没有参数，没有返回值。
func _run() -> void:
	var sequence = load("res://scripts/battle/wave_sequence.gd")
	var scene := load("res://scenes/units/orc.tscn") as PackedScene
	var template := scene.instantiate()
	var base_attack: int = template.unit_data.attack
	var base_hp: int = template.unit_data.max_hp
	var base_defence: int = template.unit_data.defence
	template.free()
	var config = load("res://data/levels/battle_level_config.gd").new()
	config.battle_scene = load("res://scenes/levels/battles/battle_001.tscn")
	for i in 6:
		config.waves.append(make_wave(scene, i + 1) if i != 3 else null)
	ResourceSaver.save(config, temporary)
	var editor = load("res://addons/wave_editor/editor.gd").new()
	editor.initial_path = temporary
	editor.doc.recovery_path = recovery
	root.add_child(editor)
	editor.size = Vector2(1550, 980)
	await process_frame
	var doc = editor.doc
	editor.repeat.button_pressed = true
	editor.loop_start.value = 3
	editor.loop_end.value = 5
	editor._apply_repeat_range()
	check(doc.config.repeat_start == 3 and doc.config.repeat_end == 5, "界面设置 3–5")
	doc.undo()
	check(doc.config.repeat_start == 1 and doc.config.repeat_end == 0, "撤销循环范围")
	doc.redo()
	editor._select_round(2)
	editor._picked(PackedInt32Array([0]))
	editor.effect_kind.select(0)
	editor.effect_amount.value = 3
	editor._apply_unit_effect()
	check(sequence.effects(doc.rounds[2].get_child(0)).get("attack", 0) == 3, "选中单位攻击增长3")
	check(sequence.effects(doc.rounds[2].get_child(1)).is_empty(), "未选中单位无效果")
	doc.undo()
	check(sequence.effects(doc.rounds[2].get_child(0)).is_empty(), "撤销效果")
	doc.redo()
	doc.set_cycle_effect("max_hp", 5)
	doc.set_cycle_effect("defence", 2)
	doc.edit_units("复制")
	check(sequence.effects(doc.rounds[2].get_child(2)).get("attack", 0) == 3, "复制单位保留效果")
	doc.undo()
	doc.edit_units("替换", scene)
	check(sequence.effects(doc.rounds[2].get_child(0)).get("attack", 0) == 3, "替换兵种保留效果")
	doc.undo()
	doc.add_round(true)
	check(sequence.effects(doc.rounds[3].get_child(0)).get("attack", 0) == 3, "复制波次保留效果")
	doc.undo()
	check(doc.save(), "保存区间及单位元数据")
	doc.open(temporary)
	check(doc.config.repeat_start == 3 and doc.config.repeat_end == 5, "重读循环范围")
	check(sequence.effects(doc.rounds[2].get_child(0)).get("attack", 0) == 3, "重读单位效果")
	check(sequence.validate_range(6, true, 5, 3) != "", "拒绝倒置范围")
	check(sequence.validate_range(6, true, 1, 7) != "", "拒绝越界范围")
	check(sequence.resolve(6, 6, true, 3, 5).index == 2, "第6回合回到第3波，跳过原始第6波")
	check(sequence.resolve(9, 6, true, 3, 5).cycle == 2, "第9回合倍率2")
	check(sequence.resolve(12, 6, true, 3, 5).cycle == 3, "第12回合倍率3")
	check(sequence.resolve(7, 6, true, 3, 5).index == 3, "循环保留空波次")
	check(sequence.resolve(7, 6, true).index == 0, "旧配置默认循环全部")
	check(sequence.resolve(4, 6, true, 3, 3).index == 2 and sequence.resolve(5, 6, true, 3, 3).cycle == 2, "单波循环")
	check(sequence.resolve(7, 6, false).index == -1, "关闭循环解析不越界")

	# 刷怪器每次从原场景复制属性，不从已经增强的单位继续累加。
	var output: Resource = doc.output()
	for actual_round in [3, 6, 9, 12]:
		var preview_team = load("res://scripts/battle/level_wave.gd").new()
		preview_team.level_data = output.waves
		preview_team.repeat_waves = true
		preview_team.repeat_start = 3
		preview_team.repeat_end = 5
		preview_team._on_battle_round_manager_phase_changed(0, actual_round)
		check(preview_team.get_child_count() == 2, "实际第%d回合生成第3波两怪" % actual_round)
		var times: int = (actual_round - 3) / 3
		check(preview_team.get_child(0).unit_data.attack == base_attack + 3 * times, "第%d回合攻击+%d" % [actual_round, 3 * times])
		check(preview_team.get_child(0).unit_data.max_hp == base_hp + 5 * times, "生命累计成长")
		check(preview_team.get_child(0).unit_data.defence == base_defence + 2 * times, "防御累计成长")
		check(preview_team.get_child(1).unit_data.attack == base_attack, "同类未配置单位不受影响")
		preview_team._on_battle_round_manager_phase_changed(0, actual_round)
		check(preview_team.get_child_count() == 2, "同回合信号不会重复出兵")
		preview_team.free()
	template = scene.instantiate()
	check(template.unit_data.attack == base_attack, "基础怪物资源没有被污染")
	template.free()
	var finite = load("res://scripts/battle/level_wave.gd").new()
	finite.level_data = output.waves
	finite.repeat_waves = false
	finite._on_battle_round_manager_phase_changed(0, 9)
	check(finite.get_child(0).position.x == 60 and finite.get_child(0).unit_data.attack == base_attack, "保留非循环耗尽后重用末波的规则")
	finite.free()

	editor._reset_playback()
	for actual_round in range(1, 13):
		editor._next()
		if actual_round in [3, 6, 9, 12]:
			@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
			check(doc.current == 2 and editor.display_cycle == (actual_round - 3) / 3, "预览与实战倍率一致")
			check(editor.records[-1].contains("当前+%d" % (actual_round - 3)), "播放记录显示累计攻击加成")
	check(editor.records[6].contains("空回合"), "播放记录显示循环中的空波")
	editor._launch()
	var snapshot := ResourceLoader.load("user://wave_editor_playtest.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(snapshot.get_meta("wave_editor_start_round") == 12, "从循环预览启动保留实际第12回合号")
	if "--capture" in OS.get_cmdline_user_args():
		editor._picked(PackedInt32Array([0]))
		editor.size = Vector2(1550, 980)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://wave_loop_preview.png")

	# 加入正式战场，检查入树初始化不会覆盖增长后的满血及攻击力。
	root.get_node("RunManager").start_new_run()
	var battle: Node = output.battle_scene.instantiate()
	battle.configure_level(output)
	battle.get_node("BattleRoundManager").first_round = 9
	battle.get_node("Entities/TeamB").last_round = 8
	root.add_child(battle)
	await process_frame
	var team: Node = battle.get_node("Entities/TeamB")
	check(team.get_child(0).unit_data.attack == base_attack + 6, "正式战场第9回合攻击+6")
	check(team.get_child(0).current_health == base_hp + 10, "正式初始化使用增长后的满血")
	var runtime = battle.card_runtime
	var grown = team.get_child(0)
	var display = grown.get_node("HealthBar").status_display
	check(display.statuses.size() == 3, "循环攻击、生命、防御都显示 Buff 图标")
	check(grown.get_node("HealthBar").visible, "满血循环单位也显示 Buff")
	check(display.statuses[0].icon == "attack" and display.statuses[0].tooltip.contains("攻击力提升：+6"), "攻击 Buff 显示累计值")
	check(display.statuses[0].tooltip == "攻击力提升：+6", "循环 Buff 只显示当前加成，不附加触发次数或成长配方")
	check(display.statuses[1].icon == "max_hp" and display.statuses[1].tooltip == "最大生命提升：+10", "生命成长提示不附加来源或期限")
	check(display.statuses[2].icon == "defence" and display.statuses[2].tooltip == "防御力提升：+4", "防御成长提示只显示当前加成")
	check(team.get_child(1).get_node("HealthBar").status_display.statuses.is_empty(), "未配置单位不显示成长 Buff")
	runtime._register_unit(grown)
	check(runtime.states[grown.get_instance_id()].buffs.size() == 3 and grown.unit_data.attack == base_attack + 6, "重复登记不叠加成长")
	var effect_script = load("res://data/card_effects/card_effect.gd")
	var extra = effect_script.new()
	extra.kind = effect_script.Kind.ATTACK_UP
	extra.amount = 4
	extra.lifetime = effect_script.Lifetime.ROUNDS
	extra.lasting_rounds = 1
	runtime._add_buff(grown, extra, "临时攻击")
	check(display.statuses.size() == 3 and display.statuses[0].tooltip.contains("攻击力提升：+10"), "同类 Buff 合并显示")
	check(grown.unit_data.attack == base_attack + 10, "循环与普通 Buff 数值只叠加一次")
	runtime._tick_buffs()
	check(grown.unit_data.attack == base_attack + 6 and display.statuses[0].tooltip.contains("攻击力提升：+6"), "临时 Buff 到期保留循环成长")
	check(runtime.describe_buffs(grown).size() == 3, "详情包含三种成长 Buff")
	# 同时覆盖运行时建立后才刷出的单位，以及首次出场零成长。
	for cycle in [0, 1, 3]:
		var late = scene.instantiate()
		late.set_meta(sequence.EFFECT_META, {"attack": 3})
		sequence.apply_effects(late, cycle)
		team.add_child(late)
		var late_display = late.get_node("HealthBar").status_display
		check(late.unit_data.attack == base_attack + 3 * cycle, "后续出场成长不重复")
		check(late_display.statuses.size() == (0 if cycle == 0 else 1), "首次无 Buff，后续循环显示 Buff")
		if cycle > 0:
			check(late_display.statuses[0].tooltip.contains("攻击力提升：+%d" % (3 * cycle)), "后续循环显示正确累计值")
	runtime.clear_battle_buffs()
	check(display.statuses.is_empty(), "战斗清理移除循环图标")
	check(grown.unit_data.attack == base_attack and grown.unit_data.max_hp == base_hp and grown.unit_data.defence == base_defence, "清理准确撤销成长")
	check(grown.get_node("HealthBar").hp_bar.max_value == base_hp, "生命 Buff 清理同步血条上限")
	root.remove_child(battle)
	battle.free()
	editor.free()
	for path in [temporary, recovery, "user://wave_editor_playtest.tres"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("WAVE_LOOP_TEST: ", checks, " checks; ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
