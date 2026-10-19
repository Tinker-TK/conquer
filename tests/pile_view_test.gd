# 这玩意儿是干嘛的（核心逻辑）：测试三个牌堆入口、数量、只读显示与暂停恢复。
# 数据是咋流动的（数据流向）：真实战场的牌堆 → 点击信号 → 查看卡面 → 关闭恢复。
# 为啥这么写（选型决策）：直接使用真实场景，防止按钮路径和游戏数据接错。
# 性能咋样（复杂度）：仅手动运行测试，不参与正常游戏。
extends Node


# 作用：Godot 入树后延迟启动测试；没有参数，没有返回值。
func _ready() -> void:
	_run.call_deferred()


# 作用：验证牌堆显示及状态恢复；没有参数，没有返回值。
func _run() -> void:
	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle)
	await get_tree().process_frame
	var hand = battle.get_node("HandManager")
	var ui = battle.get_node("CardUI")
	# 独立构造重复卡，确认展示的是实例数量，而不是只显示一种同名卡。
	var card := CardInstance.new(load("res://data/units/soldier.tres"))
	var second := CardInstance.new(load("res://data/units/soldier.tres"))
	hand.draw_pile.assign([card, second])
	hand.discard_pile.assign([card])
	hand.exhaust_pile.clear()
	hand.piles_changed.emit(2, 1)
	var before: Array = hand.draw_pile.duplicate()
	for button in ["DrawButton", "DiscardButton", "ExhaustButton"]:
		ui.get_node("CardButtons/" + button).pressed.emit()
		assert(ui.pile_view.visible and get_tree().paused)
		var expected: int = 2 if button == "DrawButton" else (1 if button == "DiscardButton" else 0)
		assert(ui.pile_view.grid.get_child_count() == expected)
		if expected == 0:
			assert("为空" in ui.pile_view.get_node("Margin/VBox/Hint").text)
		for slot in ui.pile_view.grid.get_children():
			assert(not slot.get_child(0).is_playable)
		ui.pile_view.get_node("Margin/VBox/Header/Close").pressed.emit()
		assert(not ui.pile_view.visible and not get_tree().paused)
	assert(hand.draw_pile == before)
	# 正式结算消耗牌时沿用原 piles_changed 信号，数字和内容都必须更新。
	var definition := CardDefinition.new()
	definition.card_name = "测试消耗"
	definition.after_use = CardDefinition.AfterUse.EXHAUST
	var exhausted := CardInstance.new(definition)
	hand.resolving.append(exhausted)
	hand.finish_resolve(exhausted)
	assert(ui.get_node("CardButtons/ExhaustButton").text == "消耗牌堆 · 1")
	ui.get_node("CardButtons/ExhaustButton").pressed.emit()
	assert(ui.pile_view.grid.get_child_count() == 1)
	ui._close_pile()
	# 如果打开前已经暂停，关闭不能错误地启动战斗。
	get_tree().paused = true
	ui._open_pile("DrawButton")
	ui._close_pile()
	assert(get_tree().paused)
	get_tree().paused = false
	battle.battle_finished = true
	battle.queue_free()
	await get_tree().process_frame
	print("PILE_VIEW_PASS")
	get_tree().quit()
