# 双击查看敌我单位、右键查看兵种牌；详情只读，卡牌预览不创建战斗单位。
# 属性每 0.1 秒刷新，冷却遮罩每帧读取真实 Timer；不重建正在滚动、悬停的控件。
extends Control

const UI = preload("res://scripts/ui/pixel_ui_style.gd")
const DetailIcon := preload("res://scripts/ui/unit_detail_icon.gd")
const SWORD := preload("res://assets/ui_redrawn/icons/equipment_sword.png")
const SHIELD := preload("res://assets/ui_redrawn/status/shield.png")
const HEART := preload("res://assets/ui_redrawn/icons/heart.png")
const BOOT := preload("res://assets/ui_redrawn/icons/relic_boot.png")
const SLASH := preload("res://assets/ui_redrawn/icons/crossed_swords.png")
const HEAL := preload("res://assets/ui_redrawn/status/healing.png")
const TEXT := UI.INK
const MUTED := Color("5b5550")
const GREEN := "246746"
const RED := "a73538"
const BAR_FILL = preload("res://assets/ui/UI Elements/Bars/SmallBar_Fill.png")

var battle: Node2D
var inspected: UnitBase
var card_preview: CardInstance
var preview_source: WeakRef
var preview_data: UnitData
var panel: PanelContainer
var close_button: Button
var unit_title: RichTextLabel
var portrait: TextureRect
var health_text: Label
var health_bar: ProgressBar
var stat_labels: Dictionary = {}
var scroll: ScrollContainer
var status_grid: GridContainer
var no_status: Label
var skill_list: VBoxContainer
var status_cells: Dictionary = {}
var skill_cells: Array[Dictionary] = []
var refresh_clock := 0.0
var hover_clock := 0.0
var mouse_position := Vector2.ZERO
var status_tooltip: PanelContainer
var status_text: Label
var footer: Label


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = Theme.new()
	theme.default_font = UI.FONT.chinese()
	panel = PanelContainer.new()
	panel.name = "DetailsPanel"
	panel.add_theme_stylebox_override("panel", UI.panel(Vector2(18, 18)))
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	heading.add_theme_constant_override("separation", 8)
	var title := _label("单位详情", 23)
	UI.caption(title, "blue", 23)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.custom_minimum_size = Vector2(44, 44)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.button(close_button, 22)
	var close_icon := AtlasTexture.new()
	close_icon.atlas = preload("res://assets/ui/Icons/Regular_01.png")
	close_icon.region = Rect2(13, 6, 38, 38)
	close_button.icon = close_icon
	close_button.expand_icon = true
	close_button.add_theme_constant_override("icon_max_width", 28)
	close_button.tooltip_text = "关闭单位详情"
	close_button.pressed.connect(close_details)
	heading.add_child(close_button)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_scrollbar(scroll.get_v_scroll_bar())
	column.add_child(scroll)
	# 竖向滚动条覆盖在内容右侧，预留边距，避免生命数值和技能文字被遮住。
	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override("margin_right", 16)
	scroll.add_child(content_margin)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	content_margin.add_child(body)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 12)
	body.add_child(identity)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	identity.add_child(portrait)
	unit_title = _rich(23)
	unit_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_child(unit_title)
	var life := HBoxContainer.new()
	life.add_theme_constant_override("separation", 8)
	body.add_child(life)
	life.add_child(_small_icon(HEART))
	life.add_child(_label("生命", 18, MUTED))
	health_bar = ProgressBar.new()
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(90, 19)
	health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 原图集端帽自带深色内区，盖在填充上会形成两个黑块；使用连续的细边框。
	var bar_frame := StyleBoxFlat.new()
	bar_frame.bg_color = Color("633b36")
	bar_frame.border_color = Color("a28b5c")
	bar_frame.set_border_width_all(2)
	bar_frame.set_content_margin_all(3)
	health_bar.add_theme_stylebox_override("background", bar_frame)
	var bar_fill := UI.texture_box(BAR_FILL, Vector2(1, 0), Vector2.ZERO)
	bar_fill.region_rect = Rect2(0, 30, 64, 3)
	health_bar.add_theme_stylebox_override("fill", bar_fill)
	life.add_child(health_bar)
	# ProgressBar 的填充会覆盖背景边缘，最后只描一次细边，避免满血时丢失轮廓。
	var bar_outline := Panel.new()
	var outline_style := bar_frame.duplicate() as StyleBoxFlat
	outline_style.draw_center = false
	bar_outline.add_theme_stylebox_override("panel", outline_style)
	bar_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.add_child(bar_outline)
	bar_outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	health_text = _label("", 18, Color(GREEN))
	life.add_child(health_text)
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 8)
	stats.add_theme_constant_override("v_separation", 6)
	body.add_child(stats)
	for item in [["attack", SWORD], ["defence", SHIELD], ["speed", BOOT], ["dodge", null]]:
		var cell := PanelContainer.new()
		cell.custom_minimum_size.y = 36
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var stat_frame := StyleBoxEmpty.new()
		stat_frame.content_margin_left = 4
		stat_frame.content_margin_right = 4
		stat_frame.content_margin_top = 6
		stat_frame.content_margin_bottom = 6
		cell.add_theme_stylebox_override("panel", stat_frame)
		stats.add_child(cell)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		cell.add_child(row)
		if item[1] != null:
			var icon := _small_icon(item[1])
			icon.custom_minimum_size = Vector2(18, 18)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(icon)
		var label := _rich(16)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		stat_labels[item[0]] = label
	body.add_child(_section("状态"))
	status_grid = GridContainer.new()
	status_grid.columns = 6
	status_grid.add_theme_constant_override("h_separation", 9)
	status_grid.add_theme_constant_override("v_separation", 8)
	body.add_child(status_grid)
	no_status = _label("暂无状态", 16, MUTED)
	body.add_child(no_status)
	body.add_child(_section("技能"))
	skill_list = VBoxContainer.new()
	skill_list.add_theme_constant_override("separation", 8)
	body.add_child(skill_list)
	footer = _label("双击单位查看  ·  点击 × 关闭", 14, MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)
	panel.hide()
	status_tooltip = PanelContainer.new()
	status_tooltip.name = "StatusTooltip"
	status_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_tooltip.z_index = 20
	status_tooltip.add_theme_stylebox_override("panel", _info_panel(Vector2(16, 14)))
	add_child(status_tooltip)
	status_text = _label("", 16, TEXT)
	status_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_text.custom_minimum_size.x = 300
	status_tooltip.add_child(status_text)
	status_tooltip.hide()
	mouse_position = get_viewport().get_mouse_position()


func _info_panel(padding: Vector2) -> StyleBoxTexture:
	var style := UI.panel(padding)
	style.modulate_color = Color(1.12, 1.12, 1.03)
	return style


func _style_scrollbar(bar: VScrollBar) -> void:
	bar.custom_minimum_size.x = 12
	bar.add_theme_stylebox_override("scroll", UI.texture_box(UI.CARVED, Vector2(6, 6), Vector2.ZERO))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var style := UI.texture_box(UI.BLUE_SMALL_DOWN if state == "grabber_pressed" else UI.BLUE_SMALL, Vector2(12, 12), Vector2.ZERO)
		style.region_rect = Rect2(0, 0, 64, 56)
		bar.add_theme_stylebox_override(state, style)


func _label(text: String, font_size: int, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _rich(font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.y = font_size + 8
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", TEXT)
	return label


func _small_icon(texture: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _section(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var title := _label(text, 18)
	UI.caption(title, "yellow", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	return row


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_position = event.position
		update_hover(mouse_position)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT \
		or not event.pressed or not event.double_click or not _can_inspect():
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != battle.card_ui.get_node("PlayerDeployDropZone"):
		return
	mouse_position = event.position
	var point: Vector2 = battle.get_canvas_transform().affine_inverse() * event.position
	var target := pick_unit(point)
	if target != null:
		open_unit(target)
		get_viewport().set_input_as_handled()


func _can_inspect() -> bool:
	return is_instance_valid(battle) and is_instance_valid(battle.card_runtime) and not battle.battle_finished \
		and not get_tree().paused and is_visible_in_tree() and not get_viewport().gui_is_dragging() \
		and (not is_instance_valid(RunManager.item_battle) or RunManager.item_battle.potion == null)


func _details_allowed() -> bool:
	if card_preview == null:
		return _can_inspect()
	var source = preview_source.get_ref() if preview_source != null else null
	return is_visible_in_tree() and is_instance_valid(source) and source.is_visible_in_tree() and source.can_process() \
		and not source.is_queued_for_deletion() and source.mouse_filter != Control.MOUSE_FILTER_IGNORE \
		and not get_viewport().gui_is_dragging()


func update_hover(screen_position: Vector2) -> void:
	status_tooltip.hide()
	if not _details_allowed():
		close_details()
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if panel.visible and hovered != null and (hovered == panel or panel.is_ancestor_of(hovered)):
		# 容器裁剪外的图标、文字和技能都不能冒充状态图标命中。
		if scroll.get_global_rect().has_point(screen_position):
			for cell: Dictionary in status_cells.values():
				if hovered == cell.icon or cell.icon.is_ancestor_of(hovered):
					_show_tooltip(String(cell.entry.tooltip), screen_position)
					break
		return
	if card_preview != null:
		return
	if hovered != null and hovered != battle.card_ui.get_node("PlayerDeployDropZone"):
		return
	_show_status_at(screen_position)


func _show_status_at(screen_position: Vector2) -> bool:
	var selected: UnitBase = null
	var entry: Dictionary = {}
	for unit in battle.card_runtime.living_units():
		var display: Control = unit.get_node_or_null("HealthBar/StatusDisplay")
		if display == null:
			continue
		var candidate: Dictionary = display.status_at(screen_position)
		if not candidate.is_empty() and (selected == null or unit.global_position.y >= selected.global_position.y):
			selected = unit
			entry = candidate
	if entry.is_empty():
		return false
	_show_tooltip(String(entry.tooltip), screen_position)
	return true


func _show_tooltip(text: String, screen_position: Vector2) -> void:
	status_text.text = text
	status_tooltip.reset_size()
	var local_point := get_global_transform_with_canvas().affine_inverse() * screen_position
	var bounds := get_viewport_rect().size
	var next_position := local_point + Vector2(14, 18)
	if next_position.x + status_tooltip.size.x > bounds.x - 8:
		next_position.x = local_point.x - status_tooltip.size.x - 14
	if next_position.y + status_tooltip.size.y > bounds.y - 8:
		next_position.y = local_point.y - status_tooltip.size.y - 12
	status_tooltip.position = next_position.clamp(Vector2.ONE * 8, (bounds - status_tooltip.size - Vector2.ONE * 8).max(Vector2.ONE * 8))
	status_tooltip.show()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED, NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_DRAG_BEGIN]:
		if is_instance_valid(status_tooltip):
			status_tooltip.hide()
		if is_instance_valid(panel) and (what != NOTIFICATION_VISIBILITY_CHANGED or not is_visible_in_tree()):
			close_details()


func pick_unit(point: Vector2) -> UnitBase:
	var result: UnitBase
	var closest := 65.0
	for unit in battle.card_runtime.living_units():
		var marker := unit.get_node_or_null("CastTargetCenter") as Node2D
		var center: Vector2 = marker.global_position if marker != null else unit.global_position
		var distance := center.distance_to(point)
		if distance < closest:
			result = unit
			closest = distance
	return result


func open_unit(unit: UnitBase) -> void:
	card_preview = null
	preview_source = null
	preview_data = null
	inspected = unit
	footer.text = "双击单位查看  ·  点击 × 关闭"
	_open_panel(unit.unit_data)
	refresh_details()


func open_card(card: CardInstance, source: Control) -> void:
	if card == null or not card.is_unit_card():
		return
	inspected = null
	card_preview = card
	preview_source = weakref(source)
	footer.text = "右键兵种牌查看  ·  点击 × 或 Esc 关闭"
	_open_panel(card.unit_data)
	refresh_details()


func _open_panel(data: UnitData) -> void:
	status_tooltip.hide()
	refresh_clock = 0.0
	for cell: Dictionary in status_cells.values():
		cell.root.free()
	status_cells.clear()
	for cell: Dictionary in skill_cells:
		cell.root.free()
	skill_cells.clear()
	scroll.scroll_vertical = 0
	var ally := data.unit_team == "team_a"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT if ally else Control.PRESET_TOP_RIGHT)
	panel.offset_left = 20 if ally else -450
	panel.offset_right = 450 if ally else -20
	panel.offset_top = 180
	panel.offset_bottom = minf(920, get_viewport_rect().size.y - 30)
	portrait.texture = data.card_image_2 if data.card_image_2 != null else data.card_image
	if portrait.texture == null and is_instance_valid(inspected):
		var sprite := inspected.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite != null and sprite.sprite_frames != null:
			var frame := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
			portrait.texture = frame
			if frame != null:
				var bounds := frame.get_image().get_used_rect()
				if bounds.has_area():
					var atlas := AtlasTexture.new()
					atlas.atlas = frame
					atlas.region = bounds
					portrait.texture = atlas
	panel.show()


func close_details() -> void:
	inspected = null
	card_preview = null
	preview_source = null
	preview_data = null
	panel.hide()
	status_tooltip.hide()


func _process(delta: float) -> void:
	if panel.visible and (not _details_allowed() or (card_preview == null and (not is_instance_valid(inspected) \
		or not inspected.is_inside_tree() or inspected.is_queued_for_deletion() or inspected.current_state == UnitBase.State.DEATH))):
		close_details()
	refresh_clock += delta
	if panel.visible:
		if refresh_clock >= 0.1:
			refresh_clock = 0.0
			refresh_details()
		_refresh_cooldowns()
	hover_clock += delta
	if hover_clock >= 0.05:
		hover_clock = 0.0
		update_hover(mouse_position)


func refresh_details() -> void:
	if card_preview != null:
		_refresh_card_details()
		return
	if not is_instance_valid(inspected):
		close_details()
		return
	var data := inspected.unit_data
	var state: Dictionary = battle.card_runtime.states.get(inspected.get_instance_id(), {})
	var deltas := {"attack": int(state.get("aura_bonus", 0)) + inspected.protection_attack_bonus + inspected.consecutive_attack_bonus + inspected.soldier_attack_bonus, "defence": inspected.taunt_defence_bonus - inspected.status_runtime.total_amount(&"armor_break"), "max_hp": 0,
		"speed": inspected.get_movement_speed() - float(state.get("base_speed", data.speed))}
	var keys := {CardEffect.Kind.ATTACK_UP: "attack", CardEffect.Kind.DEFENCE_UP: "defence", CardEffect.Kind.MAX_HP_UP: "max_hp"}
	for buff: Dictionary in state.get("buffs", []):
		if keys.has(buff.effect.kind):
			deltas[keys[buff.effect.kind]] += int(buff.effect.amount)
	var tactical: Dictionary = battle.card_runtime.tactics.records.get(inspected.get_instance_id(), {})
	deltas.attack += int(tactical.get("attack_delta", 0))
	deltas.defence += int(tactical.get("defence_delta", 0))
	_show_values(data, int(inspected.current_health), deltas)
	stat_labels.speed.text = "移速：%.1f%s" % [inspected.get_movement_speed(), _delta_text(deltas.speed, true)]
	var display = inspected.get_node_or_null("HealthBar/StatusDisplay")
	_sync_statuses(display.statuses if display != null else [], state, deltas)
	_sync_skills()
	_refresh_cooldowns()
	update_hover(mouse_position)


func _show_values(data: UnitData, health: int, deltas: Dictionary) -> void:
	unit_title.text = "%s · [color=%s]%s[/color]" % [data.unit_name.replace("[", "[lb]"), "236270" if data.unit_team == "team_a" else RED, "兵种牌" if card_preview != null else "己方" if data.unit_team == "team_a" else "敌方"]
	if data.unit_team == "team_b":
		unit_title.text += " · " + ["普通", "精英", "首领", "传说"][data.monster_rank]
	health_text.text = "%d / %d" % [health, data.max_hp]
	health_bar.max_value = maxi(1, data.max_hp)
	health_bar.value = health
	stat_labels.attack.text = "攻击：%d%s" % [data.attack, _delta_text(deltas.attack)]
	stat_labels.defence.text = "防御：%d%s" % [data.defence, _delta_text(deltas.defence)]
	stat_labels.speed.text = "移速：%.1f%s" % [data.speed, _delta_text(deltas.speed, true)]
	stat_labels.dodge.text = "闪避：%.0f%%" % (data.dodge_rate * 100.0)


# 预览出场数值：只复制资源，叠加本张牌训练、已保存的永久强化及自带单位强化。
func _refresh_card_details() -> void:
	preview_data = card_preview.get_summon_data()
	var state := {"buffs": [], "explosions": []}
	var deltas := {"attack": card_preview.attack_points, "defence": card_preview.defence_points, "max_hp": 0, "speed": 0.0}
	for training in [[CardEffect.Kind.ATTACK_UP, card_preview.attack_points], [CardEffect.Kind.DEFENCE_UP, card_preview.defence_points]]:
		if int(training[1]) == 0:
			continue
		var effect := CardEffect.new()
		effect.kind = training[0]
		effect.amount = training[1]
		effect.lifetime = CardEffect.Lifetime.RUN
		state.buffs.append({"effect": effect, "label": "兵种训练", "left": 0})
	var added: Array = card_preview.permanent_buffs.duplicate()
	for effect: CardEffect in card_preview.definition.effects:
		if effect != null and effect.is_unit_buff():
			added.append({"effect": effect, "label": card_preview.definition.card_name})
	var properties := {CardEffect.Kind.ATTACK_UP: "attack", CardEffect.Kind.DEFENCE_UP: "defence", CardEffect.Kind.MAX_HP_UP: "max_hp"}
	for saved: Dictionary in added:
		var effect: CardEffect = saved.effect
		if effect == null or not effect.is_unit_buff():
			continue
		state.buffs.append({"effect": effect, "label": saved.label, "left": effect.lasting_rounds})
		if properties.has(effect.kind):
			var key: String = properties[effect.kind]
			preview_data.set(key, int(preview_data.get(key)) + int(effect.amount))
			deltas[key] += int(effect.amount)
		elif effect.kind == CardEffect.Kind.DEATH_EXPLOSION:
			state.explosions.append(effect)
	var icons := {CardEffect.Kind.ATTACK_UP: "attack", CardEffect.Kind.DEFENCE_UP: "defence", CardEffect.Kind.MAX_HP_UP: "max_hp", CardEffect.Kind.POISON_ON_HIT: "poison_on_hit", CardEffect.Kind.DEATH_EXPLOSION: "explosion"}
	var names := {CardEffect.Kind.ATTACK_UP: "攻击力提升", CardEffect.Kind.DEFENCE_UP: "防御力提升", CardEffect.Kind.MAX_HP_UP: "最大生命提升", CardEffect.Kind.POISON_ON_HIT: "攻击附毒", CardEffect.Kind.DEATH_EXPLOSION: "死亡爆炸"}
	var entries: Array = []
	for kind in icons:
		var has_effect := false
		var total := 0
		for buff: Dictionary in state.buffs:
			if buff.effect.kind != kind:
				continue
			has_effect = true
			total += int(buff.effect.amount)
		if has_effect:
			var summary := "%s：%+d" % [names[kind], total]
			if kind == CardEffect.Kind.POISON_ON_HIT:
				summary = "攻击附毒：每次命中叠加 %d 层毒" % total
			elif kind == CardEffect.Kind.DEATH_EXPLOSION:
				summary = "死亡爆炸：总伤害 %d" % total
			entries.append({"icon": icons[kind], "tooltip": summary})
	if preview_data.has_sword_arrow():
		entries.append({"icon": "sword_arrow", "tooltip": UnitData.sword_arrow_description()})
	_show_values(preview_data, preview_data.max_hp, deltas)
	_sync_statuses(entries, state, deltas)
	_sync_skills()
	_refresh_cooldowns()
	update_hover(mouse_position)


func _delta_text(amount: float, decimal: bool = false) -> String:
	if is_zero_approx(amount):
		return ""
	var number := "%+.1f" % amount if decimal else "%+d" % int(amount)
	return " [color=%s](%s)[/color]" % [GREEN if amount > 0 else RED, number]


func _sync_statuses(entries: Array, state: Dictionary, deltas: Dictionary) -> void:
	var names := {"attack": "攻击", "defence": "防御", "max_hp": "生命", "poison": "毒", "poison_on_hit": "附毒", "explosion": "死亡爆炸", "mud": "减速", "burn": "灼烧", "sword_arrow": "剑矢", "protection": "庇护", "consecutive_attack": "连击", "soldier_growth": "士兵成长", "missile_mark": "飞弹标记", "stealth": "隐身"}
	names.merge({"weakness": "虚弱", "defence_down": "恐吓", "vulnerability": "易伤", "paralysis": "麻痹", "stun": "眩晕", "frenzy": "狂化", "lifesteal": "吸血", "composition": "搭配", "distance": "距离", "judger": "审判者", "converted": "策反"})
	names.merge({"taunt": "嘲讽", "taunt_guard": "嘲讽防御", "armor_break": "反击破甲"})
	names["seventh_strike"] = "七伤"
	names.merge({"bleed": "流血", "confusion": "混乱", "mortal_wounds": "禁止治疗", "sleep": "睡眠"})
	var textures := {"attack": SWORD, "defence": SHIELD, "max_hp": HEART, "mud": BOOT}
	var kinds := {"attack": CardEffect.Kind.ATTACK_UP, "defence": CardEffect.Kind.DEFENCE_UP,
		"max_hp": CardEffect.Kind.MAX_HP_UP, "poison_on_hit": CardEffect.Kind.POISON_ON_HIT, "explosion": CardEffect.Kind.DEATH_EXPLOSION}
	var incoming: Array[String] = []
	for entry: Dictionary in entries:
		incoming.append(String(entry.icon))
	for key: String in status_cells.keys():
		if not incoming.has(key):
			status_cells[key].root.free()
			status_cells.erase(key)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var key := String(entry.icon)
		if not status_cells.has(key):
			var column := VBoxContainer.new()
			column.custom_minimum_size.x = 50
			column.add_theme_constant_override("separation", 2)
			status_grid.add_child(column)
			var icon := DetailIcon.new()
			icon.custom_minimum_size = Vector2(50, 50)
			icon.texture = textures.get(key)
			icon.symbol = key
			column.add_child(icon)
			var new_badge := _label("", 13)
			new_badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			new_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			new_badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			new_badge.add_theme_constant_override("outline_size", 3)
			new_badge.add_theme_color_override("font_outline_color", Color("08121e"))
			icon.add_child(new_badge)
			var caption := _label(names.get(key, key), 12)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(caption)
			var duration := _label("", 11, MUTED)
			duration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(duration)
			status_cells[key] = {"root": column, "icon": icon, "badge": new_badge, "duration": duration}
		var cell: Dictionary = status_cells[key]
		cell.entry = entry.duplicate(true)
		status_grid.move_child(cell.root, index)
		var total := 0
		var durations: Array[String] = []
		if key == "sword_arrow":
			durations.append("卡牌强化")
		for buff: Dictionary in state.get("buffs", []):
			if kinds.has(key) and buff.effect.kind == kinds[key]:
				total += int(buff.effect.amount)
				var text := "本场战斗"
				if buff.effect.lifetime == CardEffect.Lifetime.ROUNDS:
					text = "%d 回合" % int(buff.left)
				elif buff.effect.lifetime == CardEffect.Lifetime.RUN:
					text = "本局永久"
				if not durations.has(text):
					durations.append(text)
		var badge := str(entry.get("count", ""))
		if key in ["attack", "defence", "max_hp"]:
			badge = "%+d" % int(deltas[key])
		elif key == "poison_on_hit":
			badge = str(total)
		elif key == "explosion":
			badge = str(state.get("explosions", []).size())
		elif key == "mud":
			badge = "%.0f" % float(deltas.speed)
		cell.badge.text = badge
		cell.badge.add_theme_color_override("font_color", Color("ff9e8e" if key == "mud" else "b8f19c" if key in ["attack", "defence", "max_hp"] else "fff1cd"))
		cell.duration.text = durations[0] if durations.size() == 1 else "多种期限" if durations.size() > 1 else ""
		cell.duration.visible = not cell.duration.text.is_empty()
	no_status.visible = entries.is_empty()
	status_grid.visible = not entries.is_empty()


func _sync_skills() -> void:
	var skills: Array[SkillBase] = []
	var data: UnitData = preview_data if card_preview != null else inspected.unit_data
	# 保持兵种资源中的展示顺序；战斗选择技能的优先级由管理器独立处理。
	for skill: SkillBase in data.skills:
		if skill != null and (card_preview != null or inspected.skill_manager.group_skills.has(skill)) and not skills.has(skill):
			skills.append(skill)
	if card_preview == null:
		for skill: SkillBase in inspected.skill_manager.group_skills:
			if not skills.has(skill):
				skills.append(skill)
	if data.is_skill_unlocked(data.dodge_skill) and not skills.has(data.dodge_skill):
		skills.append(data.dodge_skill)
	var previous: Array[SkillBase] = []
	for cell: Dictionary in skill_cells:
		previous.append(cell.skill)
	if previous != skills:
		for cell: Dictionary in skill_cells:
			cell.root.free()
		skill_cells.clear()
		for skill: SkillBase in skills:
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", _info_panel(Vector2(14, 12)))
			skill_list.add_child(card)
			var column := VBoxContainer.new()
			column.add_theme_constant_override("separation", 5)
			card.add_child(column)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			column.add_child(row)
			var icon := DetailIcon.new()
			icon.custom_minimum_size = Vector2(58, 58)
			icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			icon.texture = SHIELD if skill.is_passive() else HEAL if skill.target_type == SkillBase.TargetType.ALLY_LOWEST_HP else SLASH if skill.attack_rate > 1.0 else SWORD
			if skill.is_passive() and not skill.passive_icon().is_empty():
				icon.texture = null
				icon.symbol = skill.passive_icon()
			row.add_child(icon)
			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var title := _rich(20)
			info.add_child(title)
			var parameters := _rich(14)
			info.add_child(parameters)
			var description := _rich(15)
			column.add_child(description)
			skill_cells.append({"root": card, "skill": skill, "icon": icon, "title": title, "parameters": parameters, "description": description})
	for cell: Dictionary in skill_cells:
		var skill: SkillBase = cell.skill
		cell.title.text = skill.skill_name.replace("[", "[lb]")
		if skill.is_passive():
			cell.parameters.text = skill.passive_parameters()
			cell.description.text = skill.effect_description().replace("[", "[lb]")
			continue
		var reaction := data.dodge_skill == skill
		var sword_arrow: bool = data.is_basic_attack(skill) and data.has_sword_arrow()
		var attack_range: float = 300.0 if sword_arrow else skill.cast_range
		var range_text := "全地图" if skill.is_global_cast() else "%.0f" % attack_range
		cell.parameters.text = "基础 CD：%.1f 秒   范围：%s\n倍率：%.2f%s" % [skill.cooldown, range_text, skill.attack_rate, "  ·  闪避触发" if reaction else ""]
		if "projectile_damage" in skill:
			cell.parameters.text = "基础 CD：%.1f 秒   范围：%s\n每颗固定伤害：%d" % [skill.cooldown, range_text, skill.projectile_damage]
		if skill.chant_duration > 0.0:
			cell.parameters.text += "  咏唱：%.1f 秒" % skill.chant_duration
		if card_preview == null and not is_equal_approx(inspected.skill_manager.cooldown_multiplier, 1.0):
			cell.parameters.text += "\n[color=#%s]当前 CD：%.1f 秒[/color]" % [GREEN, skill.cooldown * inspected.skill_manager.cooldown_multiplier]
		var description := skill.effect_description()
		if reaction and data.card_upgrade_level >= 1 and "upgraded_stun_duration" in skill and skill.upgraded_stun_duration > 0:
			description += "\n反击命中后眩晕%.0f秒。" % skill.upgraded_stun_duration
		if description.is_empty() and skill.get_script().resource_path == "res://scripts/skills/normal_attack.gd":
			description = "对目标造成攻击力 %.0f%% 的伤害。" % (skill.attack_rate * 100.0)
		if sword_arrow:
			description += "\n远程剑矢与近战普攻共用冷却，敌人进入原近战范围（%.0f）后使用近战。" % skill.cast_range
		cell.description.text = description.replace("[", "[lb]") if not description.is_empty() else "尚未填写技能介绍"


func _refresh_cooldowns() -> void:
	if card_preview != null:
		for cell: Dictionary in skill_cells:
			cell.icon.cooldown_fraction = 0.0
		return
	if not is_instance_valid(inspected):
		return
	for cell: Dictionary in skill_cells:
		cell.icon.cooldown_fraction = inspected.skill_manager.get_cooldown_fraction(cell.skill)
