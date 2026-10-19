@tool
extends Control

signal closed
const CARD_SCENE = preload("res://scenes/cards/unit_card.tscn")
const UI = preload("res://scripts/ui/pixel_ui_style.gd")
const STYLE = preload("res://scripts/ui/comic_style.gd")
const GOLD := Color("e5cb83")
const PAPER := Color("f4eed9")
const MUTED := Color("b0c6b4")
## 商店内容画布的整体缩放倍率，1 为原布局大小；越小则商品与操作区域更紧凑，运行时还会适配窗口尺寸。不会改变商品价格或库存。
@export_range(0.75, 1.0, 0.01) var content_scale := 0.88
var session: RefCounted
var canvas: Control
var goods: Control
var title_label: Label
var wallet: Label
var message: Label
var removal_button: Button
var removal_price_label: Label
var removal_overlay: Control
var removal_grid: GridContainer
var selected_card: CardInstance
var selection_label: Label
var confirm_button: Button
var tooltip: PanelContainer
var tooltip_label: Label
var offer_buttons: Array[Button] = []
var price_labels: Array[Label] = []
var product_views: Array[Control] = []

func _ready() -> void:
	_build()
	resized.connect(_layout)
	_layout()
	if not Engine.is_editor_hint():
		RunManager.stats_changed.connect(_refresh)
		RunManager.items_changed.connect(_refresh)
		RunManager.deck_changed.connect(_refresh)
		hide()

func _box(fill: Color, edge: Color = Color("688e7f"), radius: int = 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(2)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

func _label(text: String, at: Vector2, font_size: int, color: Color = PAPER) -> Label:
	var label := STYLE.label(text, at, font_size, color)
	canvas.add_child(label)
	return label

func _button(text: String, at: Vector2, dimensions: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = dimensions
	UI.button(button, 23)
	button.pressed.connect(action)
	canvas.add_child(button)
	return button

func _build() -> void:
	var wash := ColorRect.new()
	wash.color = Color("16191e")
	add_child(wash)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 帐篷背景铺满窗口，商品桌独立缩放，不留下矩形边框。
	var room := TextureRect.new()
	room.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	room.texture = preload("res://assets/ui/shop/shop_room.svg")
	room.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(room)
	room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = Control.new()
	canvas.size = Vector2(1920, 1080)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	var background := TextureRect.new()
	background.texture = preload("res://assets/ui/shop/shop_backdrop.svg")
	background.size = Vector2(1920, 1080)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)
	title_label = _label("旅途商队", Vector2(234, 151), 46, GOLD)
	_label("沿途好货 · 只此一件", Vector2(238, 215), 21, MUTED)
	var greeting := Panel.new()
	greeting.position = Vector2(646, 157)
	greeting.size = Vector2(818, 90)
	greeting.add_theme_stylebox_override("panel", UI.panel(Vector2(18, 12)))
	greeting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(greeting)
	_label("“带上可靠的援军和好装备，前方的路会好走些。”", Vector2(671, 174), 25, UI.INK)
	_label("点击商品购买 · 悬停查看效果 · 离开后继续征途", Vector2(673, 214), 17, UI.INK)
	wallet = _label("金币 0", Vector2(1511, 169), 30, GOLD)
	_label("招兵买马", Vector2(278, 300), 22, GOLD)
	_label("卡牌精选", Vector2(902, 300), 22, GOLD)
	_label("珍奇遗物", Vector2(278, 681), 22, GOLD)
	_label("随身药水", Vector2(920, 681), 22, GOLD)
	_label("精简卡组", Vector2(1431, 681), 22, GOLD)
	goods = Control.new()
	goods.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(goods)
	removal_button = _button("", Vector2(1426, 723), Vector2(223, 198), _open_removal)
	for state in ["normal", "hover", "pressed"]:
		removal_button.add_theme_stylebox_override(state, _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0) if state == "normal" else GOLD))
	var seal := TextureRect.new()
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.texture = preload("res://assets/ui/shop/removal_seal.svg")
	seal.position = Vector2(45, 3)
	seal.size = Vector2(136, 136)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	removal_button.add_child(seal)
	var service := STYLE.label("删去一张牌", Vector2(48, 143), 22)
	removal_button.add_child(service)
	removal_price_label = STYLE.label("", Vector2(0, 171), 26, GOLD)
	removal_price_label.size.x = 223
	removal_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	removal_button.add_child(removal_price_label)
	removal_button.mouse_entered.connect(_show_tip.bind("删牌服务\n从本局卡组永久移除一张牌。每店限一次。\n首次 75 金币，每次使用后上涨 25 金币。"))
	removal_button.mouse_exited.connect(_hide_tip)
	_label("每店一次", Vector2(1500, 926), 16, MUTED)
	message = _label("欢迎光临。商品买走后就没有了，慢慢挑。", Vector2(274, 1009), 22, MUTED)
	_button("离开商店  →", Vector2(1500, 994), Vector2(222, 60), _leave)
	_build_removal()
	tooltip = PanelContainer.new()
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_theme_stylebox_override("panel", UI.panel(Vector2(18, 12)))
	tooltip_label = Label.new()
	tooltip_label.custom_minimum_size.x = 350
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_label.add_theme_font_override("font", STYLE.chinese())
	tooltip_label.add_theme_font_size_override("font_size", 21)
	tooltip_label.add_theme_color_override("font_color", UI.INK)
	tooltip.add_child(tooltip_label)
	canvas.add_child(tooltip)
	tooltip.hide()

func _layout() -> void:
	if canvas == null:
		return
	var viewport_fit := minf(size.x / 1920.0, size.y / 1080.0)
	var factor := viewport_fit * content_scale
	canvas.scale = Vector2.ONE * factor
	# 商品桌留出周围环境与 HUD 空间，整体比原版缩小 12%。
	canvas.position = (size - Vector2(1920, 1080) * factor) * 0.5 + Vector2(0, 20.0 * viewport_fit)

func open_shop(visit: RefCounted) -> void:
	if session != null and session.changed.is_connected(_refresh):
		session.changed.disconnect(_refresh)
	session = visit
	session.changed.connect(_refresh)
	title_label.text = session.title
	selected_card = null
	removal_overlay.hide()
	message.text = "欢迎光临。商品买走后就没有了，慢慢挑。"
	_hide_tip()
	_build_goods()
	_refresh()
	show()

func _build_goods() -> void:
	for child in goods.get_children():
		goods.remove_child(child)
		child.queue_free()
	offer_buttons.clear()
	price_labels.clear()
	product_views.clear()
	var counts := {"recruit": 0, "card": 0, "relic": 0, "potion": 0}
	for index in session.offers.size():
		var offer: Dictionary = session.offers[index]
		var kind: String = offer.kind
		var number: int = counts[kind]
		counts[kind] += 1
		var card_product: bool = kind in ["recruit", "card"]
		var start_x: float = {"recruit": 268.0, "card": 898.0, "relic": 292.0, "potion": 935.0}[kind]
		var x := start_x + number * (209.0 if card_product else 190.0 if kind == "relic" else 150.0)
		var button := _button("", Vector2(x, 346 if card_product else 731), Vector2(192, 286) if card_product else Vector2(152, 191), _purchase.bind(index))
		canvas.remove_child(button)
		goods.add_child(button)
		for state in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state, _box(Color(0, 0, 0, 0), GOLD if state in ["hover", "pressed"] else Color(0, 0, 0, 0), 8))
		button.tooltip_text = ""
		var view: Control
		var tip := ""
		if card_product:
			var preview := CARD_SCENE.instantiate() as UnitCard
			preview.is_playable = false
			button.add_child(preview)
			preview.position = Vector2(96, 128)
			preview.scale = Vector2.ONE * 0.65
			preview.setup(CardInstance.new(offer.data))
			view = preview
			_ignore_mouse(preview)
			preview.enable_unit_details()
			tip = preview.card_instance.definition.card_name + "\n" + preview.card_instance.get_description()
			tip += "\n购买后加入本局卡组。"
		else:
			var icon := TextureRect.new()
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.texture = offer.data.icon
			icon.position = Vector2(30, 2)
			icon.size = Vector2(92, 92)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(icon)
			view = icon
			var name_label := STYLE.label(offer.data.display_name, Vector2(0, 102), 20)
			name_label.size.x = 152
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.clip_text = true
			button.add_child(name_label)
			tip = offer.data.display_name + "\n" + offer.data.description
		if offer.sale:
			var badge := STYLE.label("半价", Vector2(126, -15), 22, Color("a8ef8a"))
			button.add_child(badge)
			tip += "\n特价 %d 金币（原价 %d）。" % [offer.price, offer.original_price]
		var price := STYLE.label("", Vector2(0, 254 if card_product else 142), 26, GOLD)
		price.size.x = button.size.x
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_child(price)
		button.mouse_entered.connect(_show_tip.bind(tip))
		button.mouse_exited.connect(_hide_tip)
		offer_buttons.append(button)
		price_labels.append(price)
		product_views.append(view)

func _refresh() -> void:
	if session == null or not is_node_ready():
		return
	wallet.text = "金币  %d" % session.run.gold
	for index in offer_buttons.size():
		var offer: Dictionary = session.offers[index]
		var unavailable: bool = offer.sold or (offer.kind == "relic" and session._owns_relic(offer.data))
		offer_buttons[index].disabled = unavailable or not session.is_active()
		price_labels[index].text = "售罄" if offer.sold else "已拥有" if unavailable else "◈ %d" % offer.price
		price_labels[index].modulate = Color.WHITE
		price_labels[index].add_theme_color_override("font_color", MUTED if unavailable else Color("eb9284") if session.run.gold < offer.price else Color("b2ee8c") if offer.sale else GOLD)
		product_views[index].modulate = Color(0.5, 0.6, 0.55, 0.3) if unavailable else Color.WHITE
	removal_button.disabled = session.removal_used or not session.is_active()
	removal_price_label.text = "已使用" if session.removal_used else "◈ %d" % session.removal_price()
	removal_price_label.add_theme_color_override("font_color", MUTED if session.removal_used else Color("eb9284") if session.run.gold < session.removal_price() else GOLD)
	if removal_overlay.visible:
		confirm_button.disabled = selected_card == null or not session.run.deck.has(selected_card) or not session.removal_error().is_empty()

func _purchase(index: int) -> void:
	_hide_tip()
	var offer: Dictionary = session.offers[index]
	var error: String = session.purchase(index)
	if not error.is_empty():
		message.text = error
		message.add_theme_color_override("font_color", Color("ffab94"))
		return
	var product_name: String = offer.data.card_name if offer.kind in ["recruit", "card"] else offer.data.display_name
	message.text = "已%s「%s」，花费 %d 金币。" % ["招募" if offer.kind == "recruit" else "购买", product_name, offer.price]
	message.add_theme_color_override("font_color", Color("c4e9b5"))
	_refresh()

func _build_removal() -> void:
	removal_overlay = Control.new()
	removal_overlay.size = Vector2(1920, 1080)
	canvas.add_child(removal_overlay)
	var dark := ColorRect.new()
	dark.color = Color(0.04, 0.08, 0.1, 0.97)
	dark.size = Vector2(1920, 1080)
	removal_overlay.add_child(dark)
	var heading := STYLE.label("选择要删去的牌", Vector2(220, 174), 38, GOLD)
	removal_overlay.add_child(heading)
	selection_label = STYLE.label("", Vector2(220, 232), 23)
	removal_overlay.add_child(selection_label)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(220, 293)
	scroll.size = Vector2(1490, 622)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	removal_overlay.add_child(scroll)
	removal_grid = GridContainer.new()
	removal_grid.columns = 6
	removal_grid.add_theme_constant_override("h_separation", 14)
	removal_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(removal_grid)
	var cancel := _button("取消", Vector2(220, 957), Vector2(170, 60), _cancel_removal)
	canvas.remove_child(cancel)
	removal_overlay.add_child(cancel)
	confirm_button = _button("确认删牌", Vector2(1370, 957), Vector2(338, 60), _confirm_removal)
	UI.button(confirm_button, 23, true)
	canvas.remove_child(confirm_button)
	removal_overlay.add_child(confirm_button)
	removal_overlay.hide()

func _open_removal() -> void:
	_hide_tip()
	var error: String = session.removal_error()
	if not error.is_empty():
		message.text = error
		return
	selected_card = null
	for child in removal_grid.get_children():
		removal_grid.remove_child(child)
		child.queue_free()
	for card: CardInstance in session.run.deck:
		var button := _button("", Vector2.ZERO, Vector2(226, 314), _select_card.bind(card))
		canvas.remove_child(button)
		button.custom_minimum_size = Vector2(226, 314)
		button.set_meta("card", card)
		removal_grid.add_child(button)
		var view := CARD_SCENE.instantiate() as UnitCard
		view.is_playable = false
		button.add_child(view)
		view.position = Vector2(113, 156)
		view.scale = Vector2.ONE * 0.77
		view.setup(card)
		_ignore_mouse(view)
		view.enable_unit_details()
	selection_label.text = "花费 %d 金币永久移除一张牌。本店限一次；取消不会扣费。" % session.removal_price()
	confirm_button.text = "确认删牌 · %d 金币" % session.removal_price()
	confirm_button.disabled = true
	removal_overlay.show()

func _select_card(card: CardInstance) -> void:
	selected_card = card
	selection_label.text = "即将永久移除「%s」，花费 %d 金币。" % [card.definition.card_name, session.removal_price()]
	for button in removal_grid.get_children():
		UI.select(button, button.get_meta("card") == card)
	_refresh()

func _cancel_removal() -> void:
	selected_card = null
	removal_overlay.hide()

func _confirm_removal() -> void:
	if selected_card == null:
		return
	var name_text := selected_card.definition.card_name
	var error: String = session.remove_card(selected_card)
	if not error.is_empty():
		selection_label.text = error
		_refresh()
		return
	_cancel_removal()
	message.text = "已从本局卡组移除「%s」。" % name_text
	_refresh()

func _leave() -> void:
	if session == null or not session.is_active() or removal_overlay.visible:
		return
	session.finish()
	_hide_tip()
	hide()
	closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and removal_overlay.visible:
		_cancel_removal()
		get_viewport().set_input_as_handled()

func _show_tip(text: String) -> void:
	if removal_overlay.visible:
		return
	tooltip_label.text = text
	tooltip.size = Vector2.ZERO
	tooltip.show()

func _hide_tip() -> void:
	if tooltip != null:
		tooltip.hide()

func _process(_delta: float) -> void:
	if tooltip != null and tooltip.visible:
		var point := canvas.get_local_mouse_position() + Vector2(24, 20)
		tooltip.position = Vector2(clampf(point.x, 20, 1900 - tooltip.size.x), clampf(point.y, 145, 1050 - tooltip.size.y))

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
