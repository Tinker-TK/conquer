# 事件效果注册点：新增效果时扩展 TYPES、validate_effect、prepare、grant 即可。
@tool
extends RefCounted

const TYPES := ["random_relic", "random_potion", "choose_cards", "train_unit", "enhance_card", "remove_card", "duplicate_card", "enhance_random", "max_hp", "gamble", "gold", "heal"]
const ROUTE = preload("res://scripts/events/route_effects.gd")
const ConfigCache = preload("res://scripts/run/game_config_cache.gd")
static var _catalog: Array[Resource] = []
static var _catalog_fingerprint := ""
static var _pools: Dictionary = {}

static func resource_paths(directory: String) -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at(directory):
		var name := file.trim_suffix(".remap")
		if name.ends_with(".tres"):
			var path := directory.path_join(name)
			if not paths.has(path):
				paths.append(path)
	paths.sort()
	return paths

static func catalog() -> Array[Resource]:
	var paths := resource_paths("res://data/events")
	var fingerprint := ConfigCache.directory_fingerprint(paths)
	if not Engine.is_editor_hint() and fingerprint == _catalog_fingerprint:
		return _catalog.duplicate()
	var events: Array[Resource] = []
	for path in paths:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) if Engine.is_editor_hint() else ConfigCache.resource(path)
		if resource is EventDefinition:
			events.append(resource)
	if not Engine.is_editor_hint():
		_catalog = events
		_catalog_fingerprint = fingerprint
	return events.duplicate()

static func content(id: String) -> Dictionary:
	for event in catalog():
		if event.id == id:
			return event.to_content()
	return {}

static func pool(paths: Array, kind: String) -> Array[Resource]:
	var resources: Array[Resource] = []
	var directory: String = {"relic": "res://data/relics", "potion": "res://data/potions",
		"unit": "res://data/units", "effect": "res://data/cards"}[kind]
	var source: Array = resource_paths(directory) if paths.is_empty() else paths
	var fingerprint := ""
	if paths.is_empty() and not Engine.is_editor_hint():
		var source_paths: Array[String] = []
		source_paths.assign(source)
		fingerprint = ConfigCache.directory_fingerprint(source_paths)
		var cached: Dictionary = _pools.get(kind, {})
		if not cached.is_empty() and cached.fingerprint == fingerprint:
			return cached.resources.duplicate()
	var seen: Dictionary = {}
	for path in source:
		if not path is String or not path.begins_with("res://") or not ResourceLoader.exists(path):
			continue
		var resource := ConfigCache.resource(path)
		var valid := _valid_resource(resource, kind)
		var key := str(resource.id) if kind in ["relic", "potion"] and valid else str(path)
		if valid and not seen.has(key):
			resources.append(resource)
			seen[key] = true
	if not fingerprint.is_empty():
		_pools[kind] = {"fingerprint": fingerprint, "resources": resources}
	return resources.duplicate()

static func _valid_resource(resource: Resource, kind: String) -> bool:
	match kind:
		"relic":
			return resource is RelicDefinition and resource.id != &"" and resource.kind != RelicDefinition.Kind.BASE_DEFENCE
		"potion":
			return resource is PotionDefinition and resource.id != &""
		"unit":
			return CardInstance.is_player_card_data(resource) and (resource is UnitData or (resource is CardDefinition and resource.category == CardDefinition.Category.RECRUIT)) and not resource.card_name.strip_edges().is_empty() and resource.card_image != null
		"effect":
			return resource is CardDefinition and resource.category != CardDefinition.Category.RECRUIT and not resource.card_name.strip_edges().is_empty() and resource.card_image != null
	return false

static func validate_pool(value: Variant, kind: String, minimum: int) -> String:
	if not value is Array or value.size() > 500:
		return "奖励池必须是资源路径数组（最多 500 项）。"
	for path in value:
		if not path is String or not path.begins_with("res://") or not path.ends_with(".tres") or not ResourceLoader.exists(path):
			return "奖励资源不存在或路径无效：%s" % str(path)
		if not _valid_resource(ConfigCache.resource(path), kind):
			return "奖励池中有类型不匹配或已停用的资源：%s" % path
	if pool(value, kind).size() < minimum:
		return "%s奖励池至少需要 %d 个不同的有效资源。" % [{"unit": "兵种", "effect": "效果牌", "relic": "遗物", "potion": "药水"}[kind], minimum]
	return ""

static func validate_effect(effect: Variant) -> String:
	if not effect is Dictionary or not effect.get("type") in TYPES:
		return "事件效果类型无效。"
	match str(effect.type):
		"random_relic":
			return validate_pool(effect.get("pool", []), "relic", 1)
		"random_potion":
			return validate_pool(effect.get("pool", []), "potion", 1)
		"choose_cards":
			var total := 0
			for kind in ["unit", "effect"]:
				var offer: Variant = effect.get(kind + "_offer", 5)
				var picks: Variant = effect.get(kind + "_picks", 1)
				if not (offer is int or offer is float) or not (picks is int or picks is float) or offer != floor(float(offer)) or picks != floor(float(picks)) or offer < 0 or offer > 5 or picks < 0 or picks > 1 or picks > offer:
					return "每组提供 0–5 张候选，选择 0 或 1 张。"
				total += int(picks)
				if int(picks) > 0:
					var issue := validate_pool(effect.get(kind + "_pool", []), kind, int(offer))
					if not issue.is_empty():
						return issue
			if total == 0:
				return "至少启用一组选牌。"
		_:
			if effect.type in ROUTE.TYPES:
				return ROUTE.validate(effect)
	return ""

static func sample(resources: Array[Resource], count: int, rng: RandomNumberGenerator) -> Array[Resource]:
	var remaining: Array[Resource] = resources.duplicate()
	var result: Array[Resource] = []
	while result.size() < count and not remaining.is_empty():
		var index := rng.randi_range(0, remaining.size() - 1)
		result.append(remaining[index])
		remaining.remove_at(index)
	return result

static func prepare(choice: Dictionary, owned: Array, rng: RandomNumberGenerator, deck: Array = []) -> Dictionary:
	var effect: Dictionary = choice.get("effect", {})
	if effect.is_empty():
		return {"type": "legacy"}
	var error := validate_effect(effect)
	if not error.is_empty():
		return {"error": error}
	var result := {"type": effect.type}
	match str(effect.type):
		"random_relic":
			var available := pool(effect.get("pool", []), "relic")
			for relic in available.duplicate():
				for existing in owned:
					if existing.id == relic.id:
						available.erase(relic)
						break
			if available.is_empty():
				return {"error": "本事件的遗物已经全部拥有，可以选择离开。", "code": "relic_pool_exhausted"}
			var options := preload("res://scripts/items/relic_catalog.gd").sample(available, owned, 3, rng)
			if options.is_empty():
				return {"error": "当前奖励池已收集齐。", "code": "relic_pool_exhausted"}
			result.reward = options[0]
			result.options = options
		"random_potion":
			var potions = load("res://scripts/items/potion_catalog.gd")
			var run: Node = Engine.get_main_loop().root.get_node_or_null("RunManager") if not Engine.is_editor_hint() else null
			var available: Array = potions.available(pool(effect.get("pool", []), "potion"), run.current_act if run != null else 1, run)
			if available.is_empty():
				return {"error": "当前幕没有可获得的药水。"}
			result.reward = potions.pick(available, run.current_act if run != null else 1, rng)
		"choose_cards":
			result.unit_picks = int(effect.get("unit_picks", 1))
			result.effect_picks = int(effect.get("effect_picks", 1))
			result.units = sample(pool(effect.get("unit_pool", []), "unit"), int(effect.get("unit_offer", 5)), rng) if result.unit_picks > 0 else []
			result.effects = sample(pool(effect.get("effect_pool", []), "effect"), int(effect.get("effect_offer", 5)), rng) if result.effect_picks > 0 else []
		"train_unit", "enhance_card":
			result.candidates = []
			for card in deck:
				if card is CardInstance and card.can_upgrade(effect.type == "train_unit"):
					result.candidates.append(card)
			if result.candidates.is_empty():
				return {"error": "没有可训练的兵种卡（可能已达次数上限）。" if effect.type == "train_unit" else "没有可强化的非兵种卡（可能已达次数上限）。"}
		"remove_card", "duplicate_card", "enhance_random":
			result.candidates = ROUTE.candidates(deck, effect.type, effect.get("filter", "any"))
			if result.candidates.size() < int(effect.get("count", 1)):
				return {"error": "没有足够的合法目标（删牌后必须至少保留 1 张牌）。"}
			if effect.type == "enhance_random":
				var remaining: Array = result.candidates.duplicate()
				result.targets = []
				for i in int(effect.get("count", 1)):
					var index := rng.randi_range(0, remaining.size() - 1)
					result.targets.append(remaining.pop_at(index))
		"max_hp", "gold", "heal":
			result.amount = int(effect.amount)
		"gamble":
			result.won = rng.randf() < float(effect.chance)
			var branch: Dictionary = effect.win if result.won else effect.lose
			result.outcome = prepare({"effect": branch}, owned, rng, deck)
			if result.outcome.has("error"):
				return result.outcome
			result.result_text = effect.get("win_text" if result.won else "lose_text", "")
	return result

static func selection_error(prepared: Dictionary, run: Object, selected: Array[int], allocation: Vector2i = Vector2i.ZERO, branch: String = "") -> String:
	var kind := str(prepared.type)
	if kind == "choose_cards":
		for group in 2:
			var picks := int(prepared.get("unit_picks" if group == 0 else "effect_picks", 1))
			var offers: Array = prepared.units if group == 0 else prepared.effects
			if picks > 0 and (selected.size() <= group or selected[group] < 0 or selected[group] >= offers.size()):
				return "请从每个启用的候选组中恰好选择 1 张牌。"
	if kind in ["train_unit", "enhance_card", "remove_card", "duplicate_card"]:
		if selected.is_empty() or selected[0] < 0 or selected[0] >= prepared.candidates.size():
			return "请选择一张目标牌。"
		var card: CardInstance = prepared.candidates[selected[0]]
		if not run.deck.has(card):
			return "这张牌已不在本局牌组中。"
		if kind == "remove_card" and run.deck.size() <= 1:
			return "不能移除牌组最后一张牌。"
		if kind in ["train_unit", "enhance_card"]:
			if not card.can_upgrade(kind == "train_unit"):
				return "这张牌已达强化上限。"
			if kind == "train_unit":
				if card.needs_soldier_choice() and branch not in ["slash", "missile"]:
					return "请选择士兵强化技能：斩击或飞弹。"
				if allocation.x < 0 or allocation.y < 0 or allocation.x + allocation.y != card.ability_points + maxi(0, card.unit_data.upgrade_ability_points):
					return "请分配完本次训练的全部能力点。"
	if kind == "enhance_random":
		for card: CardInstance in prepared.targets:
			if not run.deck.has(card) or not card.can_upgrade(false):
				return "随机强化的候选已不再合法。"
	return ""

static func grant(prepared: Dictionary, run: Object, selected: Array[int], allocation: Vector2i = Vector2i.ZERO, branch: String = "") -> Dictionary:
	var issue := selection_error(prepared, run, selected, allocation, branch)
	if not issue.is_empty():
		return {"error": issue}
	match str(prepared.type):
		"random_relic":
			if prepared.get("options", []).size() > 1:
				if selected.is_empty() or selected[0] < 0 or selected[0] >= prepared.options.size():
					return {"error": "请选择一件遗物。"}
				prepared.reward = prepared.options[selected[0]]
			if not run.add_relic(prepared.reward):
				return {"error": "这件遗物已拥有，请离开继续冒险。"}
			return {"items": [prepared.reward]}
		"random_potion":
			if not run.add_potion(prepared.reward):
				return {"error": "这瓶药水已达到本局获取上限。"}
			return {"items": [prepared.reward]}
		"choose_cards":
			var cards: Array[Resource] = []
			if prepared.unit_picks > 0:
				cards.append(prepared.units[selected[0]])
			if prepared.effect_picks > 0:
				cards.append(prepared.effects[selected[1]])
			for card in cards:
				run.add_card(card)
			return {"cards": cards}
		"train_unit", "enhance_card":
			if selected.is_empty() or selected[0] < 0 or selected[0] >= prepared.candidates.size():
				return {"error": "请选择一张要升级的卡牌。"}
			var card: CardInstance = prepared.candidates[selected[0]]
			if not run.deck.has(card):
				return {"error": "这张牌已不在本局牌组中。"}
			if prepared.type == "train_unit" and card.needs_soldier_choice() and branch not in ["slash", "missile"]:
				return {"error": "请选择士兵强化技能：斩击或飞弹。"}
			var upgraded := card.train(allocation.x, allocation.y, branch) if prepared.type == "train_unit" else card.enhance()
			if not upgraded:
				return {"error": "卡牌已达强化上限，或能力点尚未正确分配。"}
			run.deck_changed.emit()
			return {"upgraded": card, "message": card.definition.card_name + " · " + card.upgrade_summary()}
		"remove_card":
			var card: CardInstance = prepared.candidates[selected[0]]
			run.deck.erase(card)
			run.deck_changed.emit()
			return {"message": "移除 · " + card.definition.card_name}
		"duplicate_card":
			var card: CardInstance = ROUTE.clone_card(prepared.candidates[selected[0]])
			run.deck.append(card)
			run.deck_changed.emit()
			return {"cards": [card.definition], "message": "复制保留原牌的训练、强化与永久增益。"}
		"enhance_random":
			var names: Array[String] = []
			for card: CardInstance in prepared.targets:
				card.enhance()
				names.append(card.definition.card_name + " · " + card.upgrade_summary())
			run.deck_changed.emit()
			return {"message": "随机强化：\n" + "\n".join(names)}
		"max_hp":
			run.max_hp += int(prepared.amount)
			run.hp += int(prepared.amount)
		"gold":
			run.gold += int(prepared.amount)
		"heal":
			run.hp += int(prepared.amount)
		"gamble":
			var result := grant(prepared.outcome, run, selected, allocation, branch)
			result.message = ("赌局成功" if prepared.won else "赌局失败 · 获得保底") + ("\n" + str(result.message) if result.has("message") else "")
			result.result_text = prepared.result_text
			return result
	return {}
