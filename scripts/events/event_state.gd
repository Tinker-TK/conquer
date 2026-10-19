@tool
extends RefCounted
# 预览副本和失败回滚快照；正式牌的实例身份保持不变。
signal deck_changed
signal items_changed
signal stats_changed
const ROUTE = preload("res://scripts/events/route_effects.gd")
var hp := 80:
	set(value): hp = clampi(value, 0, max_hp)
var max_hp := 80:
	set(value):
		max_hp = maxi(1, value)
		hp = mini(hp, max_hp)
var gold := 99
var current_act := 1
var deck: Array[CardInstance] = []
var relics: Array[RelicDefinition] = []
var potions: Array[PotionDefinition] = []
var pending_potions: Array[PotionDefinition] = []
var potion_capacity := 3
var potion_use_counts: Dictionary = {}
var relic_draw_counts: Dictionary = {}
var base_defence := 0
var bonus_energy_max := 0
var originals: Array[CardInstance] = []
var original_definitions: Array[CardDefinition] = []
var original_units: Array[UnitData] = []

func capture(run: Object) -> void:
	if run == null:
		var rewards = load("res://scripts/events/event_rewards.gd")
		for recipe in rewards.pool([], "unit") + rewards.pool([], "effect"):
			deck.append(CardInstance.new(recipe))
		return
	for key in ["max_hp", "hp", "gold", "current_act", "base_defence", "bonus_energy_max"]:
		set(key, run.get(key))
	for key in ["potion_use_counts", "relic_draw_counts"]:
		set(key, run.get(key).duplicate(true))
	relics.assign(run.relics)
	potions.assign(run.potions)
	pending_potions.assign(run.pending_potions)
	potion_capacity = run.potion_capacity
	originals.assign(run.deck)
	for card: CardInstance in run.deck:
		deck.append(ROUTE.clone_card(card))
		original_definitions.append(card.definition)
		original_units.append(card.unit_data)

func restore(run: Object) -> void:
	for i in originals.size():
		var card: CardInstance = originals[i]
		card.definition = original_definitions[i]
		card.unit_data = original_units[i]
		for key in deck[i].persistent_upgrade_state():
			card.set(key, deck[i].persistent_upgrade_state()[key])
		card.permanent_buffs.assign(deck[i].permanent_buffs.duplicate(true))
	run.deck.assign(originals)
	run.relics.assign(relics)
	run.potions.assign(potions)
	run.pending_potions.assign(pending_potions)
	for key in ["max_hp", "hp", "gold", "base_defence", "bonus_energy_max", "potion_use_counts", "relic_draw_counts"]:
		run.set(key, get(key))
	run.deck_changed.emit()
	run.items_changed.emit()
	run.stats_changed.emit()

func add_card(recipe: Resource) -> void:
	deck.append(CardInstance.new(recipe))
	deck_changed.emit()

func can_acquire_potion(potion: PotionDefinition) -> bool:
	if potion == null:
		return false
	var count := int(potion_use_counts.get(potion.id, 0))
	for owned in potions + pending_potions:
		if owned.id == potion.id:
			count += 1
	return potion.max_per_run <= 0 or count < potion.max_per_run

func add_potion(potion: PotionDefinition) -> bool:
	if not can_acquire_potion(potion):
		return false
	if potions.size() < potion_capacity:
		potions.append(potion.duplicate(true))
	else:
		pending_potions.append(potion.duplicate(true))
	return true

func add_relic(relic: RelicDefinition) -> bool:
	for owned in relics:
		if owned.id == relic.id:
			return false
	relics.append(relic.duplicate(true))
	if preload("res://scripts/items/relic_catalog.gd").has_relic(relics, &"relic_hunter"):
		hp += 10
	if relic.kind == RelicDefinition.Kind.BASE_HEALTH:
		max_hp += relic.amount
		hp += relic.amount
	elif relic.kind == RelicDefinition.Kind.MAX_ENERGY:
		bonus_energy_max += relic.amount
	return true
