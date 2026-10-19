## 所有来源共用满格选择；未决新瓶单独保存，不静默覆盖库存。
extends CanvasLayer

var run: Node
var serial := 0
var was_paused := false
var column: VBoxContainer

func open(owner_run: Node) -> void:
	run = owner_run
	serial = run.run_serial
	layer = 180
	process_mode = Node.PROCESS_MODE_ALWAYS
	was_paused = get_tree().paused
	get_tree().paused = true
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.05, 0.96)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	column = VBoxContainer.new()
	column.custom_minimum_size.x = 760
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)
	_refresh()

func _refresh() -> void:
	for node in column.get_children():
		column.remove_child(node)
		node.queue_free()
	if serial != run.run_serial or run.pending_potions.is_empty():
		_close()
		return
	var incoming: PotionDefinition = run.pending_potions[0]
	var title := Label.new()
	title.text = "药水带已满（%d/%d）" % [run.potions.size(), run.potion_capacity]
	title.add_theme_font_size_override("font_size", 34)
	column.add_child(title)
	var description := Label.new()
	description.text = "获得：%s\n%s\n选择替换一瓶，或放弃新药水。" % [incoming.display_name, incoming.description]
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 24)
	column.add_child(description)
	for index in run.potions.size():
		var owned: PotionDefinition = run.potions[index]
		var button := Button.new()
		button.text = "替换 %s" % owned.display_name
		button.tooltip_text = owned.description
		button.custom_minimum_size.y = 58
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(_choose.bind(index))
		column.add_child(button)
	var decline := Button.new()
	decline.text = "放弃新药水 · 保留当前药水"
	decline.custom_minimum_size.y = 58
	decline.add_theme_font_size_override("font_size", 24)
	decline.pressed.connect(_choose.bind(-1))
	column.add_child(decline)

func _choose(index: int) -> void:
	if serial == run.run_serial:
		run.resolve_potion_overflow(index)
	_refresh()

func _close() -> void:
	get_tree().paused = was_paused
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(run) and serial == run.run_serial:
		get_tree().paused = was_paused
