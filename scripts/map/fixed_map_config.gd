# 这玩意儿是干嘛的（核心逻辑）：检查地图工坊导出的路线，挡住会让玩家卡关的坏配置。
# 数据是咋流动的（数据流向）：JSON 文件 → 检查战斗、事件与连线 → 转换坐标 → 交给本局地图。
# 为啥这么写（选型决策）：先完整检查再使用，导入失败时不覆盖玩家之前选好的地图。
# 性能咋样（复杂度）：仅导入或开局读取一次，最多检查 500 个节点，不在每帧运行。
extends RefCounted

const MAX_BYTES := 2 * 1024 * 1024
const GAME_MAP_PATH := "res://data/run/game_map.json"
const ACT_COUNT := 3
const DEFAULT_REWARDS := "res://data/battle_rewards/normal.tres"
const ConfigCache = preload("res://scripts/run/game_config_cache.gd")
static var _file_cache: Dictionary = {}

# 第一幕保留旧路径，已应用的路线无需重新导入。
static func game_map_paths() -> Array[String]:
	return [GAME_MAP_PATH, "res://data/run/game_map_act_2.json", "res://data/run/game_map_act_3.json"]

# 节点内数值优先，未覆盖时使用加载的模板，再沿用关卡奖励和普通奖励。
static func battle_reward_content(node: Dictionary) -> Dictionary:
	if node.has("battle_rewards") and node.battle_rewards is Dictionary:
		var content: Dictionary = node.battle_rewards.duplicate(true)
		if BattleRewardConfig.content_error(content).is_empty():
			# JSON 数值回读为浮点数，统一金币整数与百分比浮点数。
			content.gold = int(content.gold)
			content.potion_chance = float(content.potion_chance)
			content.relic_chance = float(content.relic_chance)
		return content
	var path := str(node.get("reward_config", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var rewards := ConfigCache.resource(path) as BattleRewardConfig
		if rewards != null:
			return rewards.to_content()
	var level := level_path(str(node.get("event_id", "")))
	if not level.is_empty() and ResourceLoader.exists(level):
		var config := ConfigCache.resource(level) as BattleLevelConfig
		if config != null and config.victory_rewards != null:
			return config.victory_rewards.to_content()
	return (ConfigCache.resource(DEFAULT_REWARDS) as BattleRewardConfig).to_content()

static func battle_reward_error(node: Dictionary) -> String:
	if node.has("reward_config"):
		var path: Variant = node.reward_config
		if not path is String or (not path.is_empty() and (not path.begins_with("res://") or not path.ends_with(".tres") or not ResourceLoader.exists(path))):
			return "胜利奖励配置必须是项目中有效的 .tres 资源。"
		if not path.is_empty():
			var config := ConfigCache.resource(path) as BattleRewardConfig
			if config == null:
				return "请选择 BattleRewardConfig 战斗奖励资源。"
			var issue := config.validate()
			if not issue.is_empty():
				return issue
	if node.has("battle_rewards"):
		return BattleRewardConfig.content_error(node.battle_rewards)
	return BattleRewardConfig.content_error(battle_reward_content(node))


# 作用：把直接填写的关卡编号变成资源路径；id 为 level_001 这样的文件名，返回路径或空串。
static func level_path(id: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("^level_[A-Za-z0-9_-]+$")
	return "res://data/levels/%s.tres" % id if pattern.search(id) != null else ""


# 作用：检查直接指定的战斗关卡；id 为内容编号，返回空串表示可用。
static func level_error(id: String) -> String:
	var path := level_path(id)
	if path.is_empty():
		return "关卡编号格式错误，请填写 level_001 这样的文件名，不含路径和 .tres。"
	if not ResourceLoader.exists(path):
		return "找不到战斗关卡：%s" % path
	var config := ConfigCache.resource(path) as BattleLevelConfig
	if config == null:
		return "%s 不是 BattleLevelConfig 关卡配置。" % id
	return config.validate()


# 作用：读取玩家选中的文件；path 是 JSON 路径，返回配置或带 error 的失败结果。
static func read_file(path: String, revision: String = "") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "无法读取路线文件：%s" % error_string(FileAccess.get_open_error())}
	# 限制文件大小，避免误选其他大文件时让主菜单长时间无响应。
	if file.get_length() > MAX_BYTES:
		return {"error": "路线文件不能超过 2 MB。"}
	var text := file.get_as_text()
	if Engine.is_editor_hint():
		return parse_text(text)
	if revision.is_empty():
		revision = ConfigCache.refresh()
	var fingerprint := (text + revision).md5_text()
	var cached: Dictionary = _file_cache.get(path, {})
	if not cached.is_empty() and cached.fingerprint == fingerprint:
		return cached.result.duplicate(true)
	var result := parse_text(text)
	# 错误配置也按内容缓存，修复文件后会重新检查。
	_file_cache[path] = {"fingerprint": fingerprint, "result": result.duplicate(true)}
	return result


# 作用：解析并检查导出内容；text 是文件正文，返回 data 或便于玩家理解的 error。
static func parse_text(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text.trim_prefix("\ufeff")) != OK:
		return {"error": "JSON 第 %d 行有误：%s" % [json.get_error_line(), json.get_error_message()]}
	var error := validate(json.data)
	if not error.is_empty():
		return {"error": error}
	return {"data": json.data}


# 作用：检查整数范围；value 为 JSON 数值，low/high 为上下限，返回是否有效。
static func _integer_between(value: Variant, low: int, high: int) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and value == floor(float(value)) and value >= low and value <= high


# 作用：检查短文本；value 为字段值，limit 为最大长度，返回是否有非空内容。
static func _short_text(value: Variant, limit: int) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= limit


# 作用：检查地图结构与可达性；data 为解析后的数据，返回空串表示通过，否则返回原因。
static func validate(data: Variant) -> String:
	if not data is Dictionary:
		return "地图最外层必须是 JSON 对象。"
	if not _integer_between(data.get("schema_version"), 1, 1) or data.get("mode") != "fixed":
		return "仅支持地图工坊导出的 schema_version=1、mode=fixed 配置。"
	if not _short_text(data.get("name"), 80) or not _integer_between(data.get("floors"), 2, 30):
		return "地图需要名称（1–80 字）和 2–30 层的整数层数。"
	if not data.get("locations") is Array or data.locations.is_empty() or data.locations.size() > 500:
		return "地图需要 1–500 个节点。"
	if not data.get("starting_ids") is Array or data.starting_ids.is_empty():
		return "请至少设置一个出发点。"

	# 第一轮收齐节点，再检查连线；这样 JSON 中节点的排列顺序不会影响导入。
	var by_id: Dictionary = {}
	var checked: Dictionary = {}
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]{1,80}$")
	for node in data.locations:
		if not node is Dictionary or not node.get("id") is String:
			return "每个节点都需要字符串编号。"
		var id: String = node.id
		if pattern.search(id) == null or by_id.has(id):
			return "节点编号 %s 重复或格式不合法，请使用字母、数字、下划线和短横线。" % id
		if not _short_text(node.get("title"), 80):
			return "节点 %s 缺少名称或名称过长。" % id
		if not _integer_between(node.get("type"), 0, 7) or not _integer_between(node.get("floor"), 1, int(data.floors)):
			return "节点 %s 的类型或所在层不合法。" % id
		# 指定关卡不存在时在导入阶段提示，避免玩家进入节点后悄悄打了默认战场。
		if int(node.type) in [0, 3, 6]:
			var error := _checked_level(str(node.get("event_id", "")), checked)
			if not error.is_empty():
				return "节点 %s：%s" % [id, error]
			error = battle_reward_error(node)
			if not error.is_empty():
				return "节点 %s：%s" % [id, error]
		elif int(node.type) == 7:
			var issue := unknown_error(node, checked)
			if not issue.is_empty():
				return "节点 %s：%s" % [id, issue]
		elif int(node.type) == 5:
			var result: Dictionary = load("res://scripts/shop/shop_catalog.gd").read_catalog(str(node.get("shop_catalog", "res://data/shops/caravan.json")))
			if result.has("error"):
				return "节点 %s：%s" % [id, result.error]
		else:
			if node.has("event_pool"):
				if int(node.type) != 1 or not node.event_pool is String or not node.event_pool.begins_with("res://data/events/pools/") or not node.event_pool.ends_with(".json") or ".." in node.event_pool or not FileAccess.file_exists(node.event_pool):
					return "奇遇池必须是 data/events/pools 中有效的 JSON。"
			var error := _checked_event(event_content(node), checked)
			if not error.is_empty():
				return "节点 %s：%s" % [id, error]
		if not node.get("map_pos") is Dictionary:
			return "节点 %s 缺少 map_pos 坐标。" % id
		for axis in ["x", "y"]:
			var value: Variant = node.map_pos.get(axis)
			if not (value is int or value is float) or not is_finite(float(value)) or value < 0 or value > 1:
				return "节点 %s 的坐标必须在 0–1 之间。" % id
		if not node.get("next") is Array:
			return "节点 %s 的 next 必须是目标编号数组。" % id
		by_id[id] = node

	# 强制向上前进就不会形成循环；终点必须是 Boss，避免普通事件结束后无路可走。
	for node in data.locations:
		var targets: Dictionary = {}
		for target in node.next:
			if not target is String or not by_id.has(target):
				return "节点 %s 的路线引用了不存在的目标。" % node.id
			if targets.has(target):
				return "节点 %s 有重复连线。" % node.id
			if by_id[target].floor <= node.floor or by_id[target].map_pos.y >= node.map_pos.y:
				return "路线 %s → %s 必须指向更高层，且目标坐标必须在上方。" % [node.id, target]
			targets[target] = true
		if (int(node.type) == 3) != node.next.is_empty():
			return "节点 %s：终点必须是 Boss，Boss 不能再连接后续节点。" % node.id

	# 从全部起点走一遍，保证编辑器中摆出的每个地点在游戏里都能到达。
	var reached: Dictionary = {}
	var pending: Array = []
	for id in data.starting_ids:
		if not id is String or not by_id.has(id) or reached.has(id):
			return "出发点编号不存在或重复。"
		reached[id] = true
		pending.append(id)
	while not pending.is_empty():
		var id: String = pending.pop_back()
		for target in by_id[id].next:
			if not reached.has(target):
				reached[target] = true
				pending.append(target)
	for id in by_id:
		if not reached.has(id):
			return "节点 %s 无法从任何出发点到达。" % id
	return ""


# 作用：把已校验的 JSON 节点转换成游戏节点；data 是合法配置，返回包含 Vector2 的节点列表。
static func to_locations(data: Dictionary) -> Array[Dictionary]:
	var locations: Array[Dictionary] = []
	for raw in data.locations:
		# 拷贝后再转换，避免游戏把原始 JSON 改成无法再次导出的坐标对象。
		var node: Dictionary = raw.duplicate(true)
		if int(raw.type) in [0, 3, 6]:
			# 开局冻结模板的数值，编辑项目资源不会改动正在进行的冒险。
			node.battle_rewards = battle_reward_content(raw)
		if int(raw.type) in [1, 2, 4]:
			node.event = event_content(raw).duplicate(true)
			node.erase("event_source") # 本局使用开局时的配方快照。
			node.event_id = str(raw.get("event_id", ""))
		node.type = int(raw.type)
		node.floor = int(raw.floor)
		node.map_pos = Vector2(float(raw.map_pos.x), float(raw.map_pos.y))
		locations.append(node)
	return locations


# 问号房必须携带全部候选的内容快照，避免读档后再依赖已修改的遭遇配置。
static func unknown_error(node: Dictionary, checked: Dictionary = {}) -> String:
	if not node.get("unknown_options") is Dictionary:
		return "问号房缺少 unknown_options 候选内容。"
	for kind in [0, 1, 4, 5, 6]:
		var option: Variant = node.unknown_options.get(str(kind))
		if not option is Dictionary or option.get("type") != kind:
			return "问号房缺少类型 %d 的候选。" % kind
		var issue := ""
		if kind in [0, 6]:
			issue = _checked_level(str(option.get("event_id", "")), checked)
			if issue.is_empty():
				issue = battle_reward_error(option)
		elif kind == 5:
			var result: Dictionary = load("res://scripts/shop/shop_catalog.gd").read_catalog(str(option.get("shop_catalog", "res://data/shops/caravan.json")))
			issue = str(result.get("error", ""))
		else:
			if option.has("event_pool") and (not option.event_pool is String or not option.event_pool.begins_with("res://data/events/pools/") or ".." in option.event_pool or not FileAccess.file_exists(option.event_pool)):
				return "问号房的事件池无效。"
			issue = _checked_event(event_content(option), checked)
		if not issue.is_empty():
			return issue
	return ""


# 一张随机地图会复用大量相同宝箱、营火和候选。每次完整校验内部去重，下一次仍重新检查资源。
static func _checked_event(content: Variant, checked: Dictionary) -> String:
	var key := "event:" + JSON.stringify(content, "", true)
	if not checked.has(key):
		checked[key] = event_error(content)
	return str(checked[key])

static func _checked_level(id: String, checked: Dictionary) -> String:
	var key := "level:" + id
	if not checked.has(key):
		checked[key] = level_error(id)
	return str(checked[key])


static func default_unknown_options() -> Dictionary:
	return {
		"0": {"type": 0, "title": "普通战斗", "event_id": "level_001"},
		"1": {"type": 1, "title": "旅途奇遇", "event_id": "", "event_pool": "res://data/events/pools/act1.json"},
		"4": {"type": 4, "title": "遗物宝箱", "event_id": ""},
		"5": {"type": 5, "title": "旅途商队", "event_id": "", "shop_catalog": "res://data/shops/caravan.json"},
		"6": {"type": 6, "title": "精英战斗", "event_id": "level_elite_mid", "reward_config": "res://data/battle_rewards/elite.tres"}
	}


# 作用：提供旧地图和内置地图的事件模板；id 为旧事件编号，返回可直接编辑的描述与选项。
static func default_event(id: String) -> Dictionary:
	var custom: Dictionary = load("res://scripts/events/event_rewards.gd").content(id)
	if not custom.is_empty():
		return custom
	if id == "campfire":
		return {"illustration": "res://assets/ui/events/illustrations/campfire.png", "description": "微弱的火光让士兵们暂时获得喘息。", "choices": [
			{"text": "休憩整备", "heal": 0, "heal_percent": 30.0, "gold": 0},
			{"text": "训练", "heal": 0, "gold": 0, "effect": {"type": "train_unit"}},
			{"text": "强化", "heal": 0, "gold": 0, "effect": {"type": "enhance_card"}},
			{"text": "离开", "heal": 0, "gold": 0, "leave": true}]}
	if id == "abandoned_camp":
		return {"illustration": "res://assets/ui/events/illustrations/abandoned-camp.png", "description": "你发现一座被遗弃的兵营。帐篷中还有一些可用物资。", "choices": [
			{"text": "搜刮物资", "heal": 0, "gold": 15}, {"text": "谨慎离开", "heal": 0, "gold": 0}]}
	return {}


# 作用：读取节点内的事件内容；node 为地图节点，返回配置，老模板仅在缺少 event 字段时补齐。
static func event_content(node: Dictionary) -> Variant:
	if not str(node.get("event_pool", "")).is_empty():
		return load("res://scripts/events/event_pool.gd").fallback()
	# 宝箱使用固定规则，不受从其他节点类型留下的事件选项影响。
	if int(node.get("type", -1)) == 4:
		return treasure_event()
	if node.get("event_source", "inline") == "catalog":
		return default_event(str(node.get("event_id", "")))
	if node.has("event"):
		return node.event
	return default_event(str(node.get("event_id", "")))


# 作用：宝箱统一从全部有效且未持有的遗物中抽取一件；返回事件会话使用的配方。
static func treasure_event() -> Dictionary:
	return {"title": "遗物宝箱", "illustration": "res://assets/ui/events/illustrations/treasure-closed.png", "description": "一只古老的宝箱静候在路旁。\n\n点击宝箱，打开它并获得一件随机遗物。",
		"result_text": "箱盖缓缓开启，古老的力量重见天日。\n这件遗物将陪伴你接下来的征途。",
		"choices": [{"text": "打开宝箱", "heal": 0, "gold": 0, "effect": {"type": "random_relic"}},
			{"text": "继续前进", "heal": 0, "gold": 0, "leave": true}]}


# 作用：验证事件面板和奖励；event 为事件数据，返回空串代表有效，否则返回原因。
static func event_error(event: Variant) -> String:
	if not event is Dictionary or not _short_text(event.get("description"), 2000):
		return "请在地图工坊填写事件描述。"
	if not event.get("choices") is Array or event.choices.size() < 2 or event.choices.size() > 8:
		return "事件需要 2–8 个选项。"
	if event.has("illustration") and (not event.illustration is String or (not event.illustration.is_empty() and (not event.illustration.begins_with("res://") or not ResourceLoader.exists(event.illustration) or not load(event.illustration) is Texture2D))):
		return "事件插图必须是项目中有效的图片资源。"
	for choice in event.choices:
		if not choice is Dictionary or not _short_text(choice.get("text"), 80):
			return "请填写选项文字（最多 80 字）。"
		# 当前只支持正向回血和金币奖励，防止误填负数造成隐含扣血或扣费。
		if not _integer_between(choice.get("heal", 0), 0, 9999) or not _integer_between(choice.get("gold", 0), 0, 9999):
			return "回血量和金币奖励必须是 0–9999 的整数。"
		var percent: Variant = choice.get("heal_percent", 0.0)
		if not (percent is int or percent is float) or not is_finite(float(percent)) or percent < 0 or percent > 100:
			return "休憩回复百分比必须是 0–100 的有限数字。"
		var cost: Variant = choice.get("cost", {})
		if not cost is Dictionary:
			return "选项成本必须是对象。"
		for key in cost:
			if key not in ["gold", "hp", "max_hp"] or not _integer_between(cost[key], 0, 9999):
				return "成本只允许 gold / hp / max_hp 的非负整数。"
		if choice.has("effect") and choice.has("effects"):
			return "一个选项不能同时填写 effect 与 effects。"
		if choice.has("effects") and (not choice.effects is Array or choice.effects.is_empty() or choice.effects.size() > 5):
			return "复合效果需要 1–5 个效果。"
		for effect in load("res://scripts/events/route_effects.gd").effects(choice):
			var issue: String = load("res://scripts/events/event_rewards.gd").validate_effect(effect)
			if not issue.is_empty():
				return issue
	return ""
