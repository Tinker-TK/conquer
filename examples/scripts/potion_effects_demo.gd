## F6 药水实验场：使用正式库存、目标选择和战斗运行器，独立于正式开局配置。
extends Node

const CATALOG = preload("res://scripts/items/potion_catalog.gd")
var battle: Node2D
var items: Node2D
var message: Label
var phase_button: Button
var freeze_units: CheckBox


func _ready() -> void:
	RunManager.start_new_run()
	RunManager.relics.clear()
	RunManager.potions.clear()
	RunManager.hp = 50
	battle = preload("res://scenes/battle/battle_scene.tscn").instantiate()
	add_child(battle)
	items = battle.get_node("BattleItems")
	for child in battle.get_node("Entities/TeamB").get_children():
		child.free()
	spawn_allies()
	spawn_enemies()
	_build_panel()
	if "--capture-potions" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(140, 34)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 135)
	panel.size = Vector2(460, 790)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var title := Label.new()
	title.text = "药水实验场 · 40 瓶"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "13 普通 / 17 稀有 / 10 传说\n点击药水后，在战场选择落点或目标。"
	column.add_child(subtitle)
	var controls := GridContainer.new()
	controls.columns = 3
	column.add_child(controls)
	phase_button = _button(controls, "开始交锋", toggle_phase)
	_button(controls, "补充友军", spawn_allies)
	_button(controls, "补充敌军", spawn_enemies)
	_button(controls, "制造阵亡", kill_ally)
	_button(controls, "玩家受伤", func(): RunManager.hp = maxi(1, RunManager.hp - 25))
	_button(controls, "重置实验", func(): get_tree().reload_current_scene())
	freeze_units = CheckBox.new()
	freeze_units.text = "固定单位位置，方便观察范围效果"
	freeze_units.button_pressed = true
	freeze_units.toggled.connect(_freeze)
	column.add_child(freeze_units)
	_freeze(true)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 52
	message.text = "非伤害药水可在准备阶段使用；圣盾限交锋。"
	column.add_child(message)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 510)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var recipes := CATALOG.all_potions()
	recipes.sort_custom(func(a: PotionDefinition, b: PotionDefinition): return a.rarity < b.rarity if a.rarity != b.rarity else a.id < b.id)
	for recipe in recipes:
		var button := _button(grid, recipe.display_name, _select.bind(recipe))
		button.custom_minimum_size = Vector2(210, 42)
		button.icon = recipe.icon
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 30)
		button.tooltip_text = recipe.description
		button.modulate = [Color("e2e7e9"), Color("9dc8ff"), Color("f6d991")][recipe.rarity]


func toggle_phase() -> void:
	if Global.game_phase == Global.GamePhase.AUTO_BATTLE:
		Global.game_phase = Global.GamePhase.CARD_PLAY
		battle.battle_round_manager.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
		phase_button.text = "开始交锋"
	else:
		battle.battle_round_manager.start_auto_battle()
		phase_button.text = "返回准备"


func _select(recipe: PotionDefinition) -> void:
	items._cancel_aim()
	if items.potion != null and not items.committed:
		items.clear_effect()
	var owned: PotionDefinition
	for potion in RunManager.potions:
		if potion.id == recipe.id:
			owned = potion
			break
	if owned == null:
		if not RunManager.add_potion(recipe):
			message.text = "本局已达到这瓶药水的数量上限，重置实验可恢复。"
			return
		owned = RunManager.potions.back()
	message.text = recipe.display_name + "：" + recipe.description
	if recipe.target_mode == PotionDefinition.TargetMode.PASSIVE:
		message.text += "\n已装入药水带；玩家受致命伤时自动触发。"
	elif not items.select_potion(owned):
		message.text += "\n" + (items.last_error if not items.last_error.is_empty() else "当前阶段不可使用，或已有持续药水占槽。")


func _unit(data: UnitData, at: Vector2, original: bool = false) -> UnitBase:
	var unit: UnitBase = battle.card_runtime._prepare_unit(data.duplicate())
	unit.unit_data.max_hp = 1000
	unit.floor_id = battle.get_node("Level/NavigationRegion2D").spawn_floor_at(at)
	var team := battle.get_node("Entities/TeamA" if data.unit_team == "team_a" else "Entities/TeamB")
	unit.position = team.to_local(at)
	team.add_child(unit)
	if original:
		var card := CardInstance.new(data)
		RunManager.deck.append(card)
		battle.hand_manager.move_hand_card_to_board(card, unit)
	unit.set_physics_process(false)
	return unit


func spawn_allies() -> void:
	for index in 2:
		_unit(load("res://data/units/soldier.tres"), Vector2(730 + index * 60, 530 + index * 50), true)


func spawn_enemies() -> void:
	for index in 5:
		_unit(load("res://data/units/orc.tres"), Vector2(1120 + index % 3 * 72, 510 + index / 3 * 70))


func kill_ally() -> void:
	var allies: Array = items.potion_runtime.allies()
	if not allies.is_empty():
		allies[0].die()


func _freeze(value: bool) -> void:
	for unit in battle.card_runtime.living_units():
		if not unit.has_meta("potion_decoy"):
			unit.set_physics_process(not value)


func _capture() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	toggle_phase()
	_select(load("res://data/potions/meteor.tres"))
	items.try_cast(Vector2(1200, 540))
	_select(load("res://data/potions/poison_flask.tres"))
	items.try_cast(Vector2(1200, 540))
	await get_tree().create_timer(1.2).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.maintenance/potion-demo.png")
	battle.battle_finished = true
	get_tree().quit()
