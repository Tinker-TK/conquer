extends RefCounted
## 批量特效导入核心逻辑。
## 提供:
##  - 批量重命名文件 (rename_files_batch)
##  - 由图片序列构建 SpriteFrames (build_sprite_frames_from_files)
##  - 由精灵表网格拆分构建 SpriteFrames (build_sprite_frames_from_sheet)
##  - 创建 AnimatedSprite2D 节点 (make_animated_sprite_2d)
##  - 创建独立特效场景 (make_effect_scene)
##
## 这类纯逻辑脚本不依赖 Editor 界面，也可以被普通运行时代码复用。

const SUPPORTED_EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg", "avif"]

## 按数字自然排序(把文件名中的数字段按数值比较, 避免 2.png 排在 10.png 后面)。
static func natural_sort_key(s: String) -> String:
	var result := ""
	var num_buf := ""
	var i := 0
	while i < s.length():
		var c := s[i]
		if c >= "0" and c <= "9":
			num_buf += c
		else:
			if num_buf != "":
				result += num_buf.pad_zeros(10)
				num_buf = ""
			result += c.to_lower()
		i += 1
	if num_buf != "":
		result += num_buf.pad_zeros(10)
	return result


## 批量重命名一组文件。
## old_paths: res:// 路径数组
## new_base: 目标文件名(不含扩展名), 例如 "effect_001"；若为空则保留原文件名
## start_index: 起始序号
## digits: 序号位数(如 3 -> 001)
## suffix: 追加到序号后面的后缀, 例如 "_fire"
## 返回 Dictionary: { renamed: Array[String] (新路径), failed: Array[String] (失败项), skipped: int }
static func rename_files_batch(old_paths: Array, new_base: String, start_index: int = 1, digits: int = 3, suffix: String = "") -> Dictionary:
	var renamed: Array[String] = []
	var failed: Array[String] = []
	var skipped := 0

	var idx := start_index
	for p in old_paths:
		var p_str: String = p
		var old_abs := ProjectSettings.globalize_path(p_str)
		var ext: String = p_str.get_extension()
		var dir: String = p_str.get_base_dir()
		var new_name := ""
		if new_base.is_empty():
			new_name = p_str.get_file()
		else:
			var num := str(idx).pad_zeros(digits)
			new_name = "%s_%s%s.%s" % [new_base, num, suffix, ext]
		var new_path: String = dir.path_join(new_name)
		var new_abs := ProjectSettings.globalize_path(new_path)
		if old_abs == new_abs:
			skipped += 1
			renamed.append(new_path)
		elif DirAccess.rename_absolute(old_abs, new_abs) == OK:
			# 删除旧的 .import 元数据, 让编辑器重新导入新文件
			var old_import := old_abs + ".import"
			if FileAccess.file_exists(old_import):
				DirAccess.remove_absolute(old_import)
			renamed.append(new_path)
		else:
			failed.append(p)
		idx += 1
	return {"renamed": renamed, "failed": failed, "skipped": skipped}


## 扫描目录(可递归)下的所有图片文件, 返回 res:// 路径数组(自然排序)。
static func scan_image_files(dir: String, recursive: bool = true) -> Array[String]:
	var result: Array[String] = []
	if not dir.begins_with("res://"):
		dir = "res://" + dir
	var d := DirAccess.open(dir)
	if d == null:
		return result
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if recursive and not f.begins_with("."):
				result.append_array(scan_image_files(dir.path_join(f), true))
		else:
			var ext := f.get_extension().to_lower()
			if ext in SUPPORTED_EXTS and not f.begins_with("."):
				result.append(dir.path_join(f))
		f = d.get_next()
	d.list_dir_end()
	result.sort_custom(func(a, b): return natural_sort_key(a) < natural_sort_key(b))
	return result


## 从一组图片路径构建 SpriteFrames。
static func build_sprite_frames_from_files(paths: Array, anim_name: String, fps: float = 12.0, loop: bool = true) -> SpriteFrames:
	var sf := SpriteFrames.new()
	_strip_default_animation(sf)
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, fps)
	sf.set_animation_loop(anim_name, loop)
	for p in paths:
		var tex := ResourceLoader.load(p, "Texture2D") as Texture2D
		if tex != null:
			sf.add_frame(anim_name, tex)
		else:
			push_warning("无法加载纹理: %s" % p)
	return sf


## 从精灵表(一张大图)按行列网格拆分成帧构建 SpriteFrames。
## sheet_path: 图片 res:// 路径
## cols / rows: 列数 / 行数
## frame_size: Vector2i(0,0) 时按图片尺寸均分; 也可指定单帧尺寸
static func build_sprite_frames_from_sheet(sheet_path: String, anim_name: String, cols: int, rows: int, fps: float = 12.0, loop: bool = true, frame_size: Vector2i = Vector2i.ZERO) -> SpriteFrames:
	var tex := ResourceLoader.load(sheet_path, "Texture2D") as Texture2D
	if tex == null:
		push_error("无法加载精灵表: %s" % sheet_path)
		return null
	return build_sprite_frames_from_sheet_texture(tex, anim_name, cols, rows, fps, loop, frame_size)


## 用已加载的 Texture2D 按网格拆帧(供代码复用/测试)。
static func build_sprite_frames_from_sheet_texture(tex: Texture2D, anim_name: String, cols: int, rows: int, fps: float = 12.0, loop: bool = true, frame_size: Vector2i = Vector2i.ZERO) -> SpriteFrames:
	if tex == null:
		return null
	var tw := tex.get_width()
	var th := tex.get_height()
	var fw := frame_size.x if frame_size.x > 0 else tw / cols
	var fh := frame_size.y if frame_size.y > 0 else th / rows
	var sf := SpriteFrames.new()
	_strip_default_animation(sf)
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, fps)
	sf.set_animation_loop(anim_name, loop)
	for r in rows:
		for c in cols:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(c * fw, r * fh, fw, fh)
			sf.add_frame(anim_name, at)
	return sf


## 移除 SpriteFrames 自带的无用 "default" 动画(新建时自动存在, 0 帧)。
static func _strip_default_animation(sf: SpriteFrames) -> void:
	if sf.has_animation("default") and sf.get_frame_count("default") == 0:
		sf.remove_animation("default")


## 从精灵表按"每行一个动画"拆帧: 行数 = 动画数量, 列数 = 每个动画的帧数。
## anim_names: 每行动画名数组(长度应等于 rows; 不足或为空的行自动用 fallback_prefix_序号 补)
static func build_sprite_frames_from_sheet_rows(sheet_path: String, anim_names: Array, cols: int, rows: int, fps: float = 12.0, loop: bool = true, frame_size: Vector2i = Vector2i.ZERO, fallback_prefix: String = "anim") -> SpriteFrames:
	var tex := ResourceLoader.load(sheet_path, "Texture2D") as Texture2D
	if tex == null:
		push_error("无法加载精灵表: %s" % sheet_path)
		return null
	return build_sprite_frames_from_sheet_rows_texture(tex, anim_names, cols, rows, fps, loop, frame_size, fallback_prefix)


## 用已加载的 Texture2D 按"每行一个动画"拆帧(供代码复用/测试)。
static func build_sprite_frames_from_sheet_rows_texture(tex: Texture2D, anim_names: Array, cols: int, rows: int, fps: float = 12.0, loop: bool = true, frame_size: Vector2i = Vector2i.ZERO, fallback_prefix: String = "anim") -> SpriteFrames:
	if tex == null:
		return null
	var tw := tex.get_width()
	var th := tex.get_height()
	var fw := frame_size.x if frame_size.x > 0 else tw / cols
	var fh := frame_size.y if frame_size.y > 0 else th / rows
	var sf := SpriteFrames.new()
	_strip_default_animation(sf)
	for r in rows:
		var name: String = ""
		if r < anim_names.size() and str(anim_names[r]).strip_edges() != "":
			name = str(anim_names[r]).strip_edges()
		else:
			name = "%s_%02d" % [fallback_prefix, r + 1]
		sf.add_animation(name)
		sf.set_animation_speed(name, fps)
		sf.set_animation_loop(name, loop)
		for c in cols:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(c * fw, r * fh, fw, fh)
			sf.add_frame(name, at)
	return sf


## 把 src 的所有动画合并进 target（同名动画覆盖）。返回 target。
## 用于"导入到已有的 AnimatedSprite2D"，保留节点里原有动画，只新增/覆盖。
static func merge_sprite_frames(target: SpriteFrames, src: SpriteFrames) -> SpriteFrames:
	_strip_default_animation(target)
	for anim in src.get_animation_names():
		if target.has_animation(anim):
			target.remove_animation(anim)
		target.add_animation(anim)
		target.set_animation_speed(anim, src.get_animation_speed(anim))
		target.set_animation_loop(anim, src.get_animation_loop(anim))
		var count := src.get_frame_count(anim)
		for i in count:
			target.add_frame(anim, src.get_frame_texture(anim, i))
	return target


## 创建并返回一个 AnimatedSprite2D 节点(尚未加入场景树)。
static func make_animated_sprite_2d(frames: SpriteFrames, anim_name: String, node_name: String) -> AnimatedSprite2D:
	var node := AnimatedSprite2D.new()
	node.name = node_name
	node.sprite_frames = frames
	if frames != null and frames.has_animation(anim_name):
		node.animation = anim_name
		node.autoplay = anim_name
	return node


## 创建独立特效场景(根节点 Node2D + AnimatedSprite2D 子节点)。
## 返回 PackedScene。
static func make_effect_scene(frames: SpriteFrames, anim_name: String, root_name: String) -> PackedScene:
	var root := Node2D.new()
	root.name = root_name
	var node := make_animated_sprite_2d(frames, anim_name, "AnimatedSprite2D")
	root.add_child(node)
	node.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene
