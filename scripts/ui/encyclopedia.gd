extends Control
## 暂停菜单中的只读图鉴。最多缓存三个跨页，分类跳转也走同一套书本动画。

signal close_requested

const CATALOG := preload("res://scripts/ui/encyclopedia_catalog.gd")
const PAGE := preload("res://scripts/ui/encyclopedia_page.gd")
const BOOK := preload("res://scenes/ui/pixel_book.tscn")
const STYLE := preload("res://scripts/ui/settings_style.gd")
const COLORS := [Color("a77845"), Color("477d82"), Color("965563"), Color("5c729e"), Color("7c658a")]

var book: PixelBook
var bookmarks: Array[Button] = []
var bookmark_root: Node2D
var search: LineEdit
var search_timer: Timer
var directory: MenuButton
var previous: Button
var next: Button
var close_button: Button
var heading: Label
var catalog: Dictionary = {}
var category := 0
var current_index := 0
var query := ""
var spreads: Array[Dictionary] = []
var page_cache: Dictionary = {}
var pending: Dictionary = {}
var scroll_side := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Theme.new()
	theme.default_font = STYLE.FontStyle.chinese()
	theme.default_font_size = 24
	var background := ColorRect.new()
	background.color = Color("101923")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	heading = _label("冒险图鉴", Vector2(52, 28), 36, STYLE.GOLD)
	search = LineEdit.new()
	search.name = "Search"
	search.position = Vector2(1070, 24)
	search.size = Vector2(390, 55)
	search.placeholder_text = "搜索当前分类…"
	search.add_theme_font_size_override("font_size", 23)
	add_child(search)
	search_timer = Timer.new()
	search_timer.one_shot = true
	search_timer.wait_time = 0.22
	add_child(search_timer)
	search.text_changed.connect(func(_value: String): search_timer.start())
	search_timer.timeout.connect(_filter)
	directory = MenuButton.new()
	directory.flat = false
	directory.name = "Directory"
	directory.text = "目录 ▾"
	directory.position = Vector2(1485, 24)
	directory.size = Vector2(140, 55)
	STYLE.button(directory, 23)
	add_child(directory)
	var popup := directory.get_popup()
	popup.add_theme_font_override("font", STYLE.FontStyle.chinese())
	popup.add_theme_font_size_override("font_size", 24)
	popup.id_pressed.connect(_jump)
	close_button = _button("返回设置", Vector2(1650, 24), Vector2(190, 55), func(): close_requested.emit())
	book = BOOK.instantiate() as PixelBook
	book.name = "CatalogBook"
	book.turn_duration = 0.65
	book.show_bookmark = false
	book.fitting_rect = Rect2(43, 55, 394, 280)
	book.layout_stretch = Vector2(1.45, 1)
	book.render_scale = 3.5
	book.constrain_motion_to_frame = true
	add_child(book)
	book.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	book.position = Vector2(32, 102)
	book.size = Vector2(1856, 954)
	book.turn_started.connect(_turn_started)
	book.turn_finished.connect(_turn_finished)
	bookmark_root = Node2D.new()
	bookmark_root.name = "CategoryBookmarks"
	bookmark_root.z_index = 5
	book.add_child(bookmark_root)
	for i in CATALOG.KEYS.size():
		var button := Button.new()
		button.name = CATALOG.KEYS[i]
		button.text = ["遗物", "己方\n单位", "敌方\n单位", "药水", "事件"][i]
		button.tooltip_text = CATALOG.NAMES[i] + "图鉴"
		button.position = Vector2(239 + i * 37, 300)
		button.size = Vector2(165, 100)
		button.add_theme_font_size_override("font_size", 24)
		button.add_theme_color_override("font_color", Color("fff2d9"))
		button.add_theme_color_override("font_disabled_color", Color("ddd0be"))
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(select_category.bind(i))
		bookmark_root.add_child(button)
		bookmarks.append(button)
	# 字样绘制在高分辨率纸面内，透明按钮只负责鼠标与键盘焦点。
	previous = _page_button("上一页", Vector2(65, 282), func(): book.turn_previous())
	next = _page_button("下一页", Vector2(363, 282), func(): book.turn_next())
	hide()
	book.process_mode = Node.PROCESS_MODE_DISABLED
	book._view.render_target_update_mode = SubViewport.UPDATE_DISABLED


func open_book() -> void:
	if catalog.is_empty(): catalog = CATALOG.read()
	show()
	book.process_mode = Node.PROCESS_MODE_ALWAYS
	book._view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var models := CATALOG.spreads(catalog[CATALOG.KEYS[category]], query)
	_mount(category, models, mini(current_index, models.size() - 1))
	close_button.grab_focus()


func close_book() -> void:
	if not visible: return
	_release_scroll()
	search_timer.stop()
	_discard_pending()
	if not spreads.is_empty():
		var carry: Array = page_cache.get(current_index, [])
		_mount(category, spreads, current_index, carry)
	hide()
	book.process_mode = Node.PROCESS_MODE_DISABLED
	book._view.render_target_update_mode = SubViewport.UPDATE_DISABLED


func select_category(index: int) -> void:
	if index < 0 or index >= CATALOG.KEYS.size() or book.turning: return
	if index == category and query.is_empty(): return
	var models := CATALOG.spreads(catalog[CATALOG.KEYS[index]])
	_transition(index, models, 0, "", 1 if index >= category else -1)


func _filter() -> void:
	if not visible: return
	if book.turning:
		search_timer.start()
		return
	query = search.text.strip_edges()
	_mount(category, CATALOG.spreads(catalog[CATALOG.KEYS[category]], query), 0)


func _jump(index: int) -> void:
	@warning_ignore("integer_division")
	var page := index / CATALOG.ENTRIES_PER_SPREAD
	if not book.turning and page != current_index and page >= 0 and page < spreads.size():
		_transition(category, spreads, page, query, 1 if page > current_index else -1)


func _transition(target_category: int, models: Array[Dictionary], index: int, target_query: String, direction: int) -> void:
	var views := _make_pages(models[index], target_category, index, models.size())
	var source: Array = page_cache[current_index]
	pending = {"category": target_category, "spreads": models, "index": index, "query": target_query, "views": views}
	var textures: Array[Texture2D] = []
	var pairs: Array = [source, views] if direction > 0 else [views, source]
	for pair: Array in pairs:
		for view: SubViewport in pair: textures.append(view.get_texture())
	book.page_textures = textures
	book.jump_to_spread(0 if direction > 0 else 1)
	if direction > 0: book.turn_next()
	else: book.turn_previous()
	_sync()


func _mount(index: int, models: Array[Dictionary], page: int, carry: Array = []) -> void:
	for pair: Array in page_cache.values():
		for view: SubViewport in pair:
			if not carry.has(view): view.queue_free()
	page_cache.clear()
	category = index
	spreads = models
	current_index = page
	var textures: Array[Texture2D] = []
	textures.resize(spreads.size() * 2)
	book.page_textures = textures
	page_cache[current_index] = carry if not carry.is_empty() else _make_pages(spreads[current_index], category, current_index, spreads.size())
	_apply_textures(current_index)
	book.jump_to_spread(current_index)
	search.text = query
	_rebuild_directory()
	_sync()


func _make_pages(model: Dictionary, index: int, page: int, count: int) -> Array:
	var display: Array = []
	for entry: Dictionary in model.entries:
		CATALOG.icon_for(entry)
		var item := entry.duplicate()
		item.facts = entry.facts.duplicate()
		if entry.source is RelicDefinition:
			item.facts.append("已发现" if RunManager.discovered_relics.has(str(entry.source.id)) or RunManager.has_relic(entry.source.id) else "尚未发现")
		display.append(item)
	var result: Array = []
	for side in 2:
		var view := SubViewport.new()
		view.size = PAGE.SIZE
		view.transparent_bg = true
		view.gui_disable_input = false
		view.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(view)
		var sheet := Control.new()
		sheet.set_script(PAGE)
		sheet.entries = display.slice(side * CATALOG.ENTRIES_PER_PAGE, (side + 1) * CATALOG.ENTRIES_PER_PAGE)
		sheet.category = CATALOG.NAMES[index]
		sheet.right = side == 1
		sheet.navigation_enabled = page > 0 if side == 0 else page < count - 1
		view.add_child(sheet)
		result.append(view)
	return result


func _apply_textures(index: int) -> void:
	var pair: Array = page_cache[index]
	for side in 2: book.page_textures[index * 2 + side] = pair[side].get_texture()


func _turn_started(direction: int) -> void:
	_release_scroll()
	if pending.is_empty():
		var target := book.spread_index + direction
		if not page_cache.has(target): page_cache[target] = _make_pages(spreads[target], category, target, spreads.size())
		_apply_textures(target)
	_sync()


func _turn_finished(committed: bool) -> void:
	if not pending.is_empty():
		var target := pending
		pending = {}
		if committed:
			query = target.query
			_mount(target.category, target.spreads, target.index, target.views)
		else:
			for view: SubViewport in target.views: view.queue_free()
			_mount(category, spreads, current_index, page_cache[current_index])
	else:
		current_index = book.spread_index
		for index: int in page_cache.keys():
			if absi(index - current_index) <= 1: continue
			for view: SubViewport in page_cache[index]: view.queue_free()
			page_cache.erase(index)
			book.page_textures[index * 2] = null
			book.page_textures[index * 2 + 1] = null
	_sync()


func _discard_pending() -> void:
	for view: SubViewport in pending.get("views", []): view.queue_free()
	pending = {}


func _rebuild_directory() -> void:
	var popup := directory.get_popup()
	popup.clear()
	for i in spreads.size():
		var model: Dictionary = spreads[i]
		for item in model.entries.size():
			popup.add_item("%02d  %s" % [model.first_entry + item + 1, model.entries[item].title], model.first_entry + item)


func _sync() -> void:
	var count := 0
	for model: Dictionary in spreads:
		count += model.entries.size()
	heading.text = "冒险图鉴  /  %s · %d" % [CATALOG.NAMES[category], count]
	previous.disabled = not book.can_turn(-1)
	next.disabled = not book.can_turn(1)
	search.editable = not book.turning
	directory.disabled = book.turning or count == 0
	for i in bookmarks.size():
		bookmarks[i].disabled = book.turning
		bookmarks[i].position.y = 296 if i == category else 300
		_style_bookmark(bookmarks[i], i, i == category)


func _process(_delta: float) -> void:
	if not visible: return
	var fit := book.get_layout_transform()
	bookmark_root.transform = fit * book.get_motion_transform()
	# 文字以屏幕字号绘制，取消基础拟合缩放；只随翻页本身伸缩。
	for button in bookmarks:
		button.scale = Vector2(1.0 / fit.x.x, 1.0 / fit.y.y)
		button.size = Vector2(35 * fit.x.x, 31 * fit.y.y)


func _input(event: InputEvent) -> void:
	if visible and not book.turning and event is InputEventMouse:
		_route_paper_mouse(event)
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if search.has_focus() or directory.get_popup().visible: return
	if event.keycode in [KEY_RIGHT, KEY_PAGEDOWN]: book.turn_next()
	elif event.keycode in [KEY_LEFT, KEY_PAGEUP]: book.turn_previous()
	else: return
	get_viewport().set_input_as_handled()


func _route_paper_mouse(event: InputEventMouse) -> void:
	var wheel: bool = event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
	if not wheel and scroll_side < 0 and not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed): return
	var local := book.get_global_transform_with_canvas().affine_inverse() * event.position
	var point := book._to_canvas(local)
	if scroll_side < 0 and (not Rect2(60, 66, 360, 230).has_point(point) or directory.get_popup().visible): return
	var side := scroll_side if scroll_side >= 0 else (0 if point.x < 240 else 1)
	var paper_point := (point - Vector2(60 + side * 180, 66)) / PixelBook.PAGE * Vector2(PAGE.SIZE)
	var view: SubViewport = page_cache[current_index][side]
	if not wheel and scroll_side < 0:
		var sheet: Control = view.get_child(0)
		if not sheet.readers.any(func(reader): return reader.get_v_scroll_bar().is_visible_in_tree() and reader.get_v_scroll_bar().get_global_rect().has_point(paper_point)): return
		scroll_side = side
	var motion := InputEventMouseMotion.new()
	motion.position = paper_point
	view.push_input(motion, true)
	var forwarded := event.duplicate() as InputEventMouse
	forwarded.position = paper_point
	forwarded.global_position = paper_point
	view.push_input(forwarded, true)
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed: scroll_side = -1
	get_viewport().set_input_as_handled()


func _release_scroll() -> void:
	if scroll_side < 0: return
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = get_viewport().get_mouse_position()
	_route_paper_mouse(release)
	scroll_side = -1


func _page_button(title: String, point: Vector2, callback: Callable) -> Button:
	var result := Button.new()
	result.name = title
	result.tooltip_text = title
	result.position = point
	result.size = Vector2(53, 13)
	result.flat = true
	result.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		result.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	result.pressed.connect(callback)
	bookmark_root.add_child(result)
	return result


func _style_bookmark(button: Button, index: int, active: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill: Color = COLORS[index].lightened(0.25 if active or state in ["hover", "focus"] else 0)
		var img := Image.new()
		img.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="35" height="49"><path d="M1 1 H34 V48 L17.5 41 L1 48 Z" fill="%s" stroke="#ebd5a1" stroke-width="1.2"/></svg>' % ("#" + fill.to_html(false)))
		var box := StyleBoxTexture.new()
		box.texture = ImageTexture.create_from_image(img)
		box.set_texture_margin_all(3)
		box.content_margin_bottom = 8
		button.add_theme_stylebox_override(state, box)


func _label(text: String, point: Vector2, font_size: int, color: Color) -> Label:
	var result := STYLE.FontStyle.label(text, point, font_size, color)
	add_child(result)
	return result


func _button(text: String, point: Vector2, extent: Vector2, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.position = point
	result.size = extent
	STYLE.button(result, 24)
	result.pressed.connect(callback)
	add_child(result)
	return result
