# 真实工坊、路线导入、胜利 UI 和库存回归；用真实鼠标验证奖励与三选一卡牌。
extends Node

const CONFIG = preload("res://scripts/map/fixed_map_config.gd")
const REWARDS = preload("res://scripts/battle/battle_reward_session.gd")
var failures: Array[String] = []
var checks := 0
var capture := false

func _ready() -> void:
	capture = "--capture-rewards" in OS.get_cmdline_user_args()
	_run.call_deferred()

func check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures.append(message)
		push_error(message)

func click(button: Control) -> void:
	await get_tree().process_frame
	var point := button.get_global_transform() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func shot(resource_name: String) -> void:
	if not capture:
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/checks/battle-rewards")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/checks/battle-rewards/%s.png" % resource_name)

func settle() -> void:
	for frame in 240:
		if not SceneTransition.busy:
			await get_tree().process_frame
			return
		await get_tree().process_frame
	check(false, "场景切换按时结束")

func _run() -> void:
	SceneTransition.reduced_motion = true
	var run := RunManager
	run.selected_map = {}
	run.start_new_run(load("res://data/run/run_start_data.tres"))
	check(BattleRewardConfig.content_error({"gold": 1, "potion_chance": 0, "relic_chance": 100}).is_empty(), "金币与概率边界允许配置")
	for invalid in [{"gold": 0, "potion_chance": 20, "relic_chance": 5},
		{"gold": 1.5, "potion_chance": 20, "relic_chance": 5},
		{"gold": 1, "potion_chance": 101, "relic_chance": 5},
		{"gold": 1, "potion_chance": NAN, "relic_chance": 5},
		{"gold": 1, "potion_chance": 20, "relic_chance": "5"}]:
		check(not BattleRewardConfig.content_error(invalid).is_empty(), "错误奖励数值被拒绝")
	check(not CONFIG.battle_reward_error({"reward_config": "res://data/potions/fire.tres"}).is_empty(), "错误资源类型被拒绝")
	check(not CONFIG.battle_reward_error({"reward_config": "res://missing.tres"}).is_empty(), "缺失资源被拒绝")
	check(CONFIG.battle_reward_content({"event_id": "level_001"}).gold > 0, "旧地图兼容默认奖励")
	var editor = load("res://addons/map_editor/editor.gd").new()
	get_tree().root.add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	editor.doc.new_map(true)
	editor._picked("floor_01_01")
	check(editor.reward_box.visible and editor.reward_gold.min_value == 1, "工坊战斗节点展示奖励栏目")
	editor._load_reward_config("res://data/battle_rewards/normal.tres")
	check(editor.doc.node().reward_config.ends_with("normal.tres") and editor.reward_gold.value == 35, "加载奖励模板回填数值")
	editor.reward_gold.value = 123
	editor.reward_potion.value = 100
	editor.reward_relic.value = 100
	var configured: Dictionary = editor.doc.node().battle_rewards.duplicate(true)
	check(configured == {"gold": 123, "potion_chance": 100.0, "relic_chance": 100.0}, "金币与概率写入当前战斗")
	editor._load_reward_config("res://data/battle_rewards/boss.tres")
	check(editor.reward_gold.value == 120, "支持切换另一份奖励配置")
	editor.doc.undo()
	check(editor.doc.node().battle_rewards == configured, "加载模板可撤销且恢复节点数值")
	editor.doc.redo()
	check(editor.reward_gold.value == 120, "加载模板可重做")
	editor.doc.undo()
	check(editor.doc.save("user://battle_rewards_map.json"), "奖励节点可保存")
	var imported := CONFIG.read_file("user://battle_rewards_map.json")
	check(imported.has("data") and CONFIG.battle_reward_content(imported.data.locations[0]) == configured, "奖励配置无损导入")
	await shot("workshop")
	editor._picked("floor_02_01")
	check(not editor.reward_box.visible, "非战斗节点隐藏奖励栏目")
	editor.queue_free()
	await get_tree().process_frame
	# 随机结果固定在会话创建时，概率 0 和 100 有确切边界。
	var always := {"gold": 123, "potion_chance": 100.0, "relic_chance": 100.0}
	var never := {"gold": 7, "potion_chance": 0.0, "relic_chance": 0.0}
	var reward = REWARDS.new()
	reward.initialize(run, never, 8)
	check(reward.offers.size() == 2 and reward.candidates.size() == 3, "金币卡牌必定出现，零概率不掉药水遗物")
	check(reward.candidates[0] != reward.candidates[1] and reward.candidates[1] != reward.candidates[2] and reward.candidates[0] != reward.candidates[2], "三选一候选互不重复")
	for card in REWARDS.card_pool():
		check(not card is UnitData or card.unit_team == "team_a", "奖励池排除敌军单位")
	var same = REWARDS.new()
	same.initialize(run, never, 8)
	check(same.candidates == reward.candidates, "同一随机种子产生稳定候选")
	check(not reward.claim(1, -1) and not reward.claim(1, 999), "无效卡牌选择不发奖")
	var card_count: int = run.deck.size()
	reward.skip_cards()
	check(run.deck.size() == card_count and not reward.claim(1, 0), "跳过后不能再次领取卡牌")
	var gold_before: int = run.gold
	check(reward.claim(0) and not reward.claim(0) and run.gold == gold_before + 7, "金币领取仅一次")
	reward.close()
	check(not reward.claim(0), "已结束会话不可领取")
	var exhausted = REWARDS.new()
	for relic in REWARDS.CATALOG.pool([], "relic"):
		run.add_relic(relic)
	exhausted.initialize(run, always, 3)
	check(exhausted.offers.size() == 3, "遗物全部拥有时仍提供金币卡牌药水")
	run.selected_map = imported.data
	run.start_new_run(load("res://data/run/run_start_data.tres"))
	check(run.active_map.locations[0].battle_rewards == configured, "新局冻结节点奖励数值")
	var session = load("res://scenes/app/game_session.tscn").instantiate()
	run.starting_reward_pending = false # 本组验证结算界面，不进入开局三选一。
	get_tree().root.add_child(session)
	await get_tree().process_frame
	await get_tree().process_frame
	session.map_view._on_node_enter_requested(session.map_view.node_views.floor_01_01)
	await settle()
	var battle = session.current_battle
	if not is_instance_valid(battle):
		check(false, "地图进入真实战斗")
		get_tree().quit(1)
		return
	check(run.pending_battle_rewards == configured, "工坊奖励配置传入当前战斗")
	gold_before = run.gold
	card_count = run.deck.size()
	var potion_count: int = run.potions.size()
	var relic_count: int = run.relics.size()
	battle.finish_battle(true)
	var result = battle.get_node("GameOver")
	var panel = result.reward_panel
	check(result.visible and panel.reward_buttons.size() == 4 and not panel.cards_view.visible, "胜利首先显示四种可领取奖励")
	for button in panel.reward_buttons:
		for child in button.get_children():
			if child is TextureRect:
				check(child.size == Vector2(60, 60) and Rect2(Vector2.ZERO, button.size).encloses(Rect2(child.position, child.size)), "奖励图标限制在当前行内")
	check(run.gold == gold_before and run.deck.size() == card_count and run.potions.size() == potion_count and run.relics.size() == relic_count, "胜利不自动发奖")
	await shot("victory")
	await click(panel.reward_buttons[0])
	check(run.gold == gold_before + 123 and panel.reward_buttons[0].disabled, "真实鼠标领取配置金币")
	await click(panel.reward_buttons[0])
	check(run.gold == gold_before + 123, "重复点击不多发金币")
	await click(panel.reward_buttons[1])
	check(panel.cards_view.visible and panel.card_buttons.size() == 3 and run.deck.size() == card_count, "点击卡牌奖励才显示三张牌")
	var candidates: Array = result.reward_session.candidates.duplicate()
	await shot("choose_card")
	if capture:
		get_tree().root.size = Vector2i(1024, 768)
		await get_tree().process_frame
		await shot("choose_card_4_3")
		get_tree().root.size = Vector2i(1920, 1080)
		await get_tree().process_frame
	await click(panel.back)
	await click(panel.reward_buttons[1])
	check(result.reward_session.candidates == candidates, "返回重开不能刷新卡牌候选")
	# 查看地图恢复同一奖励与卡牌界面；HUD 返回键仍可操作。
	session._on_map_pressed()
	check(get_tree().paused and not result.visible, "奖励期间可只读查看地图")
	session._on_map_pressed()
	check(not get_tree().paused and result.visible and panel.cards_view.visible and result.reward_session.candidates == candidates, "返回战斗保持候选与领取状态")
	await click(panel.card_buttons[1])
	check(run.deck.size() == card_count + 1 and run.deck.back().definition.card_name == candidates[1].card_name and panel.list_view.visible, "选一张加入本局牌库并返回列表")
	check(not result.reward_session.claim(1, 0), "卡牌只能领取一张")
	await click(panel.reward_buttons[2])
	await click(panel.reward_buttons[3])
	if panel.get_node_or_null("RelicChoice") != null:
		var picker = panel.get_node("RelicChoice")
		check(run.relics.size() == relic_count, "三选一确认前不发放遗物")
		picker.selected.emit(0)
		picker.queue_free()
	check(run.potions.size() == potion_count + 1 and run.relics.size() == relic_count + 1 and result.reward_session.remaining() == 0, "点击获得随机药水与未持有遗物")
	check(not run.completed_ids.has("floor_01_01"), "领取奖励后等待继续才完成节点")
	await shot("claimed")
	await click(panel.proceed)
	await settle()
	check(not is_instance_valid(session.current_battle) and run.completed_ids.has("floor_01_01") and session.map_layer.visible and not get_tree().paused, "继续后插旗并回到地图")
	# 再次胜利检查跳过、放弃未领与无奖励失败；同局下一场不会沿用领取状态。
	run.begin_battle("test_next", "level_001", never)
	check(session._enter_battle("level_001"), "进入第二场战斗")
	battle = session.current_battle
	battle.finish_battle(true)
	result = battle.get_node("GameOver")
	panel = result.reward_panel
	check(panel.reward_buttons.size() == 2 and not panel.reward_buttons[0].disabled, "下一场奖励重新生成")
	card_count = run.deck.size()
	gold_before = run.gold
	await click(panel.reward_buttons[1])
	await click(panel.skip)
	check(run.deck.size() == card_count and result.reward_session.offers[1].state == "skipped" and panel.list_view.visible, "真实鼠标跳过卡牌")
	await click(panel.proceed)
	await settle()
	check(run.gold == gold_before and run.deck.size() == card_count, "离开放弃未领取奖励不发奖")
	run.begin_battle("test_defeat", "level_001", always)
	check(session._enter_battle("level_001"), "进入失败验证战斗")
	battle = session.current_battle
	battle.finish_battle(false)
	result = battle.get_node("GameOver")
	check(result.reward_session == null and result.reward_panel.reward_buttons.is_empty(), "失败无奖励")
	await shot("defeat")
	session.queue_free()
	await get_tree().process_frame
	var stale = REWARDS.new()
	stale.initialize(run, always, 1)
	run.start_new_run(load("res://data/run/run_start_data.tres"))
	check(not stale.claim(0), "开始新局后旧奖励不可领取")
	if failures.is_empty():
		print("BATTLE_REWARDS_PASS: %d checks; workshop, import, probabilities, victory, click, choose, skip, no duplicates, map, defeat" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)
