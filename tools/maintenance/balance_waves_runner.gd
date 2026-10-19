extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.add_child(load("res://tools/maintenance/apply_balance_waves.gd").new())
