# 这玩意儿是干嘛的（核心逻辑）：在召唤动作的生效帧放下魔法阵，让魔法阵播完再生成怪物。
# 数据是咋流动的（数据流向）：技能配置 → 动画命中帧 → 标记点世界坐标 → 独立召唤特效。
# 为啥这么写（选型决策）：技能资源只保存配方，每次施法的等待交给特效节点，多个召唤师不会串状态。
# 性能咋样（复杂度）：每次施法只创建一个特效，不增加每帧索敌或遍历。
extends SkillBase

const SummonEffect = preload("res://scripts/combat/summon_effect.gd")

## 召唤特效播放结束后生成的单位场景，应包含有效的单位配置；需同时配置 On Hit Effect，召唤物会加入施法者所在队伍容器。
@export var summon_scene: PackedScene
## 相对施法者的召唤定位节点路径。找到 Node2D 标记时使用其世界坐标，找不到时使用 Summon Offset 作为落点。
@export var summon_marker_path: NodePath = ^"SummonPoint"
## 没有有效召唤标记时，相对施法者世界位置的备用偏移，单位为世界像素；正 X 向右、正 Y 向下，不随朝向自动翻转。
@export var summon_offset: Vector2 = Vector2(-80, 0)
## On Hit Effect 特效中播放的召唤动画名称。该动画必须存在且不能循环，播放完成后才生成召唤单位。
@export var effect_animation: StringName = &"green_magic_circle"


# 作用：管理器在召唤动作的命中帧调用；caster 是施法者，_target 不参与落点计算，没有返回值。
func execute(caster: UnitBase, _target: UnitBase = null) -> void:
	# 死亡和回合结束后不能启动召唤，避免动画仍在播放时漏出一次技能。
	if not is_instance_valid(caster) or caster.is_queued_for_deletion():
		return
	if caster.current_state == UnitBase.State.DEATH or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		return
	if on_hit_effect == null or summon_scene == null:
		push_warning("召唤技能需要配置特效和召唤单位场景")
		return

	# 特效和召唤物放进施法者的队伍容器，自动接入战场登记与清场判断。
	var team := caster.get_parent() as Node2D
	if team == null or team.is_queued_for_deletion():
		return
	var point := caster.global_position + summon_offset
	var marker := caster.get_node_or_null(summon_marker_path) as Node2D
	if marker != null:
		point = marker.global_position

	var instance := on_hit_effect.instantiate()
	var effect := instance as AnimatedSprite2D
	if effect == null:
		instance.free()
		push_warning("召唤特效的根节点必须是 AnimatedSprite2D")
		return
	# 必须使用存在且非循环的动画，否则无法收到播放完成的通知。
	if effect.sprite_frames == null or not effect.sprite_frames.has_animation(effect_animation):
		effect.free()
		push_warning("召唤特效缺少配置的动画")
		return
	if effect.sprite_frames.get_animation_loop(effect_animation):
		effect.free()
		push_warning("召唤特效动画不能循环")
		return

	# 每个特效自己保存本次施法数据，标记点移动不再影响已经落地的魔法阵。
	effect.set_script(SummonEffect)
	effect.configure(caster, summon_scene, effect_animation)
	effect.position = team.to_local(point)
	team.add_child(effect)
