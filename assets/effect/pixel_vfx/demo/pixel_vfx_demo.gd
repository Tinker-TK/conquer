extends Control
## 本地素材浏览器：所有数据来自同目录 catalog.json，不依赖游戏单例。

const BASE := "res://assets/effect/pixel_vfx/"
var data: Dictionary
var items: Array
var filtered: Array[int] = []
var current_index := -1
var effect_node: Node2D
var preview: Control
var list: ItemList
var info: Label
var search: LineEdit
var cc0: CheckBox
var pause: CheckBox
var zoom: HSlider
var idle_time := 0.0

func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(BASE + "catalog.json"))
	items = data["items"]
	var bg := ColorRect.new()
	bg.color = Color("141b2c")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 370
	row.add_child(left)
	var title := Label.new()
	title.text = "像素特效素材库 · %d 项" % items.size()
	title.add_theme_font_size_override("font_size", 24)
	left.add_child(title)
	search = LineEdit.new()
	search.placeholder_text = "搜索名称、分类、作者、许可"
	search.text_changed.connect(func(_text: String) -> void: _filter())
	left.add_child(search)
	cc0 = CheckBox.new()
	cc0.text = "只看 CC0"
	cc0.toggled.connect(func(_on: bool) -> void: _filter())
	left.add_child(cc0)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.y = 240
	list.item_selected.connect(func(index: int) -> void: show_item(filtered[index]))
	left.add_child(list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	preview = Control.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size.y = 260
	preview.clip_contents = true
	preview.resized.connect(_fit)
	right.add_child(preview)
	var tools := HBoxContainer.new()
	right.add_child(tools)
	var replay := Button.new()
	replay.text = "重播"
	replay.pressed.connect(_replay)
	tools.add_child(replay)
	pause = CheckBox.new()
	pause.text = "暂停"
	pause.toggled.connect(_pause)
	tools.add_child(pause)
	var copy := Button.new()
	copy.text = "复制场景路径"
	copy.pressed.connect(func() -> void:
		if current_index >= 0:
			DisplayServer.clipboard_set(items[current_index]["godot_path"]))
	tools.add_child(copy)
	zoom = HSlider.new()
	zoom.min_value = 1
	zoom.max_value = 6
	zoom.step = 1
	zoom.value = 3
	zoom.custom_minimum_size.x = 200
	zoom.value_changed.connect(func(_value: float) -> void: _fit())
	tools.add_child(zoom)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.y = 190
	info.add_theme_font_size_override("font_size", 18)
	right.add_child(info)
	_filter()

func _filter() -> void:
	list.clear()
	filtered.clear()
	var query := search.text.to_lower()
	for i in items.size():
		var item: Dictionary = items[i]
		var pack: Dictionary = data["packs"][item["pack"]]
		if cc0.button_pressed and not pack["cc0"]:
			continue
		var text := "%s %s %s %s %s" % [item["title"], item["name"], item["category"], pack["title"], pack["license"]]
		if not query.is_empty() and not query in text.to_lower():
			continue
		filtered.append(i)
		list.add_item("%s · %s" % [item["category"], item["title"]])
	if not filtered.is_empty():
		list.select(0)
		show_item(filtered[0])

func show_item(index: int) -> void:
	if is_instance_valid(effect_node):
		effect_node.free()
	current_index = index
	idle_time = 0.0
	var item: Dictionary = items[index]
	var pack: Dictionary = data["packs"][item["pack"]]
	var scene: PackedScene = load(item["godot_path"])
	effect_node = scene.instantiate()
	preview.add_child(effect_node)
	info.text = "%s / %s\n%s · %s · %d×%d · %d 帧\n%s\n许可：%s%s\n%s\n%s" % [pack["title"], item["title"], item["category"], item["kind"], item["width"], item["height"], item["frame_count"], item["timing"], pack["license"], "（需要署名）" if pack["credit_required"] else "", item.get("note", ""), item["godot_path"]]
	_fit()
	_pause(pause.button_pressed)

func _fit() -> void:
	if not is_instance_valid(effect_node) or current_index < 0:
		return
	var item: Dictionary = items[current_index]
	var fit_scale := minf((preview.size.x - 30) / item["width"], (preview.size.y - 30) / item["height"])
	effect_node.scale = Vector2.ONE * maxf(0.25, minf(zoom.value if zoom else 3.0, fit_scale))
	effect_node.position = preview.size / 2.0

func _pause(on: bool) -> void:
	if not is_instance_valid(effect_node): return
	if effect_node is AnimatedSprite2D:
		if on: effect_node.pause()
		else: effect_node.play()
	else:
		effect_node.set_process(not on)

func _replay() -> void:
	if not is_instance_valid(effect_node): return
	pause.button_pressed = false
	if effect_node is AnimatedSprite2D:
		effect_node.frame = 0
	effect_node.play()
	idle_time = 0.0

func _process(delta: float) -> void:
	if not is_instance_valid(effect_node) or pause.button_pressed: return
	var done: bool = not effect_node.is_playing() if effect_node is AnimatedSprite2D else not effect_node.playing
	if done:
		idle_time += delta
		if idle_time > 0.6: _replay()
