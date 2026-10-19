extends Node

# 独立 F6 演示入口，正式游戏的开局金币不受此场景影响。
func _ready() -> void:
	RunManager.selected_map = {}
	RunManager.start_new_run()
	RunManager.gold = 449
	var game := preload("res://scenes/app/game_session.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.map_view._get_location("battle_a").type = 5
	game.map_view._on_node_enter_requested(game.map_view.node_views.battle_a)
