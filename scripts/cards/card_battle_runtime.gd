# 这玩意儿是干嘛的（核心逻辑）：统一处理三类卡的目标、扣费、效果，以及本场毒和持续区域。
# 数据是咋流动的（数据流向）：牌实例当前费用 → 验证与扣费 → 通知卡面落点并结算；永久强化存在原牌。
# 为啥这么写（选型决策）：验证和扣费都读取实例费用，保证单位退场后的加费真正影响再次出牌。
# 性能咋样（复杂度）：区域每帧检查本场单位；随机出牌最多连锁 32 次，防止无限递归。
extends Node2D

signal feedback(message: String)
const MAX_CHAIN := 32
const CARD_EFFECT_NAME := preload("res://scripts/ui/card_effect_name.gd")
const BURN_GROUND_ZONE := preload("res://scripts/effects/burn_ground_zone.gd")
const MUD_GROUND_ZONE := preload("res://scripts/effects/mud_ground_zone.gd")
var battle: Node2D
var hand: Node
var rounds: Node
var states: Dictionary = {}
var zones: Array[Dictionary] = []
var ally_deaths := 0
var death_attack_per_unit := 0
var _combat_death_attack_per_unit := 0
var chain_count := 0
var preview_target: UnitBase
# 图集含有大片透明留白，只缓存实际像素范围；共享贴图的单位不重复读图。
var _target_frame_bounds: Dictionary[Texture2D, Rect2] = {}
# 常驻卡改变本场清场规则与原征召牌退场惩罚；重复使用不叠加。
var retain_allies := false
var unit_discard_cost_increase := 1
var tactics: Node
var plays: Node
var expanded: Node


func should_retain_unit(unit: UnitBase) -> bool:
	if is_instance_valid(unit) and unit.has_meta("potion_summon_end"):
		return not battle.battle_finished and unit.is_alive() and rounds.current_round < int(unit.get_meta("potion_summon_end"))
	return retain_allies and not battle.battle_finished and is_instance_valid(unit) \
		and unit.is_alive() and unit.unit_data.unit_team == "team_a"


# 作用：更新合法施放目标的预览；card 是拖动的牌、point 是世界坐标，没有返回值。
func update_cast_preview(card: CardInstance, point: Vector2) -> void:
	var target: UnitBase
	if card != null and card.definition != null and hand.hand.has(card) and (
		not get_tree().paused and rounds.can_play_cards()
	):
		# 与真正施放使用完全相同的选目标和验证入口，不扣费、不执行效果。
		target = pick_target(card.definition, point)
		if target != null:
			var context := {"runtime": self, "card": card, "position": point,
				"target": target, "depth": 0, "prepared": null}
			if not _validate_card(context, false).is_empty():
				target = null
	if is_instance_valid(preview_target) and preview_target == target:
		return
	clear_cast_preview()
	if is_instance_valid(target):
		preview_target = target
		preview_target.set_cast_preview(true)


# 作用：撤销预览，单位自行恢复选中或普通颜色；没有参数，没有返回值。
func clear_cast_preview() -> void:
	if is_instance_valid(preview_target):
		preview_target.set_cast_preview(false)
	preview_target = null


# 作用：Godot 在取消拖放、暂停或离树时清理预览；what 为通知编号，没有返回值。
func _notification(what: int) -> void:
	if what in [NOTIFICATION_DRAG_END, NOTIFICATION_PAUSED, NOTIFICATION_EXIT_TREE]:
		clear_cast_preview()


# 作用：阶段切换立即结束预览；_phase 为新阶段，没有返回值。
func _on_preview_phase_changed(_phase: int) -> void:
	clear_cast_preview()


# 作用：战场初始化时接线；owner_battle 是本场战斗，没有返回值。
func setup(owner_battle: Node2D) -> void:
	battle = owner_battle
	hand = battle.hand_manager
	rounds = battle.battle_round_manager
	z_index = 2
	plays = preload("res://scripts/cards/card_play_state.gd").new()
	plays.name = "CardPlayState"
	add_child(plays)
	plays.setup(self)
	expanded = preload("res://scripts/cards/expanded_card_runtime.gd").new()
	expanded.name = "ExpandedCards"
	add_child(expanded)
	expanded.setup(self)
	tactics = preload("res://scripts/cards/tactical_effect_runtime.gd").new()
	tactics.name = "TacticalEffects"
	add_child(tactics)
	tactics.setup(self)
	SignalBus.phase_change.connect(_on_preview_phase_changed)
	rounds.battle_round_ended.connect(_on_round_ended)
	for team_path in ["Entities/TeamA", "Entities/TeamB"]:
		var team := battle.get_node(team_path)
		team.child_entered_tree.connect(_register_unit)
		for unit in team.get_children():
			_register_unit(unit)


# 作用：登记单位的本场状态；node 为新生成单位，没有返回值。
func _register_unit(node: Node) -> void:
	if battle.battle_finished:
		if node is UnitBase:
			node.queue_free()
		return
	if not node is UnitBase or states.has(node.get_instance_id()):
		return
	if node.is_in_group("player_base") or node.is_queued_for_deletion() or not node.is_inside_tree():
		return
	if node.get_parent() not in [battle.get_node("Entities/TeamA"), battle.get_node("Entities/TeamB")]:
		return
	var id := node.get_instance_id()
	# 用弱引用判断是否属于已结束战场，不让旧攻击回调继续改变残留单位。
	node.set_meta("battle_owner", weakref(battle))
	# child_entered_tree 早于子节点和单位 ready；先确定归属，完成 ready 后才登记状态。
	if not node.is_node_ready():
		var on_ready := _register_unit.bind(node)
		if not node.ready.is_connected(on_ready):
			node.ready.connect(on_ready, CONNECT_ONE_SHOT)
		return
	var error: String = node.configuration_error()
	if not error.is_empty() or not node.is_combat_initialized():
		node.reject_initialization(error if not error.is_empty() else "单位 ready 未完成。")
		return
	states[id] = {"unit": node, "poison": 0, "poison_on_hit": 0,
		"explosions": [], "buffs": [], "aura_bonus": 0, "base_speed": node.unit_data.speed, "terrain_statuses": []}
	node.hit_received.connect(_on_hit)
	node.unit_died.connect(_on_death)
	node.tree_exited.connect(_forget_unit.bind(id), CONNECT_ONE_SHOT)
	_register_wave_buffs(node)
	_apply_aura(node)
	tactics.register_unit(node)
	var relics := battle.get_node_or_null("RelicRuntime")
	if relics != null:
		relics.unit_registered(node)
	_refresh_zone_speeds()


# 作用：接管出场时已生效的固定增益与循环成长；unit 是刚登记的单位，没有返回值，不重复修改属性。
func _register_wave_buffs(unit: UnitBase) -> void:
	var applied: Dictionary = unit.get_meta(&"wave_cycle_applied", {})
	if applied.is_empty():
		return
	var kinds := {"attack": CardEffect.Kind.ATTACK_UP, "max_hp": CardEffect.Kind.MAX_HP_UP,
		"defence": CardEffect.Kind.DEFENCE_UP}
	var sources := [
		{"values": applied.get("spawn", {}), "multiplier": 1, "single": true},
		{"values": applied.get("growth", {}), "multiplier": int(applied.get("cycle", 0)), "single": false}]
	for source: Dictionary in sources:
		for key in source["values"]:
			var amount := int(source["values"][key]) * int(source.multiplier)
			if not kinds.has(key) or amount <= 0:
				continue
			var effect := CardEffect.new()
			effect.kind = kinds[key]
			effect.amount = amount
			effect.lifetime = CardEffect.Lifetime.BATTLE
			var label := "波次单次增益（出场时生效）" if source.single else (
				"循环成长（第%d次，每次+%d）" % [applied.cycle, source["values"][key]])
			states[unit.get_instance_id()].buffs.append({"effect": effect, "label": label, "left": 0})
	unit.remove_meta(&"wave_cycle_applied")
	_refresh_unit_status(unit)


# 作用：单位真正退出本场时移除引用；id 是实例编号，没有返回值。
func _forget_unit(id: int) -> void:
	if is_instance_valid(preview_target) and preview_target.get_instance_id() == id:
		clear_cast_preview()
	states.erase(id)
	tactics.forget_unit(id)
	rounds.request_round_check()


# 作用：取得本场仍活着的单位；没有参数，返回单位数组。
func living_units() -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for state: Dictionary in states.values():
		var unit = state.unit
		if is_instance_valid(unit) and unit.is_alive():
			result.append(unit)
	return result


# 作用：按卡牌目标类型筛选单位；definition 为配方，返回合法阵营候选。
func targets_for(definition: CardDefinition) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for unit in living_units():
		var ally: bool = unit.unit_data.unit_team == "team_a"
		if definition.target == CardDefinition.Target.ANY_UNIT or (
			definition.target == CardDefinition.Target.ALLY and ally
		) or (definition.target == CardDefinition.Target.ENEMY and not ally):
			result.append(unit)
	return result


# 作用：优先命中可见身体、装备和血条，脚底附近仍可落牌；point 为世界坐标。
func pick_target(definition: CardDefinition, point: Vector2) -> UnitBase:
	var selected: UnitBase
	var visual_target: UnitBase
	var visual_distance := INF
	var distance := 65.0
	for unit in targets_for(definition):
		var hit_distance := _visual_hit_distance(unit, point)
		if hit_distance < visual_distance:
			visual_target = unit
			visual_distance = hit_distance
		var candidate := unit.global_position.distance_to(point)
		if candidate < distance:
			selected = unit
			distance = candidate
	return visual_target if visual_target != null else selected


# 作用：按精灵当前帧的实际内容命中；使用完整变换处理缩放、翻转和偏移。
func _visual_hit_distance(unit: UnitBase, point: Vector2) -> float:
	var sprite := unit.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null and sprite.is_visible_in_tree() and sprite.sprite_frames != null \
		and sprite.sprite_frames.has_animation(sprite.animation) \
		and sprite.sprite_frames.get_frame_count(sprite.animation) > sprite.frame:
		var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		if texture != null:
			if not _target_frame_bounds.has(texture):
				var image := texture.get_image()
				_target_frame_bounds[texture] = Rect2(image.get_used_rect()) if image != null else Rect2()
			var rect: Rect2 = _target_frame_bounds[texture]
			if rect.has_area():
				if sprite.flip_h:
					rect.position.x = texture.get_width() - rect.end.x
				if sprite.flip_v:
					rect.position.y = texture.get_height() - rect.end.y
				rect.position += sprite.offset - (texture.get_size() * 0.5 if sprite.centered else Vector2.ZERO)
				# 固定八个屏幕像素的容错，不把整个透明图集变成巨大的命中框。
				var sprite_transform := sprite.get_global_transform_with_canvas()
				var padding := Vector2(8.0 / maxf(sprite_transform.x.length(), 0.001),
					8.0 / maxf(sprite_transform.y.length(), 0.001))
				if Rect2(rect.position - padding, rect.size + padding * 2).has_point(sprite.to_local(point)):
					return sprite.to_global(rect.get_center()).distance_squared_to(point)
	for path in ["HealthBar/PanelContainer", "HealthBar/StatusDisplay"]:
		var control := unit.get_node_or_null(path) as Control
		if control != null and control.is_visible_in_tree() and Rect2(Vector2.ZERO, control.size).has_point(
			control.get_global_transform().affine_inverse() * point):
			return unit.global_position.distance_squared_to(point)
	return INF


# 作用：统一出牌入口；card/point 为牌和落点，free_play 为免能量，depth 为连锁深度，
# from_draw 表示随机效果从抽牌堆施放，返回是否成功。
func try_play(card: CardInstance, point: Vector2, free_play: bool = false, depth: int = 0, from_draw: bool = false, choice: Dictionary = {}) -> bool:
	clear_cast_preview()
	if depth == 0:
		chain_count = 0
	if card == null or card.definition == null:
		return false
	# 不先塞进手牌，避免触发抽牌/手牌 UI；只有随机连锁允许从抽牌堆免费出牌。
	if from_draw:
		if not free_play or depth <= 0 or not hand.draw_pile.has(card):
			return false
	elif not hand.hand.has(card):
		return false
	if get_tree().paused or not rounds.can_play_cards():
		return false
	if chain_count >= MAX_CHAIN:
		return false
	plays.prepare_cost(card)
	var definition := card.definition
	var context := {"runtime": self, "card": card, "position": point,
		"target": pick_target(definition, point), "depth": depth, "prepared": null,
		"target_card": choice.get("card"), "selected_cards": choice.get("cards", []),
		"allocation": choice.get("allocation", Vector2i.ZERO), "soldier_branch": choice.get("soldier_branch", "")}
	var evolution := definition.effects.any(func(effect: CardEffect): return effect != null and effect.kind == CardEffect.Kind.TEMPORARY_UPGRADE)
	if from_draw:
		expanded.random_choice(context)
	if evolution and from_draw and context.target_card == null:
		var candidates: Array[CardInstance] = plays.candidates(card)
		if not candidates.is_empty():
			context.target_card = candidates.pick_random()
			var selected: CardInstance = context.target_card
			if selected.is_unit_card():
				context.allocation = Vector2i(selected.ability_points + maxi(0, selected.unit_data.upgrade_ability_points), 0)
				if selected.needs_soldier_choice():
					context.soldier_branch = ["slash", "missile"].pick_random()
	var reason := _validate_card(context, free_play)
	if not reason.is_empty():
		feedback.emit(reason)
		return false
	if expanded.needs_choice(context):
		battle.card_ui.open_card_choice(card, point)
		return true
	if evolution and context.target_card == null:
		battle.card_ui.open_upgrade_choice(card, point)
		return true
	# 生成节点先验证类型再扣费，场景配错时不会吞牌或能量。
	var spawn_data: UnitData = card.get_summon_data() if definition.category == CardDefinition.Category.RECRUIT else null
	for effect in definition.effects:
		if effect.kind == CardEffect.Kind.COPY_ALLY:
			spawn_data = context.target.unit_data.duplicate()
			spawn_data.speed = float(states[context.target.get_instance_id()].base_speed)
			tactics.strip_stat_contributions(context.target, spawn_data)
			spawn_data.defence -= context.target.taunt_defence_bonus
			# 技能虚弱也属于可解除状态，复制品不继承其属性扣减。
			if context.target.status_runtime != null:
				context.target.status_runtime.strip_stat_contributions(spawn_data)
			# 驻场庇护由复制品所在位置重新获得，不能把临时光环加成烘焙进复制属性。
			spawn_data.attack -= context.target.protection_attack_bonus
			# 连击层数属于当前目标，复制品从零开始。
			spawn_data.attack -= context.target.consecutive_attack_bonus
			spawn_data.attack -= context.target.soldier_attack_bonus
			spawn_data.attack -= int(states[context.target.get_instance_id()].aura_bonus)
			# 属性副本先减去记录贡献，生成后再逐条继承，避免加成重复或永久烘焙进属性。
			for buff: Dictionary in states[context.target.get_instance_id()].buffs:
				var entry: CardEffect = buff.effect
				if entry.kind == CardEffect.Kind.ATTACK_UP:
					spawn_data.attack -= int(entry.amount)
				elif entry.kind == CardEffect.Kind.DEFENCE_UP:
					spawn_data.defence -= int(entry.amount)
				elif entry.kind == CardEffect.Kind.MAX_HP_UP:
					spawn_data.max_hp -= int(entry.amount)
	if spawn_data != null:
		context.prepared = _prepare_unit(spawn_data)
		if context.prepared == null:
			feedback.emit("无法加载对应兵种的单位场景。")
			return false
	if not expanded.prepare(context):
		feedback.emit("无法准备复活单位。")
		return false
	# 单位退场后原牌会涨价，扣费必须与卡面显示使用同一个当前费用入口。
	var played_cost := card.get_cost()
	if not free_play and not rounds.try_spend_energy(played_cost):
		if context.prepared != null:
			context.prepared.free()
		return false
	chain_count += 1
	plays.played(card, played_cost)
	# 传递实际选中的单位，释放动画跟随目标移动，不在界面重新猜测目标。
	hand.begin_resolve(card, from_draw, point, context.target)
	if definition.category == CardDefinition.Category.RECRUIT:
		var summoned := _spawn_prepared(context, point, int(context.deployment_floor))
		hand.move_hand_card_to_board(card, summoned)
		for saved: Dictionary in card.permanent_buffs:
			_add_buff(summoned, saved.effect, saved.label)
		# 征召牌附带的强化效果默认作用于自己刚召唤的单位。
		context.target = summoned
		# 原牌已离开手牌并绑定场上单位，再兑现上场抽牌，避免洗牌把自己抽回来。
		var draw_count := card.get_deployment_draw_count()
		if draw_count > 0:
			hand.draw_cards(draw_count)
	for effect in definition.effects:
		effect.execute(context)
	var relics := battle.get_node_or_null("RelicRuntime")
	if relics != null:
		if definition.category == CardDefinition.Category.RECRUIT:
			relics.deployed_unit(context.target)
		relics.card_played(context, played_cost)
	# 一张牌的多条效果只显示一次名称，空放或验证失败不会产生提示。
	if not definition.effects.is_empty():
		_show_card_effect_name(context.target, definition.card_name)
	# 单位已经按升级属性与技能生成，效果也已保存配方快照；原牌此时恢复。
	card.restore_evolution()
	if definition.category != CardDefinition.Category.RECRUIT:
		hand.finish_resolve(card)
	hand._notify_hand_changed()
	feedback.emit("")
	return true


# 作用：在实际受影响的单位头顶显示绿色来源名称；按精灵有效像素避开图集透明留白。
func _show_card_effect_name(unit: UnitBase, card_name: String) -> void:
	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion() \
		or card_name.is_empty():
		return
	var anchor := Vector2(0, -64)
	var sprite := unit.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null \
		and sprite.sprite_frames.has_animation(sprite.animation) \
		and sprite.sprite_frames.get_frame_count(sprite.animation) > sprite.frame:
		var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		if texture != null:
			if not _target_frame_bounds.has(texture):
				var image := texture.get_image()
				_target_frame_bounds[texture] = Rect2(image.get_used_rect()) if image != null else Rect2()
			var rect: Rect2 = _target_frame_bounds[texture]
			if rect.has_area():
				if sprite.flip_v:
					rect.position.y = texture.get_height() - rect.end.y
				var top := Vector2(texture.get_width() * 0.5, rect.position.y) + sprite.offset
				if sprite.centered:
					top -= texture.get_size() * 0.5
				anchor = unit.to_local(sprite.to_global(top))
	anchor.y -= 8.0
	for child in unit.get_children():
		if child.is_in_group("card_effect_names") and not child.is_queued_for_deletion():
			child.raise_line()
	var popup := CARD_EFFECT_NAME.new()
	popup.name = "CardEffectName"
	popup.card_name = card_name
	popup.anchor = anchor
	unit.add_child(popup)


# 作用：检查整张卡的目标、费用和所有效果；context 为出牌上下文，返回拒绝原因或空串。
func _validate_card(context: Dictionary, free_play: bool) -> String:
	var card: CardInstance = context.card
	var definition: CardDefinition = card.definition
	var needs_unit := definition.target in [CardDefinition.Target.ALLY, CardDefinition.Target.ENEMY, CardDefinition.Target.ANY_UNIT]
	# 单位牌按活目标验证；导航边缘或镜头移出的单位不受旧位置型效果矩形限制。
	if definition.category != CardDefinition.Category.RECRUIT and not needs_unit \
		and not battle.battlefield_rect.has_point(context.position):
		return "请把牌拖到战场范围内。"
	# 免费随机出牌仍忽略能量费用，普通出牌则必须付得起这张牌累加后的费用。
	if card.get_cost() < 0 or (not free_play and rounds.current_energy < card.get_cost()):
		return "能量不足。"
	if needs_unit and context.target == null:
		return "请拖到有效的目标单位上。"
	if definition.category == CardDefinition.Category.RECRUIT:
		context.deployment_floor = battle.get_deployment_floor(context.position)
		if definition.summon_unit == null or context.deployment_floor <= 0:
			return "请放在已烘焙导航的左半边可行走区域；没有导航时无法征召。"
		# 兵种内置的上场效果在成功部署后结算；通用效果组合仍使用独立效果牌。
		if not definition.effects.is_empty():
			return "征召牌暂不混合效果列表，请将效果配置为强化牌。"
	elif definition.effects.is_empty():
		return "这张牌还没有配置效果。"
	var total_hp_cost := 0
	var copies := 0
	for i in definition.effects.size():
		var effect: CardEffect = definition.effects[i]
		if effect == null:
			return "效果列表中有空资源。"
		var reason := effect.validate(context)
		if not reason.is_empty():
			return reason
		if effect.kind == CardEffect.Kind.PAY_HP:
			var relics := battle.get_node_or_null("RelicRuntime")
			total_hp_cost += int(relics.modified_effect(effect, context).amount if relics != null else effect.amount)
		if effect.kind == CardEffect.Kind.COPY_ALLY:
			copies += 1
		if effect.kind == CardEffect.Kind.RECALL_ALLY and i != definition.effects.size() - 1:
			return "收回单位必须是效果列表的最后一步。"
		if effect.kind == CardEffect.Kind.RANDOM_PLAY and i != definition.effects.size() - 1:
			return "随机出牌必须放在最后，避免连锁改变前面选择的目标。"
	if copies > 1:
		return "一张牌最多配置一次复制效果。"
	if total_hp_cost >= RunManager.hp:
		return "生命不足，不能用支付生命效果将自己降到零。"
	return ""


# 作用：验证一条内置效果；effect 是配方，context 是目标，返回拒绝原因或空串。
func validate_effect(effect: CardEffect, context: Dictionary) -> String:
	var relics := battle.get_node_or_null("RelicRuntime")
	if relics != null:
		effect = relics.modified_effect(effect, context)
	effect = _effect_for_current_phase(effect)
	if effect.kind not in CardEffect.Kind.values():
		return "这张牌配置了无效的效果类型。"
	if expanded.handles(effect.kind):
		return expanded.validate(effect, context)
	if effect.is_tactical():
		return tactics.validate_effect(effect, context)
	if effect.kind in [CardEffect.Kind.COMRADE, CardEffect.Kind.TEMPORARY_UPGRADE]:
		return plays.validate(effect, context)
	# 临时复制品或敌人没有对应的己方征召牌，永久强化必须在扣费前拒绝。
	if effect.is_unit_buff():
		if effect.lifetime == CardEffect.Lifetime.ROUNDS and effect.lasting_rounds < 1:
			return "强化至少持续一个战斗回合。"
		if effect.lifetime == CardEffect.Lifetime.RUN:
			if not is_instance_valid(context.target) or not hand.board_cards.has(context.target.get_instance_id()):
				return "永久强化只能施加给有原征召牌的己方单位。"
	elif effect.kind in [CardEffect.Kind.DAMAGE_ZONE, CardEffect.Kind.MUD_ZONE]:
		if effect.lifetime == CardEffect.Lifetime.RUN:
			return "地面区域不支持本局永久，请选择 Battle 或 Rounds。"
		if effect.lifetime == CardEffect.Lifetime.ROUNDS and effect.lasting_rounds < 1:
			return "区域至少持续一个战斗回合。"
	elif effect.lifetime != CardEffect.Lifetime.BATTLE:
		return "一次性效果不支持持续类型，请保留 Battle。"
	if effect.kind == CardEffect.Kind.CUSTOM:
		return "自定义效果需要继承 CardEffect，并实现 validate 与 execute。"
	if effect.kind == CardEffect.Kind.RETAIN_ALLIES and context.card.definition.after_use != CardDefinition.AfterUse.PERSIST:
		return "留存友军效果需要设置为常驻卡牌。"
	if not is_finite(effect.amount):
		return "效果数值必须是有限数字。"
	if effect.kind not in [CardEffect.Kind.HEAL_PERCENT,
		CardEffect.Kind.MUD_ZONE, CardEffect.Kind.COPY_ALLY, CardEffect.Kind.RECALL_ALLY,
		CardEffect.Kind.LOCK_DRAW] and effect.amount != floorf(effect.amount):
		return "点数、层数和张数请填写整数。"
	var targeted := effect.kind in [CardEffect.Kind.ATTACK_UP, CardEffect.Kind.HEAL_PERCENT,
		CardEffect.Kind.DEFENCE_UP, CardEffect.Kind.POISON_ON_HIT, CardEffect.Kind.DEATH_EXPLOSION,
		CardEffect.Kind.COPY_ALLY, CardEffect.Kind.RECALL_ALLY, CardEffect.Kind.MAX_HP_UP]
	if targeted and not is_instance_valid(context.target):
		return "此效果需要一个单位目标。"
	if effect.kind in [CardEffect.Kind.COPY_ALLY, CardEffect.Kind.RECALL_ALLY]:
		if context.target.unit_data.unit_team != "team_a":
			return "只能复制或收回己方单位。"
	if effect.kind == CardEffect.Kind.RECALL_ALLY and not hand.board_cards.has(context.target.get_instance_id()):
		return "临时复制品没有原牌，不能收回。"
	if effect.kind == CardEffect.Kind.DRAW and hand.draw_locked:
		return "本回合已禁止抽牌。"
	if effect.kind in [CardEffect.Kind.HEAL_PERCENT, CardEffect.Kind.MUD_ZONE] and (effect.amount <= 0 or effect.amount > 100):
		return "回复或减速百分数应在 0 到 100 之间。"
	if effect.kind in [CardEffect.Kind.DEATH_EXPLOSION, CardEffect.Kind.DAMAGE_ZONE, CardEffect.Kind.MUD_ZONE]:
		if not is_finite(effect.radius) or not is_finite(effect.interval):
			return "范围与时间必须是有限数字。"
		if effect.radius <= 0 or effect.interval < 0.1:
			return "范围必须大于零，结算间隔至少 0.1 秒。"
	if effect.kind not in [CardEffect.Kind.COPY_ALLY,
		CardEffect.Kind.RECALL_ALLY, CardEffect.Kind.LOCK_DRAW, CardEffect.Kind.RETAIN_ALLIES] and effect.amount <= 0:
		return "效果数值必须大于零。"
	if effect.kind == CardEffect.Kind.RETAIN_ALLIES and effect.amount < 0:
		return "阵亡加费不能为负数。"
	return ""


# 作用：交锋中持续效果只保留本轮，能量成长即时兑现；effect 是共享配方，返回不修改配方的快照。
func _effect_for_current_phase(effect: CardEffect) -> CardEffect:
	if Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		return effect
	if effect.is_unit_buff() or effect.kind in [CardEffect.Kind.DAMAGE_ZONE, CardEffect.Kind.MUD_ZONE]:
		var temporary := effect.duplicate() as CardEffect
		temporary.lifetime = CardEffect.Lifetime.ROUNDS
		temporary.lasting_rounds = 1
		return temporary
	if effect.kind == CardEffect.Kind.ENERGY_EACH_ROUND:
		var immediate := effect.duplicate() as CardEffect
		immediate.kind = CardEffect.Kind.GAIN_ENERGY
		return immediate
	return effect


# 作用：执行一条已验证效果；effect 为配方，context 为出牌上下文，没有返回值。
func apply_effect(effect: CardEffect, context: Dictionary) -> void:
	# 自定义效果也可能延后调用这个入口；结束的战场不能再支付生命或改变能量。
	if battle.battle_finished:
		return
	var relics := battle.get_node_or_null("RelicRuntime")
	if relics != null:
		effect = relics.modified_effect(effect, context)
	effect = _effect_for_current_phase(effect)
	if expanded.handles(effect.kind):
		expanded.apply(effect, context)
		return
	if effect.is_tactical():
		tactics.apply_effect(effect, context)
		return
	if effect.kind == CardEffect.Kind.COMRADE:
		plays.comrade_threshold = int(effect.amount)
		return
	if effect.kind == CardEffect.Kind.TEMPORARY_UPGRADE:
		context.target_card.temporary_upgrade(context.allocation, context.soldier_branch)
		hand._notify_hand_changed()
		return
	var target: UnitBase = context.target
	var amount := int(effect.amount)
	if effect.is_unit_buff():
		var label: String = context.card.definition.card_name
		_add_buff(target, effect, label)
		if effect.lifetime == CardEffect.Lifetime.RUN:
			var original: CardInstance = hand.board_cards[target.get_instance_id()]
			original.permanent_buffs.append({"effect": effect.duplicate(), "label": label})
			RunManager.deck_changed.emit()
		return
	match effect.kind:
		CardEffect.Kind.HEAL_PERCENT:
			target.get_heal(int(ceil(target.unit_data.max_hp * effect.amount / 100.0)))
		CardEffect.Kind.COPY_ALLY:
			var copied := _spawn_prepared(context, _nearby_position(target.global_position), target.floor_id)
			for buff: Dictionary in states[target.get_instance_id()].buffs:
				var inherited: CardEffect = buff.effect.duplicate()
				# 复制品没有原牌；永久效果在它身上只保留到本场结束。
				if inherited.lifetime == CardEffect.Lifetime.RUN:
					inherited.lifetime = CardEffect.Lifetime.BATTLE
				_add_buff(copied, inherited, buff.label, int(buff.left))
			copied.current_health = mini(int(target.current_health), copied.unit_data.max_hp)
			copied.get_node("HealthBar").update_hp_bar(copied.current_health)
		CardEffect.Kind.DAMAGE_ZONE, CardEffect.Kind.MUD_ZONE:
			create_zone(effect, context.position, context.card.definition.card_name)
		CardEffect.Kind.DRAW:
			hand.draw_cards(amount)
		CardEffect.Kind.LOCK_DRAW:
			hand.draw_locked = true
		CardEffect.Kind.PAY_HP:
			RunManager.hp -= amount
		CardEffect.Kind.ENERGY_EACH_ROUND:
			rounds.pending_recurring_energy += amount
		CardEffect.Kind.GAIN_ENERGY:
			# 即时补给只增加当前值，不排到下一轮，也不提高分母。
			rounds.gain_energy(amount)
		CardEffect.Kind.DEATH_ATTACK_AURA:
			death_attack_per_unit += amount
			if Global.game_phase == Global.GamePhase.AUTO_BATTLE:
				_combat_death_attack_per_unit += amount
			for unit in living_units():
				_apply_aura(unit)
		CardEffect.Kind.RANDOM_PLAY:
			_random_play(amount, int(context.depth) + 1)
		CardEffect.Kind.RECALL_ALLY:
			if hand.recall_unit(target):
				target.set_meta("recalled", true)
				target.get_parent().remove_child(target)
				target.queue_free()
		CardEffect.Kind.RETAIN_ALLIES:
			# 重复常驻不叠加；强化版可将已有的阵亡惩罚降至1，普通版不会覆盖更低惩罚。
			unit_discard_cost_increase = mini(unit_discard_cost_increase, amount) if retain_allies else amount
			retain_allies = true


# 作用：添加一次独立强化；unit 为目标，effect 为配方，label 为来源，left 可指定复制后的剩余回合。
# 返回值：没有返回值；复制配方快照，后续改资源不会改变已施加的数值。
func _add_buff(unit: UnitBase, effect: CardEffect, label: String, left: int = -1) -> void:
	var snapshot: CardEffect = effect.duplicate()
	states[unit.get_instance_id()].buffs.append({"effect": snapshot, "label": label,
		"left": snapshot.lasting_rounds if left < 0 else left})
	_change_buff_value(unit, snapshot, 1)
	if tactics != null:
		tactics.refresh_all()
	else:
		_refresh_unit_status(unit)


## 药水有独立期限，不走交锋中卡牌效果的一回合降级。
func apply_potion_buff(unit: UnitBase, effect: CardEffect, label: String) -> void:
	if is_instance_valid(unit) and unit.is_alive() and states.has(unit.get_instance_id()) and not battle.battle_finished:
		_add_buff(unit, effect, label)


func add_poison(unit: UnitBase, amount: int) -> void:
	if amount <= 0 or not is_instance_valid(unit) or not unit.is_alive() or not states.has(unit.get_instance_id()):
		return
	states[unit.get_instance_id()].poison += amount
	unit.skill_manager.interrupt_chant()
	unit.status_runtime.set_visual(&"poison", true, &"potion")
	_refresh_unit_status(unit)


func cleanse(unit: UnitBase) -> void:
	for id in [&"bleed", &"weakness", &"slow", &"armor_break", &"armor_shred", &"confusion", &"sleep"]:
		unit.remove_status(id)
	var state: Dictionary = states[unit.get_instance_id()]
	state.poison = 0
	state.erase("poison_source")
	unit.status_runtime.set_visual(&"poison", false, &"potion")
	var record: Dictionary = tactics.records.get(unit.get_instance_id(), {})
	for kind in [CardEffect.Kind.WEAKNESS, CardEffect.Kind.DEFENCE_DOWN]:
		record.get("effects", {}).erase(kind)
	tactics.refresh_all()
	_refresh_unit_status(unit)


func convert_enemy(unit: UnitBase) -> bool:
	if not is_instance_valid(unit) or not unit.is_alive() or unit.unit_data.unit_team != "team_b" or unit.unit_data.monster_rank != UnitData.MonsterRank.NORMAL:
		return false
	tactics._convert(unit)
	tactics.refresh_all()
	return true


## 去掉临时贡献后生成副本，再按原期限逐条继承，避免强化加两次。
func prepare_potion_copy(target: UnitBase) -> UnitBase:
	var data := target.unit_data.duplicate() as UnitData
	var state: Dictionary = states[target.get_instance_id()]
	data.speed = float(state.base_speed)
	tactics.strip_stat_contributions(target, data)
	target.status_runtime.strip_stat_contributions(data)
	data.defence -= target.taunt_defence_bonus
	data.attack -= target.protection_attack_bonus + target.consecutive_attack_bonus + target.soldier_attack_bonus + int(state.aura_bonus)
	for buff: Dictionary in state.buffs:
		match buff.effect.kind:
			CardEffect.Kind.ATTACK_UP: data.attack -= int(buff.effect.amount)
			CardEffect.Kind.DEFENCE_UP: data.defence -= int(buff.effect.amount)
			CardEffect.Kind.MAX_HP_UP: data.max_hp -= int(buff.effect.amount)
	return _prepare_unit(data)


func inherit_potion_buffs(unit: UnitBase, buffs: Array) -> void:
	for buff: Dictionary in buffs:
		var effect := buff.effect.duplicate() as CardEffect
		if effect.lifetime == CardEffect.Lifetime.RUN:
			effect.lifetime = CardEffect.Lifetime.BATTLE
		_add_buff(unit, effect, str(buff.label), int(buff.left))


# 作用：只增加或撤回一条强化的贡献；unit 为目标，effect 为快照，sign 为 1 或 -1，没有返回值。
func _change_buff_value(unit: UnitBase, effect: CardEffect, direction: int) -> void:
	var state: Dictionary = states[unit.get_instance_id()]
	match effect.kind:
		CardEffect.Kind.ATTACK_UP:
			unit.unit_data.attack += int(effect.amount) * direction
		CardEffect.Kind.DEFENCE_UP:
			unit.unit_data.defence += int(effect.amount) * direction
		CardEffect.Kind.MAX_HP_UP:
			unit.unit_data.max_hp += int(effect.amount) * direction
			if unit.current_health != null:
				unit.current_health = mini(int(unit.current_health) + (int(effect.amount) if direction > 0 else 0), unit.unit_data.max_hp)
				var health_bar := unit.get_node("HealthBar")
				if health_bar.is_node_ready():
					health_bar.hp_bar.max_value = unit.unit_data.max_hp
					health_bar.update_hp_bar(unit.current_health)
		CardEffect.Kind.POISON_ON_HIT:
			state.poison_on_hit += int(effect.amount) * direction
		CardEffect.Kind.DEATH_EXPLOSION:
			if direction > 0:
				state.explosions.append(effect)
			else:
				state.explosions.erase(effect)


# 作用：回合末逐条扣剩余回合；没有参数，没有返回值。同名强化不合并、不刷新旧计时。
func _tick_buffs() -> void:
	for unit in living_units():
		var buffs: Array = states[unit.get_instance_id()].buffs
		for i in range(buffs.size() - 1, -1, -1):
			var buff: Dictionary = buffs[i]
			if buff.effect.lifetime != CardEffect.Lifetime.ROUNDS:
				continue
			buff.left -= 1
			if buff.left <= 0:
				_change_buff_value(unit, buff.effect, -1)
				buffs.remove_at(i)
		_refresh_unit_status(unit)


# 作用：撤销单位身上所有活跃强化；unit 是死亡或结算单位，没有返回值，不删除原牌永久记录。
func _clear_unit_buffs(unit: UnitBase) -> void:
	for buff: Dictionary in states[unit.get_instance_id()].buffs:
		_change_buff_value(unit, buff.effect, -1)
	states[unit.get_instance_id()].buffs.clear()
	_refresh_unit_status(unit)


# 作用：本场结束清理效果显示与属性；没有参数，没有返回值。永久记录留在 CardInstance。
func clear_battle_buffs() -> void:
	clear_cast_preview()
	plays.clear_battle()
	expanded.clear_battle()
	tactics.clear_battle()
	retain_allies = false
	unit_discard_cost_increase = 1
	_clear_combat_aura()
	for zone in zones:
		_clear_zone_visual(zone)
	zones.clear()
	_refresh_zone_speeds()
	queue_redraw()
	for unit in living_units():
		unit.clear_combat_statuses()
		states[unit.get_instance_id()].poison = 0
		_clear_unit_buffs(unit)


# 作用：生成内部诊断用的逐来源记录；界面悬停提示由下方的汇总入口生成。
func describe_buffs(unit: UnitBase) -> Array[String]:
	var result: Array[String] = []
	if relics_runtime() != null:
		for status: Dictionary in relics_runtime().statuses_for(unit):
			result.append(String(status.tooltip))
	if unit.unit_data.has_sword_arrow():
		result.append(UnitData.sword_arrow_description() + " · 来自士兵远近普攻")
	for buff: Dictionary in states.get(unit.get_instance_id(), {}).get("buffs", []):
		var effect: CardEffect = buff.effect
		var duration_text := "本场战斗"
		if effect.lifetime == CardEffect.Lifetime.ROUNDS:
			duration_text = "剩余 %d 战斗回合" % buff.left
		elif effect.lifetime == CardEffect.Lifetime.RUN:
			duration_text = "本局永久"
		var names := {CardEffect.Kind.ATTACK_UP: "攻击", CardEffect.Kind.DEFENCE_UP: "防御",
			CardEffect.Kind.POISON_ON_HIT: "攻击附毒", CardEffect.Kind.DEATH_EXPLOSION: "死亡爆炸伤害",
			CardEffect.Kind.MAX_HP_UP: "最大生命"}
		result.append("%s：%s +%d · %s" % [buff.label, names[effect.kind], int(effect.amount), duration_text])
	for entry: Dictionary in tactics.statuses_for(unit):
		result.append(String(entry.tooltip))
	for entry: Dictionary in unit.protection_statuses():
		result.append(String(entry.tooltip))
	for entry: Dictionary in unit.consecutive_attack_statuses():
		result.append(String(entry.tooltip))
	for entry: Dictionary in unit.stealth_statuses():
		result.append(String(entry.tooltip))
	for entry: Dictionary in unit.active_statuses():
		result.append(String(entry.tooltip))
	return result



# 作用：将同类强化合并成一个图标；提示只显示当前总加成，来源与期限留在玩法记录中。
func _refresh_unit_status(unit: UnitBase) -> void:
	var health_bar := unit.get_node_or_null("HealthBar")
	if health_bar == null:
		return
	if battle.battle_finished or unit.current_state == UnitBase.State.DEATH:
		health_bar.set_statuses([])
		return
	var state: Dictionary = states.get(unit.get_instance_id(), {})
	var positive: Array[Dictionary] = []
	var negative: Array[Dictionary] = []
	if unit.unit_data.has_sword_arrow():
		positive.append({"icon": "sword_arrow", "tooltip": UnitData.sword_arrow_description()})
	positive.append_array(unit.protection_statuses())
	positive.append_array(unit.consecutive_attack_statuses())
	positive.append_array(unit.stealth_statuses())
	if relics_runtime() != null:
		positive.append_array(relics_runtime().statuses_for(unit))
	var names := {CardEffect.Kind.ATTACK_UP: "攻击力提升", CardEffect.Kind.DEFENCE_UP: "防御力提升",
		CardEffect.Kind.POISON_ON_HIT: "攻击附毒", CardEffect.Kind.DEATH_EXPLOSION: "死亡爆炸",
		CardEffect.Kind.MAX_HP_UP: "最大生命提升"}
	var icons := {CardEffect.Kind.ATTACK_UP: "attack", CardEffect.Kind.DEFENCE_UP: "defence",
		CardEffect.Kind.POISON_ON_HIT: "poison_on_hit", CardEffect.Kind.DEATH_EXPLOSION: "explosion",
		CardEffect.Kind.MAX_HP_UP: "max_hp"}
	# 首次批量显示时也按真实强化记录的施加顺序输入，常规更新由图标组件保留原位置。
	var kinds: Array[int] = []
	for buff: Dictionary in state.get("buffs", []):
		var effect: CardEffect = buff.effect
		if not kinds.has(effect.kind):
			kinds.append(effect.kind)
	if int(state.get("aura_bonus", 0)) > 0 and not kinds.has(CardEffect.Kind.ATTACK_UP):
		kinds.append(CardEffect.Kind.ATTACK_UP)
	for kind in kinds:
		var total := 0
		for buff: Dictionary in state.get("buffs", []):
			var effect: CardEffect = buff.effect
			if effect.kind == kind:
				total += int(effect.amount)
		if kind == CardEffect.Kind.ATTACK_UP and int(state.get("aura_bonus", 0)) > 0:
			total += int(state.aura_bonus)
		if total > 0:
			var summary := "%s：+%d" % [names[kind], total]
			if kind == CardEffect.Kind.POISON_ON_HIT:
				summary = "攻击附毒：每次命中叠加 %d 层毒" % total
			elif kind == CardEffect.Kind.DEATH_EXPLOSION:
				summary = "死亡爆炸：总伤害 %d" % total
			positive.append({"icon": icons[kind], "tooltip": summary})
	negative.append_array(state.get("terrain_statuses", []))
	var poison := int(state.get("poison", 0))
	if poison > 0:
		negative.append({"icon": "poison", "count": poison,
			"tooltip": "中毒：%d 层\n每个战斗回合结束受到 %d 点无视防御的伤害。" % [poison, poison]})
	positive.append_array(negative)
	positive.append_array(tactics.statuses_for(unit) if tactics != null else [])
	positive.append_array(expanded.statuses_for(unit) if expanded != null else [])
	# 技能和战术卡可能施加同类状态，保留一个图标并同时展示两个来源的说明。
	for entry: Dictionary in unit.active_statuses():
		var merged := false
		for existing: Dictionary in positive:
			if existing.icon == entry.icon:
				existing.tooltip += "\n" + String(entry.tooltip)
				merged = true
				break
		if not merged:
			positive.append(entry)
	health_bar.set_statuses(positive)


# 作用：准备兵种场景但不入树；data 为兵种数据，返回单位或空。
func _prepare_unit(data: UnitData) -> UnitBase:
	var path := "res://scenes/units/%s.tscn" % data.unit_english_name
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate()
	if not node is UnitBase:
		node.free()
		return null
	node.unit_data = data
	if not node.configuration_error().is_empty():
		node.free()
		return null
	return node


# 作用：把预先检查过的单位放入战场；context 含单位，point 是世界坐标，返回单位。
func _spawn_prepared(context: Dictionary, point: Vector2, floor_id: int) -> UnitBase:
	var unit: UnitBase = context.prepared
	unit.floor_id = floor_id
	battle.get_node("Entities/TeamA").add_child(unit)
	unit.global_position = point
	context.prepared = null
	return unit


# 作用：为复制品取一个附近合法落点；point 为原单位位置，返回限制在战场内的新位置。
func _nearby_position(point: Vector2) -> Vector2:
	var rect: Rect2 = battle.battlefield_rect.grow(-25.0)
	return (point + Vector2(45, 25)).clamp(rect.position, rect.end)


# 作用：随机免费打出若干张手牌；count 是成功张数上限，depth 是连锁深度，没有返回值。
func _random_play(count: int, depth: int) -> void:
	var candidates: Array = hand.draw_pile.duplicate()
	candidates.shuffle()
	var played := 0
	for card: CardInstance in candidates:
		if played >= count or chain_count >= MAX_CHAIN:
			break
		if not hand.draw_pile.has(card):
			continue
		var definition := card.definition
		var rect: Rect2 = battle.deployment_rect.grow(-30.0)
		var point := Vector2(randf_range(rect.position.x, rect.end.x), randf_range(rect.position.y, rect.end.y))
		if definition.category == CardDefinition.Category.RECRUIT:
			var valid_point: Variant = battle.random_deployment_position()
			if valid_point == null:
				continue
			point = valid_point
		if definition.target in [CardDefinition.Target.ALLY, CardDefinition.Target.ENEMY, CardDefinition.Target.ANY_UNIT]:
			var possible := targets_for(definition)
			possible.shuffle()
			for unit in possible:
				if try_play(card, unit.global_position, true, depth, true):
					played += 1
					break
		elif try_play(card, point, true, depth, true):
			played += 1


# 作用：实际命中后叠毒；unit 为受击者，attacker 为攻击者，没有返回值。
func _on_hit(unit: UnitBase, attacker: UnitBase) -> void:
	var relics := battle.get_node_or_null("RelicRuntime")
	if relics != null and Global.game_phase == Global.GamePhase.AUTO_BATTLE:
		relics.hit(unit, attacker)
	if Global.game_phase == Global.GamePhase.AUTO_BATTLE:
		expanded.hit_received(unit)
	if Global.game_phase != Global.GamePhase.AUTO_BATTLE or not is_instance_valid(attacker):
		return
	if attacker.unit_data.unit_team == unit.unit_data.unit_team:
		return
	if states.has(attacker.get_instance_id()) and states.has(unit.get_instance_id()):
		var added := int(states[attacker.get_instance_id()].poison_on_hit)
		if added > 0:
			unit.skill_manager.interrupt_chant()
			states[unit.get_instance_id()].poison += added
			states[unit.get_instance_id()].poison_source = weakref(attacker)
			_refresh_unit_status(unit)


# 作用：回合结束时按毒层数造成无视防御的伤害；没有参数，没有返回值。
func _on_round_ended() -> void:
	if battle.battle_finished:
		return
	expanded.end_round()
	for unit in living_units():
		var source: WeakRef = states[unit.get_instance_id()].get("poison_source")
		unit.take_effect_damage(int(states[unit.get_instance_id()].poison), source.get_ref() if source != null else null, &"poison")
	# 先结算本轮毒和死亡爆炸，再扣持续回合；最后一回合的效果也能完整生效。
	_tick_buffs()
	_tick_zones()
	_clear_combat_aura()
	tactics.end_round()
	# HP 胜负只由回合管理器判断，本脚本只处理毒、强化和区域期限。


# 作用：本轮结束撤回交锋中施加的光环，准备阶段光环保留原期限；没有参数，没有返回值。
func _clear_combat_aura() -> void:
	if _combat_death_attack_per_unit == 0:
		return
	death_attack_per_unit -= _combat_death_attack_per_unit
	_combat_death_attack_per_unit = 0
	for unit in living_units():
		_apply_aura(unit)


# 作用：单位死亡时统计伤亡并触发爆炸；unit 是死者，没有返回值。
func _on_death(unit: UnitBase) -> void:
	if preview_target == unit:
		clear_cast_preview()
	if battle.battle_finished or not states.has(unit.get_instance_id()):
		return
	var relics := battle.get_node_or_null("RelicRuntime")
	if relics != null:
		relics.unit_died(unit)
	expanded.unit_died(unit)
	tactics.unit_died(unit)
	if unit.unit_data.unit_team == "team_a":
		ally_deaths += 1
		for survivor in living_units():
			_apply_aura(survivor)
	# 死者已经标记 DEATH；连锁爆炸不会让同一单位重复死亡。
	var explosions: Array = states[unit.get_instance_id()].explosions.duplicate()
	_clear_unit_buffs(unit)
	for effect: CardEffect in explosions:
		if effect.has_meta("potion_enemy_only"):
			preload("res://scripts/effects/combat_vfx.gd").spawn(unit, "PoisonImpactVFX", 0.8, 1.3)
		for other in living_units():
			if effect.has_meta("potion_enemy_only") and other.unit_data.unit_team == unit.unit_data.unit_team:
				continue
			if other.global_position.distance_to(unit.global_position) <= effect.radius:
				other.take_effect_damage(int(effect.amount), unit)
	tactics.refresh_all()
	# 等同帧其它死亡与爆炸处理完再检查两队，避免最后两兵同时死亡被误判。
	rounds.request_round_check()


# 作用：更新己方伤亡光环，避免反复叠加旧加成；unit 为待更新单位，没有返回值。
func _apply_aura(unit: UnitBase) -> void:
	if unit.unit_data.unit_team != "team_a":
		_refresh_unit_status(unit)
		return
	var state: Dictionary = states[unit.get_instance_id()]
	var bonus := ally_deaths * death_attack_per_unit
	unit.unit_data.attack += bonus - int(state.aura_bonus)
	state.aura_bonus = bonus
	if tactics != null:
		tactics.refresh_all()
	else:
		_refresh_unit_status(unit)


# 作用：固定物理步更新区域；delta 是秒数，没有返回值。暂停时跟随战场停止。
func _physics_process(delta: float) -> void:
	if not is_instance_valid(battle) or battle.battle_finished:
		return
	var units := living_units()
	if Global.game_phase == Global.GamePhase.AUTO_BATTLE:
		for i in range(zones.size() - 1, -1, -1):
			var zone: Dictionary = zones[i]
			var effect: CardEffect = zone.effect
			zone.clock += delta
			while zone.clock >= effect.interval:
				zone.clock -= effect.interval
				if effect.kind == CardEffect.Kind.DAMAGE_ZONE:
					for unit in units:
						if _zone_hits(effect, unit) and unit.global_position.distance_to(zone.position) <= effect.radius:
								if zone.get("source", &"card") == &"relic" and relics_runtime() != null:
									relics_runtime().dispatching = true
									unit.take_effect_damage(int(effect.amount), null, &"relic")
									relics_runtime().dispatching = false
								else:
									unit.take_effect_damage(int(effect.amount), null, &"burn")
		queue_redraw()
	_refresh_zone_speeds()


# 作用：每轮战斗结束时递减区域期限；没有参数，没有返回值。本场区域不扣回合。
func _tick_zones() -> void:
	for i in range(zones.size() - 1, -1, -1):
		var zone: Dictionary = zones[i]
		if zone.effect.lifetime == CardEffect.Lifetime.ROUNDS:
			zone.rounds_left -= 1
			if zone.rounds_left <= 0:
				_clear_zone_visual(zone)
				zones.remove_at(i)
	# 泥潭消失时立即恢复速度，不等下一帧，也不能撤掉另一个仍存在的泥潭。
	_refresh_zone_speeds()
	queue_redraw()


# 作用：区域到期或战斗结束时同时撤销对应特效，不影响其它重叠区域。
func _clear_zone_visual(zone: Dictionary) -> void:
	var visual: Node2D = zone.get("visual")
	if is_instance_valid(visual):
		visual.hide()
		visual.queue_free()


# 作用：按当前区域重算速度和地形减益；离开、区域到期或消失后立即撤销显示。
func _refresh_zone_speeds() -> void:
	for unit in living_units():
		var multiplier := 1.0
		var burns: Array[String] = []
		var terrain_order: Array[String] = []
		for zone in zones:
			var effect: CardEffect = zone.effect
			if unit.global_position.distance_to(zone.position) > effect.radius:
				continue
			# 沿用现有泥潭对所有单位减速的规则；多块重叠取最强减速。
			if effect.kind == CardEffect.Kind.MUD_ZONE:
				if not terrain_order.has("mud"):
					terrain_order.append("mud")
				multiplier = minf(multiplier, 1.0 - effect.amount / 100.0)
			elif effect.kind == CardEffect.Kind.DAMAGE_ZONE and _zone_hits(effect, unit):
				if not terrain_order.has("burn"):
					terrain_order.append("burn")
				var duration := "本场战斗"
				if effect.lifetime == CardEffect.Lifetime.ROUNDS:
					duration = "剩余 %d 战斗回合" % int(zone.rounds_left)
				burns.append("每 %.1f 秒受到 %d 点伤害 · %s" % [effect.interval, int(effect.amount), duration])
			# 每块区域首次影响此单位时提示一次，持续伤害和逐帧减速不会刷屏。
			if (effect.kind == CardEffect.Kind.MUD_ZONE or _zone_hits(effect, unit)) \
				and not zone.get("notified_units", {}).has(unit.get_instance_id()):
				_show_card_effect_name(unit, zone.get("card_name", ""))
				zone.get_or_add("notified_units", {})[unit.get_instance_id()] = true
		var state: Dictionary = states[unit.get_instance_id()]
		unit.unit_data.speed = float(state.base_speed) * multiplier * expanded.speed_multiplier(unit)
		var terrain: Array[Dictionary] = []
		if multiplier < 1.0:
			terrain.append({"icon": "mud", "tooltip": "泥沼减速：移速降低 %.0f%%\n当前移速：%.1f\n重叠泥沼取最强减速，离开后恢复。" % [(1.0 - multiplier) * 100.0, unit.unit_data.speed]})
		if not burns.is_empty():
			terrain.append({"icon": "burn", "tooltip": "灼烧：处于 %d 个火焰区域\n%s\n只在交锋阶段结算伤害，离开区域后解除。" % [burns.size(), "\n".join(burns)]})
		# 同帧进入多种地形时，沿用区域实际创建的先后顺序。
		terrain.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return terrain_order.find(String(a.icon)) < terrain_order.find(String(b.icon)))
		# 区域循环本来就在每帧运行；只在显示内容改变时向 UI 推送。
		if state.get("terrain_statuses", []) != terrain:
			state.terrain_statuses = terrain
			_refresh_unit_status(unit)


# 作用：筛选伤害区域阵营；effect 为配置、unit 为候选，返回是否命中该阵营。
func _zone_hits(effect: CardEffect, unit: UnitBase) -> bool:
	return effect.affected_team == CardEffect.AffectedTeam.BOTH or (
		effect.affected_team == CardEffect.AffectedTeam.ALLIES and unit.unit_data.unit_team == "team_a"
	) or (effect.affected_team == CardEffect.AffectedTeam.ENEMIES and unit.unit_data.unit_team != "team_a")


func relics_runtime() -> Node:
	return battle.get_node_or_null("RelicRuntime")


## 卡牌与遗物共享区域表现和期限，各自保存来源，互不覆盖。
func create_zone(effect: CardEffect, point: Vector2, label: String, source: StringName = &"card") -> void:
	var zone := {"effect": effect.duplicate(), "position": point,
		"rounds_left": effect.lasting_rounds, "clock": 0.0,
		"card_name": label, "notified_units": {}, "source": source}
	zones.append(zone)
	var visual: Node2D
	if effect.kind == CardEffect.Kind.DAMAGE_ZONE:
		visual = BURN_GROUND_ZONE.new(effect.radius)
		visual.pattern_seed = fposmod(point.x * 0.031 + point.y * 0.057, 1024.0)
	else:
		visual = MUD_GROUND_ZONE.new(effect.radius)
	var terrain := battle.get_node("Level/NavigationRegion2D")
	visual.position = to_local(point)
	visual.z_as_relative = false
	visual.z_index = terrain.get_floor_z_index(terrain.spawn_floor_at(point)) - 1
	add_child(visual)
	zone.visual = visual
	_refresh_zone_speeds()
	queue_redraw()


# 作用：泥潭印记保留底色；火焰地形由焦草 Shader 直接融合原地面。
func _draw() -> void:
	for zone in zones:
		var effect: CardEffect = zone.effect
		var point := to_local(zone.position)
		if effect.kind == CardEffect.Kind.MUD_ZONE:
			draw_circle(point, effect.radius, Color(0.5, 0.3, 0.12, 0.3))
