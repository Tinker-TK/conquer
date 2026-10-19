# 用真实施放与鼠标输入检查状态施加顺序、每行五个、左对齐及清理，开发测试才加载。
extends Node

var battle
var runtime
var ally: UnitBase
var enemy: UnitBase


func _ready() -> void:
	_run.call_deferred()


func _play(effect: CardEffect, point: Vector2, label: String = "状态测试") -> void:
	var definition := CardDefinition.new()
	definition.card_name = label
	definition.target = CardDefinition.Target.POSITION if effect.kind in [CardEffect.Kind.MUD_ZONE, CardEffect.Kind.DAMAGE_ZONE] else CardDefinition.Target.ALLY
	definition.effects.append(effect)
	var card := CardInstance.new(definition)
	battle.hand_manager.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	assert(runtime.try_play(card, point), "效果牌必须通过真实施放入口")


func _effect(kind: CardEffect.Kind, amount: int, lifetime: CardEffect.Lifetime = CardEffect.Lifetime.BATTLE, left: int = 1) -> CardEffect:
	var effect := CardEffect.new()
	effect.kind = kind
	effect.amount = amount
	effect.lifetime = lifetime
	effect.lasting_rounds = left
	return effect


func _entry(entries: Array, icon: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.icon == icon:
			return entry
	return {}


func _icons(display: Control) -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in display.statuses:
		result.append(String(entry.icon))
	return result


func _mouse(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)


func _run() -> void:
	var start := load("res://data/run/run_start_data.tres").duplicate(true) as RunStartData
	start.starting_relics.clear()
	start.starting_potions.clear()
	RunManager.start_new_run(start)
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	runtime = battle.card_runtime
	runtime.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var recruit := CardInstance.new(load("res://data/units/soldier.tres"))
	battle.hand_manager.hand.append(recruit)
	battle.battle_round_manager.current_energy = 99
	assert(runtime.try_play(recruit, Vector2(450, 450)))
	ally = battle.get_node("Entities/TeamA").get_children().back()
	enemy = battle.get_node("Entities/TeamB").get_child(0)
	enemy.global_position = Vector2(850, 500)
	for unit in runtime.living_units():
		unit.set_physics_process(false)
	var health = ally.get_node("HealthBar")
	var display = health.status_display
	var innate_icons := _icons(display)
	assert(innate_icons == ["sword_arrow"] and health.visible and not health.panel.visible,
		"默认士兵已有剑矢状态，满血仍不显示血条")
	var base_attack: int = ally.unit_data.attack
	_play(_effect(CardEffect.Kind.ATTACK_UP, 5, CardEffect.Lifetime.ROUNDS), ally.global_position, "短期磨刀")
	_play(_effect(CardEffect.Kind.ATTACK_UP, 7), ally.global_position, "战斗磨刀")
	_play(_effect(CardEffect.Kind.DEFENCE_UP, 4, CardEffect.Lifetime.RUN), ally.global_position, "永久护甲")
	_play(_effect(CardEffect.Kind.POISON_ON_HIT, 3), ally.global_position)
	assert(health.visible and not health.panel.visible, "满血单位也要显示状态，血条仍按原规则隐藏")
	assert(_icons(display) == innate_icons + ["attack", "defence", "poison_on_hit"], "同类合并，按实际施加顺序排列")
	assert(_entry(display.statuses, "attack").tooltip.contains("攻击力提升：+12"))
	assert(_entry(display.statuses, "attack").tooltip == "攻击力提升：+12")
	assert(_entry(display.statuses, "defence").tooltip == "防御力提升：+4")
	assert(ally.unit_data.attack == base_attack + 12)
	var mud := _effect(CardEffect.Kind.MUD_ZONE, 50, CardEffect.Lifetime.ROUNDS)
	mud.radius = 60
	_play(mud, ally.global_position)
	var fire := _effect(CardEffect.Kind.DAMAGE_ZONE, 5)
	fire.radius = 60
	fire.affected_team = CardEffect.AffectedTeam.ENEMIES
	_play(fire, ally.global_position)
	assert(_icons(display) == innate_icons + ["attack", "defence", "poison_on_hit", "mud"], "减益与增益混排，友军不受敌军专属火焰影响")
	var enemy_display = enemy.get_node("HealthBar").status_display
	assert(enemy_display.statuses.is_empty())
	enemy.global_position = ally.global_position + Vector2(45, 0)
	runtime._refresh_zone_speeds()
	assert(_entry(enemy_display.statuses, "burn").tooltip.contains("每 1.0 秒受到 5 点伤害"))
	assert(_entry(display.statuses, "mud").tooltip.contains("移速降低 50%"))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	enemy.get_hurt(1, ally, false)
	enemy.get_hurt(1, ally, false)
	assert(_entry(enemy_display.statuses, "poison").count == 6)
	assert(_entry(enemy_display.statuses, "poison").tooltip.contains("6 点无视防御"))
	enemy.global_position = Vector2(850, 500)
	runtime._refresh_zone_speeds()
	assert(_icons(enemy_display) == ["poison"], "离开地形后仅保留真实毒状态")
	# 在泥沼之后再施加增益、灼烧和毒，确认混排顺序及第六、第七个图标换行。
	Global.game_phase = Global.GamePhase.CARD_PLAY
	battle.battle_round_manager.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	_play(_effect(CardEffect.Kind.DEATH_EXPLOSION, 7), ally.global_position)
	var both_fire := _effect(CardEffect.Kind.DAMAGE_ZONE, 3)
	both_fire.radius = 60
	both_fire.affected_team = CardEffect.AffectedTeam.BOTH
	_play(both_fire, ally.global_position)
	runtime._add_buff(enemy, _effect(CardEffect.Kind.POISON_ON_HIT, 2), "敌军毒刃")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	ally.get_hurt(1, enemy, false)
	assert(_icons(display) == innate_icons + ["attack", "defence", "poison_on_hit", "mud", "explosion", "burn", "poison"])
	assert(_entry(display.statuses, "poison").count == 2)
	assert(display.icon_rect(0).position == Vector2.ZERO)
	assert(display.icon_rect(4).position == Vector2(56, 0))
	assert(display.icon_rect(5).position == Vector2(0, 14), "第六个图标必须从下一行左侧开始")
	assert(display.icon_rect(6).position == Vector2(14, 14))
	assert(is_equal_approx(display.get_global_transform_with_canvas().origin.x, health.panel.get_global_transform_with_canvas().origin.x), "图标左边应与血条左边对齐")
	var burn_point: Vector2 = display.get_global_transform_with_canvas() * display.icon_rect(_icons(display).find("burn")).get_center()
	assert(display.status_at(burn_point).icon == "burn", "换行后的图标仍能正确命中")

	var inspector = battle.card_ui.get_node("UnitInspector")
	await get_tree().process_frame
	var icon_point: Vector2 = display.get_global_transform_with_canvas() * display.icon_rect(_icons(display).find("attack")).get_center()
	assert(display.status_at(icon_point).icon == "attack")
	_mouse(icon_point)
	await get_tree().process_frame
	inspector.update_hover(icon_point)
	assert(inspector.status_tooltip.visible and inspector.status_text.text.contains("+12"), "真实鼠标悬停应显示加成")
	assert(not inspector.panel.visible, "图标提示不同时打开大型单位详情")
	inspector.open_unit(ally)
	inspector.update_hover(icon_point)
	assert(inspector.panel.visible and inspector.inspected == ally, "悬停状态图标不会关闭已打开的单位详情")
	inspector.close_details()
	assert(display.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var camera := battle.get_node("Camera2D") as Camera2D
	camera.zoom = Vector2.ONE * 1.5
	camera.global_position = Vector2(800, 520)
	camera.force_update_scroll()
	icon_point = display.get_global_transform_with_canvas() * display.icon_rect(_icons(display).find("defence")).get_center()
	_mouse(icon_point)
	await get_tree().process_frame
	inspector.update_hover(icon_point)
	assert(inspector.status_tooltip.visible and inspector.status_text.text.contains("防御力提升：+4"))
	icon_point = display.get_global_transform_with_canvas() * display.icon_rect(_icons(display).find("burn")).get_center()
	_mouse(icon_point)
	await get_tree().process_frame
	inspector.update_hover(icon_point)
	assert(inspector.status_tooltip.visible and inspector.status_text.text.contains("灼烧"), "缩放后下一行的提示仍然正确")
	_mouse(Vector2(20, 20))
	await get_tree().process_frame
	inspector.update_hover(Vector2(20, 20))
	assert(not inspector.status_tooltip.visible)
	runtime._tick_buffs()
	runtime._tick_zones()
	assert(_entry(display.statuses, "attack").tooltip.contains("攻击力提升：+7"))
	assert(_entry(display.statuses, "attack").tooltip.find("短期磨刀") == -1)
	assert(_entry(display.statuses, "mud").is_empty(), "泥潭到期应立即撤销图标和减速")
	assert(_icons(display) == innate_icons + ["attack", "defence", "poison_on_hit", "explosion", "burn", "poison"], "解除状态后应补齐空位，不改动其余图标的先后顺序")
	assert(is_equal_approx(ally.unit_data.speed, runtime.states[ally.get_instance_id()].base_speed))
	# 重新进入的泥沼放在末尾；同帧进入多种地形时按区域创建顺序追加。
	Global.game_phase = Global.GamePhase.CARD_PLAY
	battle.battle_round_manager.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	_play(_effect(CardEffect.Kind.MUD_ZONE, 35), ally.global_position)
	assert(_icons(display).back() == "mud")
	enemy.global_position = ally.global_position + Vector2(45, 0)
	runtime._refresh_zone_speeds()
	assert(_icons(enemy_display) == ["poison", "poison_on_hit", "burn", "mud"])
	if "--status-preview" in OS.get_cmdline_user_args():
		Global.game_phase = Global.GamePhase.CARD_PLAY
		battle.battle_round_manager.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
		camera.zoom = Vector2.ONE
		camera.global_position = Vector2(960, 540)
		camera.force_update_scroll()
		_play(_effect(CardEffect.Kind.MUD_ZONE, 35), ally.global_position)
		fire.affected_team = CardEffect.AffectedTeam.BOTH
		_play(fire, ally.global_position)
		enemy.global_position = Vector2(800, 500)
		runtime._refresh_zone_speeds()
		ally.get_hurt(1, null, false)
		await get_tree().create_timer(0.5).timeout
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.maintenance/unit-status-preview.png")
		icon_point = display.get_global_transform_with_canvas() * display.icon_rect(0).get_center()
		_mouse(icon_point)
		await get_tree().process_frame
		inspector.update_hover(icon_point)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.maintenance/unit-status-tooltip.png")
	# 静止鼠标下状态清除也不能残留提示；暂停通知必须立即隐藏。
	get_tree().paused = true
	assert(not inspector.status_tooltip.visible)
	get_tree().paused = false
	enemy.die()
	assert(enemy_display.statuses.is_empty())
	battle.finish_battle(true)
	assert(display.statuses.is_empty())
	inspector.update_hover(icon_point)
	assert(not inspector.status_tooltip.visible)
	assert(runtime.states[ally.get_instance_id()].poison == 0)
	battle.queue_free()
	await get_tree().process_frame
	print("UNIT_STATUS_PASS")
	get_tree().quit()
