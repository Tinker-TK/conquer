extends SceneTree
var REWARDS
var SESSION
var POOL
var CONFIG
var checks := 0
var failures: Array[String] = []
var run: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func selection(a: int, b: int) -> Array[int]:
	return [a, b]

func reset_run() -> void:
	run.selected_map = {}
	run.start_new_run()
	run.gold = 300
	run.hp = 50

func begin(id: String, index: int, preview: bool = false) -> RefCounted:
	var session = SESSION.new()
	session.configure(REWARDS.content(id), run, preview)
	var prepared: Dictionary = session.choose(index)
	check(not prepared.has("error"), "选项可准备：%s / %d / %s" % [id, index, prepared.get("error", "")])
	return session

func finish(session: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	for step in 6:
		var prepared: Dictionary = session.prepared
		var selected: Array[int] = [0, 0]
		var allocation := Vector2i.ZERO
		var branch := ""
		if prepared.type == "train_unit":
			var card = prepared.candidates[0]
			allocation.x = card.ability_points + maxi(0, card.unit_data.upgrade_ability_points)
			branch = "slash" if card.needs_soldier_choice() else ""
		result = session.claim(selected, allocation, branch)
		if not result.get("pending", false):
			break
	return result

func _run() -> void:
	REWARDS = load("res://scripts/events/event_rewards.gd")
	SESSION = load("res://scripts/events/event_session.gd")
	POOL = load("res://scripts/events/event_pool.gd")
	CONFIG = load("res://scripts/map/fixed_map_config.gd")
	run = root.get_node("RunManager")
	reset_run()
	var count := 0
	for resource in REWARDS.catalog():
		if not resource.id.begins_with("act1_"):
			continue
		count += 1
		check(resource.validate().is_empty(), "路线事件配方合法：" + resource.id)
		for index in resource.to_content().choices.size():
			reset_run()
			var session := begin(resource.id, index)
			var result := finish(session)
			check(not result.has("error") and session.claimed, "选项可完整结算：%s / %d / %s" % [resource.id, index, result.get("error", "")])
			var before: int = run.gold
			check(session.claim().has("error") and run.gold == before, "选项不能重复领取")
	check(count == 20, "20 个正式路线事件")
	reset_run()
	run.gold = 19
	var session = SESSION.new()
	session.configure(REWARDS.content("act1_retired_drillmaster"), run)
	check(not session.option_error(0).is_empty() and session.choose(0).has("error") and run.gold == 19, "金币不足禁用且不扣款")
	run.hp = 1
	session.configure(REWARDS.content("act1_caravan_wreck"), run)
	check(session.choose(0).has("error") and run.hp == 1, "生命成本必须留 1 点")
	run.max_hp = 17
	session.configure(REWARDS.content("act1_golden_idol"), run)
	check(session.choose(0).has("error") and run.max_hp == 17, "最大生命成本必须留 10 点")
	reset_run()
	run.deck.resize(1)
	session.configure(REWARDS.content("act1_silent_altar"), run)
	check(session.choose(0).has("error") and run.deck.size() == 1, "不移除最后一张牌")
	reset_run()
	run.hp = 30
	session = begin("act1_caravan_wreck", 1)
	finish(session)
	check(run.max_hp == 84 and run.hp == 44 and run.gold == 265, "上限 +4 同时补 4 血，额外治疗叠加")
	reset_run()
	session = begin("crossroads_recruitment", 0)
	check(session.prepared.units.size() == 3 and session.prepared.effects.is_empty(), "教学单组三选一")
	var before_size: int = run.deck.size()
	check(session.claim(selection(-1, -1)).has("error") and run.deck.size() == before_size, "未选牌不能确认")
	finish(session)
	check(run.deck.size() == before_size + 1, "教学只得一张牌")
	reset_run()
	var target = run.deck[2]
	target.attack_points = 4
	target.defence_points = 2
	target.soldier_specialization = "missile"
	target.permanent_buffs.append({"attack": 3})
	session = begin("act1_twin_barracks", 0)
	finish(session)
	var copy = run.deck[-1]
	check(copy != target and copy.attack_points == 4 and copy.defence_points == 2 and copy.soldier_specialization == "missile" and copy.permanent_buffs == target.permanent_buffs, "复制保留强化并独立实例")
	copy.permanent_buffs.clear()
	check(not target.permanent_buffs.is_empty(), "复制不共享永久增益数组")
	reset_run()
	session = begin("act1_last_forge", 0)
	before_size = run.deck.size()
	var original = session.prepared.candidates[0]
	check(session.claim(selection(0, -1)).get("pending", false) and run.deck.size() == before_size, "熔炼第一步不提前删除")
	check(not session.prepared.candidates.has(original), "第二步不能强化被熔掉的牌")
	session.cancel()
	check(run.deck.size() == before_size and run.deck.has(original), "取消复合事件不失去卡牌")
	check(session.claim().has("error"), "取消后必须重新选择选项才能结算")
	session.choose(0)
	finish(session)
	check(run.deck.size() == before_size - 1 and not run.deck.has(original), "熔炼只删选中的牌")
	reset_run()
	var one_tactic = run.deck[0]
	var one_recruit = run.deck[2]
	run.deck.assign([one_tactic, one_recruit])
	session = begin("act1_last_forge",0)
	check(session.prepared.candidates.size() == 1 and session.prepared.candidates[0] == one_recruit, "熔炼候选保留唯一强化目标")
	finish(session)
	check(run.deck.size() == 1 and run.deck[0] == one_tactic and one_tactic.upgrade_count == 1, "两张牌的熔炼可原子完成")
	reset_run()
	var real_cards: Array = run.deck.duplicate()
	var before_gold: int = run.gold
	var before_hp: int = run.hp
	session = begin("act1_golden_idol", 0, true)
	var real_relics: int = run.relics.size()
	finish(session)
	check(run.max_hp == 80 and run.hp == before_hp and run.gold == before_gold and run.relics.size() == real_relics and run.deck == real_cards, "预览不修改正式本局")
	reset_run()
	var content: Dictionary = REWARDS.content("act1_blood_pact")
	content._seed = 91827
	session.configure(content, run)
	var fixed_offer: Dictionary = session.choose(0)
	session.choose(1)
	check(session.choose(0) == fixed_offer, "更换选项不重抽候选")
	var resumed = SESSION.new()
	resumed.configure(content, run)
	var resumed_offer: Dictionary = resumed.choose(0)
	check(fixed_offer.units == resumed_offer.units and fixed_offer.effects == resumed_offer.effects, "重建会话沿用节点种子")
	for chance in [0.0, 1.0]:
		reset_run()
		content = {"description": "赌局测试", "choices": [{"text": "押注", "cost": {"gold": 30}, "effect": {"type": "gamble", "chance": chance, "win": {"type": "gold", "amount": 90}, "lose": {"type": "gold", "amount": 0}}}, {"text": "离开", "leave": true}]}
		session.configure(content, run)
		session.choose(0)
		finish(session)
		check(run.gold == (360 if chance == 1 else 270), "赌局先扣注金，成功返还本金内的总奖金")
	reset_run()
	var pool: Dictionary = POOL.snapshot("res://data/events/pools/act1.json")
	var rng := RandomNumberGenerator.new()
	rng.seed = 426
	for index in 12:
		var event: Dictionary = POOL.draw(pool, 6, run, rng)
		if event.id == "abandoned_camp":
			continue
		check(not run.seen_events.has(event.id), "抽池不放回")
		run.seen_events.append(event.id)
		for tag in event.tags:
			run.event_tag_counts[tag] = int(run.event_tag_counts.get(tag, 0)) + 1
	check(int(run.event_tag_counts.get("relic", 0)) <= 1 and int(run.event_tag_counts.get("duplicate", 0)) <= 1 and int(run.event_tag_counts.get("remove", 0)) <= 2, "同类事件次数上限")
	check(POOL.draw({"entries": []}, 3, run, rng).id == "abandoned_camp", "空池保底可继续")
	for name in ["bear", "skeleton", "skeleton_archer", "greatsword_skeleton"]:
		var recruit = load("res://data/event_recruits/%s.tres" % name)
		check(recruit.unit_team == "team_a" and recruit.card_image != null, "事件征召使用己方配方：" + name)
		var unit_scene = load("res://scenes/units/%s.tscn" % name).instantiate()
		unit_scene.unit_data = recruit
		check(unit_scene.configuration_error().is_empty(), "事件征召可加载战斗单位：" + name)
		unit_scene.free()
	var route: Dictionary = CONFIG.read_file("res://data/run/game_map.json")
	check(not route.has("error"), "正式第一章路线可导入：" + str(route.get("error", "")))
	reset_run()
	run.selected_map = route.data
	run.start_new_run()
	var node: Dictionary
	for location in CONFIG.to_locations(run.active_map):
		if location.get("event_pool", "") != "":
			node = location
			break
	var drawn: Dictionary = run.resolve_route_event(node)
	var saved_id: String = drawn.id
	check(run.save_run(true).is_empty(), "抽到事件后检查点可保存")
	run.event_visits.clear()
	check(run.load_saved_run().is_empty(), "扩展存档可恢复")
	var reloaded: Dictionary = run.resolve_route_event(node)
	check(reloaded.id == saved_id and reloaded._seed == drawn._seed, "存档恢复不重抽事件和奖励种子")
	check(run.pending_route_node == node.id, "读档后保留已进入的奇遇节点")
	run.complete_location(str(node.id))
	check(run.pending_route_node.is_empty(), "完成事件后解除节点锁定")
	var panel = load("res://scripts/map/event_panel.gd").new()
	root.add_child(panel)
	panel.size = Vector2(1920,1080)
	run.gold = 0
	panel.open_content(REWARDS.content("act1_retired_drillmaster"), run)
	check(panel.choice_1.disabled and "金币" in panel.choice_1.tooltip_text, "界面置灰并解释金币不足")
	panel.open_content(REWARDS.content("crossroads_recruitment"), run)
	panel._choose(0)
	check(panel.confirm_button.disabled, "单组选牌初始不可确认")
	panel._select_card(0,0)
	check(not panel.confirm_button.disabled, "单组选满一张即可确认")
	panel.queue_free()
	var editor = load("res://addons/event_editor/editor.gd").new()
	root.add_child(editor)
	editor._load("res://data/events/act1_caravan_wreck.tres")
	var custom: Dictionary = JSON.parse_string(editor.inputs.route_config.text)
	custom.choices[1].cost.gold = 41
	editor.inputs.route_config.text = JSON.stringify(custom)
	check(editor.apply_inputs() and editor.doc.event.choices[1].cost.gold == 41, "工坊可编辑路线成本")
	editor.doc.undo()
	check(editor.doc.event.choices[1].cost.gold == 35, "路线选项修改可撤销")
	custom.choices[1].cost.gold = -1
	editor.inputs.route_config.text = JSON.stringify(custom)
	check(not editor.apply_inputs() and editor.doc.event.choices[1].cost.gold == 35, "工坊拒绝负数成本并保留草稿")
	editor.queue_free()
	await process_frame
	print("ROUTE_EVENTS_TEST: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
