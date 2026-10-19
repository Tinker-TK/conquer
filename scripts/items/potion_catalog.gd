extends RefCounted

const CACHE = preload("res://scripts/run/game_config_cache.gd")
const WEIGHTS := [[70, 27, 3], [55, 38, 7], [40, 45, 15]]
const BOSS_WEIGHTS := [[0, 100, 0], [0, 60, 40], [0, 40, 60]]


static func all_potions() -> Array[PotionDefinition]:
	var result: Array[PotionDefinition] = []
	for file in DirAccess.get_files_at("res://data/potions"):
		var name := file.trim_suffix(".remap")
		if name.ends_with(".tres"):
			var resource := CACHE.resource("res://data/potions/" + name) as PotionDefinition
			if resource != null:
				result.append(resource)
	result.sort_custom(func(a: PotionDefinition, b: PotionDefinition): return a.id < b.id)
	return result


static func available(pool: Array, act: int, run: Node = null, shop: bool = false) -> Array[Resource]:
	var result: Array[Resource] = []
	for potion: PotionDefinition in pool:
		if act < potion.min_act or act > potion.max_act:
			continue
		if shop and potion.rarity == PotionDefinition.Rarity.LEGENDARY and act < 3:
			continue
		if run != null and not run.can_acquire_potion(potion):
			continue
		result.append(potion)
	return result


## 先抽稀有度再抽同级配方，扩充某级数量不会改变稀有度概率。
static func pick(pool: Array, act: int, rng: RandomNumberGenerator, boss: bool = false) -> PotionDefinition:
	var groups := [[], [], []]
	for potion: PotionDefinition in pool:
		groups[potion.rarity].append(potion)
	var weights: Array = (BOSS_WEIGHTS if boss else WEIGHTS)[clampi(act, 1, 3) - 1]
	var total := 0
	for index in 3:
		if not groups[index].is_empty():
			total += int(weights[index])
	# 自定义事件池可能只有一种稀有度，允许其显式配置。
	if total <= 0:
		return pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else null
	var roll := rng.randi_range(1, total)
	for index in 3:
		if groups[index].is_empty():
			continue
		roll -= int(weights[index])
		if roll <= 0:
			return groups[index][rng.randi_range(0, groups[index].size() - 1)]
	return null
