## 遗物奖励共用的无重复、稀有度和流派加权抽取。
extends RefCounted

static func has_relic(owned: Array, id: StringName) -> bool:
	return owned.any(func(relic: RelicDefinition): return relic.id == id)

static func weight(relic: RelicDefinition, owned: Array) -> float:
	var tags: Array[StringName] = []
	for item: RelicDefinition in owned:
		for tag in item.tags:
			if not tags.has(tag):
				tags.append(tag)
	var value := 0.8
	for tag in relic.tags:
		if tags.has(tag):
			value = 1.5
	for pair in [[&"wide", &"tall"], [&"death", &"guard"]]:
		if (relic.tags.has(pair[0]) and tags.has(pair[1])) or (relic.tags.has(pair[1]) and tags.has(pair[0])):
			value *= 0.3
	return value

static func sample(pool: Array, owned: Array, count: int, rng: RandomNumberGenerator, boss_only: bool = false, rare_chance: float = 0.30) -> Array[Resource]:
	var available: Array[Resource] = []
	for relic: RelicDefinition in pool:
		if has_relic(owned, relic.id) or (boss_only and relic.rarity != RelicDefinition.Rarity.BOSS) or (not boss_only and relic.rarity == RelicDefinition.Rarity.BOSS):
			continue
		available.append(relic)
	var result: Array[Resource] = []
	while result.size() < count and not available.is_empty():
		var rarity := RelicDefinition.Rarity.BOSS if boss_only else (RelicDefinition.Rarity.RARE if rng.randf() < rare_chance else RelicDefinition.Rarity.COMMON)
		var group := available.filter(func(relic: RelicDefinition): return relic.rarity == rarity)
		if group.is_empty():
			group = available
		var total := 0.0
		for relic: RelicDefinition in group:
			total += weight(relic, owned)
		var roll := rng.randf() * total
		var index := group.size() - 1
		for i in group.size():
			roll -= weight(group[i], owned)
			if roll <= 0:
				index = i
				break
		result.append(group[index])
		available.erase(group[index])
	return result
