# 这玩意儿是干嘛的（核心逻辑）：用现有卡面只读展示全部卡组或指定牌堆。
# 数据是咋流动的（数据流向）：全部卡组或牌堆快照 → 网格卡面；关闭按钮通知调用方恢复界面。
# 为啥这么写（选型决策）：读取总牌组而非合并临时牌堆，单位上场后仍能看到对应牌。
# 性能咋样（复杂度）：只在打开或牌组改变时重建卡面，关闭时不更新。
extends Control

signal close_requested
const UI = preload("res://scripts/ui/pixel_ui_style.gd")
const CARD_SCENE = preload("res://scenes/cards/unit_card.tscn")
@onready var grid: GridContainer = $Margin/VBox/Scroll/Grid
@onready var scroll: ScrollContainer = $Margin/VBox/Scroll
@onready var title: Label = $Margin/VBox/Header/Title
var _show_full_deck := true
var _cards: Array[CardInstance] = []
var _heading := "全部卡组"


# 作用：Godot 在界面入树时连接关闭和布局事件；没有参数，没有返回值。
func _ready() -> void:
	UI.button($Margin/VBox/Header/Close, 26)
	UI.caption(title, "blue", 30)
	$Margin/VBox/Hint.add_theme_stylebox_override("normal", UI.strip())
	$Margin/VBox/Hint.add_theme_color_override("font_color", UI.INK)
	$Margin/VBox/Header/Close.pressed.connect(_on_close_pressed)
	scroll.resized.connect(_update_columns)
	RunManager.deck_changed.connect(_on_deck_changed)


# 作用：打开全部卡组，保留真实卡牌不改动牌堆；没有参数，没有返回值。
func open_deck() -> void:
	_show_full_deck = true
	_heading = "全部卡组"
	$Margin/VBox/Hint.text = "包含手牌、抽牌堆、弃牌堆及已上场的牌。此处仅供查看，不能出牌。"
	show()
	_rebuild_cards()
	scroll.scroll_vertical = 0


# 作用：展示指定牌堆的快照；cards 是真实卡实例列表，heading 是标题，hint 是说明，没有返回值。
func open_cards(cards: Array[CardInstance], heading: String, hint: String) -> void:
	_show_full_deck = false
	_cards = cards.duplicate()
	_heading = heading
	$Margin/VBox/Hint.text = hint + ("\n当前牌堆为空。" if _cards.is_empty() else "")
	show()
	_rebuild_cards()
	scroll.scroll_vertical = 0


# 作用：Godot 收到未被界面处理的键盘输入时关闭面板；event 为输入，没有返回值。
func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_requested.emit()


# 作用：通知外壳关闭，由按钮触发；没有参数，没有返回值。
func _on_close_pressed() -> void:
	close_requested.emit()


# 作用：牌组变化时刷新当前可见面板；没有参数，没有返回值。
func _on_deck_changed() -> void:
	if visible and _show_full_deck:
		_rebuild_cards()


# 作用：为每张拥有的牌生成只读卡面；没有参数，没有返回值。
func _rebuild_cards() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var displayed: Array[CardInstance] = RunManager.deck if _show_full_deck else _cards
	title.text = "%s · %d 张" % [_heading, displayed.size()]
	for card: CardInstance in displayed:
		# 原卡面围绕中心向外绘制，所以增加一个固定大小的格子承载它。
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(290, 410)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(slot)
		var view := CARD_SCENE.instantiate() as UnitCard
		view.is_playable = false
		slot.add_child(view)
		view.position = Vector2(160, 215)
		view.setup(card)
		_ignore_mouse(view)
		view.enable_unit_details()
	_update_columns()


# 作用：根据面板实际宽度计算列数；没有参数，没有返回值。
func _update_columns() -> void:
	grid.columns = maxi(1, int((scroll.size.x - 20.0) / 306.0))


# 作用：让卡面不拦截滚轮或拖放；node 为待处理的卡面节点，没有返回值。
func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
