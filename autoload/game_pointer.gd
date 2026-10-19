# 游戏及各类界面控件统一使用原始像素光标，热点对准透明边距内的箭头尖端。
extends Node

const CURSOR_TEXTURE := preload("res://assets/ui/Pointers/01.png")
const CURSOR_HOTSPOT := Vector2(22, 17)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# 按钮、卡牌拖放和文字控件会切换光标形状，给全部形状注册同一图片。
	for shape in range(Input.CURSOR_ARROW, Input.CURSOR_HELP + 1):
		Input.set_custom_mouse_cursor(CURSOR_TEXTURE, shape, CURSOR_HOTSPOT)


func _exit_tree() -> void:
	# Input 会持有光标贴图；在渲染器关闭前解除引用，避免游戏退出时遗留 GPU 纹理。
	for shape in range(Input.CURSOR_ARROW, Input.CURSOR_HELP + 1):
		Input.set_custom_mouse_cursor(null, shape)
