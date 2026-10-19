# 这玩意儿是干嘛的（核心逻辑）：提供独立练兵场，左边加己方、右边加敌方，按按钮开始自动战斗。
# 数据是咋流动的（数据流向）：普通/强化按钮 → 独立单位属性与原牌训练规则 → 阵营容器和导航 → 原有技能逻辑。
# 为啥这么写（选型决策）：复用单位本身，不接入卡牌、基地和地图进度，方便反复测试怪物。
# 性能咋样（复杂度）：只在点击时生成单位；每 0.2 秒统计人数，背景网格只绘制一次。
extends Node2D

## 单独怪物测试场景中可添加的单位场景列表；界面按 UnitData 的原始阵营分成己方与敌方按钮。只影响测试场景，不加入正式关卡波次或初始牌组。
@export var unit_scenes: Array[PackedScene] = []

# 有些怪物暂时共用兽人数据，按钮仍按场景外观命名，避免骷髅也显示成“哥布林”。
const SCENE_NAMES := {"elite_orc": "精英兽人", "greatsword_skeleton": "巨剑骷髅",
	"orc_rider": "兽人骑手", "skeleton": "骷髅", "skeleton_archer": "骷髅弓箭手", "slime": "史莱姆"}

var team_a: Node2D
var team_b: Node2D
var start_button: Button
var count_label: Label
var status_label: Label
var running := false
var refresh_left := 0.0
var spawn_buttons: Dictionary = {}
# 场景路径 → 强化次数 → 按钮，按各兵种配置的上限提供全部测试等级。
var upgrade_buttons: Dictionary = {}
var branch_upgrade_buttons: Dictionary = {}


# 作用：Godot 打开测试场景时建立场地和操作界面；没有参数，没有返回值。
func _ready() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	_build_arena()
	_build_ui()
	_refresh_counts()


# 作用：建立平坦可导航场地和两个队伍容器；没有参数，没有返回值。
func _build_arena() -> void:
	var polygon := NavigationPolygon.new()
	polygon.vertices = PackedVector2Array([Vector2(340, 170), Vector2(1580, 170), Vector2(1580, 910), Vector2(340, 910)])
	polygon.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region := NavigationRegion2D.new()
	region.name = "Navigation"
	region.navigation_polygon = polygon
	add_child(region)
	# 召唤技能把召唤物放在施法者的父节点，因此两队各有自己的容器。
	team_a = Node2D.new()
	team_a.name = "TeamA"
	team_a.y_sort_enabled = true
	add_child(team_a)
	team_b = Node2D.new()
	team_b.name = "TeamB"
	team_b.y_sort_enabled = true
	add_child(team_b)


# 作用：Godot 绘制静态练兵场背景；没有参数，没有返回值。
func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Color("111d26"))
	draw_rect(Rect2(320, 150, 1280, 780), Color("1c3038"))
	draw_rect(Rect2(340, 170, 440, 740), Color("203b46"))
	draw_rect(Rect2(1140, 170, 440, 740), Color("403038"))
	for x in range(340, 1581, 80):
		draw_line(Vector2(x, 170), Vector2(x, 910), Color(1, 1, 1, 0.035))
	for y in range(170, 911, 80):
		draw_line(Vector2(340, y), Vector2(1580, y), Color(1, 1, 1, 0.035))
	draw_line(Vector2(960, 170), Vector2(960, 910), Color("65818a"), 2)
	draw_rect(Rect2(320, 150, 1280, 780), Color("54727a"), false, 2)


# 作用：创建界面文字；parent 是所属节点，text 为文字，point/size 为布局，返回标签。
func _label(parent: Node, text: String, point: Vector2, size: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = point
	label.size = size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	parent.add_child(label)
	return label


# 作用：建立两侧单位列表和战斗按钮；没有参数，没有返回值。
func _build_ui() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	_label(hud, "怪物对战测试场", Vector2(500, 20), Vector2(920, 48)).add_theme_font_size_override("font_size", 34)
	_label(hud, "TEAM A · 己方", Vector2(25, 95), Vector2(270, 45)).modulate = Color("82d6f2")
	_label(hud, "TEAM B · 敌方", Vector2(1625, 95), Vector2(270, 45)).modulate = Color("ffa3a3")
	count_label = _label(hud, "", Vector2(530, 78), Vector2(860, 40))
	status_label = _label(hud, "己方可选择强化次数添加单位；布置好双方后开始战斗。", Vector2(320, 1024), Vector2(1280, 42))
	var left := _unit_list(hud, Vector2(25, 150))
	var right := _unit_list(hud, Vector2(1625, 150))
	for scene in unit_scenes:
		if scene == null:
			continue
		# 只实例化读取原始数据，不入树、不启动技能；展示后立即释放这个临时对象。
		var preview := scene.instantiate() as UnitBase
		if preview == null:
			continue
		var data := preview.unit_data
		if data == null:
			preview.free()
			continue
		var team := data.unit_team
		var button := Button.new()
		var scene_name := scene.resource_path.get_file().get_basename()
		button.text = "+ " + str(SCENE_NAMES.get(scene_name, data.unit_name)) + "  ·  " + scene_name
		button.custom_minimum_size = Vector2(250, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 16)
		button.tooltip_text = "生命 %d / 攻击 %d / 防御 %d\n%s" % [data.max_hp, data.attack, data.defence, scene.resource_path]
		button.pressed.connect(spawn_unit.bind(scene, team))
		if team == "team_a":
			var group := VBoxContainer.new()
			group.add_theme_constant_override("separation", 4)
			left.add_child(group)
			group.add_child(button)
			var levels: Dictionary = {}
			if data.max_upgrade_count > 0:
				var grid := GridContainer.new()
				grid.columns = 2
				grid.add_theme_constant_override("h_separation", 6)
				grid.add_theme_constant_override("v_separation", 4)
				group.add_child(grid)
				for level in range(1, data.max_upgrade_count + 1):
					var upgrade := Button.new()
					upgrade.text = "飞弹%d次" % level if data.unit_english_name == "soldier" else "强化%d次" % level
					upgrade.custom_minimum_size = Vector2(120, 38)
					upgrade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					upgrade.add_theme_font_size_override("font_size", 16)
					upgrade.tooltip_text = "添加强化%d次的%s，累计%d个能力点全部加到攻击，并启用对应强化效果和已解锁技能。" % [level, data.unit_name, level * maxi(0, data.upgrade_ability_points)]
					upgrade.pressed.connect(spawn_unit.bind(scene, team, level, "missile" if data.unit_english_name == "soldier" else ""))
					grid.add_child(upgrade)
					levels[level] = upgrade
					if data.unit_english_name == "soldier":
						var slash := Button.new()
						slash.text = "斩击%d次" % level
						slash.custom_minimum_size = Vector2(120, 38)
						slash.add_theme_font_size_override("font_size", 16)
						slash.tooltip_text = "添加斩击分支士兵：放弃弓箭，350范围飞跃，每个敌人仅一次；斩过的目标死亡，自身攻击+1。"
						slash.pressed.connect(spawn_unit.bind(scene, team, level, "slash"))
						grid.add_child(slash)
						if not branch_upgrade_buttons.has(scene.resource_path):
							branch_upgrade_buttons[scene.resource_path] = {}
						branch_upgrade_buttons[scene.resource_path][level] = {"slash": slash, "missile": upgrade}
			upgrade_buttons[scene.resource_path] = levels
		else:
			right.add_child(button)
		spawn_buttons[scene.resource_path] = button
		preview.free()
	start_button = Button.new()
	start_button.text = "开始战斗"
	start_button.position = Vector2(650, 955)
	start_button.size = Vector2(280, 58)
	start_button.pressed.connect(start_battle)
	hud.add_child(start_button)
	var clear_button := Button.new()
	clear_button.text = "清空重置"
	clear_button.position = Vector2(990, 955)
	clear_button.size = Vector2(280, 58)
	clear_button.pressed.connect(clear_arena)
	hud.add_child(clear_button)


# 作用：创建可滚动的单位按钮容器；hud 是界面层，point 是列表位置，返回列表。
func _unit_list(hud: CanvasLayer, point: Vector2) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.position = point
	scroll.size = Vector2(270, 780)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hud.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return list


# 作用：创建普通或指定强化次数的单位；upgrade_level 按原牌规则逐次训练，能力点全部加攻击，返回单位或空。
func spawn_unit(scene: PackedScene, team: String, upgrade_level: int = 0, branch: String = "") -> UnitBase:
	if team not in ["team_a", "team_b"] or scene == null:
		return null
	if upgrade_level < 0:
		status_label.text = "强化次数不能小于0。"
		return null
	if upgrade_level > 0 and team != "team_a":
		status_label.text = "强化按钮仅用于己方单位。"
		return null
	var container := team_a if team == "team_a" else team_b
	# 在本方区域寻找空位，不把多次点击生成的单位叠在一起。
	var spawn_point := Vector2.INF
	for row in range(10):
		for column in range(4):
			var point := Vector2(720 - column * 90 if team == "team_a" else 1200 + column * 90, 225 + row * 70)
			var occupied := false
			for unit in team_a.get_children() + team_b.get_children():
				if unit is UnitBase and not unit.is_queued_for_deletion() and unit.global_position.distance_to(point) < 60:
					occupied = true
					break
			if not occupied:
				spawn_point = point
				break
		if spawn_point != Vector2.INF:
			break
	if spawn_point == Vector2.INF:
		status_label.text = "本方生成区域已满，请等待单位移动或清空重置。"
		return null
	var instance := scene.instantiate()
	var unit := instance as UnitBase
	if unit == null or unit.unit_data == null or unit.unit_data.unit_team != team:
		instance.free()
		return null
	var attack_gain := 0
	if upgrade_level > 0:
		# 使用真实单牌训练入口；出场前写入独立数据，让技能管理器正确安装解锁后的技能。
		var card := CardInstance.new(unit.unit_data)
		if upgrade_level > card.get_upgrade_limit():
			status_label.text = "此单位最多可强化%d次。" % card.get_upgrade_limit()
			unit.free()
			return null
		for _training in upgrade_level:
			if not card.train(maxi(0, unit.unit_data.upgrade_ability_points), 0, branch):
				status_label.text = "此单位无法强化，请检查可强化次数。"
				unit.free()
				return null
		attack_gain = card.attack_points
		unit.unit_data = card.get_summon_data()
	unit.position = spawn_point
	container.add_child(unit)
	unit.animated_sprite_2d.flip_h = team == "team_b"
	var scene_name := scene.resource_path.get_file().get_basename()
	var display_name := str(SCENE_NAMES.get(scene_name, unit.unit_data.unit_name))
	if upgrade_level > 0:
		display_name += "（强化%d次，攻击+%d）" % [upgrade_level, attack_gain]
		if unit.unit_data.unit_english_name == "soldier":
			display_name += " · " + ("斩击" if unit.unit_data.get_soldier_specialization() == "slash" else "飞弹")
	status_label.text = "已添加 %s；%s" % [display_name, "战斗中可继续增兵。" if running else "双方准备好后点击开始战斗。"]
	_refresh_counts()
	return unit


# 作用：双方都有存活单位时开启自动战斗；没有参数，没有返回值。
func start_battle() -> void:
	if _living_count(team_a) == 0 or _living_count(team_b) == 0:
		status_label.text = "请先在左右两边各添加至少一个单位。"
		return
	# 不设置战斗倒计时或基地，持续运行以便观察技能和增兵后的行为。
	running = true
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	start_button.disabled = true
	start_button.text = "自动战斗中"
	status_label.text = "自动战斗已开始，可以继续点击两侧按钮增加单位。"


# 作用：移除本次测试的单位与临时特效；没有参数，没有返回值。
func clear_arena() -> void:
	running = false
	Global.game_phase = Global.GamePhase.CARD_PLAY
	# 立即停止旧单位处理，再延迟释放，避免同一帧的导航回调继续移动或发动技能。
	for unit in team_a.get_children() + team_b.get_children():
		unit.process_mode = Node.PROCESS_MODE_DISABLED
		unit.queue_free()
	# 原有投射物和命中特效会挂在当前场景根节点，一并清理才不会污染下一次测试。
	for child in get_children():
		if child.name not in ["Navigation", "TeamA", "TeamB", "HUD"]:
			child.process_mode = Node.PROCESS_MODE_DISABLED
			child.queue_free()
	start_button.disabled = false
	start_button.text = "开始战斗"
	status_label.text = "已清空，请重新布置双方单位。"
	_refresh_counts()


# 作用：统计一队还活着的单位；team 为队伍容器，返回数量。
func _living_count(team: Node2D) -> int:
	var count := 0
	for unit in team.get_children():
		if unit is UnitBase and not unit.is_queued_for_deletion() and unit.current_state != UnitBase.State.DEATH:
			count += 1
	return count


# 作用：刷新双方存活数，召唤出来的单位也会纳入；没有参数，没有返回值。
func _refresh_counts() -> void:
	count_label.text = "TEAM A  %d   存活       /       TEAM B  %d   存活" % [_living_count(team_a), _living_count(team_b)]


# 作用：Godot 每帧推进统计间隔；delta 为经过秒数，没有返回值。
func _process(delta: float) -> void:
	refresh_left -= delta
	if refresh_left <= 0:
		refresh_left = 0.2
		_refresh_counts()
