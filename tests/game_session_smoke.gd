# 保留旧的 --script 入口，实际测试在 autoload 完成后由通用启动器加载。
extends "res://tests/card_framework_test_runner.gd"


func default_test_script() -> String:
	return "game_session_smoke_case.gd"
