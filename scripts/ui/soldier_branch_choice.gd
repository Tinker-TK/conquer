@tool
extends HBoxContainer

signal chosen(branch: String)
var selected_branch := ""
var buttons: Dictionary = {}


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 16)
	for branch in ["slash", "missile"]:
		var button := Button.new()
		button.text = "选择斩击 · 放弃弓箭" if branch == "slash" else "选择飞弹 · 保留弓箭"
		button.custom_minimum_size = Vector2(270, 48)
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", 20)
		button.tooltip_text = "350范围飞跃，每个敌人只斩一次；斩过的目标死亡，自身攻击+1。" if branch == "slash" else "0.8倍率标记；命中时有N名士兵攻击目标，这N名士兵各攻击+N。"
		button.pressed.connect(select_branch.bind(branch))
		add_child(button)
		buttons[branch] = button
	hide()


func set_card(card: CardInstance) -> void:
	selected_branch = ""
	visible = card != null and card.needs_soldier_choice()
	for button: Button in buttons.values():
		button.set_pressed_no_signal(false)


func select_branch(branch: String) -> void:
	if branch not in buttons:
		return
	selected_branch = branch
	for key in buttons:
		buttons[key].set_pressed_no_signal(key == branch)
	chosen.emit(branch)
