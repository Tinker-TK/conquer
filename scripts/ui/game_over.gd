# 这玩意儿是干嘛的（核心逻辑）：展示胜负，把返回流程交给 GameSession，独立战斗也使用漫画切场。
# 数据是咋流动的（数据流向）：战斗写入胜负 → 玩家点击继续 → 外壳接收信号。
# 为啥这么写（选型决策）：战斗不负责销毁整局，常驻 HUD 和地图才不会消失。
# 性能咋样（复杂度）：只响应结算和按钮，没有每帧开销。
extends CanvasLayer

signal continue_requested(won: bool)
var leaving := false

var over_label: String = ''
var reward_session: RefCounted
var reward_panel: Control

# 作用：Godot 在进入战斗时隐藏结算面板；没有参数，没有返回值。
func _ready() -> void:
	# 低于常驻 HUD 和地图查看层，高于手牌；查看地图时由战斗控制显隐。
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Control.hide()
	reward_panel = preload("res://scripts/ui/battle_reward_panel.gd").new()
	add_child(reward_panel)
	reward_panel.continue_requested.connect(_on_button_pressed)
	hide()

func show_result(won: bool, level: BattleLevelConfig = null) -> void:
	if won:
		if reward_session == null:
			var content: Dictionary = RunManager.pending_battle_rewards.duplicate(true)
			if content.is_empty():
				var config := level.victory_rewards if level != null and level.victory_rewards != null else load("res://data/battle_rewards/normal.tres") as BattleRewardConfig
				content = config.to_content()
			reward_session = preload("res://scripts/battle/battle_reward_session.gd").new()
			var boss_reward := level != null and level.victory_rewards != null and level.victory_rewards.resource_path == "res://data/battle_rewards/boss.tres"
			reward_session.initialize(RunManager, content, -1, boss_reward)
			reward_panel.open_rewards(reward_session)
	else:
		reward_panel.show_defeat()
	show()

# 作用：点击结算按钮后，根据胜负前往地图或主菜单。
# 参数：没有参数，由结算按钮调用。
# 返回值：没有返回值。
func _on_button_pressed() -> void:
	# 防止快速双击触发两次关卡切换。
	if leaving:
		return
	leaving = true
	if reward_session != null:
		reward_session.close()
	if continue_requested.get_connections().is_empty():
		# 单独用 F6 测试战斗时没有外壳，返回主菜单即可。
		get_tree().paused = false
		SceneTransition.change_scene("res://scenes/ui/main_ui.tscn", "返回主菜单 / 再整旗鼓")
		return
	continue_requested.emit(Global.game_phase == Global.GamePhase.VICTORY)
	
# 作用：点击退出时关闭游戏；没有参数，没有返回值。
func _on_button_2_pressed() -> void:
	get_tree().quit()


# 作用：Godot 在面板显隐变化时刷新胜负文字；没有参数，没有返回值。
func _on_visibility_changed() -> void:
	$Control/Label.text = over_label
