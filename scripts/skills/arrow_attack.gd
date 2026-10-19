# 这玩意儿是干嘛的（核心逻辑）：把远程技能变成飞行的投射物。
# 数据是咋流动的（数据流向）：施法帧 → 投射物携带伤害、目标和特效 → 命中时结算。
# 为啥这么写（选型决策）：命中特效交给投射物播放，才能出现在真正撞到敌人的时刻。
# 性能咋样（复杂度）：每次施法只创建一颗投射物，不增加索敌遍历。
extends SkillBase

## 此技能发射投射物的弹道编号：0 为直线，1 为抛物线。发射时覆盖投射物场景的默认弹道，其速度和高度仍由投射物场景配置。
@export var projectile_trajectory: int = 1   # 0=直线 1=抛物线；技能自己的弹道类型
## 投射物最多命中的敌人数；1 为普通单目标弹，超过 1 启用直线穿透逻辑，沿发射时方向飞行并对不同敌人分别判定。抛物线分支仍按单目标落点处理。
@export var pierce_count: int = 1   # 能穿透的敌人数量；1 = 普通箭
## 直线弹穿透沿途全部敌人，不受 Pierce Count 限制；同一敌人每颗箭最多命中一次。
@export var pierce_all: bool = false
## 发射的投射物场景，根节点应支持 Projectile 的 fire 接口；未配置时不会发射。飞行速度、命中半径、弧线高度等在该场景上调整。
@export var projectile_scene: PackedScene  # 发射子弹场景
## 投射物相对施法者的发射偏移，单位为世界像素；X 随单位左右朝向翻转，正 Y 向单位上方偏移。
@export var projectile_pos: Vector2 = Vector2(30, 10)


# 作用：caster 向 target 发射技能配置的投射物；没有返回值。
func execute(caster: UnitBase, target: UnitBase = null) -> void:
	if not is_instance_valid(caster) or not is_instance_valid(target) or projectile_scene == null:
		return
	if target.is_queued_for_deletion() or target.current_state == UnitBase.State.DEATH:
		return
	var damage := int(caster.unit_data.attack * attack_rate)  # 己方单位造成的伤害
	var enemy_group := caster.enemy_team()
	var projectile: Node2D = projectile_scene.instantiate()
	var parent := caster.get_tree().current_scene
	if parent == null:
		parent = caster.get_parent()
	parent.add_child(projectile)
	projectile.global_position = caster.global_position + Vector2(-projectile_pos.x if caster.animated_sprite_2d.flip_h else projectile_pos.x, -projectile_pos.y)  # 从角色上半身射出
	var traj: int = projectile_trajectory
	projectile.pierce_all = pierce_all
	projectile.fire(caster, target, damage, traj, pierce_count, enemy_group, on_hit_effect)
	# 每颗弹携带发射时的独立状态配置，命中或穿透时再施加。
	projectile.status_skill = self
	projectile.damage_kind = combat_number_kind()
	projectile.defence_segments = defence_segments()
	for status: UnitStatusEffect in status_effects:
		if status != null:
			projectile.status_effects.append(status.duplicate() as UnitStatusEffect)
	# 发射时保存音色，攻击者死亡或改放另一技能后，命中声仍属于这颗投射物。
	projectile.hit_sound_profile = caster.combat_audio.attack_profile(caster, self)
