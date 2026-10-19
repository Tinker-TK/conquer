# 这玩意儿是干嘛的（核心逻辑）：保管地图草稿、节点编号、撤销历史和保存状态。
# 数据是咋流动的（数据流向）：界面修改字典 → 事务快照 → JSON 文件 → 游戏共用校验器。
# 为啥这么写（选型决策）：独立文档层让拖动、属性修改和撤销使用同一套数据，保留未知扩展字段。
# 性能咋样（复杂度）：完成编辑时复制最多 500 个节点，拖动途中只更新坐标，不每帧写磁盘。
@tool
extends RefCounted

signal changed
const CONFIG = preload("res://scripts/map/fixed_map_config.gd")
const RECOVERY := "user://map_editor_recovery.json"
var data: Dictionary = {}
var path := ""
var baseline := ""
var saved_text := ""
var selection := ""
var error := ""
var history: Array[Dictionary] = []
var future: Array[Dictionary] = []
var before: Dictionary = {}

# 作用：查询是否有未保存修改；没有参数，返回是否需要保存。
func is_dirty() -> bool:
	return not data.is_empty() and (path.is_empty() or JSON.stringify(data, "", true, true) != saved_text)

# 作用：取得选中节点；没有参数，返回节点或空字典。
func node() -> Dictionary:
	return find(selection)

# 作用：按编号查询节点；id 为编号，返回配置或空。
func find(id: String) -> Dictionary:
	for location in data.get("locations", []):
		if location.id == id:
			return location
	return {}

# 作用：取得地图完整快照；没有参数，返回配置和选中编号。
func snapshot() -> Dictionary:
	return {"data": data.duplicate(true), "selection": selection}

# 作用：开始一次编辑事务；没有参数，没有返回值。
func begin() -> void:
	before = snapshot()

# 作用：结束编辑并记录撤销；没有参数，没有返回值。
func commit() -> void:
	normalize()
	if not before.is_empty() and before.data != data:
		history.append(before)
		if history.size() > 80:
			history.pop_front()
		future.clear()
	before = {}
	changed.emit()
	write_recovery()

# 作用：恢复历史快照；state 为配置与选中项，没有返回值。
func restore(state: Dictionary) -> void:
	data = state.data.duplicate(true)
	selection = state.selection
	changed.emit()
	write_recovery()

# 作用：撤销最近修改；没有参数，没有返回值。
func undo() -> void:
	if not history.is_empty():
		future.append(snapshot())
		restore(history.pop_back())

# 作用：重做刚撤销的修改；没有参数，没有返回值。
func redo() -> void:
	if not future.is_empty():
		history.append(snapshot())
		restore(future.pop_back())

# 作用：同步由层级决定的纵坐标并补旧事件；没有参数，没有返回值。
func normalize() -> void:
	data.schema_version = int(data.schema_version)
	data.floors = int(data.floors)
	var bound_events: Dictionary = {}
	for location in data.get("locations", []):
		# JSON 将数字读成浮点数；回填整数才能让原生控件和撤销快照保持相同类型。
		location.type = int(location.type)
		location.floor = int(location.floor)
		location.map_pos.y = 0.93 - float(location.floor - 1) / (int(data.floors) - 1) * 0.86
		if int(location.type) == 1 and not str(location.get("event_pool", "")).is_empty():
			location.title = "旅途奇遇"
			location.event = load("res://scripts/events/event_pool.gd").fallback()
		if int(location.type) in [1, 2] and location.get("event_source", "inline") == "catalog":
			var id := str(location.get("event_id", ""))
			if not bound_events.has(id):
				bound_events[id] = CONFIG.default_event(id)
			var bound: Dictionary = bound_events[id]
			if not bound.is_empty():
				var previous_title := str(location.get("event", {}).get("title", ""))
				if location.title == previous_title and bound.has("title"):
					location.title = bound.title
				location.event = bound.duplicate(true)
		if int(location.type) in [1, 2] and not location.has("event"):
			location.event = CONFIG.default_event(str(location.get("event_id", "")))
			if location.event.is_empty():
				location.event = CONFIG.default_event("campfire" if int(location.type) == 2 else "abandoned_camp")
		if int(location.type) in [1, 2]:
			for choice in location.event.choices:
				choice.heal = int(choice.get("heal", 0))
				choice.gold = int(choice.get("gold", 0))

# 作用：刷新工坊事件快照，实际内容变化时记为一次可撤销编辑；没有参数，没有返回值。
func refresh_event_bindings() -> void:
	if data.is_empty():
		return
	begin()
	normalize()
	if before.data != data:
		commit()
	else:
		before = {}

# 作用：生成稳定且不重复的编号；floor 为创建层，返回编号。
func next_id(floor: int) -> String:
	var sequence := 1
	while not find("floor_%02d_%02d" % [floor, sequence]).is_empty():
		sequence += 1
	return "floor_%02d_%02d" % [floor, sequence]

# 作用：创建一个节点；kind 为类型，floor 为层，x 为横向比例，没有返回值。
func add_node(kind: int, floor: int, x: float) -> void:
	if data.locations.size() >= 500:
		error = "最多支持 500 个节点。"
		return
	begin()
	var id := next_id(floor)
	var location := {"id": id, "title": ["战斗", "事件", "篝火", "Boss", "宝箱", "商店", "精英", "随机事件"][kind], "type": kind,
		"event_id": "level_002" if kind == 3 else "level_001" if kind == 0 else "level_elite_mid" if kind == 6 else "",
		"floor": floor, "map_pos": {"x": clampf(x, 0.03, 0.97), "y": 0.0}, "next": []}
	if kind == 7:
		location.unknown_options = CONFIG.default_unknown_options()
	if kind == 6:
		location.reward_config = "res://data/battle_rewards/elite.tres"
	if kind in [1, 2]:
		location.event = CONFIG.default_event("campfire" if kind == 2 else "abandoned_camp")
	data.locations.append(location)
	if floor == 1:
		data.starting_ids.append(id)
	selection = id
	commit()

# 作用：删除选中节点和关联连线；没有参数，没有返回值。
func delete_node() -> void:
	if node().is_empty():
		return
	begin()
	data.locations.erase(node())
	data.starting_ids.erase(selection)
	for location in data.locations:
		location.next.erase(selection)
	selection = ""
	commit()

# 作用：创建向上的连线；from/to 为编号，返回是否成功。
func connect_nodes(from: String, to: String) -> bool:
	var source := find(from)
	var target := find(to)
	if source.is_empty() or target.is_empty() or int(target.floor) <= int(source.floor):
		error = "请选择更高层的目标节点。"
		return false
	if source.next.has(to):
		error = "路线已经存在。"
		return false
	begin()
	source.next.append(to)
	commit()
	return true

# 作用：删除一条路线；from/to 为编号，没有返回值。
func disconnect_nodes(from: String, to: String) -> void:
	if find(from).is_empty() or not find(from).next.has(to):
		return
	begin()
	find(from).next.erase(to)
	commit()

# 作用：改名并同步起点和路线；id 为新编号，返回是否成功。
func rename_node(id: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]{1,80}$")
	if pattern.search(id) == null or (id != selection and not find(id).is_empty()):
		error = "编号需唯一，只能包含字母、数字、下划线或短横线。"
		return false
	begin()
	var old := selection
	node().id = id
	for location in data.locations:
		for i in location.next.size():
			if location.next[i] == old:
				location.next[i] = id
	for i in data.starting_ids.size():
		if data.starting_ids[i] == old:
			data.starting_ids[i] = id
	selection = id
	commit()
	return true

# 作用：创建空地图或示例；example 为是否建立十层示例，没有返回值。
func new_map(example: bool = false) -> void:
	data = {"schema_version": 1, "mode": "fixed", "name": "新地图", "floors": 10, "starting_ids": [], "locations": []}
	path = ""
	baseline = ""
	saved_text = ""
	selection = ""
	history.clear()
	future.clear()
	if example:
		data.name = "第一章 · 余烬之路"
		for floor in range(1, 11):
			var kinds: Array = [3] if floor == 10 else [0, 0] if floor == 1 else [4, 4] if floor == 5 else [0, 5] if floor in [3, 8] else [1, 2] if floor % 2 == 0 else [0, 1]
			for i in kinds.size():
				add_node(kinds[i], floor, float(i + 1) / (kinds.size() + 1))
		for location in data.locations:
			for target in data.locations:
				if target.floor == location.floor + 1:
					location.next.append(target.id)
		history.clear()
	selection = ""
	normalize()
	changed.emit()
	write_recovery()

# 作用：检查文件可编辑结构，允许未完成路线；raw 为数据，返回错误或空串。
func draft_error(raw: Variant) -> String:
	if not raw is Dictionary or raw.get("schema_version") != 1 or raw.get("mode") != "fixed":
		return "需要 v1 固定路线 JSON。"
	if not raw.get("name") is String or raw.name.length() > 80 or not CONFIG._integer_between(raw.get("floors"), 2, 30):
		return "名称或层数格式不正确。"
	if not raw.get("locations") is Array or raw.locations.size() > 500 or not raw.get("starting_ids") is Array:
		return "节点或起点列表不合法。"
	var ids: Dictionary = {}
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]{1,80}$")
	for location in raw.locations:
		if not location is Dictionary or not location.get("id") is String or pattern.search(location.id) == null or ids.has(location.id):
			return "节点编号格式错误或重复。"
		if not location.get("title") is String or location.title.length() > 80 or not CONFIG._integer_between(location.get("type"), 0, 7) or not CONFIG._integer_between(location.get("floor"), 1, int(raw.floors)):
			return "节点名称、类型或层级格式错误。"
		if not location.get("map_pos") is Dictionary or not (location.map_pos.get("x") is float or location.map_pos.get("x") is int) or not is_finite(float(location.map_pos.x)) or location.map_pos.x < 0 or location.map_pos.x > 1 or not location.get("next") is Array:
			return "节点坐标或路线列表格式错误。"
		if location.has("event_id") and not location.event_id is String:
			return "战斗关卡名必须是文本。"
		if int(location.type) in [0, 3, 6] and (location.has("battle_rewards") or location.has("reward_config")):
			var reward_error := CONFIG.battle_reward_error(location)
			if not reward_error.is_empty():
				return reward_error
		if location.has("event"):
			var event: Variant = location.event
			if not event is Dictionary or not event.get("description") is String or event.description.length() > 2000 or not event.get("choices") is Array or event.choices.size() < 2 or event.choices.size() > 8:
				return "事件结构不合法。"
			for choice in event.choices:
				if not choice is Dictionary or not choice.get("text") is String or choice.text.length() > 80 or not CONFIG._integer_between(choice.get("heal", 0), 0, 9999) or not CONFIG._integer_between(choice.get("gold", 0), 0, 9999):
					return "事件选项结构不合法。"
				var percent: Variant = choice.get("heal_percent", 0)
				if not (percent is int or percent is float) or not is_finite(float(percent)) or percent < 0 or percent > 100:
					return "休憩回复百分比必须是 0–100 的有限数字。"
				if choice.has("effect"):
					var issue: String = load("res://scripts/events/event_rewards.gd").validate_effect(choice.effect)
					if not issue.is_empty():
						return issue
		ids[location.id] = true
	for id in raw.starting_ids:
		if not id is String or not ids.has(id) or raw.starting_ids.count(id) != 1:
			return "出发点不存在或重复。"
	for location in raw.locations:
		for id in location.next:
			if not id is String or not ids.has(id) or location.next.count(id) != 1:
				return "路线目标不存在或重复。"
	return ""

# 作用：打开 JSON，检查成功才替换当前文档；target 为路径，返回是否成功。
func open(target: String) -> bool:
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null or file.get_length() > CONFIG.MAX_BYTES:
		error = "文件无法读取或超过 2 MB。"
		return false
	var raw: Variant = JSON.parse_string(file.get_as_text().trim_prefix("\ufeff"))
	error = draft_error(raw)
	if not error.is_empty():
		return false
	data = raw
	path = target
	baseline = FileAccess.get_sha256(target)
	normalize()
	saved_text = JSON.stringify(data, "", true, true)
	selection = ""
	history.clear()
	future.clear()
	changed.emit()
	return true

# 作用：安全写入 JSON；target 为路径，text 为正文，返回是否成功。
func write_json(target: String, text: String) -> bool:
	var file := FileAccess.open(target + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "无法写入：" + error_string(FileAccess.get_open_error())
		return false
	file.store_string(text)
	file.flush()
	var result := file.get_error()
	file.close()
	if result == OK:
		result = DirAccess.rename_absolute(target + ".tmp", target)
	if result != OK:
		error = "保存失败：" + error_string(result)
		return false
	return true

# 作用：保存地图并避免覆盖外部修改；target 为可选新路径，返回是否成功。
func save(target: String = "") -> bool:
	target = path if target.is_empty() else target
	if target.is_empty():
		error = "请先另存为。"
		return false
	var exists := FileAccess.file_exists(target)
	if target == path and (FileAccess.get_sha256(target) if exists else "") != baseline:
		error = "磁盘文件已被外部修改，请另存为或重新打开。"
		return false
	normalize()
	if not write_json(target, JSON.stringify(data, "\t", true, true)):
		return false
	path = target
	baseline = FileAccess.get_sha256(target)
	saved_text = JSON.stringify(data, "", true, true)
	error = ""
	write_recovery()
	changed.emit()
	return true

# 作用：保存未完成草稿以便恢复；没有参数，返回是否成功。
func write_recovery() -> bool:
	if not is_dirty():
		if FileAccess.file_exists(RECOVERY):
			DirAccess.remove_absolute(RECOVERY)
		return true
	return write_json(RECOVERY, JSON.stringify({"data": data, "path": path, "baseline": baseline, "saved_text": saved_text}, "", true, true))

# 作用：恢复上次未保存的草稿；没有参数，返回是否成功。
func recover() -> bool:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECOVERY))
	if not raw is Dictionary or not draft_error(raw.get("data")).is_empty():
		error = "恢复文件不可读取。"
		return false
	data = raw.data
	path = str(raw.get("path", ""))
	baseline = str(raw.get("baseline", ""))
	saved_text = str(raw.get("saved_text", ""))
	selection = ""
	history.clear()
	future.clear()
	normalize()
	changed.emit()
	return true
