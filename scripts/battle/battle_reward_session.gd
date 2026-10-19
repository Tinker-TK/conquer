# 胜利时抽取一次，点击才入库；卡牌候选、领取和跳过状态在查看地图后仍保留。
extends RefCounted

signal changed
const CATALOG = preload("res://scripts/events/event_rewards.gd")
const POTIONS = preload("res://scripts/items/potion_catalog.gd")
const RELICS = preload("res://scripts/items/relic_catalog.gd")
var run: Node
var run_serial: int
var offers: Array[Dictionary] = []
var candidates: Array[Resource] = []
var closed := false
var error := ""

static func card_pool() -> Array[Resource]:
	var cards: Array[Resource] = []
	for data in CATALOG.pool([], "unit") + CATALOG.pool([], "effect"):
		# 敌军数据也存放在 units 目录，只有已有己方卡牌可进入胜利奖励。
		if data is UnitData and data.unit_team != "team_a":
			continue
		if data is CardDefinition and data.category == CardDefinition.Category.RECRUIT and data.summon_unit.unit_team != "team_a":
			continue
		cards.append(data)
	return cards

static func _drops(chance: float, rng: RandomNumberGenerator) -> bool:
	# 不依赖浮点随机数的端点，确保 0% 不掉落、100% 必定掉落。
	return chance >= 100.0 or (chance > 0.0 and rng.randf() < chance / 100.0)

func initialize(owner_run: Node, content: Dictionary, random_seed: int = -1, boss_reward: bool = false) -> void:
	run = owner_run
	run_serial = run.run_serial
	error = BattleRewardConfig.content_error(content)
	if not error.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	if random_seed < 0:
		rng.randomize()
	else:
		rng.seed = random_seed
	var boss: bool = boss_reward or run.is_boss_battle()
	var elite: bool = run.is_elite_battle()
	candidates = preload("res://scripts/cards/card_reward_catalog.gd").sample(card_pool(), 3, rng, 0.50 if elite else 0.30, boss)
	offers = [{"kind": "gold", "amount": int(content.gold), "state": "available"},
		{"kind": "cards", "state": "available"}]
	if _drops(float(content.potion_chance), rng):
		var potions := POTIONS.available(CATALOG.pool([], "potion"), run.current_act, run)
		if elite:
			potions = potions.filter(func(p: PotionDefinition): return p.rarity != PotionDefinition.Rarity.COMMON)
		if not potions.is_empty():
			offers.append({"kind": "potion", "data": POTIONS.pick(potions, run.current_act, rng, boss), "state": "available"})
	var relic_chance: float = 100.0 if boss else float(content.relic_chance) + (15.0 if RELICS.has_relic(run.relics, &"relic_hunter") else 0.0)
	if _drops(relic_chance, rng):
		var options := RELICS.sample(CATALOG.pool([], "relic"), run.relics, 3 if boss or run.relics.is_empty() else 1, rng, boss, 0.50 if elite else 0.30)
		if not options.is_empty():
			offers.append({"kind": "relic", "data": options[0], "options": options, "state": "available"})

func is_active() -> bool:
	return not closed and is_instance_valid(run) and run.run_serial == run_serial and error.is_empty()

func available(index: int) -> bool:
	return is_active() and index >= 0 and index < offers.size() and offers[index].state == "available"

func claim(index: int, card_index: int = -1) -> bool:
	if not available(index):
		return false
	var offer := offers[index]
	if offer.kind == "cards" and (card_index < 0 or card_index >= candidates.size()):
		return false
	if offer.kind == "potion" and not run.can_acquire_potion(offer.data):
		return false
	if offer.kind == "relic" and offer.get("options", []).size() > 1:
		if card_index < 0 or card_index >= offer.options.size():
			return false
		offer.data = offer.options[card_index]
	# 先锁定状态再发送库存变化，防止重复输入和信号重入发放两次。
	offer.state = "claimed"
	match str(offer.kind):
		"gold":
			run.gold += offer.amount
		"cards":
			run.add_card(candidates[card_index])
		"potion":
			run.add_potion(offer.data)
		"relic":
			if not run.add_relic(offer.data):
				offer.state = "skipped"
	changed.emit()
	return true

func skip_cards() -> void:
	for index in offers.size():
		if offers[index].kind == "cards" and available(index):
			offers[index].state = "skipped"
			changed.emit()
			return

func remaining() -> int:
	var count := 0
	for offer in offers:
		if offer.state == "available":
			count += 1
	return count

func close() -> void:
	closed = true
	for offer in offers:
		if offer.state == "available":
			offer.state = "skipped"
	changed.emit()
