# 这玩意儿是干嘛的（核心逻辑）：验证波次单次增益的编辑、持久化、循环叠加与真实 Buff 显示。
# 数据是咋流动的（数据流向）：临时三波关卡 → 批量增益操作 → 保存重读 → 正式战场刷怪。
# 为啥这么写（选型决策）：夹具和恢复文件放 user://，不修改正式关卡或怪物资源。
# 性能咋样（复杂度）：按需执行，检查完成后自动退出。
extends SceneTree

var checks := 0
var failures: Array[String] = []
const TEMPORARY := "user://wave_spawn_fixture.tres"
const RECOVERY := "user://wave_spawn_recovery.tres"

# 作用：自动加载完成后开始测试；没有参数，没有返回值。
func _initialize() -> void:
	_run.call_deferred()

# 作用：记录检查结果；value 为条件、message 为失败说明，没有返回值。
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

# 作用：创建两个独立怪物的波次；scene 为怪物场景、index 为波号，返回打包场景。
func make_wave(scene: PackedScene, index: int) -> PackedScene:
	var wave := Node2D.new()
	wave.name = "Wave%d" % index
	for i in 2:
		var unit := scene.instantiate()
		unit.position = Vector2(-100 - i * 100, 0)
		wave.add_child(unit, true)
		unit.owner = wave
	var packed := PackedScene.new()
	packed.pack(wave)
	wave.free()
	return packed

# 作用：运行编辑器和实战的完整验证；没有参数，没有返回值。
func _run() -> void:
	var sequence = load("res://scripts/battle/wave_sequence.gd")
	var scene := load("res://scenes/units/orc.tscn") as PackedScene
	var template = scene.instantiate()
	var base_attack: int = template.unit_data.attack
	var base_hp: int = template.unit_data.max_hp
	var base_defence: int = template.unit_data.defence
	template.free()
	var config = load("res://data/levels/battle_level_config.gd").new()
	config.battle_scene = load("res://scenes/levels/battles/battle_001.tscn")
	for i in 3:
		config.waves.append(make_wave(scene, i + 1))
	ResourceSaver.save(config, TEMPORARY)
	var editor = load("res://addons/wave_editor/editor.gd").new()
	editor.initial_path = TEMPORARY
	editor.doc.recovery_path = RECOVERY
	root.add_child(editor)
	editor.size = Vector2(1550, 980)
	await process_frame
	var doc = editor.doc
	editor._select_round(2)
	editor._picked(PackedInt32Array([0, 1]))
	editor.effect_mode.select(1)
	editor._effect_kind_changed(1)
	editor.effect_kind.select(0)
	editor.effect_amount.value = 5
	editor._apply_unit_effect()
	check(sequence.effects(doc.rounds[2].get_child(0), sequence.SPAWN_META).get("attack") == 5, "界面配置单次攻击+5")
	check(sequence.effects(doc.rounds[2].get_child(1), sequence.SPAWN_META).get("attack") == 5, "多选批量配置")
	check(sequence.effects(doc.rounds[2].get_child(0)).is_empty(), "单次配置不写入循环配置")
	doc.undo()
	check(sequence.effects(doc.rounds[2].get_child(0), sequence.SPAWN_META).is_empty(), "单次编辑可撤销")
	doc.redo()
	editor._picked(PackedInt32Array([0]))
	doc.set_spawn_effect("max_hp", 7)
	doc.set_spawn_effect("defence", 2)
	doc.set_cycle_effect("attack", 3)
	doc.set_cycle_effect("max_hp", 4)
	doc.set_cycle_effect("defence", 1)
	editor.effect_mode.select(0)
	editor._effect_kind_changed(0)
	check(editor.effect_amount.value == 3, "切换循环模式显示循环原值")
	editor.effect_mode.select(1)
	editor._effect_kind_changed(1)
	check(editor.effect_amount.value == 5, "切换单次模式显示单次原值")
	editor._clear_unit_effect()
	check(not sequence.effects(doc.rounds[2].get_child(0), sequence.SPAWN_META).has("attack"), "清除当前单次属性")
	check(sequence.effects(doc.rounds[2].get_child(0)).get("attack") == 3 and sequence.effects(doc.rounds[2].get_child(0), sequence.SPAWN_META).get("max_hp") == 7, "清除保留其他模式与属性")
	doc.undo()
	doc.edit_units("复制")
	check(sequence.effects(doc.rounds[2].get_child(2), sequence.SPAWN_META).get("attack") == 5, "复制单位保留固定增益")
	doc.undo()
	doc.edit_units("替换", scene)
	check(sequence.effects(doc.rounds[2].get_child(0), sequence.SPAWN_META).get("max_hp") == 7, "替换兵种保留单次增益")
	check(sequence.effects(doc.rounds[2].get_child(0)).get("attack") == 3, "替换同时保留循环成长")
	doc.undo()
	doc.add_round(true)
	check(sequence.effects(doc.rounds[3].get_child(0), sequence.SPAWN_META).get("attack") == 5, "复制回合保留单次增益")
	doc.undo()
	doc.set_repeat_range(2, 3)
	doc.set_field("repeat_waves", true)
	check(doc.save(), "保存带两种增益的关卡")
	check(doc.open(TEMPORARY), "重读关卡")
	check(sequence.effects(doc.rounds[2].get_child(0), sequence.SPAWN_META).get("attack") == 5, "保存重读保留固定增益")
	check(sequence.effects(doc.rounds[2].get_child(0)).get("attack") == 3, "保存重读保留循环成长")
	editor._select_round(2)
	editor._picked(PackedInt32Array([0]))
	doc.set_spawn_effect("attack", 6)
	var restored = load("res://addons/wave_editor/document.gd").new()
	restored.recovery_path = RECOVERY
	check(restored.recover(), "增益编辑可恢复草稿")
	check(sequence.effects(restored.rounds[2].get_child(0), sequence.SPAWN_META).get("attack") == 6, "恢复保留最新单次值")
	restored.history.clear_history()
	restored.history.free()
	restored.clear_nodes()
	doc.undo()
	var output: Resource = doc.output()
	for actual_round in [3, 5, 7, 9]:
		var preview_team = load("res://scripts/battle/level_wave.gd").new()
		preview_team.level_data = output.waves
		preview_team.repeat_waves = true
		preview_team.repeat_start = 2
		preview_team.repeat_end = 3
		preview_team._on_battle_round_manager_phase_changed(0, actual_round)
		var multiplier: int = (actual_round - 3) / 2
		var unit = preview_team.get_child(0)
		check(unit.unit_data.attack == base_attack + 5 + 3 * multiplier, "第%d回合固定+循环攻击" % actual_round)
		check(unit.unit_data.max_hp == base_hp + 7 + 4 * multiplier, "固定与循环生命叠加")
		check(unit.unit_data.defence == base_defence + 2 + multiplier, "固定与循环防御叠加")
		check(preview_team.get_child(1).unit_data.attack == base_attack + 5, "仅单次配置的单位每轮保持固定值")
		preview_team.free()
	var finite = load("res://scripts/battle/level_wave.gd").new()
	finite.level_data = output.waves
	finite.repeat_waves = false
	finite._on_battle_round_manager_phase_changed(0, 5)
	check(finite.get_child(0).unit_data.attack == base_attack + 5, "非循环耗尽重用末波仅应用固定增益")
	finite.free()
	editor._reset_playback()
	for i in 9:
		editor._next()
	check(editor.records[2].contains("攻击力单次+5") and editor.records[2].contains("当前+0"), "首次播放显示固定加成与零循环成长")
	check(editor.records[8].contains("攻击力单次+5") and editor.records[8].contains("当前+9"), "循环播放分别显示两种贡献")
	if "--capture" in OS.get_cmdline_user_args():
		editor._picked(PackedInt32Array([0]))
		editor.size = Vector2(1550, 980)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://wave_spawn_preview.png")

	# 实际入树顺序会先登记 Buff，再初始化满血和血条。
	root.get_node("RunManager").start_new_run()
	var battle: Node = output.battle_scene.instantiate()
	battle.configure_level(output)
	battle.get_node("BattleRoundManager").first_round = 3
	battle.get_node("Entities/TeamB").last_round = 2
	root.add_child(battle)
	await process_frame
	var team: Node = battle.get_node("Entities/TeamB")
	var runtime = battle.card_runtime
	var first = team.get_child(0)
	var display = first.get_node("HealthBar").status_display
	check(first.current_health == base_hp + 7 and first.get_node("HealthBar").hp_bar.max_value == base_hp + 7, "首波满血和血条使用单次生命增益")
	check(display.statuses.size() == 3 and first.get_node("HealthBar").visible, "首次满血也显示三种单次 Buff")
	check(display.statuses[0].tooltip == "攻击力提升：+5", "Buff 悬停只显示当前固定加成")
	check(not display.statuses[0].tooltip.contains("循环成长"), "首次没有零值循环 Buff")
	runtime._register_unit(first)
	check(first.unit_data.attack == base_attack + 5 and runtime.states[first.get_instance_id()].buffs.size() == 3, "重复登记不重复增加固定增益")
	team._on_battle_round_manager_phase_changed(0, 5)
	var repeated = team.get_child(2)
	var repeated_display = repeated.get_node("HealthBar").status_display
	check(first.unit_data.attack == base_attack + 5 and repeated.unit_data.attack == base_attack + 8, "新单位增长不修改旧单位")
	check(repeated_display.statuses.size() == 3 and runtime.states[repeated.get_instance_id()].buffs.size() == 6, "两种贡献合并图标并分别登记")
	check(repeated_display.statuses[0].tooltip == "攻击力提升：+8", "固定与循环成长只显示当前合计值")
	check(runtime.describe_buffs(repeated).size() == 6, "详情保留两种 Buff 来源")
	var effect_script = load("res://data/card_effects/card_effect.gd")
	var extra = effect_script.new()
	extra.kind = effect_script.Kind.ATTACK_UP
	extra.amount = 4
	extra.lifetime = effect_script.Lifetime.ROUNDS
	extra.lasting_rounds = 1
	runtime._add_buff(repeated, extra, "临时攻击")
	check(repeated.unit_data.attack == base_attack + 12 and repeated_display.statuses[0].tooltip.contains("攻击力提升：+12"), "普通 Buff 与两种波次增益叠加一次")
	runtime._tick_buffs()
	check(repeated.unit_data.attack == base_attack + 8 and repeated_display.statuses[0].tooltip.contains("攻击力提升：+8"), "到期仅清除临时贡献")
	first.die()
	check(display.statuses.is_empty(), "死亡清除单次 Buff 图标")
	runtime.clear_battle_buffs()
	check(repeated_display.statuses.is_empty(), "战斗结束清除两种 Buff")
	check(repeated.unit_data.attack == base_attack and repeated.unit_data.max_hp == base_hp and repeated.unit_data.defence == base_defence, "清理准确还原全部属性")
	root.remove_child(battle)
	battle.free()
	template = scene.instantiate()
	check(template.unit_data.attack == base_attack and template.unit_data.max_hp == base_hp, "基础怪物资源未被污染")
	template.free()
	editor.free()
	for path in [TEMPORARY, RECOVERY]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("WAVE_SPAWN_EFFECT_TEST: ", checks, " checks; ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
