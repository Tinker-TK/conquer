# 这玩意儿是干嘛的（核心逻辑）：用地图工坊当前草稿开启一局真实冒险。
# 数据是咋流动的（数据流向）：编辑器测试快照 → 校验 → RunManager 本局配置 → GameSession。
# 为啥这么写（选型决策）：独立测试场景避免修改玩家主菜单保存的地图选择。
# 性能咋样（复杂度）：只在启动实战时读取一次 JSON，随后由正常游戏流程运行。
extends Node

# 作用：引擎运行测试场景后载入快照；没有参数，没有返回值。
func _ready() -> void:
	var result := RunManager.FixedMapConfig.read_file("user://map_editor_playtest.json")
	if result.has("error"):
		push_error("地图实战快照无效：" + str(result.error))
		return
	RunManager.selected_map = result.data
	RunManager.selected_act_maps.clear()
	RunManager.start_new_run()
	# 场景切换延后，避免在当前场景刚入树时就销毁它。
	get_tree().change_scene_to_file.call_deferred("res://scenes/app/game_session.tscn")
