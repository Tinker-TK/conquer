# 这玩意儿是干嘛的（核心逻辑）：
# 管理从下往上推进的分叉地图：生成地点图标、画路线、限制可前往的节点，
# 并在事件完成后给节点插旗、解锁后续路线。
#
# 数据是咋流动的（数据流向）：
# 本局导入配置（未导入时使用内置路线）→ locations 配置地点 → MapNode 显示图标 → 玩家点击并播放画圈 →
# 普通地点按节点配置显示事件并发奖，战斗地点通知 GameSession → 完成后显示旗帜。
#
# 为啥这么写（选型决策）：
# Map 只管理路线和进度，MapNode 只负责单个图标与画圈动画，
# EventPanel 只负责显示事件内容，三个部分不会互相混乱。
#
# 性能咋样（复杂度）：
# 开局只创建少量地图节点；路线和按钮状态只在进入、完成事件时刷新，
# 不会每帧重复计算。

extends Control

# 战斗交给 GameSession 加载，地图不再销毁整局场景。
signal battle_requested(event_id: String)
var view_only := false

# 所有地点使用同一个 MapNode 父类场景。
# 在 Map 场景 Inspector 中，将它指定为 map_node.tscn。
## 所有地图地点使用的节点场景，应指定项目 MapNode 场景，包含图标、选中圈和完成旗帜；地图运行时为各地点实例化此场景。
@export var map_node_scene: PackedScene

# 在 Map 场景 Inspector 中，为每种地点拖入对应图标。
## 普通战斗地点的地图图标纹理；只改变图标外观，战斗内容由地点绑定的关卡配置决定。
@export var battle_icon: Texture2D
## 事件地点的地图图标纹理；只改变外观，具体事件由地点事件编号决定。
@export var event_icon: Texture2D
## 休息或篝火地点的地图图标纹理；只改变外观，不修改休憩、训练或强化规则。
@export var rest_icon: Texture2D
## Boss 战斗地点的地图图标纹理；只改变外观，实际敌人仍由地点的战斗关卡和波次决定。
@export var boss_icon: Texture2D
## 路线底部的出征营地图案，仅连接起始房间，不增加楼层或可进入地点。
@export var start_icon: Texture2D
## 宝箱地点的地图图标纹理；只改变外观，不决定宝箱奖励。
@export var treasure_icon: Texture2D
## 商店地点的地图图标纹理；只改变外观，不修改商品池、库存或价格。
@export var shop_icon: Texture2D
## 精英房沿用原首领图标；战斗和奖励仍由精英遭遇配置决定。
@export var elite_icon: Texture2D
## 随机事件使用原问号图标，进入后揭晓，结果随本局存档保存。
@export var unknown_icon: Texture2D

# 每个地图图标占用的区域大小。
const NODE_SIZE := Vector2(88.0, 88.0)
const BOSS_NODE_SIZE := Vector2(360.0, 270.0)
const START_NODE_SIZE := Vector2(320.0, 240.0)
const START_AREA_HEIGHT := 300.0


# 地点类型决定使用哪张图标，也决定之后进入哪种内容。
enum NodeType {
	BATTLE,
	EVENT,
	REST,
	BOSS,
	TREASURE,
	SHOP,
	ELITE,
	UNKNOWN
}


# 未导入时保留十层测试地图；导入后层数、起点与路线全部由配置决定。
var locations: Array[Dictionary] = []
var starting_ids: Array[String] = ["battle_a", "battle_b"]
var map_name := "翠绿原野"
var floor_count := 10


# 作用：读取本局路线，没有导入时生成十层测试地图；没有参数，没有返回值。
func _build_locations() -> void:
	locations.clear()
	if not RunManager.active_map.is_empty():
		var config: Dictionary = RunManager.active_map
		locations = RunManager.FixedMapConfig.to_locations(config)
		starting_ids.assign(config.starting_ids)
		map_name = config.name
		floor_count = int(config.floors)
		return
	starting_ids.assign(["battle_a", "battle_b"])
	map_name = "翠绿原野"
	floor_count = 10
	# 每一行代表一层；后续可在这里调整该层的事件组合。
	var rows: Array = [
		[NodeType.BATTLE, NodeType.BATTLE],
		[NodeType.EVENT, NodeType.REST],
		[NodeType.BATTLE, NodeType.SHOP],
		[NodeType.BATTLE, NodeType.REST],
		[NodeType.TREASURE, NodeType.TREASURE],
		[NodeType.BATTLE, NodeType.REST],
		[NodeType.EVENT, NodeType.BATTLE],
		[NodeType.BATTLE, NodeType.SHOP],
		[NodeType.REST, NodeType.BATTLE],
		[NodeType.BOSS],
	]
	for row in rows.size():
		for column in rows[row].size():
			var kind: int = rows[row][column]
			var event_id := "level_001" if row % 2 == 0 else "level_002"
			var title := "普通战斗"
			match kind:
				NodeType.SHOP:
					event_id = "caravan"
					title = "旅途商队"
				NodeType.EVENT:
					event_id = ["forgotten_reliquary", "wandering_alchemist", "crossroads_recruitment"][row % 3]
					title = ["遗忘的圣匣", "旅人的药剂", "岔路的援军"][row % 3]
				NodeType.REST:
					event_id = "campfire"
					title = "篝火"
				NodeType.BOSS:
					event_id = "level_002"
					title = "最终 Boss"
				NodeType.TREASURE:
					event_id = ""
					title = "遗物宝箱"
			# 保留原先两个开场战斗的编号，已有的战场配置仍可用。
			if row == 0:
				event_id = "level_001" if column == 0 else "level_002"
			var next_ids: Array[String] = []
			if row + 1 < rows.size():
				for next_column in rows[row + 1].size():
					next_ids.append(_location_id(row + 1, next_column))
			locations.append({
				"id": _location_id(row, column),
				"title": "第 %d / 10 站 · %s" % [row + 1, title],
				"type": kind,
				"event_id": event_id,
				"event": RunManager.FixedMapConfig.default_event(event_id),
				"floor": row + 1,
				"map_pos": Vector2(0.5 if row == 9 else (0.35 if column == 0 else 0.65),
					0.93 - float(row) / 9.0 * 0.86),
				"next": next_ids,
			})


# 作用：给每层节点生成稳定编号；row/column 从零开始，返回节点编号。
func _location_id(row: int, column: int) -> String:
	if row == 0:
		return "battle_a" if column == 0 else "battle_b"
	if row == 1:
		return "event_a" if column == 0 else "rest_a"
	if row == 9:
		return "boss"
	return "floor_%02d_%d" % [row + 1, column]

# current_id：最后完成的地点。
# pending_id：已进入事件、等待完成的地点。
# locked_node_id：红圈正在播放或事件正在打开的地点。
var current_id := ""
var pending_id := ""
var locked_node_id := ""

# 已完成地点的编号列表；之后保存进 RunManager。
var completed_ids: Array[String] = []

# 保存“地点编号 → 实际 MapNode 节点”的对应关系。
var node_views: Dictionary = {}
var start_view: TextureRect

# 当前正在处理事件的节点，用于事件结束后插旗。
var active_node: MapNode



@onready var routes_view = $ScrollContainer/MapContent/Routes
@onready var nodes_root: Control = $ScrollContainer/MapContent/Nodes
@onready var map_content: Control = $ScrollContainer/MapContent
@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var status_label: Label = $HUD/Status
@onready var event_panel: EventPanel = $EventPanel
@onready var shop_panel: Control = $ShopPanel


# 作用：初始化地图，由 Godot 在场景进入树后调用。
# 参数：没有参数。
# 返回值：没有返回值。
func _ready() -> void:
	if map_node_scene == null:
		push_error("Map 的 map_node_scene 尚未在 Inspector 中指定。")
		return
	# 恢复跨场景保存的进度，让返回地图后的旗帜和路线保持正确。
	current_id = RunManager.current_id
	completed_ids = RunManager.completed_ids.duplicate()
	_build_locations()
	# 图标与层间距一起收紧，长路线仍按层数提供足够的滚动空间。
	map_content.custom_minimum_size.y = maxf(1080.0, 340.0 * floor_count)
	if start_icon != null and not starting_ids.is_empty():
		map_content.custom_minimum_size.y += START_AREA_HEIGHT
		_create_start_marker()
	_create_nodes()
	# 每条图例绑定一种地点类型，统一交给同一个回调处理。
	_connect_legend($HUD/BattleLegend, NodeType.BATTLE)
	_connect_legend($HUD/EventLegend, NodeType.UNKNOWN)
	_connect_legend($HUD/RestLegend, NodeType.REST)
	_connect_legend($HUD/EliteLegend, NodeType.ELITE)
	_connect_legend($HUD/TreasureLegend, NodeType.TREASURE)
	_connect_legend($HUD/ShopLegend, NodeType.SHOP)

	# 地图内容尺寸变化时，重新摆放图标和路线。
	map_content.resized.connect(_layout_map)

	# EventPanel 完成选择后，通知地图推进进度。
	event_panel.resolved.connect(_on_event_resolved)
	shop_panel.closed.connect(_on_shop_closed)

	_layout_map()
	_refresh_nodes()

	# 等容器完成布局，再恢复进入战斗前的滚动位置。
	await get_tree().process_frame

	if current_id.is_empty():
		# 起点位于底部；等容器布局完成后滚到底，开局才能直接看到起点。
		var bar := scroll_container.get_v_scroll_bar()
		scroll_container.scroll_vertical = int(bar.max_value - bar.page)
	else:
		scroll_container.scroll_vertical = RunManager.map_scroll


# 公共出发营地仅用于表现路线的起点；第一层房间仍直接可选。
func _create_start_marker() -> void:
	start_view = TextureRect.new()
	start_view.name = "ExpeditionStart"
	start_view.texture = start_icon
	start_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	start_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	start_view.size = START_NODE_SIZE
	start_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nodes_root.add_child(start_view)


# 作用：根据 locations 配置创建全部地图节点。
# 参数：没有参数。
# 返回值：没有返回值。
func _create_nodes() -> void:
	for location in locations:
		var map_node := map_node_scene.instantiate() as MapNode

		if map_node == null:
			push_error("map_node_scene 的根节点必须挂载 MapNode 脚本。")
			return

		# 节点进入场景树前先完成配置，
		# MapNode._ready() 才能正确显示对应图标。
		map_node.node_id = location["id"]
		map_node.event_id = location["event_id"]
		var display: Dictionary = RunManager.route_location(str(location.id))
		if display.is_empty():
			display = location
		map_node.icon_texture = _get_icon(int(display.type))
		map_node.size = BOSS_NODE_SIZE if int(location.type) == NodeType.BOSS else NODE_SIZE
		map_node.tooltip_text = "随机事件 · 进入后揭晓" if int(display.type) in [NodeType.EVENT, NodeType.UNKNOWN] else str(display.title)
		if int(location.type) == NodeType.BOSS:
			# Boss 的图案、点击区、红圈均随节点放大，完成旗帜也保留可读尺寸。
			var flag := map_node.get_node("CompletedFlag") as TextureRect
			flag.offset_left = -52.0
			flag.offset_top = -52.0
			flag.offset_right = 10.0
			flag.offset_bottom = 10.0
			var title := Label.new()
			title.text = "幕终首领"
			title.position = Vector2(0.0, -44.0)
			title.size = Vector2(BOSS_NODE_SIZE.x, 36.0)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.add_theme_color_override("font_color", Color("291000"))
			title.add_theme_font_size_override("font_size", 26)
			title.mouse_filter = Control.MOUSE_FILTER_IGNORE
			map_node.add_child(title)

		# 红圈开始时锁住地图；画完后再进入对应事件。
		map_node.selection_started.connect(
			_on_node_selection_started
		)
		map_node.enter_requested.connect(
			_on_node_enter_requested
		)

		nodes_root.add_child(map_node)
		node_views[map_node.node_id] = map_node


# 作用：根据地点类型返回对应图标。
# 参数 node_type：NodeType 中的地点类型。
# 返回值：该类型要显示的 Texture2D。
func _get_icon(node_type: NodeType) -> Texture2D:
	match node_type:
		NodeType.ELITE:
			return elite_icon if elite_icon != null else boss_icon
		NodeType.UNKNOWN:
			return unknown_icon if unknown_icon != null else event_icon
		NodeType.SHOP:
			return shop_icon
		NodeType.BATTLE:
			return battle_icon
		NodeType.EVENT:
			return event_icon
		NodeType.REST:
			return rest_icon
		NodeType.BOSS:
			return boss_icon
		NodeType.TREASURE:
			return treasure_icon

	return null


# 作用：排列地图节点，并将相连节点的中心传给路线绘制脚本。
# 参数：没有参数。
# 返回值：没有返回值。
func _layout_map() -> void:
	var lines: Array[PackedVector2Array] = []
	# 底部单独预留营地区域，不改变存档中的房间坐标与楼层计数。
	var route_height := map_content.size.y - (START_AREA_HEIGHT if start_view != null else 0.0)

	# 先确定所有节点的位置。
	for location in locations:
		var map_node: MapNode = node_views[location["id"]]
		var ratio: Vector2 = location["map_pos"]

		var center := Vector2(
			map_content.size.x * ratio.x,
			route_height * ratio.y
		)
		if int(location.type) == NodeType.BOSS:
			# 短固定地图也要为大图标和上方标题留够空间，避免裁到顶栏内。
			center.y = maxf(center.y, BOSS_NODE_SIZE.y * 0.5 + 160.0)

		map_node.position = center - map_node.size * 0.5

	# 再读取节点最终位置，绘制连线。
	for location in locations:
		var from_node: MapNode = node_views[location["id"]]

		for next_id in location["next"]:
			var to_node: MapNode = node_views[next_id]

			var start := from_node.position + from_node.size * 0.5
			var end := to_node.position + to_node.size * 0.5
			lines.append(PackedVector2Array([
				_route_anchor(from_node, end), _route_anchor(to_node, start)
			]))

	if start_view != null:
		start_view.position = Vector2(
			(map_content.size.x - START_NODE_SIZE.x) * 0.5,
			map_content.size.y - START_NODE_SIZE.y - 60.0
		)
		var origin := start_view.position + start_view.size * 0.5
		for id in starting_ids:
			if not node_views.has(id):
				continue
			var first_node: MapNode = node_views[id]
			var first_center := first_node.position + first_node.size * 0.5
			lines.append(PackedVector2Array([
				_route_anchor(start_view, first_center), _route_anchor(first_node, origin)
			]))

	routes_view.set_routes(lines)


# Routes 仍负责原有的端点留白；大图案按连线方向补上矩形边界差值。
func _route_anchor(view: Control, towards: Vector2) -> Vector2:
	var center := view.position + view.size * 0.5
	if view.size == NODE_SIZE:
		return center
	var direction := center.direction_to(towards)
	var half := view.size * 0.5
	var radius := minf(
		half.x / maxf(absf(direction.x), 0.001),
		half.y / maxf(absf(direction.y), 0.001)
	)
	return center + direction * maxf(0.0, radius - NODE_SIZE.x * 0.5)


# 作用：根据编号找到地点配置。
# 参数 location_id：地点唯一编号。
# 返回值：找到时返回地点字典，找不到时返回空字典。
func _get_location(location_id: String) -> Dictionary:
	for location in locations:
		if location["id"] == location_id:
			return location

	return {}


# 作用：判断当前地图状态下是否能进入某个地点。
# 参数 location_id：准备进入的地点编号。
# 返回值：true 表示节点可点击，false 表示节点锁定。
func _can_enter(location_id: String) -> bool:
	if view_only or RunManager.chapter_cleared:
		return false
	# 红圈动画或事件面板尚未结束时，整张地图不能再选择。
	if locked_node_id != "":
		return false

	# 已完成节点不能重复进入。
	if completed_ids.has(location_id):
		return false
	if not RunManager.pending_route_node.is_empty():
		return location_id == RunManager.pending_route_node

	# 开局仅能选择起始地点。
	if current_id == "":
		return starting_ids.has(location_id)

	# 后续仅能沿当前地点的 next 路线前进。
	var current_location := _get_location(current_id)

	if current_location.is_empty():
		return false

	return current_location["next"].has(location_id)


# 作用：某个节点开始播放红圈时锁住地图。
# 参数 node：刚被玩家点击的地点。
# 返回值：没有返回值。
func _on_node_selection_started(node: MapNode) -> void:
	locked_node_id = node.node_id
	_refresh_nodes()


# 作用：红圈画完后，根据 event_id 打开对应事件内容。
# 参数 node：画圈动画已结束的地点。
# 返回值：没有返回值。
func _on_node_enter_requested(node: MapNode) -> void:
	# 即使其他代码误调用入口，只读模式也不能触发事件。
	if view_only or completed_ids.has(node.node_id) or not pending_id.is_empty():
		return
	if not RunManager.pending_route_node.is_empty() and RunManager.pending_route_node != node.node_id:
		return
	RunManager.map_scroll = scroll_container.scroll_vertical
	RunManager.capture_location_checkpoint()
	active_node = node
	pending_id = node.node_id
	# 按类型判断战斗，新增 battle_03 等编号不必继续扩写 match。
	var location: Dictionary = RunManager.resolve_map_location(_get_location(node.node_id))
	if int(location.type) != NodeType.UNKNOWN:
		node.icon_button.texture_normal = _get_icon(int(location.type))
		node.tooltip_text = str(location.title)
	if location["type"] in [NodeType.BATTLE, NodeType.BOSS, NodeType.ELITE]:
		RunManager.map_scroll = scroll_container.scroll_vertical
		RunManager.begin_battle(node.node_id, str(location.event_id), RunManager.FixedMapConfig.battle_reward_content(location))
		battle_requested.emit(str(location.event_id))
		return
	if location["type"] == NodeType.SHOP:
		var visit := RunManager.begin_shop(node.node_id, str(location.get("shop_catalog", "res://data/shops/caravan.json")))
		if visit == null:
			cancel_pending_battle()
			status_label.text = RunManager.shop_error
			return
		shop_panel.open_shop(visit)
		return

	# 文案和奖励都来自当前节点；配置校验通过后才允许打开面板。
	var event: Dictionary = RunManager.resolve_route_event(location)
	var issue := RunManager.FixedMapConfig.event_error(event)
	if not issue.is_empty():
		cancel_pending_battle()
		status_label.text = issue
		return
	var content := event.duplicate(true)
	if not content.has("title"):
		content.title = location.title
	if location["type"] == NodeType.TREASURE:
		event_panel.open_treasure(content, RunManager)
	else:
		event_panel.open_content(content, RunManager)


# 作用：玩家在事件面板做出选择后，完成当前地点并插旗。
# 参数 choice_index：玩家点击的选项编号，从 0 开始。
# 返回值：没有返回值。
func _on_event_resolved(choice_index: int) -> void:
	if active_node == null or pending_id == "":
		return

	var location := _get_location(pending_id)
	var event: Dictionary = event_panel.session.event
	if choice_index < 0 or choice_index >= event.choices.size():
		return
	# EventSession 已经领取奖励；继续按钮只推进地图，不再次发奖。

	current_id = pending_id
	completed_ids.append(current_id)
	# 普通事件的进度也要保存，否则下一次战斗返回后会丢失。
	RunManager.complete_location(current_id)

	# 事件真正结束后才显示旗帜。
	active_node.set_completed(true)

	pending_id = ""
	locked_node_id = ""
	active_node = null

	_refresh_nodes()


# 作用：根据当前进度更新每个 MapNode 的可点击状态和完成状态。
# 参数：没有参数。
# 返回值：没有返回值。
func _on_shop_closed() -> void:
	if active_node == null or pending_id.is_empty() or _effective_location(pending_id).type != NodeType.SHOP:
		return
	RunManager.complete_location(pending_id)
	active_node.set_completed(true)
	resume_after_battle()

# 查看地图只隐藏商店，继续回来保留库存、删牌选择与已购商品。
func set_pending_panel_visible(enabled: bool) -> void:
	if pending_id.is_empty():
		return
	if _effective_location(pending_id).type == NodeType.SHOP:
		shop_panel.visible = enabled
		shop_panel._hide_tip()
	else:
		event_panel.visible = enabled

func _refresh_nodes() -> void:
	for location in locations:
		var location_id: String = location["id"]
		var map_node: MapNode = node_views[location_id]

		# 已完成节点保持插旗状态。
		if completed_ids.has(location_id):
			map_node.set_completed(true)

		# MapNode 自己会根据可进入状态决定图标能否点击。
		map_node.set_available(_can_enter(location_id))

	_refresh_status()


# 作用：更新 HUD 的当前地图提示文字。
# 参数：没有参数。
# 返回值：没有返回值。
func _refresh_status() -> void:
	if view_only:
		status_label.text = "仅查看地图，点击顶部返回继续当前事件。"
		return
	if locked_node_id != "" and pending_id == "":
		status_label.text = "正在进入地点……"
		return

	if pending_id != "":
		var location := _effective_location(pending_id)
		status_label.text = "正在处理：%s" % location["title"]
		return

	if current_id == "":
		status_label.text = "%s · 共 %d 层\n请选择出发点。" % [map_name, floor_count]
		if not RunManager.map_seed.is_empty():
			status_label.text += "\n种子：" + RunManager.map_seed
			status_label.tooltip_text = "地图种子：%s\n难度：%s" % [RunManager.map_seed, RunManager.map_difficulty]
		return

	var current_location := _get_location(current_id)

	if current_location.is_empty():
		status_label.text = "当前进度与地图不匹配，请返回主菜单重新开始。"
	elif RunManager.chapter_cleared:
		status_label.text = "已完成 %d 个地点\n%s" % [completed_ids.size(), "征途通关！" if RunManager.run_cleared else "第%d幕通关！" % RunManager.current_act]
	else:
		status_label.text = "第 %d / %d 层 · 已完成 %d 站\n请选择后续地点。" % [current_location.floor, floor_count, completed_ids.size()]


# 作用：让一条图例监听鼠标进入和离开。
# 参数 legend：HUD 中的一条图例。
# 参数 node_type：这条图例对应的地点类型。
# 返回值：没有返回值。
func _connect_legend(legend: Control, node_type: NodeType) -> void:
	legend.mouse_entered.connect(
		_on_legend_entered.bind(node_type)
	)
	legend.mouse_exited.connect(_on_legend_exited)


# 作用：鼠标进入图例时，突出显示地图上同类型的地点。
# 参数 node_type：鼠标当前指向的图例类型。
# 返回值：没有返回值。
func _on_legend_entered(node_type: NodeType) -> void:
	for location in locations:
		var map_node: MapNode = node_views[location["id"]]

		# 匹配类型的放大，其余恢复，避免残留上次的高亮。
		var kind := int(_effective_location(str(location.id)).type)
		var matches_type: bool = kind in [NodeType.EVENT, NodeType.UNKNOWN] if node_type == NodeType.UNKNOWN else kind == node_type
		map_node.set_legend_highlight(matches_type)


# 作用：鼠标离开图例时，恢复所有地图节点的大小。
# 参数：没有参数。
# 返回值：没有返回值。
func _on_legend_exited() -> void:
	for map_node: MapNode in node_views.values():
		map_node.set_legend_highlight(false)


# 作用：外壳切换地图的操作权限；enabled 为 true 时只能查看，没有返回值。
func set_view_only(enabled: bool) -> void:
	view_only = enabled
	_refresh_nodes()


# 作用：胜利返回时同步已完成地点并解锁下一站；没有参数，没有返回值。
func resume_after_battle() -> void:
	current_id = RunManager.current_id
	completed_ids = RunManager.completed_ids.duplicate()
	pending_id = ""
	locked_node_id = ""
	active_node = null
	set_view_only(false)


# 作用：战斗加载失败时取消红圈并恢复选路；没有参数，没有返回值。
func cancel_pending_battle() -> void:
	if is_instance_valid(active_node):
		active_node.set_completed(false)
	RunManager.pending_battle_id = ""
	RunManager.pending_event_id = ""
	RunManager.pending_battle_rewards = {}
	resume_after_battle()


func _effective_location(id: String) -> Dictionary:
	var resolved: Dictionary = RunManager.route_location(id)
	return _get_location(id) if resolved.is_empty() else resolved

