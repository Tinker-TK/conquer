# 卡面只描述当前实际效果；强化数值、持续时间和技能等级直接读取实例配置。
extends RefCounted


static func effects_text(definition: CardDefinition) -> String:
	var lines: PackedStringArray = []
	var target := "1名己方单位"
	match definition.target:
		CardDefinition.Target.ENEMY:
			target = "1名敌方单位"
		CardDefinition.Target.ANY_UNIT:
			target = "1名单位"
	for effect: CardEffect in definition.effects:
		if effect == null:
			continue
		var text := _effect_text(effect, target)
		# 自定义效果保留策划编写的整张牌说明，避免遗漏未识别的规则。
		if text.is_empty():
			return definition.card_discription
		lines.append(text)
	if lines.is_empty():
		return definition.card_discription
	if definition.after_use == CardDefinition.AfterUse.EXHAUST:
		lines.append("消耗。")
	if definition.retain_in_hand:
		lines.append("固有：回合结束保留在手牌。")
	return "\n".join(lines)


static func unit_text(data: UnitData, upgrade_level: int) -> String:
	var lines: PackedStringArray = ["征召1名%s。" % data.unit_name]
	var draw_count := data.get_deployment_draw_count(upgrade_level)
	if draw_count > 0:
		lines[0] += "上场时，抽%d张牌。" % draw_count
	if data.has_sword_arrow(upgrade_level):
		lines.append("剑矢：300内射箭或近战，共用冷却。")
	for skill: SkillBase in data.skills:
		if data.is_skill_unlocked(skill, upgrade_level):
			var text: String = skill.card_text_for_cost(maxi(0, data.combat_card_cost if data.combat_card_cost >= 0 else data.card_cost)) if skill.has_method("card_text_for_cost") else _skill_text(skill)
			if not text.is_empty():
				lines.append(text)
	if data.dodge_skill != null and data.dodge_skill.is_active_at_upgrade_level(upgrade_level):
		var counter := "反击：%s%%闪避并反击" % _number(data.dodge_rate * 100.0)
		if upgrade_level >= 1 and "upgraded_stun_duration" in data.dodge_skill and data.dodge_skill.upgraded_stun_duration > 0:
			counter += "，眩晕%s秒" % _number(data.dodge_skill.upgraded_stun_duration)
		if "counter_armor_break" in data.dodge_skill and data.dodge_skill.counter_armor_break > 0:
			counter += "，每次使目标防御-%d（本场可叠）" % data.dodge_skill.counter_armor_break
		lines.append(counter + "。")
	return "\n".join(lines)


static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(value))
	return str(snappedf(value, 0.01))


static func _duration(effect: CardEffect) -> String:
	match effect.lifetime:
		CardEffect.Lifetime.RUN:
			return "本局永久生效"
		CardEffect.Lifetime.ROUNDS:
			return "持续本回合" if effect.lasting_rounds == 1 else "持续%d回合" % effect.lasting_rounds
	return "持续本场战斗"


static func _effect_text(effect: CardEffect, target: String) -> String:
	var amount := _number(effect.amount)
	var duration := _duration(effect)
	match effect.kind:
		CardEffect.Kind.ATTACK_UP:
			return "使%s攻击力+%s，%s。" % [target, amount, duration]
		CardEffect.Kind.DEFENCE_UP:
			return "使%s防御力+%s，%s。" % [target, amount, duration]
		CardEffect.Kind.MAX_HP_UP:
			return "使%s生命上限+%s，并回复等量生命，%s。" % [target, amount, duration]
		CardEffect.Kind.HEAL_PERCENT:
			return "为%s回复最大生命值的%s%%。" % [target, amount]
		CardEffect.Kind.POISON_ON_HIT:
			return "使%s每次攻击命中附加%s层中毒，%s。" % [target, amount, duration]
		CardEffect.Kind.DEATH_EXPLOSION:
			return "使%s死亡时爆炸，对半径%s内的所有单位造成%s点伤害，无视防御。%s。" % [target, _number(effect.radius), amount, duration]
		CardEffect.Kind.COPY_ALLY:
			return "复制1名己方单位，保留当前生命。"
		CardEffect.Kind.DAMAGE_ZONE:
			var team: String = ["敌方单位", "己方单位", "所有单位"][effect.affected_team]
			return "在指定位置生成半径%s的火焰区域，每%s秒对其中的%s造成%s点伤害，%s。" % [_number(effect.radius), _number(effect.interval), team, amount, duration]
		CardEffect.Kind.MUD_ZONE:
			return "在指定位置生成半径%s的泥潭，其中所有单位移动速度降低%s%%，%s。" % [_number(effect.radius), amount, duration]
		CardEffect.Kind.DRAW:
			return "抽%s张牌。" % amount
		CardEffect.Kind.LOCK_DRAW:
			return "本回合无法再抽牌。"
		CardEffect.Kind.PAY_HP:
			return "消耗%s点玩家生命。" % amount
		CardEffect.Kind.GAIN_ENERGY:
			return "获得%s点能量，可超过上限。" % amount
		CardEffect.Kind.ENERGY_EACH_ROUND:
			return "从下回合起，每回合额外获得%s点能量，持续本场战斗。" % amount
		CardEffect.Kind.DEATH_ATTACK_AURA:
			return "本场战斗每有1名己方单位阵亡，全体己方单位攻击力+%s（计入此前阵亡）。" % amount
		CardEffect.Kind.RANDOM_PLAY:
			return "从抽牌堆随机打出%s张牌，不消耗能量。" % amount
		CardEffect.Kind.RECALL_ALLY:
			return "撤回1名己方单位，将其征召牌返回手牌。"
		CardEffect.Kind.RETAIN_ALLIES:
			return "本场战斗，己方存活单位保留至下回合；己方单位阵亡时，其征召牌费用+%s。" % amount
		CardEffect.Kind.WEAKNESS:
			return "本回合，使1名敌方单位攻击力-%s，可叠加。" % amount
		CardEffect.Kind.DEFENCE_DOWN:
			return "本回合，使1名敌方单位防御力-%s，可叠加。" % amount
		CardEffect.Kind.VULNERABILITY:
			return "本回合，使1名敌方单位受到的攻击伤害提高%s%%，不可叠加。" % amount
		CardEffect.Kind.PARALYSIS:
			return "本回合，使1名敌方单位每%s秒眩晕%s秒，不可叠加。" % [_number(effect.interval), amount]
		CardEffect.Kind.CONVERT_ENEMY:
			return "将1名普通或精英敌方单位转为己方，保留当前生命。" if effect.can_convert_elite else "将1名普通敌方单位转为己方，保留当前生命。"
		CardEffect.Kind.FRENZY:
			return "使1名己方单位在本场战斗中：\n己方存活≥%d名时，攻防降至%s%%；仅剩自身时，攻击+%s%%、防御+%s%%、技能冷却-%s%%，攻击回复实际伤害%s%%的生命。" % [effect.crowded_unit_count, _number(effect.crowded_stat_percent), _number(effect.solo_attack_bonus_percent), _number(effect.solo_defence_bonus_percent), _number(effect.cooldown_reduction_percent), amount]
		CardEffect.Kind.RETREAT_DRAW:
			return "本回合结束时，每有1名己方单位存活，下回合额外抽%s张牌。" % amount
		CardEffect.Kind.DIVERSE_ARMY:
			return "本场战斗，己方存活兵种至少%d种时，全体己方单位攻击力+%s。" % [effect.required_unit_types, amount]
		CardEffect.Kind.KEEP_DISTANCE:
			return "本场战斗，己方攻击随目标距离提高：贴身为%s%%，距离%s及以上为%s%%。" % [_number(effect.minimum_attack_percent), _number(effect.distance_for_max_bonus), amount]
		CardEffect.Kind.JUDGER:
			return "使1名己方单位每击杀1名敌人，攻击力+%s，持续本场战斗。" % amount
		CardEffect.Kind.COMRADE:
			return "本场每打出费用≥%s的牌，下张单位牌0费。\n该单位牌回弃牌堆时恢复原费用，按普通规则加费。" % amount
		CardEffect.Kind.TEMPORARY_UPGRADE:
			return "升级1张其它手牌，单位牌可分配攻击与防御点。目标下次使用后恢复升级前原状。"
		CardEffect.Kind.BLEED:
			return "使1名敌方单位流血，每秒受到%s点伤害，无视防御，持续%s秒。" % [amount, _number(effect.status_seconds)]
		CardEffect.Kind.HEALING_BAN:
			return "使1名敌方单位在%s秒内无法回复生命（包括治疗与吸血）。" % _number(effect.status_seconds)
		CardEffect.Kind.ARMOR_SHRED:
			return "本场，使1名敌方单位每次受到攻击命中时防御-%s，减防可叠加。" % amount
		CardEffect.Kind.SLEEP:
			return "使1名敌方单位睡眠%s秒，受到攻击命中立即醒来。" % _number(effect.status_seconds)
		CardEffect.Kind.SHIELD:
			return "使1名己方单位获得%s护盾，先于生命抵扣伤害，交锋结束清除。" % amount
		CardEffect.Kind.OVERFLOW_SHIELD:
			return "本场，使1名己方单位治疗溢出按1:1转为护盾；护盾在交锋结束清除。"
		CardEffect.Kind.MISSING_HEALTH_SHIELD:
			return "使1名己方单位获得相当于已损失生命值%s%%的护盾，向下取整，交锋结束清除。" % amount
		CardEffect.Kind.KNOCKBACK_IMMUNITY:
			return "本场，使1名己方单位不再被击退。"
		CardEffect.Kind.TUTOR_UNIT:
			return "从抽牌堆选择最多%s张单位牌加入手牌，不算抽牌。" % amount
		CardEffect.Kind.DISCARD_DRAW:
			return "选择并弃置1张其它手牌，然后抽%s张牌。" % amount
		CardEffect.Kind.SACRIFICE:
			return "常驻：本场每有%s名敌方单位阵亡，获得1能量，跨回合累计。" % amount
		CardEffect.Kind.RESURRECT:
			return "以%s%%最大生命复活本场最早阵亡的1名己方单位。" % amount
		CardEffect.Kind.DEATH_DRAW:
			return "常驻：本场每有1名己方单位阵亡，抽%s张牌。" % amount
		CardEffect.Kind.ARMY_ATTACK:
			return "常驻：本场全体己方单位攻击+%s，包含之后入场的友军。" % amount
		CardEffect.Kind.ARMY_DEFENCE:
			return "常驻：本场全体己方单位防御+%s，包含之后入场的友军。" % amount
		CardEffect.Kind.ARMY_SPEED:
			return "常驻：本场全体己方单位移动速度+%s%%，包含之后入场的友军。" % amount
		CardEffect.Kind.BATTLE_STANDARD:
			return "在指定位置放置不可移动的战旗；本场半径%s内友军攻击+%s，离开后失效。" % [_number(effect.radius), amount]
		CardEffect.Kind.SPIKE_TRAP:
			return "在指定位置放置地刺；敌人进入时受到%s点伤害并眩晕%s秒，触发后消失。" % [amount, _number(effect.status_seconds)]
		CardEffect.Kind.TRANSCRIBE:
			return "消耗所有其它手牌，再抽等量的牌。抽到的牌临时强化，下次成功使用后还原；单位训练点加攻击，士兵选飞弹。" if effect.upgrades_drawn_cards else "将所有其它手牌直接放入消耗牌堆，再抽等量的牌。"
		CardEffect.Kind.REFORMATION:
			return "将%s张随机其它手牌变为同当前费用的其它牌，持续本场。" % amount
		CardEffect.Kind.HAND_DISCOUNT:
			return "当前其它手牌本回合费用-%s，最低0费。" % amount
		CardEffect.Kind.OVERDRAFT:
			return "本回合能量上限+%s，并获得%s能量；下回合能量上限-%d，之后恢复。" % [amount, amount, effect.next_round_penalty]
		CardEffect.Kind.THRIFT:
			return "常驻：本场能量上限-1，从下回合起每回合额外抽1张牌。"
	return ""


static func _skill_text(skill: SkillBase) -> String:
	var text := skill.card_effect_description()
	if not text.is_empty():
		return text
	var script_name: String = skill.get_script().resource_path.get_file()
	var rate := _number(skill.attack_rate * 100.0)
	var hits := skill.hit_frame.size()
	match script_name:
		"normal_attack.gd":
			if skill.skill_name == "普通攻击":
				return ""
			if hits == 1:
				return "%s：造成%s%%攻击力伤害。" % [skill.skill_name, rate]
			return "%s：%d次×%s%%伤害。" % [skill.skill_name, hits, rate]
		"area_attack.gd":
			return "%s：对周围敌人造成%s%%攻击力伤害。" % [skill.skill_name, rate]
		"arrow_attack.gd":
			if skill.pierce_all and skill.projectile_trajectory == 0:
				return "%s：对射击路线上的所有敌人造成%s%%攻击力伤害。" % [skill.skill_name, rate]
			if skill.pierce_count > 1 and skill.projectile_trajectory == 0:
				return "%s：穿透最多%d名敌人，造成%s%%攻击力伤害。" % [skill.skill_name, skill.pierce_count, rate]
			return "%s：远程攻击，造成%s%%攻击力伤害。" % [skill.skill_name, rate]
		"ally_heal.gd":
			return "%s：为生命最低的友军回复%s%%攻击力的生命。" % [skill.skill_name, rate]
		"dash_attack.gd":
			return "%s：冲锋攻击沿途敌人（施放范围%s，伤害%s%%攻击力）。" % [skill.skill_name, _number(skill.cast_range), rate]
	return ""
