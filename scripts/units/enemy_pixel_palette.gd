@tool
extends Resource
## 新怪物的源色与旧角色目标色一一对应；同种单位共享只读色板纹理。

@export var source_colors: PackedColorArray
@export var target_colors: PackedColorArray
var _source_texture: ImageTexture
var _target_texture: ImageTexture


func source_texture() -> ImageTexture:
	if _source_texture == null:
		_source_texture = _texture(source_colors)
	return _source_texture


func target_texture() -> ImageTexture:
	if _target_texture == null:
		_target_texture = _texture(target_colors)
	return _target_texture


func _texture(colors: PackedColorArray) -> ImageTexture:
	var image := Image.create(colors.size(), 1, false, Image.FORMAT_RGBA8)
	for index in colors.size():
		image.set_pixel(index, 0, colors[index])
	return ImageTexture.create_from_image(image)
