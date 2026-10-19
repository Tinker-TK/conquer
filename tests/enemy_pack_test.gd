# 用真实动画命中和投射物落点验证 Enemy Pack，覆盖旧单位与新单位的白烟退场。
extends Node

const ENEMIES := ["bear", "bomb_fish", "bumblebee", "giant_bat", "gnoll", "gnome",
	"harpoon_shark", "hex_shaman", "imp", "lizard", "minotaur", "paddle_shark", "panda",
	"skull", "slingshot_gnome", "snake", "spear_goblin", "spider", "thief", "torch_goblin",
	"troll", "turtle", "pig_rider"]
const RANGED := ["bomb_fish", "gnoll", "harpoon_shark", "hex_shaman", "slingshot_gnome"]
var checks := 0
var failures: Array[String] = []
var caster: UnitBase
var projectiles := 0
var hits := 0
var hit_frames: Array[int] = []
var deaths := 0
var preview_starts: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _projectile_added(child: Node) -> void:
	if child is Projectile and is_instance_valid(caster):
		projectiles += 1
		hit_frames.append(caster.animated_sprite_2d.frame)


func _hit(_unit: UnitBase, _attacker: UnitBase) -> void:
	hits += 1
	if is_instance_valid(caster) and caster.unit_data.unit_english_name not in RANGED:
		hit_frames.append(caster.animated_sprite_2d.frame)


func _death(_unit: UnitBase) -> void:
	deaths += 1


func _run() -> void:
	var arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	await _frames(2)
	arena.child_entered_tree.connect(_projectile_added)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	for id: String in ENEMIES:
		var path := "res://scenes/units/%s.tscn" % id
		_check(arena.spawn_buttons.has(path), id + " 可从测试场添加")
		caster = load(path).instantiate() as UnitBase
		arena.team_b.add_child(caster)
		caster.position = Vector2(1050, 500)
		caster.set_physics_process(false)
		var sprite := caster.animated_sprite_2d
		_check_pixel_style(sprite, id)
		var skill: SkillBase = caster.unit_data.skills[0]
		_check(caster.unit_data.skills.size() == 1 and caster.skill_manager.group_skills.size() == 1, id + " 只有一种攻击")
		_check(caster.unit_data.unit_english_name == id and caster.unit_data.unit_team == "team_b" and caster.is_in_group("team_b"), id + " 独立数据和敌方分组")
		_check(caster.unit_data.unit_type >= 21, id + " 独立兵种类型")
		_check(sprite.sprite_frames.get_animation_names().size() == 3 and skill.cast_animation == "attack_01", id + " idle/walk/attack_01 动画契约")
		for animation in [&"idle", &"walk", &"attack_01"]:
			_check(sprite.sprite_frames.get_animation_speed(animation) == 10.0, id + " 官网 10 FPS: " + animation)
		_check(not sprite.sprite_frames.get_animation_loop(&"attack_01"), id + " 攻击播完解锁")
		for frame: int in skill.hit_frame:
			_check(frame >= 0 and frame < sprite.sprite_frames.get_frame_count(&"attack_01"), id + " 命中帧存在")
		if id == "troll":
			_check(sprite.sprite_frames.get_frame_count(&"attack_01") == 43, "巨魔蓄力、三轮挥棒、两轮喘息组成一次攻击")
			_check(skill.hit_frame == [7, 10, 13, 16, 19, 22], "巨魔六次挥棒均有独立命中帧")
		elif id == "imp":
			_check(sprite.sprite_frames.get_frame_count(&"attack_01") == 20, "喷火开始、持续三轮、结束组成一次攻击")
			_check(skill.hit_frame == [4, 8, 12], "喷火按三轮持续段分别命中")
		elif id == "panda":
			_check(skill.hit_frame == [5, 7, 9], "双节棍按自身三段旋转节奏命中")
		elif id == "torch_goblin":
			_check(skill.hit_frame == [2, 5], "火把按两次旋转节奏命中")
		var target := load("res://scenes/units/soldier.tscn").instantiate() as UnitBase
		arena.team_a.add_child(target)
		target.set_physics_process(false)
		target.position = caster.position - Vector2(220.0 if id in RANGED else skill.cast_range - 10.0, 0)
		target.current_health = 10000
		target.hit_received.connect(_hit)
		hits = 0
		projectiles = 0
		hit_frames.clear()
		var manager := caster.skill_manager
		manager.current_skill = skill
		manager.current_target = target
		caster.switch_state(UnitBase.State.ATTACK)
		manager.attack()
		await _frames(5)
		_check(hits == 0 and projectiles == 0, id + " 前摇阶段不提前结算")
		var cast_seconds := 0.0
		for frame in sprite.sprite_frames.get_frame_count(&"attack_01"):
			cast_seconds += sprite.sprite_frames.get_frame_duration(&"attack_01", frame) / sprite.sprite_frames.get_animation_speed(&"attack_01")
		await _frames(ceili((cast_seconds + 1.0) * 60.0))
		_check(not manager.is_casting, id + " 攻击自动收尾")
		_check(hits == skill.hit_frame.size(), id + " 真实伤害次数与命中帧一致")
		_check(hit_frames == skill.hit_frame, id + " 真实命中/发射帧准确")
		_check(projectiles == (1 if id in RANGED else 0), id + " 发射正确投射物")
		if id == "troll":
			var twin := load(path).instantiate() as UnitBase
			arena.team_b.add_child(twin)
			twin.set_physics_process(false)
			sprite.material.set_shader_parameter("flash_intensity", 0.8)
			_check(sprite.material != twin.animated_sprite_2d.material and twin.animated_sprite_2d.material.get_shader_parameter("flash_intensity") == 0.0, "同种怪物受击闪红不串到另一个实例")
			_check(sprite.material.get_shader_parameter("palette_texture") == twin.animated_sprite_2d.material.get_shader_parameter("palette_texture"), "同种怪物共享只读旧色色板")
			twin.free()
		caster.free()
		target.free()
		caster = null
		await _frames(2)
	for id: String in RANGED:
		var projectile: Node = load("res://scenes/projectiles/%s_projectile.tscn" % id).instantiate()
		arena.add_child(projectile)
		projectile.set_physics_process(false)
		_check_pixel_style(projectile.get_node("AnimatedSprite2D"), id + " 投射物")
		projectile.free()
	var shaman_hit: AnimatedSprite2D = load("res://scenes/effects/hex_shaman_hit.tscn").instantiate()
	arena.add_child(shaman_hit)
	_check_pixel_style(shaman_hit, "咒术萨满命中特效")
	shaman_hit.free()
	for id in ["orc", "troll", "imp", "bomb_fish"]:
		var unit := load("res://scenes/units/%s.tscn" % id).instantiate() as UnitBase
		arena.team_b.add_child(unit)
		unit.set_physics_process(false)
		unit.position = Vector2(1000, 500)
		var target := load("res://scenes/units/soldier.tscn").instantiate() as UnitBase
		arena.team_a.add_child(target)
		target.set_physics_process(false)
		target.position = unit.position - Vector2(60, 0)
		target.hit_received.connect(_hit)
		caster = unit
		projectiles = 0
		hits = 0
		unit.skill_manager.current_skill = unit.unit_data.skills[0]
		unit.skill_manager.current_target = target
		unit.switch_state(UnitBase.State.ATTACK)
		unit.skill_manager.attack()
		await _frames(5)
		unit.unit_died.connect(_death)
		deaths = 0
		unit.take_effect_damage(99999)
		unit.die()
		_check(unit.current_state == UnitBase.State.DEATH and deaths == 1, id + " 死亡只结算一次")
		# 有 death 动画的单位先完整播放，再进入白烟；退场期间不再推进战斗。
		for _frame in 180:
			if unit.get_node_or_null("DeathSmoke") != null:
				break
			await _frames(1)
		var smoke := unit.get_node_or_null("DeathSmoke")
		_check(smoke != null and unit.current_state == UnitBase.State.DEATH and deaths == 1, id + " 白烟死亡只触发一次")
		if smoke == null:
			caster = null
			unit.free()
			target.free()
			continue
		_check(not unit.is_physics_processing() and not unit.skill_manager.is_casting and not unit.get_node("HealthBar").visible, id + " 死亡立即停止战斗、隐藏血条")
		unit.get_node("HealthBar").set_statuses([])
		_check(not unit.get_node("HealthBar").visible, id + " 死后状态刷新不重新显示空血条")
		await _frames(12)
		_check(not unit.animated_sprite_2d.visible and unit.collision_layer == 0 and unit.collision_mask == 0, id + " 白烟遮住身体后消失且不阻挡")
		var paused_time: float = smoke.elapsed
		get_tree().paused = true
		for _index in 5:
			await get_tree().process_frame
		get_tree().paused = false
		_check(is_equal_approx(smoke.elapsed, paused_time), id + " 暂停冻结白烟")
		await _frames(60)
		_check(not is_instance_valid(unit) and not is_instance_valid(smoke), id + " 单位和白烟全部清理")
		_check(projectiles == 0 and hits == 0, id + " 死亡取消前摇，白烟期间不继续攻击或发射")
		caster = null
		target.free()
	arena.queue_free()
	await _frames(2)
	await _preview_once()
	print("ENEMY_PACK_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_pixel_style(sprite: AnimatedSprite2D, id: String) -> void:
	var material := sprite.material as ShaderMaterial
	_check(material != null and material.shader.resource_path == "res://shaders/unit_pixel_style.gdshader", id + " 实战使用像素风材质")
	_check(material.get_shader_parameter("pixel_step") == 2.0 and material.get_shader_parameter("match_palette") == true, id + " 使用 2 像素和旧配色")
	_check(material.get_shader_parameter("source_palette_texture") != null and material.get_shader_parameter("palette_texture") != null, id + " 入树时建立对应色板")
	var initial := sprite.animation
	for animation in sprite.sprite_frames.get_animation_names():
		# 覆盖换动画、跨图集切片及末帧；捕捉 UnitBase 复制材质后控制器仍持有旧材质的情况。
		sprite.play(animation)
		sprite.frame = sprite.sprite_frames.get_frame_count(animation) - 1
		var texture := sprite.sprite_frames.get_frame_texture(animation, sprite.frame) as AtlasTexture
		_check(material.get_shader_parameter("frame_origin") == texture.region.position and material.get_shader_parameter("frame_size") == texture.region.size, id + " " + animation + " 换帧更新当前材质，网格不串邻帧")
	sprite.stop()
	sprite.play(initial)


func _preview_animation_changed(sprite: AnimatedSprite2D, id: String) -> void:
	if sprite.animation == &"attack_01":
		preview_starts[id] = int(preview_starts.get(id, 0)) + 1


func _preview_once() -> void:
	var preview = load("res://examples/scenes/enemy_pack_preview.tscn").instantiate()
	get_tree().root.add_child(preview)
	get_tree().current_scene = preview
	await _frames(2)
	var units: Dictionary = {}
	for unit: UnitBase in preview.units:
		var id := unit.unit_data.unit_english_name
		units[id] = unit
		unit.animated_sprite_2d.animation_changed.connect(_preview_animation_changed.bind(unit.animated_sprite_2d, id))
	var attacks: Array = preview.get_children().filter(func(node: Node): return node is Button and node.text == "攻击")
	_check(attacks.size() == 1, "攻击预览按钮存在")
	var button := attacks[0] as Button
	button.pressed.emit()
	await _frames(60)
	_check(units.thief.animated_sprite_2d.animation == &"idle" and units.troll.animated_sprite_2d.animation == &"attack_01", "短动作结束即待机，巨魔继续自己的整套连击")
	await _frames(120)
	_check(units.troll.animated_sprite_2d.animation == &"attack_01" and preview_starts.troll == 1, "超过原统一 2.7 秒后，巨魔动作仍连续且不被重启")
	await _frames(320)
	for id: String in units:
		_check(preview_starts.get(id, 0) == 1 and units[id].animated_sprite_2d.animation == &"idle", id + " 一次点击只完整播放一套，长时间等待也不自动重播")
	button.pressed.emit()
	await _frames(12)
	button.pressed.emit()
	for id: String in units:
		_check(units[id].animated_sprite_2d.frame == 0, id + " 途中再次点击可从第一帧重新预览")
	preview._die_all()
	for _frame in 240:
		if preview.units.all(func(unit): return not is_instance_valid(unit)):
			break
		await _frames(1)
	for unit in preview.units:
		_check(not is_instance_valid(unit), "单次攻击预览仍允许白烟中断和清理")
	preview._spawn_all()
	for unit: UnitBase in preview.units:
		_check(unit.animated_sprite_2d.animation == &"idle", "重新生成回到待机，不隐式触发攻击")
	preview.queue_free()
	await _frames(2)
