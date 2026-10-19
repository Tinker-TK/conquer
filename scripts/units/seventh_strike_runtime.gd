# 每个出场剑士分别计数；不将进度保存进原牌或共享技能资源。
extends Node

var caster: UnitBase
var skill: SkillBase
var hits := 0


func _ready() -> void:
	name = "SeventhStrike"
	caster.attack_damage_dealt.connect(_on_damage)
	caster.unit_died.connect(func(_unit): clear())


func cost() -> int:
	return maxi(0, caster.unit_data.combat_card_cost if caster.unit_data.combat_card_cost >= 0 else caster.unit_data.card_cost)


func _enabled() -> bool:
	return caster.current_state != UnitBase.State.DEATH and not caster._encounter_finished() \
		and caster.unit_data.is_skill_unlocked(skill)


func _on_damage(target: UnitBase, amount: int) -> void:
	if not _enabled() or Global.game_phase != Global.GamePhase.AUTO_BATTLE or amount <= 0 \
		or not is_instance_valid(target) or target.unit_data.unit_team == caster.unit_data.unit_team:
		return
	hits += 1
	if hits >= skill.damage_trigger_count:
		hits = 0
		var damage := maxi(1, int(target.unit_data.max_hp * (skill.true_damage_base_percent + cost()) / 100.0))
		# 额外真伤不是新的攻击事件，不递归计数、触发反击或重复附加攻击上毒。
		target.take_effect_damage(damage, caster, &"true_damage")
	caster._refresh_passive_status()


func status_entry() -> Dictionary:
	return {"icon": "seventh_strike", "count": hits,
		"tooltip": "七伤：%d/%d次伤害\n下次触发造成目标最大生命%.0f%%真实伤害。\n原牌费用x=%d；忽略临时0费，触发后清零。" % [hits, skill.damage_trigger_count, skill.true_damage_base_percent + cost(), cost()]}


func clear() -> void:
	hits = 0
	if is_instance_valid(caster):
		caster._refresh_passive_status()


func _physics_process(_delta: float) -> void:
	if not _enabled() and hits > 0:
		clear()
