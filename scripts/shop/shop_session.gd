extends RefCounted

signal changed
const CATALOG = preload("res://scripts/shop/shop_catalog.gd")
const POTIONS = preload("res://scripts/items/potion_catalog.gd")
var run: Node
var node_id := ""
var offers: Array[Dictionary] = []
var removal_used := false
var finished := false
var title := "旅途商队"

func initialize(owner_run: Node, location_id: String, catalog: Dictionary, seed_value: int = 0) -> void:
	run = owner_run
	node_id = location_id
	title = str(catalog.get("name", "旅途商队"))
	var rng := RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	for kind in ["recruit", "card", "relic", "potion"]:
		var key: String = {"recruit": "recruits", "card": "cards", "relic": "relics", "potion": "potions"}[kind]
		var pool: Array = catalog[key].duplicate(true)
		if kind == "card" and int(catalog.card_count) > 0:
			var rare_cards := pool.filter(func(entry: Dictionary): return CATALOG.ConfigCache.resource(entry.path).rarity == CardDefinition.Rarity.RARE)
			if not rare_cards.is_empty():
				var entry: Dictionary = rare_cards[rng.randi_range(0, rare_cards.size() - 1)]
				pool.erase(entry)
				offers.append({"kind": kind, "data": CATALOG.ConfigCache.resource(entry.path), "price": int(entry.price), "original_price": int(entry.price), "sold": false, "sale": false})
		if kind == "relic":
			pool = pool.filter(func(entry: Dictionary):
				var relic: RelicDefinition = CATALOG.ConfigCache.resource(entry.path)
				return relic.rarity != RelicDefinition.Rarity.BOSS and not _owns_relic(relic))
			# 可售稀有遗物尚未集齐时，第一格保底稀有。
			var rare: Array = pool.filter(func(entry: Dictionary): return CATALOG.ConfigCache.resource(entry.path).rarity == RelicDefinition.Rarity.RARE)
			if not rare.is_empty() and int(catalog.relic_count) > 0:
				var entry: Dictionary = rare[rng.randi_range(0, rare.size() - 1)]
				pool.erase(entry)
				offers.append({"kind": kind, "data": CATALOG.ConfigCache.resource(entry.path), "price": int(entry.price), "original_price": int(entry.price), "sold": false, "sale": false})
		if kind == "potion":
			var recipes: Array[Resource] = []
			for entry: Dictionary in pool:
				recipes.append(CATALOG.ConfigCache.resource(entry.path))
			var available := POTIONS.available(recipes, run.current_act, run, true)
			for index in mini(int(catalog.potion_count), available.size()):
				var recipe := POTIONS.pick(available, run.current_act, rng)
				available.erase(recipe)
				var price := recipe.price
				for entry: Dictionary in pool:
					if entry.path == recipe.resource_path:
						price = int(entry.price)
						break
				offers.append({"kind": kind, "data": recipe, "price": price, "original_price": price, "sold": false, "sale": false})
			continue
		var existing := offers.filter(func(offer: Dictionary): return offer.kind == kind).size()
		for index in mini(int(catalog[kind + "_count"]) - existing, pool.size()):
			var entry: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
			offers.append({"kind": kind, "data": CATALOG.ConfigCache.resource(entry.path), "price": int(entry.price), "original_price": int(entry.price), "sold": false, "sale": false})
	# 一张征召或功能牌打五折；打开卡组或地图不会重新抽商品。
	var card_indices: Array[int] = []
	for index in offers.size():
		if offers[index].kind in ["recruit", "card"]:
			card_indices.append(index)
	if not card_indices.is_empty():
		var sale: Dictionary = offers[card_indices[rng.randi_range(0, card_indices.size() - 1)]]
		sale.price = maxi(1, int(ceil(float(sale.price) * 0.5)))
		sale.sale = true
	if preload("res://scripts/items/relic_catalog.gd").has_relic(run.relics, &"merchant_seal"):
		for offer in offers:
			offer.price = maxi(1, ceili(float(offer.price) * 0.8))

func _owns_relic(relic: RelicDefinition) -> bool:
	for owned in run.relics:
		if owned.id == relic.id:
			return true
	return false

func is_active() -> bool:
	return is_instance_valid(run) and not finished and run.shop_visits.get(node_id) == self

func purchase_error(index: int) -> String:
	if not is_active():
		return "商店已经结束。"
	if index < 0 or index >= offers.size():
		return "商品不存在。"
	var offer: Dictionary = offers[index]
	if offer.sold:
		return "这件商品已经售罄。"
	if offer.kind == "relic" and _owns_relic(offer.data):
		return "已经拥有这件遗物。"
	if offer.kind == "potion" and not run.can_acquire_potion(offer.data):
		return "这瓶药水已达到本局获取上限。"
	if run.gold < offer.price:
		return "金币不足，还需要 %d 金币。" % (offer.price - run.gold)
	return ""

func purchase(index: int) -> String:
	var error := purchase_error(index)
	if not error.is_empty():
		return error
	var offer: Dictionary = offers[index]
	# 先锁住商品再通知 HUD，快速连点与信号重入也只能扣款一次。
	offer.sold = true
	run.gold -= offer.price
	match offer.kind:
		"recruit", "card":
			run.add_card(offer.data)
		"relic":
			run.add_relic(offer.data)
		"potion":
			run.add_potion(offer.data)
	changed.emit()
	return ""

func removal_price() -> int:
	var price: int = 75 + 25 * run.shop_removal_count
	return maxi(1, ceili(price * 0.8)) if preload("res://scripts/items/relic_catalog.gd").has_relic(run.relics, &"merchant_seal") else price

func removal_error() -> String:
	if not is_active():
		return "商店已经结束。"
	if removal_used:
		return "本店删牌服务已使用。"
	if run.deck.size() <= 1:
		return "卡组至少需要保留一张牌。"
	if run.gold < removal_price():
		return "删牌需要 %d 金币，还差 %d。" % [removal_price(), removal_price() - run.gold]
	return ""

func remove_card(card: CardInstance) -> String:
	var error := removal_error()
	if not error.is_empty():
		return error
	if card == null or not run.deck.has(card):
		return "这张牌不在当前卡组中。"
	var price := removal_price()
	removal_used = true
	run.deck.erase(card)
	run.shop_removal_count += 1
	run.gold -= price
	run.deck_changed.emit()
	changed.emit()
	return ""

func finish() -> void:
	finished = true
	changed.emit()
