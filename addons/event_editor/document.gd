# 可撤销的事件草稿；保存前校验，拒绝覆盖磁盘上的外部修改。
@tool
extends RefCounted
signal changed
const RECOVERY := "user://event_editor_recovery.tres"
var event: EventDefinition
var path := ""
var baseline := ""
var saved := ""
var error := ""
var history: Array[EventDefinition] = []
var future: Array[EventDefinition] = []

func fingerprint() -> String:
	return JSON.stringify({"id": event.id, "content": event.to_content()}, "", true) if event != null else ""

func is_dirty() -> bool:
	return event != null and (path.is_empty() or fingerprint() != saved)

func begin() -> void:
	history.append(event.duplicate(false))
	if history.size() > 80:
		history.pop_front()
	future.clear()

func commit() -> void:
	changed.emit()
	recover_save()

func undo() -> void:
	if not history.is_empty():
		future.append(event.duplicate(false))
		event = history.pop_back()
		commit()

func redo() -> void:
	if not future.is_empty():
		history.append(event.duplicate(false))
		event = future.pop_back()
		commit()

func open(target: String) -> bool:
	var resource := ResourceLoader.load(target, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is EventDefinition:
		error = "请选择 EventDefinition 事件资源。"
		return false
	event = resource.duplicate(false)
	path = target
	baseline = FileAccess.get_sha256(target)
	saved = fingerprint()
	history.clear()
	future.clear()
	error = ""
	changed.emit()
	return true

func new_event(template: int) -> void:
	var sources := ["forgotten_reliquary", "wandering_alchemist", "crossroads_recruitment", "campfire"]
	if template == EventDefinition.Template.CUSTOM:
		event = load("res://data/events/act1_caravan_wreck.tres").duplicate(false)
	else:
		event = load("res://data/events/%s.tres" % sources[template]).duplicate(false)
		event.template = template
	event.id = "new_event"
	event.title = "新的奇遇"
	path = ""
	baseline = ""
	saved = ""
	history.clear()
	future.clear()
	changed.emit()

func save(target: String = "") -> bool:
	if event == null:
		return false
	target = (path if target.is_empty() else target).simplify_path()
	error = event.validate()
	if not error.is_empty():
		return false
	if not target.begins_with("res://data/events/") or not target.ends_with(".tres") or target.get_file() != event.id + ".tres":
		error = "请保存到 data/events，文件名必须与事件编号一致。"
		return false
	if target == path and (FileAccess.get_sha256(target) if FileAccess.file_exists(target) else "") != baseline:
		error = "文件已被外部修改，请重新打开或另存为。"
		return false
	if target != path and FileAccess.file_exists(target):
		error = "目标编号已经存在，请更换新事件编号。"
		return false
	# 临时文件仍使用 .tres 后缀，保存器才能正确识别资源格式。
	var temporary := target.trim_suffix(".tres") + ".tmp.tres"
	var result := ResourceSaver.save(event, temporary)
	if result == OK:
		result = DirAccess.rename_absolute(temporary, target)
	if result != OK:
		error = "保存失败：" + error_string(result)
		return false
	path = target
	baseline = FileAccess.get_sha256(target)
	saved = fingerprint()
	error = ""
	changed.emit()
	return true

func recover_save() -> bool:
	if not is_dirty():
		return true
	return ResourceSaver.save(event, RECOVERY) == OK

func recover() -> bool:
	if not FileAccess.file_exists(RECOVERY):
		error = "没有可恢复的事件草稿。"
		return false
	if not open(RECOVERY):
		return false
	path = ""
	baseline = ""
	saved = ""
	changed.emit()
	return true
