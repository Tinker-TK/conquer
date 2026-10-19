# 这玩意儿是干嘛的（核心逻辑）：保管关卡草稿、撤销历史和磁盘版本，避免误覆盖。
# 数据是咋流动的（数据流向）：界面操作 → 独立波次节点 → 快照历史 → 检查文件指纹 → 保存。
# 为啥这么写（选型决策）：快照保留完整 PackedScene，撤销不会丢失技能或自定义单位属性。
# 性能咋样（复杂度）：每次完成操作打包各回合，拖动中不打包；适合几十回合的人工编排。
@tool
extends RefCounted

signal changed
const CONFIG_SCRIPT = preload("res://data/levels/battle_level_config.gd")
const SEQUENCE = preload("res://scripts/battle/wave_sequence.gd")
const RECOVERY := "user://wave_editor_recovery.tres"
var config: Resource
var rounds: Array[Node2D] = []
var path := ""
var baseline := ""
var current := -1
var selection := PackedInt32Array()
var revision := 0
var saved_revision := 0
var serial := 0
var history := UndoRedo.new()
var before: Dictionary = {}
var error := ""
var recovery_path := RECOVERY

# 作用：查询草稿是否偏离已保存状态；没有参数，返回是否需要保存。
func is_dirty() -> bool:
	return config != null and (path.is_empty() or revision != saved_revision)

# 作用：计算文件内容指纹；target 是路径，返回摘要，文件不存在时返回空。
func fingerprint(target: String) -> String:
	return FileAccess.get_sha256(target) if FileAccess.file_exists(target) else ""

# 作用：释放树外节点；没有参数，没有返回值。界面销毁前必须调用。
func clear_nodes() -> void:
	for wave in rounds:
		wave.free()
	rounds.clear()

# 作用：把当前节点打包为兼容游戏的资源；没有参数，返回独立资源或失败时空。
func output() -> Resource:
	if config == null:
		return null
	var result: Resource = config.duplicate()
	var waves: Array[PackedScene] = []
	for wave in rounds:
		# 树外新建的根节点默认没有名字，打包前命名，避免重载场景时出现空名称错误。
		if str(wave.name).is_empty():
			wave.name = "Wave"
		if wave.get_child_count() == 0:
			waves.append(null)
		else:
			var scene := PackedScene.new()
			if scene.pack(wave) != OK:
				error = "波次打包失败，草稿仍保留在编辑器中。"
				return null
			waves.append(scene)
	result.waves = waves
	return result

# 作用：读取并检查关卡，成功后才替换草稿；target 为路径，返回是否成功。
func open(target: String) -> bool:
	var starting_fingerprint := fingerprint(target)
	var loaded := ResourceLoader.load(target, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if loaded == null or loaded.get_script() != CONFIG_SCRIPT:
		error = "请选择 BattleLevelConfig 关卡资源。"
		return false
	if fingerprint(target) != starting_fingerprint:
		error = "读取期间文件发生变化，请重新打开。"
		return false
	# 不支持的波次必须拒绝，不能悄悄删掉非单位节点或脚本后保存。
	for packed in loaded.waves:
		if packed == null:
			continue
		var node: Node = packed.instantiate()
		var valid := node is Node2D
		for child in node.get_children():
			valid = valid and child is UnitBase
		node.free()
		if not valid:
			error = "波次根节点必须是 Node2D，直接子节点只支持战斗单位；原草稿未改变。"
			return false
	path = target
	baseline = starting_fingerprint
	_reset(loaded)
	return true

# 作用：创建空白关卡草稿；没有参数，没有返回值。
func new_level() -> void:
	path = ""
	baseline = ""
	_reset(CONFIG_SCRIPT.new())
	rounds.append(Node2D.new())
	current = 0
	changed.emit()

# 作用：开始一份新的文档历史；resource 是新配置，没有返回值。
func _reset(resource: Resource) -> void:
	history.clear_history()
	serial = 0
	revision = 0
	saved_revision = 0
	_restore({"config": resource, "current": 0, "selection": PackedInt32Array(), "revision": 0})
	error = ""

# 作用：保存撤销前的完整状态；没有参数，没有返回值。
func begin() -> void:
	before = snapshot()

# 作用：取得包括选择项的快照；没有参数，返回供历史使用的状态。
func snapshot() -> Dictionary:
	return {"config": output(), "current": current, "selection": selection.duplicate(), "revision": revision}

# 作用：完成一次编辑并加入撤销；label 是操作名称，没有返回值。
func commit(label: String) -> void:
	serial += 1
	revision = serial
	var after := snapshot()
	history.create_action(label)
	history.add_do_method(_restore.bind(after))
	history.add_undo_method(_restore.bind(before))
	history.commit_action(false)
	before = {}
	changed.emit()
	write_recovery()

# 作用：恢复快照并通知界面；state 是历史状态，没有返回值。
func _restore(state: Dictionary) -> void:
	clear_nodes()
	config = state.config.duplicate()
	for packed in state.config.waves:
		rounds.append(packed.instantiate() if packed != null else Node2D.new())
	current = clampi(state.current, -1, rounds.size() - 1)
	selection = state.selection.duplicate()
	revision = state.revision
	changed.emit()

# 作用：撤销最近操作并更新恢复文件；没有参数，没有返回值。
func undo() -> void:
	if history.has_undo():
		history.undo()
		write_recovery()

# 作用：重做刚才撤销的操作；没有参数，没有返回值。
func redo() -> void:
	if history.has_redo():
		history.redo()
		write_recovery()

# 作用：插入或复制回合；copy 表示复制当前阵型，没有返回值。
func add_round(copy: bool = false) -> void:
	begin()
	var wave := Node2D.new()
	if copy and current >= 0:
		wave.free()
		var packed := PackedScene.new()
		packed.pack(rounds[current])
		wave = packed.instantiate()
	current += 1
	rounds.insert(current, wave)
	selection.clear()
	commit("复制回合" if copy else "添加回合")

# 作用：删除选中回合；没有参数，没有返回值。
func delete_round() -> void:
	if current < 0:
		return
	begin()
	rounds[current].free()
	rounds.remove_at(current)
	current = mini(current, rounds.size() - 1)
	selection.clear()
	commit("删除回合")

# 作用：上下移动回合；delta 为 -1 或 1，没有返回值。
func move_round(delta: int) -> void:
	var target := current + delta
	if current < 0 or target < 0 or target >= rounds.size():
		return
	begin()
	var wave := rounds[current]
	rounds.remove_at(current)
	rounds.insert(target, wave)
	current = target
	commit("排序回合")

# 作用：添加敌方怪物；scene 为怪物场景，没有返回值。
func add_unit(scene: PackedScene) -> void:
	if current < 0 or scene == null:
		return
	begin()
	var unit := scene.instantiate() as Node2D
	unit.position = Vector2(-60 * (rounds[current].get_child_count() % 5), 0)
	rounds[current].add_child(unit, true)
	unit.owner = rounds[current]
	selection = PackedInt32Array([unit.get_index()])
	commit("添加怪物")

# 作用：批量删除、复制或替换；kind 为操作，scene 为替换用场景，没有返回值。
func edit_units(kind: String, scene: PackedScene = null) -> void:
	if current < 0 or selection.is_empty():
		return
	begin()
	var chosen: Array[Node] = []
	for index in selection:
		chosen.append(rounds[current].get_child(index))
	selection.clear()
	for old in chosen:
		if kind == "删除":
			old.free()
			continue
		var unit: Node2D
		if kind == "复制":
			# 复制单个节点用完整波次打包后取出，可保留场景实例的全部覆盖值。
			var packed := PackedScene.new()
			packed.pack(rounds[current])
			var clone := packed.instantiate()
			unit = clone.get_child(old.get_index())
			clone.remove_child(unit)
			clone.free()
			unit.position = old.position + Vector2(32, 32)
		else:
			unit = scene.instantiate()
			unit.position = old.position
			# 替换兵种保留该站位的循环成长设定；清除效果由独立按钮处理。
			unit.set_meta(SEQUENCE.EFFECT_META, SEQUENCE.effects(old))
			unit.set_meta(SEQUENCE.SPAWN_META, SEQUENCE.effects(old, SEQUENCE.SPAWN_META))
		rounds[current].add_child(unit, true)
		unit.owner = rounds[current]
		if kind == "替换":
			rounds[current].move_child(unit, old.get_index())
			old.free()
		selection.append(unit.get_index())
	commit(kind + "怪物")

# 作用：一次性设置循环范围，支持完整撤销；first/last 为一基范围，没有返回值。
func set_repeat_range(first: int, last: int) -> void:
	if config.repeat_start == first and config.repeat_end == last:
		return
	begin()
	config.repeat_start = first
	config.repeat_end = last
	commit("修改循环范围")

# 作用：设置选中单位的循环增长；key 为属性、amount 为增量（0 清除），没有返回值。
func set_cycle_effect(key: String, amount: int) -> void:
	_set_unit_effect(key, amount, SEQUENCE.EFFECT_META, "修改单位循环效果")

# 作用：设置选中单位每次出场的固定增益；key 为属性、amount 为增量（0 清除），没有返回值。
func set_spawn_effect(key: String, amount: int) -> void:
	_set_unit_effect(key, amount, SEQUENCE.SPAWN_META, "修改单位单次增益")

# 作用：把整组增益编辑纳入一次撤销；key/amount 为数值、metadata 为配置键、label 为历史名称，没有返回值。
func _set_unit_effect(key: String, amount: int, metadata: StringName, label: String) -> void:
	if current < 0 or selection.is_empty() or not SEQUENCE.LABELS.has(key):
		return
	begin()
	for index in selection:
		var unit := rounds[current].get_child(index)
		var values := SEQUENCE.effects(unit, metadata)
		if amount > 0:
			values[key] = amount
		else:
			values.erase(key)
		# 替换独立字典，单次增益与循环成长互不覆盖，撤销快照也不会被修改。
		unit.set_meta(metadata, values)
	commit(label)

# 作用：替换地形或关卡属性；key 是导出字段，value 是新值，没有返回值。
func set_field(key: String, value: Variant) -> void:
	if config.get(key) == value:
		return
	begin()
	config.set(key, value)
	commit("修改" + key)

# 作用：检查保存和实战的必备条件；resource 为待检查关卡，返回错误或空串。
func validate(resource: Resource) -> String:
	if resource == null:
		return "没有可保存的关卡。"
	if resource.battle_scene == null:
		return "请先拖入 battle_001 这类战斗场景作为地形。"
	var range_error := SEQUENCE.validate_range(resource.waves.size(), resource.repeat_waves, resource.repeat_start, resource.repeat_end)
	if not range_error.is_empty():
		return range_error
	if not resource.waves.any(func(wave: PackedScene) -> bool: return wave != null):
		return "至少需要一个有怪物的回合。"
	if resource.battle_duration < 1 or not is_finite(resource.battle_duration) or resource.energy_per_round < 0 or resource.cards_per_round < 0:
		return "战斗时长、能量或抽牌数不合法。"
	return ""

# 作用：检查冲突后原子替换磁盘文件；target 为空时保存原文件，返回成功与否。
func save(target: String = "") -> bool:
	var destination := path if target.is_empty() else target
	var resource := output()
	error = validate(resource)
	if not error.is_empty():
		return false
	if destination.is_empty() or not destination.ends_with(".tres"):
		error = "请指定 .tres 保存路径。"
		return false
	var expected := baseline if destination == path else ""
	if fingerprint(destination) != expected:
		error = "文件已被外部修改（或目标已存在），未覆盖。请重新读取或另存为新文件。"
		return false
	# 同目录临时文件保证重命名不会跨磁盘；写完再次检查，缩短覆盖竞争窗口。
	var staging := destination.get_base_dir().path_join(".wave-editor-%d.tres" % Time.get_ticks_usec())
	# 原子替换仍保留原资源 UID，否则其他场景的 uid 引用会指向旧身份。
	var uid := ResourceLoader.get_resource_uid(destination) if FileAccess.file_exists(destination) else ResourceUID.INVALID_ID
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	var result := ResourceSaver.save(resource, staging)
	if result == OK:
		result = ResourceSaver.set_uid(staging, uid)
	if result == OK and fingerprint(destination) != expected:
		DirAccess.remove_absolute(staging)
		error = "写入期间目标发生变化，已停止保存。请另存为或重新读取。"
		return false
	if result == OK:
		result = DirAccess.rename_absolute(staging, destination)
	if result != OK:
		DirAccess.remove_absolute(staging)
		error = "保存失败：" + error_string(result)
		return false
	path = destination
	if ResourceUID.has_id(uid):
		ResourceUID.set_id(uid, destination)
	else:
		ResourceUID.add_id(uid, destination)
	baseline = fingerprint(path)
	saved_revision = revision
	discard_recovery()
	changed.emit()
	return true

# 作用：保留退出或冲突时的恢复草稿；没有参数，返回写入是否成功。
func write_recovery() -> bool:
	if not is_dirty():
		discard_recovery()
		return true
	var resource := output()
	if resource == null:
		return false
	resource.set_meta("wave_editor_path", path)
	resource.set_meta("wave_editor_baseline", baseline)
	resource.set_meta("wave_editor_current", current)
	return ResourceSaver.save(resource, recovery_path) == OK

# 作用：清除已经保存或明确放弃的草稿；没有参数，没有返回值。
func discard_recovery() -> void:
	if FileAccess.file_exists(recovery_path):
		DirAccess.remove_absolute(recovery_path)

# 作用：恢复上次中断的草稿并保留旧指纹；没有参数，返回是否成功。
func recover() -> bool:
	var resource := ResourceLoader.load(recovery_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if resource == null or resource.get_script() != CONFIG_SCRIPT:
		return false
	path = resource.get_meta("wave_editor_path", "")
	baseline = resource.get_meta("wave_editor_baseline", "")
	var selected_round: int = resource.get_meta("wave_editor_current", 0)
	for key in ["wave_editor_path", "wave_editor_baseline", "wave_editor_current"]:
		resource.remove_meta(key)
	_reset(resource)
	current = selected_round
	saved_revision = -1
	changed.emit()
	return true