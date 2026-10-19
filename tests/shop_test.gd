extends Node

var CATALOG: GDScript
var SHOP: GDScript
var CONFIG: GDScript
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		push_error(text)

# 用实际鼠标输入验证内容缩放后的命中范围。
func click_button(button: Control) -> void:
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

func _run() -> void:
	var root := get_tree().root
	CATALOG = load("res://scripts/shop/shop_catalog.gd")
	SHOP = load("res://scripts/shop/shop_session.gd")
	CONFIG = load("res://scripts/map/fixed_map_config.gd")
	var run := root.get_node("RunManager")
	run.selected_map = {}
	run.start_new_run(load("res://data/run/run_start_data.tres"))
	var catalog: Dictionary = CATALOG.read_catalog()
	check(catalog.has("data"), "商品池能加载")
	if not catalog.has("data"):
		get_tree().quit(1)
		return
	check(CATALOG.read_catalog("res://data/shops/missing.json").has("error"), "无效商店被拒绝")
	var shop = SHOP.new()
	shop.initialize(run, "test_shop", catalog.data, 121)
	run.shop_visits.test_shop = shop
	check(shop.offers.size() == 13, "13 件陈列商品")
	var kinds: Dictionary = {}
	var sales := 0
	for offer in shop.offers:
		kinds[offer.kind] = int(kinds.get(offer.kind, 0)) + 1
		if offer.sale:
			sales += 1
			check(offer.price == int(ceil(offer.original_price * 0.5)), "特价为半价")
	check(kinds == {"recruit": 3, "card": 4, "relic": 3, "potion": 3} and sales == 1, "四种商品与一张特价牌")
	run.gold = 0
	var deck_count: int = run.deck.size()
	check(not shop.purchase(0).is_empty() and run.gold == 0 and run.deck.size() == deck_count and not shop.offers[0].sold, "金币不足不扣费不发奖")
	check(not shop.purchase(-1).is_empty() and not shop.purchase(999).is_empty(), "非法商品编号")
	run.gold = 5000
	for index in shop.offers.size():
		var offer: Dictionary = shop.offers[index]
		var before: int = run.gold
		var card_count: int = run.deck.size()
		var relic_count: int = run.relics.size()
		var potion_count: int = run.potions.size()
		check(shop.purchase(index).is_empty() and run.gold == before - offer.price, "商品只扣标价")
		match offer.kind:
			"recruit", "card":
				check(run.deck.size() == card_count + 1 and run.deck.back().definition.card_name == offer.data.card_name, "招募与购牌加入本局")
			"relic":
				check(run.relics.size() == relic_count + 1, "购买遗物加入库存")
			"potion":
				check(run.potions.size() == potion_count + 1, "购买药水加入库存")
		before = run.gold
		check(not shop.purchase(index).is_empty() and run.gold == before, "售罄连点不扣款")
	check(run.begin_shop("test_shop") == shop, "同节点再次打开不刷新库存")
	var same_a = run.add_card(load("res://data/units/soldier.tres"))
	var same_b = run.add_card(load("res://data/units/soldier.tres"))
	var fake := CardInstance.new(load("res://data/units/soldier.tres"))
	check(not shop.remove_card(fake).is_empty(), "拒绝不属于卡组的牌")
	run.gold = 74
	check(not shop.remove_card(same_a).is_empty() and run.deck.has(same_a) and run.gold == 74, "删牌金币不足无副作用")
	run.gold = 1000
	check(shop.remove_card(same_a).is_empty() and not run.deck.has(same_a) and run.deck.has(same_b) and run.gold == 925, "删牌只移除指定实例")
	check(shop.removal_used and not shop.remove_card(same_b).is_empty(), "每店只删一次")
	var other = run.begin_shop("another_shop")
	check(other.removal_price() == 100, "下一店删牌价格上涨")
	for offer in other.offers:
		if offer.kind == "relic":
			check(not other._owns_relic(offer.data), "不卖已持有遗物")
	other.finish()
	check(not other.purchase(0).is_empty() and not other.remove_card(same_b).is_empty(), "离店后不能交易")
	run.start_new_run(load("res://data/run/run_start_data.tres"))
	check(run.shop_visits.is_empty() and run.shop_removal_count == 0 and not shop.is_active(), "新局重置库存与费用，旧会话失效")
	var game = load("res://scenes/app/game_session.tscn").instantiate()
	run.starting_reward_pending = false # 开局三选一由balance-framework覆盖，本组直接进入商店。
	root.add_child(game)
	get_tree().current_scene = game
	await get_tree().process_frame
	await get_tree().process_frame
	var map = game.map_view
	check(map.NodeType.SHOP == 5 and map.NodeType.TREASURE == 4, "保留既有节点编号")
	check(map.locations.filter(func(candidate: Dictionary): return candidate.type == 5).size() == 2, "默认地图有两家商店")
	# 从真实地图入口打开商店，在内存把起点改为商店以缩短测试。
	var location: Dictionary = map._get_location("battle_a")
	location.type = 5
	run.gold = 600
	map._on_node_enter_requested(map.node_views.battle_a)
	var panel = map.shop_panel
	check(panel.visible and map.pending_id == "battle_a" and run.completed_ids.is_empty(), "进入商店不自动完成节点")
	var first_offer: Dictionary = panel.session.offers[0]
	await click_button(panel.offer_buttons[0])
	check(first_offer.sold and panel.price_labels[0].text == "售罄", "点击购买更新售罄卡面")
	game.map_button.pressed.emit()
	check(not panel.visible and map.view_only, "商店可查看只读地图")
	game.map_button.pressed.emit()
	check(panel.visible and not map.view_only and panel.session.offers[0].sold, "返回商店保留商品状态")
	game.deck_button.pressed.emit()
	check(game.deck_open and get_tree().paused, "商店能查看卡组")
	game.deck_view.close_requested.emit()
	check(not get_tree().paused and panel.visible, "关卡组恢复商店")
	panel._open_removal()
	check(panel.removal_overlay.visible and panel.confirm_button.disabled, "删牌先选牌")
	var gold_before: int = run.gold
	panel._select_card(run.deck[0])
	check(not panel.confirm_button.disabled, "选择具体牌后可确认")
	panel._cancel_removal()
	check(run.gold == gold_before and not panel.session.removal_used, "取消删牌不扣费")
	panel._open_removal()
	var selected = run.deck[0]
	panel._select_card(selected)
	panel.confirm_button.pressed.emit()
	check(not run.deck.has(selected) and run.gold == gold_before - 75 and panel.removal_button.disabled, "UI 确认删牌")
	panel._leave()
	check(not panel.visible and run.completed_ids.has("battle_a") and map.pending_id.is_empty() and map._can_enter("event_a"), "离店插旗并解锁后续路线")
	# 固定地图可导入商店，缺失商品配置会在导入时明确拒绝。
	var level = load("res://data/levels/level_001.tres")
	var original_waves = level.waves.duplicate()
	if level.waves.is_empty():
		level.waves.append(load("res://scenes/levels/waves/wave_01.tscn"))
	var route := {"schema_version": 1, "mode": "fixed", "name": "商店路线", "floors": 2, "starting_ids": ["shop"], "locations": [
		{"id": "shop", "title": "商店", "type": 5, "floor": 1, "map_pos": {"x": 0.5, "y": 0.9}, "next": ["boss"]},
		{"id": "boss", "title": "Boss", "type": 3, "event_id": "level_001", "floor": 2, "map_pos": {"x": 0.5, "y": 0.1}, "next": []}]}
	check(CONFIG.validate(route).is_empty(), "固定地图接受商店节点")
	route.locations[0].shop_catalog = "res://data/shops/missing.json"
	check(not CONFIG.validate(route).is_empty(), "固定地图拒绝缺失商店资源")
	level.waves.assign(original_waves)
	var editor = load("res://addons/map_editor/editor.gd").new()
	root.add_child(editor)
	editor.doc.new_map(true)
	check(editor.doc.data.locations.filter(func(node: Dictionary): return int(node.type) == 5).size() == 2, "地图工坊示例包含商店")
	editor.doc.add_node(5, 4, 0.4)
	check(editor.doc.node().title == "商店" and int(editor.doc.node().type) == 5, "原生工坊可新增商店")
	check(editor.kind_input.item_count == 8 and editor.treasure_hint.visible and not editor.event_box.visible, "原生工坊显示商店配置提示")
	check(editor.doc.draft_error(editor.doc.data).is_empty(), "工坊读写结构接受商店")
	check(panel.product_views[7].size == Vector2(92, 92), "遗物图标按陈列尺寸绘制")
	if failures.is_empty():
		print("SHOP_TEST_PASS: %d checks" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)
