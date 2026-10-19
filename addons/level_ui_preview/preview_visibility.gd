# 只改变编辑器实例的绘制状态，不修改节点 visible 或场景资源。
@tool
extends RefCounted

var items: Array[CanvasItem] = []
var hidden := true


func set_scene(scene: Node) -> void:
	restore()
	items.clear()
	# 战斗本体、战斗模板和继承关卡共用这两个 UI 层。
	# 单独打开 CardUI / GameOver 场景时仍可正常编辑界面。
	if not is_instance_valid(scene) or not scene.has_node("Level"):
		return
	for path in ["CardUI", "GameOver"]:
		var layer := scene.get_node_or_null(path) as CanvasLayer
		if layer != null:
			_collect_items(layer)
	apply()


func set_hidden(value: bool) -> void:
	hidden = value
	if hidden:
		apply()
	else:
		restore()


func apply() -> void:
	if not hidden:
		return
	for item in items:
		if is_instance_valid(item) and item.is_inside_tree():
			RenderingServer.canvas_item_set_visible(item.get_canvas_item(), false)


func restore() -> void:
	for item in items:
		if is_instance_valid(item) and item.is_inside_tree():
			# 尊重控件及其父级本来的显隐状态，避免把原本隐藏的 UI 打开。
			RenderingServer.canvas_item_set_visible(item.get_canvas_item(), item.is_visible_in_tree())


func _collect_items(node: Node) -> void:
	if node is CanvasItem:
		items.append(node)
	# 遍历完整分支，包含跨普通 Node、top_level 和嵌套 CanvasLayer 的控件。
	for child in node.get_children():
		_collect_items(child)
