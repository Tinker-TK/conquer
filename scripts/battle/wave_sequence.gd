# 这玩意儿是干嘛的（核心逻辑）：让游戏与编辑器共用波次区间循环及单位成长算法。
# 数据是咋流动的（数据流向）：实际回合号 → 原始波次下标与重复次数 → 单位独立属性加成。
# 为啥这么写（选型决策）：按回合计算倍率，不依赖上轮存活单位，跳到后期实战也能正确成长。
# 性能咋样（复杂度）：每回合常数次运算，每个出场单位只检查三种属性。
@tool
extends RefCounted

const EFFECT_META := &"wave_cycle_effects"
const SPAWN_META := &"wave_spawn_effects"
const LABELS := {"attack": "攻击力", "max_hp": "最大生命", "defence": "防御"}

# 作用：检查循环范围；count 为波次数、enabled 为开关、first/last 为一基起止，last=0 表示末波，返回错误或空。
static func validate_range(count: int, enabled: bool, first: int, last: int) -> String:
	if not enabled:
		return ""
	var end := count if last == 0 else last
	if first < 1 or end < first or end > count:
		return "循环范围无效：需要 1 ≤ 起始波 ≤ 结束波 ≤ 波次数；结束波 0 表示末波。"
	return ""

# 作用：解析实际回合；round_number 为一基回合号，其余为波次数与范围，返回 index=-1 表示无有效波次。
static func resolve(round_number: int, count: int, enabled: bool, first: int = 1, last: int = 0) -> Dictionary:
	if round_number < 1 or count <= 0 or not validate_range(count, enabled, first, last).is_empty():
		return {"index": -1, "cycle": 0}
	if not enabled:
		return {"index": round_number - 1 if round_number <= count else -1, "cycle": 0}
	var end := count if last == 0 else last
	if round_number <= end:
		return {"index": round_number - 1, "cycle": 0}
	# 例如 3–5 的长度为 3；第 6、9、12 回合重用第 3 波，成长倍率依次为 1、2、3。
	var length := end - first + 1
	var elapsed := round_number - end - 1
	@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
	return {"index": first - 1 + elapsed % length, "cycle": 1 + int(elapsed / length)}

# 作用：读取单位增益值；unit 为波次单位、metadata 指定循环或单次配置，返回允许属性的独立字典。
static func effects(unit: Node, metadata: StringName = EFFECT_META) -> Dictionary:
	var raw: Variant = unit.get_meta(metadata, {})
	var result := {}
	if raw is Dictionary:
		for key in LABELS:
			var value: Variant = raw.get(key, 0)
			if (value is int or value is float) and is_finite(float(value)) and value > 0:
				result[key] = int(value)
	return result

# 作用：入树前应用单次增益与循环成长；unit 为本次新单位、cycle 为重复次数，没有返回值。
static func apply_effects(unit: Node, cycle: int) -> void:
	var fixed := effects(unit, SPAWN_META)
	var growth := effects(unit) if cycle > 0 else {}
	if (fixed.is_empty() and growth.is_empty()) or unit.get("unit_data") == null:
		return
	# 每个新单位只加一次固定值；循环部分从原场景按倍率计算，不污染基础资源。
	var data: Resource = unit.get("unit_data").duplicate()
	for key in LABELS:
		var amount := int(fixed.get(key, 0)) + int(growth.get(key, 0)) * maxi(0, cycle)
		if amount > 0:
			data.set(key, int(data.get(key)) + amount)
	unit.set("unit_data", data)
	# 保存已施加的独立快照，战斗 Buff 系统只登记来源，避免再加一次属性。
	unit.set_meta(&"wave_cycle_applied", {"spawn": fixed, "growth": growth, "cycle": maxi(0, cycle)})

# 作用：给清单和播放记录提供可核对的加成文字；unit 是单位，cycle 为重复次数，返回说明。
static func describe(unit: Node, cycle: int) -> String:
	var parts: Array[String] = []
	var fixed := effects(unit, SPAWN_META)
	for key in fixed:
		parts.append("%s单次+%d" % [LABELS[key], fixed[key]])
	var growth := effects(unit)
	for key in growth:
		parts.append("%s每循环+%d / 当前+%d" % [LABELS[key], growth[key], int(growth[key]) * cycle])
	return "；".join(parts)