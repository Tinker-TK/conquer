# 这玩意儿是干嘛的（核心逻辑）：处理场景树木的遮挡显示。
# 数据是咋流动的（数据流向）：场景节点和信号提供输入，本脚本更新所属模块的状态与显示。
# 为啥这么写（选型决策）：保持原有接口，把同类职责归到一起，便于查找和配置。
# 性能咋样（复杂度）：按已有节点回调执行；此次整理只迁移路径，不增加新的循环。
extends Node2D

var unit_entered_count: int = 0
# 动态树木使用 AnimatedSprite2D，静态树木和灌木仍使用 Sprite2D；两者都通过 CanvasItem 调整透明度。
@onready var sprite: CanvasItem = get_node("AnimatedSprite2D") if has_node("AnimatedSprite2D") else get_node("Sprite2D")

func _physics_process(_delta: float) -> void:
	if unit_entered_count >= 1:
		sprite.modulate.a = 0.4
	else:
		sprite.modulate.a = 1

func _on_transparent_check_body_entered(_body: Node2D) -> void:
	unit_entered_count += 1

func _on_transparent_check_body_exited(_body: Node2D) -> void:
	unit_entered_count -= 1
