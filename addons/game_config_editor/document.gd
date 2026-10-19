# 这玩意儿是干嘛的（核心逻辑）：保存配置表的编辑草稿，让改单元格、新增行和新增列都能撤销。
# 数据是咋流动的（数据流向）：实际资源快照 → 独立字典草稿 → 保存工具校验 → 游戏资源文件。
# 为啥这么写（选型决策）：不直接修改编辑器缓存中的资源，未保存的数值不会提前进入游戏。
# 性能咋样（复杂度）：只在编辑操作时复制草稿，最多保留 64 步历史，不参与游戏每帧运行。
@tool
extends RefCounted

signal changed(structure: bool)
const FORMAT := "ballsprite-config-catalog-v1"
const LABELS = preload("res://addons/game_config_editor/labels.gd")
var data: Dictionary = {}
var error := ""
var recovery_path := "user://game_config_editor_recovery.json"
var past: Array[Dictionary] = []
var future: Array[Dictionary] = []

# 作用：载入快照或导入合集；source 是配置字典，返回是否符合合集格式。
func open(source: Dictionary) -> bool:
	if source.get("format") != FORMAT or not source.get("records") is Array:
		error = "文件不是受支持的游戏配置合集。"
		return false
	# 导入文件只当作数据读取；缺少字段结构时拒绝，避免坏文件让界面崩溃。
	for row in source.records:
		if not row is Dictionary or not row.get("id") is String or not row.get("script") is String or not row.get("group") is String or not row.get("fields") is Array:
			error = "配置行结构无效。"
			return false
		for item in row.fields:
			if not item is Dictionary or not item.get("name") is String or not item.has("value") or not item.has("base") or not item.has("type"):
				error = "配置字段结构无效。"
				return false
	for key in ["pending_rows", "pending_columns", "custom_columns"]:
		if not source.get(key, []) is Array:
			error = "新增配置的格式无效。"
			return false
	if not source.get("editor_inputs", {}) is Dictionary:
		error = "未提交格子的格式无效。"
		return false
	data = source.duplicate(true)
	# JSON 将所有数字读成小数；整数数组恢复整数，显示 [0,1] 并保持草稿比较一致。
	for row: Dictionary in data.records:
		for item: Dictionary in row.fields:
			if int(item.type) == TYPE_ARRAY and int(item.get("array_type", TYPE_NIL)) == TYPE_INT:
				item.value = _integer_array(item.value)
				item.base = _integer_array(item.base)
	data["pending_rows"] = data.get("pending_rows", [])
	data["pending_columns"] = data.get("pending_columns", [])
	data["custom_columns"] = data.get("custom_columns", [])
	data["editor_inputs"] = data.get("editor_inputs", {})
	past.clear()
	future.clear()
	error = ""
	changed.emit(true)
	return true

# 作用：按路径找到配置行；id 是资源路径，返回配置行或空字典。
func record(id: String) -> Dictionary:
	for row: Dictionary in data.get("records", []):
		if row.id == id:
			return row
	return {}

# 作用：查找某个字段；row 是配置行，name 是英文配置名，返回字段或空字典。
func field(row: Dictionary, name: String) -> Dictionary:
	if row.get("group") == "skills" and name == "unit_name":
		var names := skill_unit_names(str(row.id))
		var text := "、".join(names) if not names.is_empty() else "未关联单位"
		return {"name": name, "type": TYPE_STRING, "hint": PROPERTY_HINT_NONE, "editable": false,
			"value": text, "base": text, "description": "根据单位的技能列表和防守反击配置自动显示关联单位；共享技能列出全部单位名称。修改关联请编辑单位资源的技能配置。"}
	for item: Dictionary in row.get("fields", []):
		if item.name == name:
			return item
	return {}


# 作用：从实际单位引用取得技能的所属单位名称；skill_id 为技能路径，返回去重名称列表。
func skill_unit_names(skill_id: String) -> PackedStringArray:
	var names: PackedStringArray = []
	for unit: Dictionary in data.get("records", []):
		if unit.get("group") != "units":
			continue
		var skills: Variant = value(unit, "skills")
		if (skills is Array and skills.has(skill_id)) or value(unit, "dodge_skill") == skill_id:
			var name := str(value(unit, "unit_name"))
			if not names.has(name):
				names.append(name)
	names.sort()
	return names

# 作用：读取格子内容；row 是配置行，name 是字段名，返回配置值或 null。
func value(row: Dictionary, name: String) -> Variant:
	return field(row, name).get("value")

# 作用：确定实际资源类别；row 是配置行，返回后端使用的类别名。
func family(row: Dictionary) -> String:
	return "card_effects" if str(row.get("script", "")).ends_with("/card_effect.gd") else str(row.get("group", ""))

# 作用：确定一行属于哪张表；row 为配置行，category 为分类，返回是否显示。
func matches(row: Dictionary, category: String) -> bool:
	if category == "card_effects":
		return family(row) == category
	if str(row.id).contains("::"):
		return false
	if category in ["allies", "enemies"]:
		return row.group == "units" and value(row, "unit_team") == ("team_a" if category == "allies" else "team_b")
	return row.group == category

# 作用：获取配置行的显示名称；row 为配置行，返回策划可读的名称。
func title(row: Dictionary) -> String:
	if family(row) == "card_effects":
		var owner := record(str(row.id).get_slice("::", 0))
		var kind := int(value(row, "kind"))
		var label: String = LABELS.EFFECTS.get(kind, "效果 " + str(kind))
		return str(value(owner, "card_name")) + " · " + label
	for name in ["skill_name", "unit_name", "card_name", "display_name"]:
		var text: Variant = value(row, name)
		if text != null and not str(text).is_empty():
			return str(text)
	return str(row.id).get_file().get_basename()

# 作用：判断新行是否还没保存；id 为资源路径，返回是否待创建。
func is_new(id: String) -> bool:
	for row: Dictionary in data.get("pending_rows", []):
		if row.id == id:
			return true
	return false

# 作用：统计待保存的操作；没有参数，返回新行、新列和修改格子的总数。
func change_count() -> int:
	var total: int = data.get("pending_rows", []).size() + data.get("pending_columns", []).size() + data.get("editor_inputs", {}).size()
	for row: Dictionary in data.get("records", []):
		for item: Dictionary in row.fields:
			if not same_value(item.get("value"), item.get("base")):
				total += 1
	return total

# 作用：判断退出或重读前是否需要保护草稿；没有参数，返回是否未保存。
func is_dirty() -> bool:
	return change_count() > 0

# 作用：修改一个可编辑格子；id 为行路径，name 为字段，next 为新值，返回是否提交。
func set_value(id: String, name: String, next: Variant) -> bool:
	var item := field(record(id), name)
	if item.is_empty() or not item.get("editable", false):
		error = "此字段只能通过关联资源配置修改。"
		return false
	if same_value(item.value, next):
		return true
	var before := data.duplicate(true)
	item.value = next
	_commit(before, false)
	return true

# 作用：一次提交整块粘贴的数据；edits 含行、字段和新值，返回是否全部可编辑。
func set_values(edits: Array) -> bool:
	for edit: Dictionary in edits:
		if not field(record(edit.id), edit.name).get("editable", false):
			error = "粘贴包含不可编辑字段。"
			return false
	var before := data.duplicate(true)
	for edit: Dictionary in edits:
		field(record(edit.id), edit.name).value = edit.value
	if before != data:
		_commit(before, true)
	return true

# 作用：将文本转换为字段数值；item 是字段定义，text 是输入，返回转换结果并设置错误。
func parse(item: Dictionary, text: String) -> Variant:
	error = ""
	match int(item.type):
		TYPE_INT:
			if not text.is_valid_int():
				error = "请输入整数。"
				return null
			return int(text)
		TYPE_FLOAT:
			if not text.is_valid_float() or not is_finite(float(text)):
				error = "请输入有效小数。"
				return null
			return float(text)
		TYPE_ARRAY, TYPE_VECTOR2:
			var json := JSON.new()
			if json.parse(text) != OK:
				error = "数组使用 JSON 格式，例如 [0,1]。"
				return null
			var parsed: Variant = json.data
			if not parsed is Array or (int(item.type) == TYPE_VECTOR2 and parsed.size() != 2):
				error = "数组使用 JSON 格式，例如 [1, 3]；坐标需有两个数值。"
				return null
			if item.get("name") == "unlock_upgrade_levels":
				for level in parsed:
					if not (level is int or level is float) or not is_finite(float(level)) or level != int(level) or level < 0 or level > 99:
						error = "解锁强化等级使用整数数组，例如 [0,1]；每个等级必须在 0～99 之间。"
						return null
			if int(item.get("array_type", TYPE_NIL)) == TYPE_INT:
				return _integer_array(parsed)
			return parsed
	return text


# 标量整数与 JSON 小数可相等，数组与标量不能直接比较。
static func same_value(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return left == right
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for i in left.size():
			if not same_value(left[i], right[i]):
				return false
		return true
	return typeof(left) == typeof(right) and left == right


func _integer_array(source: Variant) -> Variant:
	if not source is Array:
		return source
	var result: Array = []
	for item in source:
		if (item is int or item is float) and is_finite(float(item)) and item == int(item):
			result.append(int(item))
		else:
			# 保留非法导入值交给校验提示，不能截断小数变成另一个等级。
			result.append(item)
	return result

# 作用：复制已有配置创建新行；source 为模板路径，slug 为新英文标识，display 为名称，返回新路径或空。
func add_row(source: String, slug: String, display: String) -> String:
	var template := record(source)
	if template.is_empty() or is_new(source) or not _valid_name(slug):
		error = "请选择已保存的模板，并填写 2～50 位小写 snake_case 标识。"
		return ""
	var kind := family(template)
	var owner := source.get_slice("::", 0)
	var id := owner + "::Resource_" + slug if kind == "card_effects" else "res://data/" + kind + "/" + slug + ".tres"
	if not record(id).is_empty() or (kind != "card_effects" and FileAccess.file_exists(id)):
		error = "这个英文标识已存在。"
		return ""
	var before := data.duplicate(true)
	var row := template.duplicate(true)
	row.id = id
	row.file = id.get_slice("::", 0)
	row.used_by = [owner] if kind == "card_effects" else []
	# 新单位有自己的场景和英文标识；技能、图片等引用仍沿用模板。
	for item: Dictionary in row.fields:
		item.base = _copy(item.value)
		if item.name in ["unit_english_name", "id"]:
			item.value = slug
			item.base = slug
	var name_field: String = {"cards": "card_name", "units": "unit_name", "skills": "skill_name", "relics": "display_name", "potions": "display_name"}.get(kind, "")
	if not display.is_empty() and not field(row, name_field).is_empty():
		field(row, name_field).value = display
	data.records.append(row)
	data.pending_rows.append({"family": kind, "source": source, "id": id})
	# 效果列表由后端按新增行追加；这里同时更新显示值与基线，避免误报只读字段被手改。
	if kind == "card_effects":
		var effects := field(record(owner), "effects")
		if not effects.is_empty():
			effects.value.append(id)
			effects.base.append(id)
	_commit(before, true)
	return id

# 作用：取消尚未保存的新行；id 是资源路径，没有返回值。
func remove_row(id: String) -> void:
	if not is_new(id):
		return
	var before := data.duplicate(true)
	data.pending_rows = data.pending_rows.filter(func(row: Dictionary) -> bool: return row.id != id)
	data.records = data.records.filter(func(row: Dictionary) -> bool: return row.id != id)
	for row: Dictionary in data.records:
		var effects := field(row, "effects")
		if not effects.is_empty():
			effects.value.erase(id)
			effects.base.erase(id)
	_commit(before, true)

# 作用：给一个资源类型增加字段；column 含类别、英文名、中文名、类型和默认值，返回成功与否。
func add_column(column: Dictionary) -> bool:
	if not _valid_name(str(column.get("name", ""))) or str(column.get("label", "")).strip_edges().is_empty():
		error = "请填写有效英文配置名和中文名称。"
		return false
	for row: Dictionary in data.records:
		if family(row) == column.family and not field(row, column.name).is_empty():
			error = "此类资源已经有同名字段。"
			return false
	var types := {"int": TYPE_INT, "float": TYPE_FLOAT, "text": TYPE_STRING, "bool": TYPE_BOOL}
	if not types.has(column.get("dtype")):
		error = "字段类型不支持。"
		return false
	var before := data.duplicate(true)
	data.pending_columns.append(column.duplicate(true))
	for row: Dictionary in data.records:
		if family(row) == column.family:
			row.fields.append({"name": column.name, "label": column.label, "description": column.get("description", ""), "type": types[column.dtype], "hint": 0, "hint_string": "", "editable": true, "value": column.default, "base": null, "new": true})
	_commit(before, true)
	return true

# 作用：取消尚未应用的新列；kind 是类别，name 是字段名，没有返回值。
func remove_column(kind: String, name: String) -> void:
	var exists := false
	for column: Dictionary in data.pending_columns:
		if column.family == kind and column.name == name:
			exists = true
	if not exists:
		return
	var before := data.duplicate(true)
	data.pending_columns = data.pending_columns.filter(func(column: Dictionary) -> bool: return column.family != kind or column.name != name)
	for row: Dictionary in data.records:
		if family(row) == kind:
			row.fields = row.fields.filter(func(item: Dictionary) -> bool: return item.name != name)
	_commit(before, true)

# 作用：记录一项编辑事务；before 是操作前的草稿，structure 指是否需要重建表格，没有返回值。
func _commit(before: Dictionary, structure: bool) -> void:
	past.append(before)
	if past.size() > 64:
		past.pop_front()
	future.clear()
	error = ""
	write_recovery()
	changed.emit(structure)

# 作用：撤销上次编辑；没有参数，没有返回值。
func undo() -> void:
	if past.is_empty():
		return
	future.append(data.duplicate(true))
	data = past.pop_back()
	write_recovery()
	changed.emit(true)

# 作用：重做被撤销的编辑；没有参数，没有返回值。
func redo() -> void:
	if future.is_empty():
		return
	past.append(data.duplicate(true))
	data = future.pop_back()
	write_recovery()
	changed.emit(true)

# 作用：保存可恢复草稿；没有参数，返回是否成功，干净草稿会删除旧恢复文件。
func write_recovery() -> bool:
	if not is_dirty():
		discard_recovery()
		return true
	var file := FileAccess.open(recovery_path, FileAccess.WRITE)
	if file == null:
		error = "恢复草稿写入失败，请导出 HTML 或 JSON 保存。"
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

# 作用：明确放弃草稿或保存成功时删除恢复文件；没有参数，没有返回值。
func discard_recovery() -> void:
	if FileAccess.file_exists(recovery_path):
		DirAccess.remove_absolute(recovery_path)

# 作用：复制配置值；source 是任意字段值，返回与草稿独立的数组、字典或标量。
func _copy(source: Variant) -> Variant:
	return source.duplicate(true) if source is Array or source is Dictionary else source

# 作用：限制新文件和变量名；text 是英文标识，返回是否是有效的 snake_case。
func _valid_name(text: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]{1,49}$")
	return regex.search(text) != null
