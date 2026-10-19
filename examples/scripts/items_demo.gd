# 这玩意儿是干嘛的（核心逻辑）：F6 试玩开局遗物与原三种药水，不改正式开局资源；雷云有独立试玩场景。
# 数据是咋流动的（数据流向）：示例初始配置 → 新测试局 → 原战场初始化。
# 为啥这么写（选型决策）：独立演示场景避免为了测试而给每个正式新局强塞全部遗物。
# 性能咋样（复杂度）：只在演示场景开始时读取一次配置。
extends "res://scripts/battle/battle_scene.gd"


# 作用：Godot 入树时重置一局演示并初始化战场；没有参数，没有返回值。
func _ready() -> void:
	RunManager.start_new_run(load("res://examples/data/run_items_example.tres"))
	super._ready()
