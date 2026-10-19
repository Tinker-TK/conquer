## 先抽品质再抽同品质牌，避免扩充普通池后稀有率被稀释。
extends RefCounted

static func rare(card: Resource) -> bool:
	return card is CardDefinition and card.rarity == CardDefinition.Rarity.RARE

static func sample(pool: Array[Resource], count: int, rng: RandomNumberGenerator, rare_chance: float = 0.30, boss: bool = false) -> Array[Resource]:
	var remaining := pool.duplicate()
	var result: Array[Resource] = []
	while result.size() < count and not remaining.is_empty():
		var want_rare := rng.randf() < rare_chance
		if result.is_empty():
			want_rare = boss # 普通首格保底普通；首领首格保底稀有。
		var group := remaining.filter(func(card: Resource): return rare(card) == want_rare)
		if group.is_empty():
			group = remaining
		var choice: Resource = group[rng.randi_range(0, group.size() - 1)]
		remaining.erase(choice)
		result.append(choice)
	return result
