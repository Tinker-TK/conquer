# 故障注入只修改此隔离进程的内存，生产启动与默认游戏不会加载。
extends SceneTree


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	if "--missing-global" in OS.get_cmdline_user_args():
		root.get_node("Global").set_script(null)
		root.get_node("RuntimeGuard")._ready()
	else:
		root.add_child(load("res://tests/fixtures/unit_initialization_failure.gd").new())
