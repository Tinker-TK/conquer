# 用真实卡面检查全部卡牌、强化后的效果与存档恢复，防止说明和玩法脱节。
extends Node

var checks := 0
var failures: Array[String] = []
var catalog: Array[Dictionary] = []
var views: Array[UnitCard] = []


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _view(card: CardInstance) -> void:
	var view := load("res://scenes/cards/unit_card.tscn").instantiate() as UnitCard
	view.is_playable = false
	add_child(view)
	view.setup(card)
	views.append(view)
	var text := card.get_description()
	check(not text.is_empty() and not text.contains("强化后") and not text.contains("待配置"), "当前卡牌说明完整：" + card.definition.card_name)
	check(view.get_node("CardDiscription").text == text and view.tooltip_text.contains(text), "卡面与悬停同步：" + card.definition.card_name)


func _run() -> void:
	for directory in ["res://data/cards", "res://data/units"]:
		for file in DirAccess.get_files_at(directory):
			if file.get_extension() != "tres":
				continue
			var path: String = directory.path_join(file)
			var data := load(path)
			if not CardInstance.is_player_card_data(data):
				continue
			var card := CardInstance.new(data)
			catalog.append({"path": path, "name": card.definition.card_name, "base": card.get_description()})
			_view(CardInstance.new(data))
			if card.can_upgrade(card.is_unit_card()):
				if card.is_unit_card():
					check(card.train(card.unit_data.upgrade_ability_points, 0), "通过正式训练入口升级")
				else:
					check(card.enhance(), "通过正式强化入口升级")
				catalog.back()["upgraded"] = card.get_description()
				_view(card)
	check(catalog.size() == 61, "覆盖50张效果牌和11张征召牌")
	# 两个士兵分支及临时进化的附加说明也必须完整显示。
	for branch in ["slash", "missile"]:
		var soldier := CardInstance.new(load("res://data/units/soldier.tres"))
		check(soldier.train(soldier.unit_data.upgrade_ability_points, 0, branch), "选择士兵强化分支：" + branch)
		_view(soldier)
		var evolution := CardInstance.new(soldier.unit_data)
		check(evolution.temporary_upgrade(Vector2i(2, 0), branch), "选择士兵临时进化分支：" + branch)
		_view(evolution)
	var evolved_axe := CardInstance.new(load("res://data/units/armored_axeman.tres"))
	check(evolved_axe.temporary_upgrade(Vector2i(2, 0)), "装甲斧手临时强化同时保留两种技能")
	_view(evolved_axe)
	var evolved_knight := CardInstance.new(load("res://data/units/knight.tres"))
	check(evolved_knight.temporary_upgrade(Vector2i(2, 0)), "骑士临时强化显示血影斩击、眩晕与抽牌")
	_view(evolved_knight)
	var evolved_templar := CardInstance.new(load("res://data/units/knight_templar.tres"))
	check(evolved_templar.temporary_upgrade(Vector2i(2, 0)), "圣殿骑士临时强化显示嘲讽防御与反击破甲")
	_view(evolved_templar)
	var evolved_lancer := CardInstance.new(load("res://data/units/lancer.tres"))
	check(evolved_lancer.temporary_upgrade(Vector2i(2, 0)), "骑兵临时强化显示两次加速冲锋")
	_view(evolved_lancer)
	var evolved_sword := CardInstance.new(load("res://data/units/swords_man.tres"))
	check(evolved_sword.temporary_upgrade(Vector2i(2, 0)), "剑士临时强化显示三道风和费用真伤")
	_view(evolved_sword)
	var examples := load("res://examples/data/card_examples.tres") as RunStartData
	for data: Resource in examples.cards:
		var card := CardInstance.new(data)
		catalog.append({"example": true, "name": card.definition.card_name, "base": card.get_description()})
		_view(card)
	var definition := load("res://data/cards/power_enhance.tres").duplicate(true) as CardDefinition
	definition.effects[0].upgrade_amount = 2
	definition.max_upgrade_count = 2
	var upgraded := CardInstance.new(definition)
	var peer := CardInstance.new(definition)
	check(upgraded.enhance() and upgraded.get_description().contains("攻击力+5"), "强化说明读取实际效果增量")
	check(peer.get_description().contains("攻击力+3") and definition.effects[0].amount == 3, "同名牌和共享资源的说明不被强化污染")
	check(upgraded.enhance() and upgraded.get_description().contains("攻击力+7"), "多次强化显示最终数值")
	var start := RunStartData.new()
	start.cards.assign([definition])
	RunManager.start_new_run(start)
	RunManager.deck[0] = upgraded
	check(RunManager.save_run().is_empty(), "保存强化卡牌")
	check(RunManager.load_saved_run().is_empty() and RunManager.deck[0].get_description().contains("攻击力+7"), "读档后说明保留实际强化数值")
	var effect := definition.effects[0].duplicate() as CardEffect
	definition = definition.duplicate(true) as CardDefinition
	definition.effects.assign([effect])
	effect.lifetime = CardEffect.Lifetime.ROUNDS
	effect.lasting_rounds = 3
	check(CardInstance.new(definition).get_description().contains("持续3回合"), "说明读取回合期限")
	effect.lifetime = CardEffect.Lifetime.RUN
	check(CardInstance.new(definition).get_description().contains("本局永久生效"), "永久强化标明持续期限")
	effect.kind = CardEffect.Kind.CUSTOM
	definition.card_discription = "自定义效果说明。"
	check(CardInstance.new(definition).get_description() == definition.card_discription, "自定义效果保留配置文案")
	for id in ["defend", "heal", "death_explosion", "draw_hp", "poison_on_hit", "recall_ally", "copy_ally"]:
		var text := CardInstance.new(load("res://data/cards/%s.tres" % id)).get_description()
		var expected := {"defend": "防御力+2", "heal": "30%", "death_explosion": "半径160", "draw_hp": "4点玩家生命", "poison_on_hit": "2层中毒", "recall_ally": "返回手牌", "copy_ally": "保留当前生命"}
		check(text.contains(expected[id]), "修正旧文案与真实效果不符：" + id)
	# 等待真实字体排版后检查全部基础牌、升级牌和示例牌，不能出现底部截断。
	await get_tree().process_frame
	await get_tree().process_frame
	for view: UnitCard in views:
		var label := view.get_node("CardDiscription") as RichTextLabel
		check(label.get_content_height() <= label.size.y, "卡面说明完整显示：%s %s（%d/%.0f）" % [view.card_instance.definition.card_name, view.card_instance.soldier_specialization, label.get_content_height(), label.size.y])
	DirAccess.make_dir_recursive_absolute("res://.maintenance")
	var output := FileAccess.open("res://.maintenance/card-descriptions.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(catalog, "\t"))
	output.close()
	print("CARD_DESCRIPTION_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
