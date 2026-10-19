# 这玩意儿是干嘛的（核心逻辑）：这是数据表插件的底层仓库管理员，负责查找数据、读取结构、保存 Resource，并维护每条记录不会倒退或重复的持久 ID。
# 数据是咋流动的（数据流向）：Dock 把数据类型和记录路径传进来，本脚本读取 .gd/.tres 与 ID 计数器，再把记录字典交回界面；确认保存时才写回资源和计数器。
# 为啥这么写（选型决策）：ID 放进 Resource 元数据，不污染游戏业务字段；下一个编号单独保存在类型文件夹的隐藏计数文件中，因此删除最大 ID 后也不会重复使用旧号。
# 性能咋样（复杂度）：只在打开类型或确认保存时扫描一次对应文件夹，ID 计数器只是一个很小的文本文件，不会参与游戏每帧运行。
class_name DataTableCore
extends RefCounted
## 数据表格编辑器的纯逻辑层。
## 负责：数据目录扫描、数据结构(schema)反射、记录加载/保存、
## 额外属性(脚本里未声明的属性)的文本级保留、新建数据类型文件夹。

const DATA_DIR := "res://data"
const PROPERTY_HELP = preload("res://addons/shared/script_property_help.gd")
const RECORD_ID_META := "_data_table_id"
const ID_COUNTER_FILE := ".data_table_id_counter"

# ============================================================
# 目录与数据类型
# ============================================================

## 返回 data/ 下所有子文件夹名(即所有数据类型)，按名称排序。
static func list_types() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not f.begins_with(".") and dir.current_is_dir():
			out.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## 探测某数据类型的结构脚本(含 class_name 且 extends Resource 的 .gd)。
## 返回 { script_path, class_name, props, error }。
static func detect_schema(folder: String) -> Dictionary:
	var schema := {"script_path": "", "class_name": "", "props": [] as Array, "error": ""}
	var dir_path := DATA_DIR.path_join(folder)
	var gd_files := _list_files(dir_path, ["gd"])
	if gd_files.is_empty():
		schema.error = "该文件夹下没有 .gd 脚本，无法确定数据结构。请添加一个 extends Resource 的脚本并定义 @export 字段。"
		return schema

	# 优先：含 class_name 且 extends Resource 的脚本(结构基类)。
	for f in gd_files:
		var text := _read_text(f)
		if _has_class_name(text) and _extends_resource(text):
			schema.script_path = f
			schema.class_name = _extract_class_name(text)
			break

	# 回退 1：文件名 == 文件夹名。
	if schema.script_path == "":
		for f in gd_files:
			if f.get_file().get_basename() == folder:
				schema.script_path = f
				schema.class_name = _extract_class_name(_read_text(f))
				break
	# 回退 2：第一个 .gd。
	if schema.script_path == "":
		schema.script_path = gd_files[0]
		schema.class_name = _extract_class_name(_read_text(gd_files[0]))

	schema.props = extract_props(schema.script_path)
	return schema


## 反射结构脚本，返回 @export 属性列表。
## 每个属性字典: { name, type, hint, hint_string, annotation, default }。
static func extract_props(script_path: String) -> Array:
	var props: Array = []
	var s := load(script_path)
	var obj: Object = null
	if s != null:
		obj = s.new()
	var src := _read_text(script_path)

	if s != null and obj != null:
		for p in s.get_script_property_list():
			var usage: int = p.get("usage", 0)
			if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var nm: String = p["name"]
			if _is_internal_prop(nm):
				continue
			props.append({
				"name": nm,
				"type": int(p["type"]),
				"hint": int(p.get("hint", 0)),
				"hint_string": p.get("hint_string", ""),
				"annotation": _find_export_annotation(src, nm),
				"default": obj.get(nm),
			})

	# 反射失败时，退化为源码解析(仅能拿到名称与大致类型)。
	if props.is_empty():
		props = _parse_exports_from_source(src)
	var descriptions: Dictionary = PROPERTY_HELP.descriptions(s) if s is Script else PROPERTY_HELP.from_source(src)
	for prop in props:
		prop["description"] = descriptions.get(str(prop.name), "")
	return props


## 返回某属性如果为枚举时的选项列表 [{name, value}]；非枚举返回空数组。
## 兼容两种 hint_string 格式：@export_enum 的 "a,b,c"，以及脚本枚举的 "Name:Value,..."。
static func enum_entries(prop: Dictionary) -> Array:
	var out: Array = []
	if int(prop.get("hint", 0)) != PROPERTY_HINT_ENUM:
		return out
	var hs: String = prop.get("hint_string", "")
	if hs != "":
		var tokens := hs.split(",", false)
		for i in tokens.size():
			var tok: String = tokens[i]
			var nm := tok
			var value := i
			var colon := tok.find(":")
			if colon != -1:
				nm = tok.substr(0, colon)
				var vstr := tok.substr(colon + 1)
				if vstr.is_valid_int():
					value = vstr.to_int()
			out.append({"name": nm, "value": value})
		return out
	# 脚本枚举回退：从类型注解(如 Global.UnitType)解析枚举名。
	var ann: String = prop.get("annotation", "")
	if ann.contains("."):
		var names := resolve_script_enum(ann)
		for i in names.size():
			out.append({"name": names[i], "value": i})
	return out


## 返回某属性如果为枚举时的选项名列表；非枚举返回空数组。
static func enum_options(prop: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for e in enum_entries(prop):
		out.append(e["name"])
	return out


# ============================================================
# 记录
# ============================================================

## 返回某类型文件夹下所有记录文件(.tres/.res)，按名称排序。
static func list_records(folder: String) -> Array[String]:
	var out: Array[String] = []
	for f in _list_files(DATA_DIR.path_join(folder), ["tres", "res"]):
		out.append(f)
	out.sort()
	return out


## 加载一条记录文件。返回记录字典。
static func load_record(path: String, schema: Dictionary) -> Dictionary:
	var rec := {
		"path": path,
		"base_name": path.get_file().get_basename(),
		"res": null,
		"original": {},
		"extra": [] as Array,
		"uid": "",
		"script_path": "",
		"row_id": 0,
		"id_pending": false,
		"is_new": false,
		"deleted": false,
		"dirty": false,
		"error": "",
	}
	var text := _read_text(path)
	rec.uid = _extract_uid(text)
	# 数据表是磁盘文件的编辑入口，刷新时必须读取最新的 .tres；普通 load() 会复用编辑器内存缓存，
	# 这样玩家刚从别处保存的技能（例如 Normal_attack.tres）可能仍显示成旧内容或漏掉刚写入的元数据。
	# IGNORE 只让本次表格读取绕过缓存，不会粗暴替换主编辑器正在检查的 Resource 实例。
	var res = ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		rec.error = "无法加载资源: " + path
		rec.script_path = parse_script_path(text)
		return rec
	rec.res = res
	rec.script_path = _record_script_path(res, text)
	if res.has_meta(RECORD_ID_META):
		rec.row_id = maxi(int(res.get_meta(RECORD_ID_META, 0)), 0)
	for prop in schema.props:
		var nm: String = prop["name"]
		rec.original[nm] = _snapshot(res.get(nm))
	rec.extra = parse_extra_props(text, schema)
	return rec


## 新建一条记录(内存中，不写盘)。base_name 不含扩展名。
static func new_record(folder: String, schema: Dictionary, base_name: String) -> Dictionary:
	var path := DATA_DIR.path_join(folder).path_join(base_name + ".tres")
	var res: Resource = null
	var s := load(schema.script_path)
	if s != null:
		res = s.new()
	else:
		res = Resource.new()
	return {
		"path": path,
		"base_name": base_name,
		"res": res,
		"original": {},
		"extra": [] as Array,
		"uid": "",
		"script_path": schema.get("script_path", ""),
		"row_id": 0,
		"id_pending": false,
		"is_new": true,
		"deleted": false,
		"dirty": true,
		"error": "",
	}


## 保存一条记录到磁盘，并做文本后处理：恢复 uid、追加额外属性。
static func save_record(rec: Dictionary, schema: Dictionary) -> Dictionary:
	var path: String = rec["path"]
	var res: Resource = rec["res"]
	if res == null:
		return {"ok": false, "error": "记录为空: " + path}
	var err := ResourceSaver.save(res, path)
	if err != OK:
		return {"ok": false, "error": "保存失败 %s: %s" % [path, error_string(err)]}

	var text := _read_text(path)
	var uid: String = rec.get("uid", "")
	if uid != "" and not text.contains("uid=\"" + uid + "\""):
		text = _inject_uid(text, uid)
	var extra: Array = rec.get("extra", [])
	if not extra.is_empty():
		text = _inject_extra_props(text, extra)
	if _write_text(path, text) != OK:
		return {"ok": false, "error": "写入失败: " + path}
	return {"ok": true, "error": ""}


## 删除记录文件(含可能的 .uid 伴生文件)。
static func delete_record_file(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path) + ".uid")


## 读取某个数据类型下一个可用的 ID。folder 是 data/ 子文件夹名；返回至少为 1 的编号。
## 计数文件不存在代表该类型首次启用 ID，此时从 1 开始。
static func read_next_record_id(folder: String) -> int:
	var path := DATA_DIR.path_join(folder).path_join(ID_COUNTER_FILE)
	var text := _read_text(path).strip_edges()
	if text.is_valid_int():
		return maxi(text.to_int(), 1)
	return 1


## 保存某个数据类型下一个可用的 ID。folder 是类型目录，next_id 是尚未分配的编号；返回 Godot 错误码。
## 单独保存计数器可以防止删除当前最大 ID 后，下次新建记录又重复使用旧编号。
static func write_next_record_id(folder: String, next_id: int) -> int:
	var path := DATA_DIR.path_join(folder).path_join(ID_COUNTER_FILE)
	return _write_text(path, str(maxi(next_id, 1)))


## 检查某数据类型是否已经保存过独立 ID 计数器。folder 是 data/ 下的文件夹名；返回 true 表示该类型已使用独立编号规则。
## 用这个标记区分“旧版全局编号”与“正常删除过早期记录后留下的编号空洞”，避免误把正确的历史 ID 重排。
static func has_record_id_counter(folder: String) -> bool:
	var path := DATA_DIR.path_join(folder).path_join(ID_COUNTER_FILE)
	return FileAccess.file_exists(path)


# ============================================================
# 记录对应脚本
# ============================================================

## 读文本文件（脚本源码等）。
static func read_text_file(path: String) -> String:
	return _read_text(path)


## 写文本文件，返回错误码(OK 表示成功)。
static func write_text_file(path: String, text: String) -> int:
	return _write_text(path, text)


## 从加载好的资源取其 script 的路径；失败则回退文本解析。
static func _record_script_path(res: Resource, text: String) -> String:
	if res != null:
		var scr = res.get("script")
		if scr is Script:
			var rp: String = scr.resource_path
			if rp != "":
				return rp
	return parse_script_path(text)


## 从 .tres 文本中解析出该记录使用的脚本路径：
## 找到 [resource] 里 "script = ExtResource(\"id\")"，再找对应 id 的 Script 类型 ext_resource。
static func parse_script_path(text: String) -> String:
	var rid := ""
	for line in text.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("script = ExtResource("):
			var a := t.find("\"")
			if a != -1:
				var b := t.find("\"", a + 1)
				if b != -1:
					rid = t.substr(a + 1, b - a - 1)
			break
	if rid == "":
		return ""
	for line in text.split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		if line.contains("type=\"Script\"") and line.contains("id=\"" + rid + "\""):
			var re := RegEx.new()
			re.compile("path=\"([^\"]+)\"")
			var m := re.search(line)
			if m != null:
				return m.get_string(1)
	return ""


## 向资源的某个属性写入值；对数组属性复用其已有类型化数组以避免类型不匹配。
static func set_value(res: Resource, prop: Dictionary, value) -> void:
	var nm: String = prop["name"]
	var ptype: int = prop["type"]
	if ptype == TYPE_ARRAY:
		var arr = res.get(nm)
		if arr == null or not (arr is Array):
			arr = []
		arr.clear()
		if value is Array:
			for v in value:
				arr.append(v)
		res.set(nm, arr)
	else:
		res.set(nm, value)


## 把属性值格式化为表格里显示的简短字符串。
static func display_value(prop: Dictionary, value) -> String:
	if value == null:
		return "—"
	var ptype: int = prop["type"]
	var hint: int = prop["hint"]
	if hint == PROPERTY_HINT_ENUM:
		for e in enum_entries(prop):
			if int(e["value"]) == int(value):
				return e["name"]
		return str(value)
	if ptype == TYPE_BOOL:
		return "true" if value else "false"
	if ptype == TYPE_OBJECT:
		if value is Resource:
			var rp: String = value.resource_path
			return rp if rp != "" else "<%s>" % value.get_class()
		return str(value)
	if ptype == TYPE_ARRAY:
		if value is Array:
			var parts: Array[String] = []
			for e in value:
				if e is Resource:
					var rp: String = e.resource_path
					parts.append(rp if rp != "" else "<Resource>")
				else:
					parts.append(str(e))
			return "[" + ", ".join(parts) + "]"
		return str(value)
	return str(value)


## 从编辑器拖拽数据中提取资源文件路径列表。
## 兼容 FileSystem 面板拖拽(type="files"/"files_and_dirs")、
## 资源列表拖拽(type="resources")以及检查器资源属性拖拽(type="resource"/"obj_resource")。
static func drag_paths(data) -> Array[String]:
	var out: Array[String] = []
	if not (data is Dictionary):
		return out
	var t: String = data.get("type", "")
	if t == "files" or t == "files_and_dirs":
		for f in data.get("files", []):
			out.append(str(f))
	elif t == "resources":
		for f in data.get("resources", []):
			out.append(str(f))
	elif t == "resource" or t == "obj_resource":
		var r = data.get("resource")
		if r is Resource and r.resource_path != "":
			out.append(r.resource_path)
	return out


# ============================================================
# 额外属性(脚本未声明属性)的文本级保留
# ============================================================

## 从 .tres 文本中解析出脚本未声明的额外属性行。
static func parse_extra_props(text: String, schema: Dictionary) -> Array:
	var out: Array = []
	var declared := {}
	for prop in schema.props:
		declared[prop["name"]] = true

	var in_resource := false
	for line in text.split("\n"):
		var t := line.strip_edges()
		if t == "[resource]":
			in_resource = true
			continue
		if t.begins_with("[") and t.ends_with("]"):
			in_resource = false
		if not in_resource or t == "" or t.begins_with(";"):
			continue
		var eq := t.find("=")
		if eq <= 0:
			continue
		var key := t.substr(0, eq).strip_edges()
		var raw := t.substr(eq + 1).strip_edges()
		if key == "script" or key.begins_with("metadata/"):
			continue
		if key in declared:
			continue
		out.append(_make_extra(key, raw))
	return out


# ============================================================
# 新建数据类型
# ============================================================

## 新建数据类型文件夹 + 结构脚本。返回错误信息(空串表示成功)。
static func create_type(folder_name: String) -> String:
	var name := folder_name.strip_edges()
	if name == "":
		return "名称不能为空"
	if not _is_valid_identifier(name):
		return "名称需为合法标识符(仅字母/数字/下划线，且不能以数字开头)"
	var dir_path := DATA_DIR.path_join(name)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		return "已存在同名类型: " + name
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	if err != OK:
		return "创建目录失败: " + error_string(err)

	var cls_name := _to_pascal_case(name)
	var src := "class_name %s\nextends Resource\n\n## 此记录的英文标识，用于区分同类配置；实际引用与判重规则由读取此资源的系统决定。\n@export var id: String = \"名称\"\n" % cls_name
	var script_path := dir_path.path_join(name + ".gd")
	var f := FileAccess.open(script_path, FileAccess.WRITE)
	if f == null:
		return "无法写入脚本文件: " + script_path
	f.store_string(src)
	f.close()
	return ""


# ============================================================
# 内部工具
# ============================================================

static func _list_files(dir_path: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not f.begins_with(".") and not dir.current_is_dir():
			if exts.is_empty() or f.get_extension().to_lower() in exts:
				out.append(dir_path.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()
	return out


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	return txt


static func _write_text(path: String, text: String) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK


static func _has_class_name(text: String) -> bool:
	for line in text.split("\n"):
		if line.strip_edges().begins_with("class_name "):
			return true
	return false


static func _extends_resource(text: String) -> bool:
	for line in text.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("extends "):
			return t.trim_prefix("extends ").strip_edges() == "Resource"
	return false


static func _extract_class_name(text: String) -> String:
	for line in text.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("class_name "):
			return t.trim_prefix("class_name ").strip_edges()
	return ""


static func _extract_uid(text: String) -> String:
	var re := RegEx.new()
	re.compile("uid=\"([^\"]+)\"")
	var m := re.search(text)
	if m == null:
		return ""
	return m.get_string(1)


static func _is_internal_prop(nm: String) -> bool:
	return nm in ["script", "resource_name", "resource_path", "resource_local_to_scene", "resource_scene_unique_id"]


## 从源码中提取某 @export 变量的类型注解(例如 Global.UnitType / Array[SkillBase])。
static func _find_export_annotation(src: String, var_name: String) -> String:
	var re := RegEx.new()
	re.compile("@export[^\\n]*\\bvar\\s+" + var_name + "\\s*:\\s*([^\\s=]+)")
	var m := re.search(src)
	if m == null:
		return ""
	return m.get_string(1)


## 从脚本类名/自动加载名解析枚举名列表(如 Global.UnitType)。
static func resolve_script_enum(annotation: String) -> Array[String]:
	var parts := annotation.split(".")
	if parts.size() < 2:
		return []
	var owner := parts[0]
	var enum_name := parts[1]
	var script_path := _find_script_path(owner)
	if script_path == "":
		return []
	var text := _read_text(script_path)
	var re := RegEx.new()
	re.compile("enum\\s+" + enum_name + "\\s*\\{([^}]*)\\}")
	var m := re.search(text)
	if m == null:
		return []
	var names: Array[String] = []
	for tok in m.get_string(1).split(","):
		var t := tok.strip_edges()
		if t == "":
			continue
		var eq := t.find("=")
		if eq != -1:
			t = t.substr(0, eq).strip_edges()
		names.append(t)
	return names


static func _find_script_path(owner: String) -> String:
	# 1) 自动加载
	var auto := ProjectSettings.get_setting("autoload/" + owner, "")
	if auto is String and auto != "":
		return String(auto).trim_prefix("*")
	# 2) 全局类名
	for gc in ProjectSettings.get_global_class_list():
		if String(gc.get("class", "")) == owner:
			return String(gc.get("path", ""))
	return ""


## 源码级解析 @export 变量(反射失败时的回退)。
static func _parse_exports_from_source(src: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("@export(?:_enum\\(([^)]*)\\))?[^\\n]*\\bvar\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*([^\\s=]+)")
	for m in re.search_all(src):
		var nm := m.get_string(2)
		var ann := m.get_string(3)
		var hint := 0
		var hint_string := ""
		var type := _type_from_annotation(ann)
		var enum_args := m.get_string(1)
		if enum_args != "":
			hint = PROPERTY_HINT_ENUM
			var names: Array[String] = []
			for tok in enum_args.split(","):
				var t := tok.strip_edges().trim_prefix("\"").trim_suffix("\"")
				if t != "":
					names.append(t)
			hint_string = ", ".join(names)
		out.append({
			"name": nm,
			"type": type,
			"hint": hint,
			"hint_string": hint_string,
			"annotation": ann,
			"default": null,
		})
	return out


static func _type_from_annotation(ann: String) -> int:
	var a := ann.strip_edges()
	if a.begins_with("Array"):
		return TYPE_ARRAY
	match a:
		"String", "StringName":
			return TYPE_STRING
		"int":
			return TYPE_INT
		"float":
			return TYPE_FLOAT
		"bool":
			return TYPE_BOOL
		"PackedScene":
			return TYPE_OBJECT
		_:
			return TYPE_OBJECT


static func _snapshot(v):
	if v is Array:
		return v.duplicate(false)
	return v


static func _make_extra(key: String, raw: String) -> Dictionary:
	var kind := _infer_kind(raw)
	var value = raw
	match kind:
		"int":
			value = raw.to_int()
		"float":
			value = raw.to_float()
		"bool":
			value = raw == "true"
		"string":
			value = _unescape_string(raw.substr(1, raw.length() - 2))
	return {"key": key, "raw": raw, "kind": kind, "value": value}


static func _infer_kind(raw: String) -> String:
	if raw == "":
		return "opaque"
	var r := raw.strip_edges()
	if r.begins_with("Array") or r.begins_with("[") or r.begins_with("{") \
			or r.begins_with("ExtResource(") or r.begins_with("Object(") \
			or r.begins_with("SubResource(") or r.begins_with("PackedStringArray(") \
			or r.begins_with("Vector2(") or r.begins_with("Vector3(") or r.begins_with("Color("):
		return "opaque"
	if r == "true" or r == "false":
		return "bool"
	if r.begins_with("\""):
		return "string"
	if r.is_valid_float():
		return "int" if r.is_valid_int() else "float"
	return "string"


static func _inject_uid(text: String, uid: String) -> String:
	var lines := text.split("\n")
	for i in lines.size():
		var l := lines[i]
		if l.begins_with("[gd_resource"):
			if not l.contains("uid="):
				var idx := l.find(" format=")
				if idx == -1:
					idx = l.length() - 1
				lines[i] = l.substr(0, idx) + " uid=\"" + uid + "\"" + l.substr(idx)
			break
	return "\n".join(lines)


static func _inject_extra_props(text: String, extra: Array) -> String:
	var out := text
	if not out.ends_with("\n"):
		out += "\n"
	for e in extra:
		out += _format_extra(e) + "\n"
	return out


static func _format_extra(e: Dictionary) -> String:
	var key: String = e["key"]
	var kind: String = e["kind"]
	match kind:
		"int":
			return "%s = %d" % [key, int(e["value"])]
		"float":
			return "%s = %s" % [key, str(float(e["value"]))]
		"bool":
			return "%s = %s" % [key, "true" if bool(e["value"]) else "false"]
		"string":
			return "%s = \"%s\"" % [key, _escape_string(str(e["value"]))]
		_:
			return "%s = %s" % [key, e["raw"]]


static func _escape_string(s: String) -> String:
	return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")


static func _unescape_string(s: String) -> String:
	return s.replace("\\\"", "\"").replace("\\\\", "\\").replace("\\n", "\n")


static func _is_valid_identifier(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^[A-Za-z_][A-Za-z0-9_]*$")
	return re.search(s) != null


static func _to_pascal_case(s: String) -> String:
	var parts := s.replace("-", "_").replace(" ", "_").split("_")
	var out := ""
	for p in parts:
		if p != "":
			out += p.substr(0, 1).to_upper() + p.substr(1)
	return out if out != "" else "Data"
