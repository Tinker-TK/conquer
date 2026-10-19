# 按幕、进度、普通/精英/Boss 和难度选择关卡；仅在生成地图时读取。
@tool
extends RefCounted

const CONFIG = preload("res://scripts/map/fixed_map_config.gd")
const PHASES := ["early", "middle", "late", "boss"]
const KINDS := ["normal", "elite", "boss"]

static func phase(floor_number: int, rooms: int, boss: bool = false) -> String:
	if boss:
		return "boss"
	return "early" if floor_number <= rooms / 3.0 else "middle" if floor_number <= rooms * 2.0 / 3.0 else "late"

static func matches(rule: Dictionary, act: int, progress: String, kind: String, difficulty: String) -> bool:
	return rule.acts.any(func(value): return int(value) == act) and progress in rule.phases and kind in rule.kinds and difficulty in rule.difficulties

static func validate(data: Variant, difficulties: Array) -> String:
	if not data is Dictionary or data.get("schema_version") != 1 or not CONFIG._integer_between(data.get("config_version"), 1, 999999):
		return "遭遇池需要 schema_version=1 和正整数 config_version。"
	if not data.get("rules") is Array or data.rules.is_empty():
		return "遭遇池缺少 rules。"
	for rule in data.rules:
		if not rule is Dictionary:
			return "遭遇规则必须是对象。"
		for field in ["acts", "phases", "kinds", "difficulties", "levels"]:
			if not rule.get(field) is Array or rule[field].is_empty():
				return "遭遇规则缺少非空数组：%s" % field
		for act in rule.acts:
			if not CONFIG._integer_between(act, 1, 3):
				return "遭遇幕编号只能为 1–3。"
		for value in rule.phases:
			if value not in PHASES:
				return "遭遇进度仅支持 early / middle / late / boss。"
		for value in rule.kinds:
			if value not in KINDS:
				return "遭遇类型仅支持 normal / elite / boss。"
		for value in rule.difficulties:
			if value not in difficulties:
				return "遭遇池引用未配置的难度：%s" % value
		for entry in rule.levels:
			if not entry is Dictionary or not CONFIG._integer_between(entry.get("weight", 1), 1, 10000):
				return "遭遇权重必须是 1–10000 的整数。"
			var issue := CONFIG.level_error(str(entry.get("level", "")))
			if not issue.is_empty():
				return issue
		if rule.has("reward_config"):
			var issue := CONFIG.battle_reward_error({"reward_config": rule.reward_config})
			if not issue.is_empty():
				return issue
	# 所有可选幕、难度和进度均需有候选，不在玩家进入节点时才发现空池。
	for act in range(1, 4):
		for difficulty in difficulties:
			for progress in PHASES:
				for kind in (["boss"] if progress == "boss" else ["normal", "elite"]):
					if find_rule(data, act, progress, kind, difficulty).is_empty():
						return "缺少遭遇：第%d幕 / %s / %s / %s。" % [act, progress, kind, difficulty]
	return ""

# 按文件顺序采用第一条匹配规则，允许将特定幕/难度的规则放在通用规则之前。
static func find_rule(data: Dictionary, act: int, progress: String, kind: String, difficulty: String) -> Dictionary:
	for rule: Dictionary in data.rules:
		if matches(rule, act, progress, kind, difficulty):
			return rule
	return {}

static func pick(data: Dictionary, act: int, floor_number: int, rooms: int, kind: String, difficulty: String, rng: RandomNumberGenerator) -> Dictionary:
	var progress := phase(floor_number, rooms, kind == "boss")
	var rule := find_rule(data, act, progress, kind, difficulty)
	if rule.is_empty():
		return {}
	var total := 0
	for entry: Dictionary in rule.levels:
		total += int(entry.get("weight", 1))
	var roll := rng.randi_range(1, total)
	var selected: Dictionary = rule.levels.back()
	for entry: Dictionary in rule.levels:
		roll -= int(entry.get("weight", 1))
		if roll <= 0:
			selected = entry
			break
	var result := {"event_id": str(selected.level), "encounter": {"act": act, "phase": progress, "kind": kind, "difficulty": difficulty}}
	if rule.has("reward_config"):
		result.reward_config = rule.reward_config
	result.battle_rewards = CONFIG.battle_reward_content(result)
	return result
