extends RefCounted

const DEFAULT_PATH := "res://data/shops/caravan.json"
const ConfigCache = preload("res://scripts/run/game_config_cache.gd")

# 商品池与价格在 JSON 配置；导入地图时同样检查，避免进入商店后才发现坏资源。
static func read_catalog(path: String = DEFAULT_PATH) -> Dictionary:
	if not path.begins_with("res://data/shops/") or not path.ends_with(".json") or ".." in path:
		return {"error": "商店配置必须位于 res://data/shops/，使用 .json 文件。"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "找不到商店配置：" + path}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"error": "商店 JSON 格式错误：" + json.get_error_message()}
	var data: Variant = json.data
	if not data is Dictionary:
		return {"error": "商店配置必须为对象。"}
	for key in ["recruits", "cards", "relics", "potions"]:
		if not data.get(key) is Array or data[key].is_empty():
			return {"error": "商店缺少商品池：" + key}
		var seen: Dictionary = {}
		for entry in data[key]:
			if not entry is Dictionary or not entry.get("path") is String or not _price(entry.get("price")):
				return {"error": "商店商品需要资源路径与 1–9999 的整数价格。"}
			if seen.has(entry.path) or not entry.path.begins_with("res://data/") or not ResourceLoader.exists(entry.path):
				return {"error": "商品资源不存在或重复：" + entry.path}
			seen[entry.path] = true
			var resource := ConfigCache.resource(entry.path)
			var valid := false
			match key:
				"recruits":
					valid = resource is UnitData and resource.unit_team == "team_a"
				"cards":
					valid = resource is CardDefinition and resource.category != CardDefinition.Category.RECRUIT
				"relics":
					valid = resource is RelicDefinition and resource.id != &"" and resource.kind != RelicDefinition.Kind.BASE_DEFENCE
				"potions":
					valid = resource is PotionDefinition and resource.id != &""
			if not valid:
				return {"error": "商品类型与商品池不匹配：" + entry.path}
	for key in ["recruit_count", "card_count", "relic_count", "potion_count"]:
		var capacity: int = {"recruit_count": 3, "card_count": 4, "relic_count": 3, "potion_count": 3}[key]
		if not _price(data.get(key)) or data[key] > capacity:
			return {"error": "商店 %s 陈列数量必须为 1–%d 的整数。" % [key, capacity]}
	return {"data": data}

static func _price(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= 1 and value <= 9999
