# 所有卡牌界面共用一份只读详情层；不生成战斗单位、不暂停交锋，也不修改卡牌。
extends CanvasLayer

var inspector: Control


static func show_for(card: CardInstance, source: Control) -> void:
	if card == null or not card.is_unit_card():
		return
	var viewport := source.get_viewport()
	var overlay := viewport.get_node_or_null("CardUnitDetails")
	if overlay == null:
		overlay = load("res://scripts/ui/card_unit_details.gd").new()
		overlay.name = "CardUnitDetails"
		viewport.add_child(overlay)
	overlay.inspector.open_card(card, source)


func _ready() -> void:
	# 牌堆查看会暂停战斗；只读详情仍能滚动、悬停和关闭。
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 150
	inspector = preload("res://scenes/ui/unit_inspector.tscn").instantiate()
	add_child(inspector)


func _input(event: InputEvent) -> void:
	if inspector.panel.visible and event.is_action_pressed("ui_cancel"):
		inspector.close_details()
		get_viewport().set_input_as_handled()
