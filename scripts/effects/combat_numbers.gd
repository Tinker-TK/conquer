# 战斗数值只负责显示；固定物理步推进，确定性错位不消耗战斗随机数。
# 数字挂在战场上，单位死亡退场后，最后一击仍能完整播放。
class_name CombatNumbers
extends Node2D

const FONT := preload("res://assets/fonts/numbers/lilita_one/LilitaOne-Regular.ttf")
const LIFETIME := 0.95
const MAX_NUMBERS := 192
const COLORS := {
	&"normal": Color("ffffff"),
	&"skill": Color("ffcd62"),
	&"bleed": Color("ff647c"),
	&"poison": Color("c58aff"),
	&"burn": Color("ff914d"),
	&"lightning": Color("ffe76b"),
	&"true_damage": Color("f18cff"),
	&"heal": Color("68f39b"),
	&"shield": Color("69baff"),
}
const LANES := [Vector2.ZERO, Vector2(-18, 8), Vector2(18, -8), Vector2(-28, -8), Vector2(28, 8)]
var _entries: Array[Dictionary] = []


static func show_number(target: Node2D, amount: int, kind: StringName = &"normal") -> Label:
	if amount <= 0 or not is_instance_valid(target) or not target.is_inside_tree():
		return null
	var world: Node = target.get_parent()
	if target.has_meta("battle_owner"):
		var reference: WeakRef = target.get_meta("battle_owner")
		if reference != null and is_instance_valid(reference.get_ref()):
			world = reference.get_ref()
	else:
		# 独立怪物测试场没有 battle_owner；也不能把数字混进 TeamA/TeamB 的单位列表。
		while world.get_parent() is Node2D:
			world = world.get_parent()
	var layer := world.get_node_or_null("CombatNumbers") as CombatNumbers
	if layer == null:
		layer = CombatNumbers.new()
		layer.name = "CombatNumbers"
		world.add_child(layer)
	return layer._spawn_number(target, amount, kind)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_as_relative = false
	z_index = 3900
	set_physics_process(false)


func _spawn_number(target: Node2D, amount: int, kind: StringName) -> Label:
	if _entries.size() >= MAX_NUMBERS:
		var oldest: Dictionary = _entries.pop_front()
		oldest.label.queue_free()
	# 缓存单位身体范围；伤害、治疗与护盾统一从身体中心弹出。
	if not target.has_meta("combat_number_bounds"):
		target.set_meta("combat_number_bounds", target._smoke_body_rect())
	var body: Rect2 = target.get_meta("combat_number_bounds")
	var anchor := body.get_center()
	var tick := Engine.get_physics_frames()
	var previous_tick := int(target.get_meta("combat_number_tick", -1000))
	var sequence := int(target.get_meta("combat_number_sequence", 0)) if tick - previous_tick < 30 else 0
	target.set_meta("combat_number_tick", tick)
	target.set_meta("combat_number_sequence", sequence + 1)
	var lane: Vector2 = LANES[sequence % LANES.size()]
	var label := Label.new()
	label.text = ("+%d" if kind in [&"heal", &"shield"] else "%d") % amount
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 30 if kind == &"skill" else 28)
	label.add_theme_color_override("font_color", COLORS.get(kind, COLORS[&"skill"]))
	label.add_theme_color_override("font_outline_color", Color("182131"))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.08, 0.55))
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.set_meta("amount", amount)
	label.set_meta("kind", kind)
	add_child(label)
	label.size = label.get_minimum_size()
	label.pivot_offset = label.size * 0.5
	lane.x *= maxf(1.0, label.size.x / 40.0)
	# 只在数值变化时取一次世界坐标，后续动画不再读取单位位置。
	var origin := to_local(target.to_global(anchor)) + lane - label.size * 0.5
	# 同一单位短时间内连击或同时回血、加盾时，避开尚未消失的数字。
	# 为弹出放大预留空间；至多八次尝试，密集群战也有固定上限。
	var target_id := target.get_instance_id()
	for attempt in 8:
		var overlaps := false
		var bounds := Rect2(origin - label.size * 0.1, label.size * 1.2).grow(4.0)
		for entry: Dictionary in _entries:
			if int(entry.target_id) != target_id:
				continue
			var previous: Label = entry.label
			if bounds.intersects(Rect2(previous.position - previous.size * 0.1, previous.size * 1.2)):
				overlaps = true
				break
		if not overlaps:
			break
		# 连续数值横向散开，避免避让逻辑把起点重新推到头顶。
		origin.x += (label.size.x * 1.2 + 4.0) * (-1.0 if sequence % 2 else 1.0)
	_entries.append({"label": label, "origin": origin, "drift": lane.x * 0.45, "age": 0.0, "target_id": target_id})
	_pose(_entries.back())
	set_physics_process(true)
	return label


func _physics_process(delta: float) -> void:
	for index in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[index]
		entry.age += delta
		if float(entry.age) >= LIFETIME:
			entry.label.queue_free()
			_entries.remove_at(index)
		else:
			_pose(entry)
	if _entries.is_empty():
		set_physics_process(false)


func _pose(entry: Dictionary) -> void:
	var age: float = entry.age
	var label: Label = entry.label
	label.position = entry.origin + Vector2(float(entry.drift) * age, -68.0 * age + 20.0 * age * age)
	var pop := lerpf(0.65, 1.2, sin(minf(age / 0.10, 1.0) * PI * 0.5)) if age < 0.10 else lerpf(1.2, 1.0, clampf((age - 0.10) / 0.12, 0.0, 1.0))
	label.scale = Vector2.ONE * pop
	label.modulate.a = 1.0 - smoothstep(0.55, LIFETIME, age)


func clear() -> void:
	for entry: Dictionary in _entries:
		entry.label.queue_free()
	_entries.clear()
	set_physics_process(false)
