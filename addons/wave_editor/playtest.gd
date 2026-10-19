# 这玩意儿是干嘛的（核心逻辑）：用编辑器快照从指定回合启动真正的战斗场景。
# 数据是咋流动的（数据流向）：user:// 测试快照 → 初始牌组 → configure_level → 指定起始回合。
# 为啥这么写（选型决策）：独立运行进程不修改正式资源，不假装恢复前几回合的战斗状态。
# 性能咋样（复杂度）：启动时读取一次，之后使用正式战斗流程。
extends Node

var battle: Node

# 作用：引擎进入测试场景时开战；没有参数，没有返回值。
func _ready() -> void:
	var config := load("user://wave_editor_playtest.tres") as Resource
	if config == null or config.battle_scene == null:
		push_error("没有可用的波次实战快照，请从波次编辑器启动。")
		return
	RunManager.start_new_run()
	battle = config.battle_scene.instantiate()
	battle.configure_level(config)
	var first := maxi(1, int(config.get_meta("wave_editor_start_round", 1)))
	battle.get_node("BattleRoundManager").first_round = first
	battle.get_node("Entities/TeamB").last_round = first - 1
	add_child(battle)
	# 明示测试起点和新开局语义，避免将后续回合测试误认为完整存档回放。
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var label := Label.new()
	label.text = "波次实战检查 · 从第 %d 回合新开局 · 使用初始牌组 · F8 停止" % first
	label.position = Vector2(20, 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
