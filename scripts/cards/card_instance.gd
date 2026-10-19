# 这玩意儿是干嘛的（核心逻辑）：代表一张具体的牌，保存它自己的退场加费和永久强化。
# 数据是咋流动的（数据流向）：配方 → 本牌实例；退场加费与基础费用相加，供卡面和出牌统一读取。
# 为啥这么写（选型决策）：加费存在实例里，不修改共享配方，避免同兵种的其它牌一起涨价。
# 性能咋样（复杂度）：创建时转换旧配方一次，读取费用只做一次加法，牌堆间移动同一个实例。
extends RefCounted
class_name CardInstance

const DESCRIPTION = preload("res://scripts/cards/card_description.gd")

static var next_id: int = 1

var id: int
var unit_data: UnitData
var definition: CardDefinition
# 本场每次绑定的单位退场进弃牌堆时累加，整场结束时归零，开场再次重置。
var cost_increase: int = 0
# 每张具体征召牌独有，不能写进共享的 UnitData；开始新局创建新实例自然清空。
var permanent_buffs: Array[Dictionary] = []
var upgrade_count: int = 0
var ability_points: int = 0
var attack_points: int = 0
var defence_points: int = 0
var soldier_specialization: String = ""
# 费用减免与进化只属于本场运行状态，不改基础费用和已有永久升级。
var next_unit_discount := false
var free_until_discard := false
var round_cost_reduction: int = 0
var potion_cost_free := false
var relic_cost_reduction := 0
var _evolution_snapshot: Dictionary = {}


# 敌方 UnitData 仅供战斗和波次使用；外层封装成征召牌也不能进入玩家牌组。
static func is_player_card_data(data: Resource) -> bool:
	if data is UnitData:
		return data.unit_team == "team_a"
	if data is CardDefinition:
		return data.category != CardDefinition.Category.RECRUIT or (
			data.summon_unit != null and data.summon_unit.unit_team == "team_a")
	return false

# 作用：创建具体卡牌；data 是旧兵种配置或通用卡配置，没有返回值。
func _init(data: Resource) -> void:
	id = next_id
	next_id += 1
	if data is CardDefinition:
		definition = data
		unit_data = data.summon_unit
	elif data is UnitData:
		unit_data = data
		definition = CardDefinition.new()
		definition.category = CardDefinition.Category.RECRUIT
		definition.target = CardDefinition.Target.POSITION
		definition.summon_unit = data
		definition.card_name = data.card_name
		definition.card_discription = data.card_discription
		definition.card_cost = data.card_cost
		definition.card_image = data.card_image
		definition.card_image_2 = data.card_image_2
	else:
		push_error("牌组只能放 UnitData 或 CardDefinition 资源。")


# 作用：读取实际费用；战友减免优先，否则返回基础费用加上累计退场加费。
func get_cost() -> int:
	if next_unit_discount or free_until_discard or potion_cost_free:
		return 0
	return maxi(0, get_intrinsic_cost() - round_cost_reduction - relic_cost_reduction)


# 卡牌本身的当前费用，包括退场加费，不受战友0费或本次免费打出的影响。
func get_intrinsic_cost() -> int:
	return definition.card_cost + cost_increase


func can_evolve() -> bool:
	return _evolution_snapshot.is_empty() and can_upgrade(is_unit_card())


func temporary_upgrade(allocation: Vector2i, branch: String = "") -> bool:
	if not can_evolve():
		return false
	var snapshot := persistent_upgrade_state()
	var original := definition
	var succeeded := train(allocation.x, allocation.y, branch) if is_unit_card() else enhance()
	if succeeded:
		_evolution_snapshot = snapshot
		_evolution_snapshot.definition = original
	return succeeded


func restore_evolution() -> void:
	if _evolution_snapshot.is_empty():
		return
	definition = _evolution_snapshot.definition
	for key in ["upgrade_count", "ability_points", "attack_points", "defence_points"]:
		set(key, int(_evolution_snapshot[key]))
	soldier_specialization = str(_evolution_snapshot.get("soldier_specialization", ""))
	_evolution_snapshot.clear()


func persistent_definition() -> CardDefinition:
	return _evolution_snapshot.get("definition", definition)


func persistent_upgrade_state() -> Dictionary:
	if not _evolution_snapshot.is_empty():
		var original := _evolution_snapshot.duplicate()
		original.erase("definition")
		return original
	return {"upgrade_count": upgrade_count, "ability_points": ability_points,
		"attack_points": attack_points, "defence_points": defence_points, "soldier_specialization": soldier_specialization}


func reset_battle_modifiers() -> void:
	potion_cost_free = false
	next_unit_discount = false
	free_until_discard = false
	round_cost_reduction = 0
	relic_cost_reduction = 0
	restore_evolution()


func is_unit_card() -> bool:
	return definition != null and definition.category == CardDefinition.Category.RECRUIT and unit_data != null


func get_upgrade_limit() -> int:
	return maxi(0, unit_data.max_upgrade_count if is_unit_card() else definition.max_upgrade_count)


func can_upgrade(training: bool) -> bool:
	if definition == null or training != is_unit_card() or upgrade_count >= get_upgrade_limit():
		return false
	if definition.category == CardDefinition.Category.RECRUIT and unit_data == null:
		return false
	return not training or unit_data.unit_team == "team_a"


# 训练只写实例；出场属性与技能解锁都使用这张牌自己的升级次数。
func needs_soldier_choice() -> bool:
	return is_unit_card() and unit_data.unit_english_name == "soldier" and upgrade_count == 0


func train(attack_gain: int, defence_gain: int, branch: String = "") -> bool:
	if not can_upgrade(true) or attack_gain < 0 or defence_gain < 0:
		return false
	var available := ability_points + maxi(0, unit_data.upgrade_ability_points)
	if attack_gain + defence_gain != available:
		return false
	if not branch.is_empty() and branch not in ["slash", "missile"]:
		return false
	if needs_soldier_choice():
		# 旧脚本调用兼容飞弹；面向玩家的训练/进化入口必须显式选择。
		soldier_specialization = branch if not branch.is_empty() else "missile"
	upgrade_count += 1
	ability_points = available - attack_gain - defence_gain
	attack_points += attack_gain
	defence_points += defence_gain
	return true


func enhance() -> bool:
	if not can_upgrade(false):
		return false
	# 独立配方与效果快照，避免同名牌和 .tres 资源跟着被强化。
	definition = definition.duplicate(true)
	definition.card_cost = maxi(0, definition.card_cost + definition.upgrade_cost_change)
	for effect in definition.effects:
		if effect != null:
			effect.amount += effect.upgrade_amount
			if effect.lifetime == CardEffect.Lifetime.ROUNDS:
				effect.lasting_rounds += effect.upgrade_lasting_rounds
			effect.can_convert_elite = effect.can_convert_elite or effect.upgrade_can_convert_elite
			effect.status_seconds += effect.upgrade_status_seconds
			effect.upgrades_drawn_cards = effect.upgrades_drawn_cards or effect.upgrade_upgrades_drawn_cards
	upgrade_count += 1
	return true


func get_summon_data() -> UnitData:
	if not is_unit_card():
		return null
	var result := unit_data.duplicate() as UnitData
	result.attack += attack_points
	result.defence += defence_points
	result.card_upgrade_level = upgrade_count
	result.soldier_specialization = soldier_specialization
	result.combat_card_cost = get_intrinsic_cost()
	result.skills = result.get_unlocked_skills()
	if not result.is_skill_unlocked(result.dodge_skill):
		result.dodge_skill = null
	return result


# 读取原征召牌自己的强化记录；能力/强化牌即使携带单位数据，也不触发征召上场抽牌。
func get_deployment_draw_count() -> int:
	return unit_data.get_deployment_draw_count(upgrade_count) if is_unit_card() else 0


# 卡面和悬停共用当前效果的说明，不改写共享配方或存档中的原始文案。
func get_description() -> String:
	var text := ""
	if is_unit_card():
		var preview := unit_data.duplicate() as UnitData
		preview.soldier_specialization = soldier_specialization
		preview.combat_card_cost = get_intrinsic_cost()
		text = DESCRIPTION.unit_text(preview, upgrade_count)
	else:
		text = DESCRIPTION.effects_text(definition) if definition != null else ""
	if not _evolution_snapshot.is_empty():
		text += "\n进化：下次使用后恢复升级前原状。"
	return text


func upgrade_summary() -> String:
	var text := "训练" if is_unit_card() else "强化"
	text += " %d/%d" % [upgrade_count, get_upgrade_limit()]
	if is_unit_card():
		text += " · 攻击 +%d / 防御 +%d" % [attack_points, defence_points]
		if unit_data.unit_english_name == "soldier" and upgrade_count > 0:
			text += "\n强化分支：" + ("斩击" if soldier_specialization == "slash" else "飞弹")
		var draw_count := get_deployment_draw_count()
		if draw_count > 0:
			text += "\n上场效果：立刻抽%d张牌" % draw_count
		if upgrade_count > 0:
			var preview := get_summon_data()
			if preview.has_sword_arrow():
				text += "\n保留剑矢：射程300，远近普攻共用冷却"
			var unlocked: PackedStringArray = []
			for skill: SkillBase in preview.skills:
				if preview.is_skill_unlocked(skill):
					unlocked.append(skill.skill_name)
			if unit_data.dodge_skill != null and unit_data.dodge_skill.is_active_at_upgrade_level(upgrade_count):
				unlocked.append(unit_data.dodge_skill.skill_name)
			text += "\n当前生效技能：" + ("、".join(unlocked) if not unlocked.is_empty() else "无")
	elif upgrade_count > 0:
		text += "\n当前费用：%d\n%s" % [get_intrinsic_cost(), get_description()]
	return text
