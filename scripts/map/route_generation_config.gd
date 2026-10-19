# 配置不进入存档恢复流程；只有新局读取并验证，旧局只使用已生成的快照。
@tool
extends RefCounted

const PATH := "res://data/map_generation/route_rules.json"
const CONFIG = preload("res://scripts/map/fixed_map_config.gd")
const CATALOG = preload("res://scripts/map/encounter_catalog.gd")

static func read_file(path: String = PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > CONFIG.MAX_BYTES:
		return {"error": "随机路线配置无法读取或超过 2 MB：%s" % path}
	var rules: Variant = JSON.parse_string(file.get_as_text())
	var issue := validate(rules)
	if not issue.is_empty():
		return {"error": issue}
	var encounters: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(rules.encounter_catalog)))
	issue = CATALOG.validate(encounters, rules.difficulties.keys())
	if not issue.is_empty():
		return {"error": issue}
	return {"data": rules, "encounters": encounters}

static func validate(rules: Variant) -> String:
	if not rules is Dictionary or rules.get("schema_version") != 1 or not CONFIG._integer_between(rules.get("config_version"), 1, 999999) or not rules.get("enabled") is bool:
		return "随机路线需要 schema_version=1、config_version 和 enabled。"
	for field in ["rooms", "columns", "paths", "shops", "max_prune_iterations"]:
		var limits: Array = {"rooms": [12, 24], "columns": [3, 9], "paths": [2, 10], "shops": [0, 8], "max_prune_iterations": [1, 50]}[field]
		if not CONFIG._integer_between(rules.get(field), int(limits[0]), int(limits[1])):
			return "随机路线参数 %s 超出范围。" % field
	for field in ["rest_quota", "unknown_quota"]:
		var pair: Variant = rules.get(field)
		if not pair is Array or pair.size() != 2 or not CONFIG._integer_between(pair[0], 0, 30) or not CONFIG._integer_between(pair[1], int(pair[0]), 30):
			return "随机路线配额 %s 应为 [最小值, 最大值]。" % field
	if not rules.get("difficulties") is Dictionary or rules.difficulties.is_empty():
		return "随机路线缺少难度档。"
	for tier in rules.difficulties.values():
		if not tier is Dictionary or not CONFIG._integer_between(tier.get("elites"), 0, 15):
			return "难度档需要 0–15 的精英数量。"
	if rules.get("difficulty") not in rules.difficulties or not rules.get("seed", "") is String or str(rules.get("seed", "")).length() > 64:
		return "随机路线默认难度或种子无效。"
	if not rules.get("act_names") is Array or rules.act_names.size() != 3 or not rules.get("event_pools") is Array or rules.event_pools.size() != 3:
		return "请为三幕分别配置名称和事件池。"
	for name in rules.act_names:
		if not CONFIG._short_text(name, 80):
			return "幕名称应为 1–80 字。"
	for path in rules.event_pools:
		if not path is String or not path.begins_with("res://data/events/pools/") or not FileAccess.file_exists(path):
			return "随机路线事件池路径无效。"
	if not rules.get("encounter_catalog") is String or not FileAccess.file_exists(rules.encounter_catalog):
		return "随机路线遭遇池路径无效。"
	var shop: Dictionary = load("res://scripts/shop/shop_catalog.gd").read_catalog(str(rules.get("shop_catalog", "")))
	if shop.has("error"):
		return str(shop.error)
	if not rules.get("unknown_base_odds") is Dictionary:
		return "问号房需要基础概率。"
	var total := 0.0
	for kind in ["battle", "elite", "shop", "treasure"]:
		var chance: Variant = rules.unknown_base_odds.get(kind)
		if not (chance is int or chance is float) or not is_finite(float(chance)) or chance < 0 or chance > 1:
			return "问号房概率应为 0–1 的数字。"
		total += float(chance)
	return "问号房基础概率之和不能超过 1。" if total > 1.0 else ""
