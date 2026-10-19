@tool
extends TextureRect
## 纸纹和高清撕边随地图滚动，纸张覆盖图例背后的区域，不包含装饰图案。

var _scroll: ScrollContainer
var _content: Control
var _paper_material: ShaderMaterial


func _ready() -> void:
	_scroll = get_node("../ScrollContainer") as ScrollContainer
	_content = _scroll.get_node("MapContent") as Control
	_paper_material = material.duplicate() as ShaderMaterial
	material = _paper_material
	resized.connect(_sync_surface)
	_content.resized.connect(_sync_surface)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll)
	_sync_surface.call_deferred()


func _on_scroll(_value: float) -> void:
	_sync_surface()


func _sync_surface() -> void:
	if _paper_material == null or not is_instance_valid(_content):
		return
	_paper_material.set_shader_parameter("surface_size", Vector2(size.x, maxf(4400.0, _content.size.y + 100.0)))
	_paper_material.set_shader_parameter("scroll_y", float(_scroll.scroll_vertical))
