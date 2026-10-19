extends Node
const CATALOG = preload("res://scripts/items/potion_catalog.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	var recipes := CATALOG.all_potions()
	check(recipes.size() == 40, "正式药水目录应有40瓶")
	var ids := {}
	var counts := [0, 0, 0]
	for recipe in recipes:
		check(not ids.has(recipe.id), "药水ID唯一：" + recipe.id)
		ids[recipe.id] = true
		counts[recipe.rarity] += 1
		check(recipe.icon != null and (recipe.kind != PotionDefinition.Kind.EFFECTS or recipe.icon.get_size() == Vector2(64, 64)), "图标存在，新瓶64像素：" + recipe.id)
		check(not recipe.description.is_empty() and recipe.price > 0 and recipe.min_act >= 1 and recipe.min_act <= recipe.max_act and recipe.max_act <= 3, "配方元数据：" + recipe.id)
		check(recipe.target_mode >= 0 and recipe.target_mode <= 8, "目标模式：" + recipe.id)
		if recipe.kind == PotionDefinition.Kind.EFFECTS:
			check(not recipe.effects.is_empty(), "新药水必须配置能力：" + recipe.id)
			for effect in recipe.effects:
				check(effect != null and is_finite(effect.amount), "效果资源有效：" + recipe.id)
	check(counts == [13, 17, 10], "13普通、17稀有、10传说")
	for act in [1, 2, 3]:
		check(CATALOG.available(recipes, act).size() == [23, 37, 40][act - 1], "幕池数量：%d" % act)
	var rng := RandomNumberGenerator.new()
	rng.seed = 98765
	var pool := CATALOG.available(recipes, 3)
	var rolls := [0, 0, 0]
	for index in 10000:
		rolls[CATALOG.pick(pool, 3, rng).rarity] += 1
	check(abs(rolls[0] - 4000) < 300 and abs(rolls[1] - 4500) < 300 and abs(rolls[2] - 1500) < 200, "第三幕稀有度按40/45/15抽取")
	var first_shop := CATALOG.available(recipes, 1, null, true)
	check(first_shop.all(func(p: PotionDefinition): return p.rarity != PotionDefinition.Rarity.LEGENDARY), "第一幕商店不出传说")
	var old := PotionDefinition.new()
	check(old.kind == 0 and old.target_mode == 0 and old.effects.is_empty(), "旧字段默认行为兼容")
	check(load("res://data/potions/fire.tres").damage == 6 and load("res://data/potions/lightning.tres").damage == 20 and load("res://data/potions/tornado.tres").damage == 8 and load("res://data/potions/thunder_cloud.tres").damage == 6, "旧4瓶伤害不变")
	print("POTION_CATALOG_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
