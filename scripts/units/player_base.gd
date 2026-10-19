# 这玩意儿是干嘛的（核心逻辑）：仅保留旧主堡资源的加载兼容性，正式战场不再实例化它。
# 数据是咋流动的（数据流向）：旧场景加载 → 禁用碰撞与处理；不读取、不修改 Run 生命值。
# 为啥这么写（选型决策）：先解除所有战斗依赖，再保留旧美术资源供查阅，不让测试场景误触发旧规则。
# 性能咋样（复杂度）：入树后不逐帧工作，也不发送战斗死亡信号。
extends UnitBase

var active := false
var is_selected := false

# 作用：Godot 加载旧资源时禁用实体；没有参数，没有返回值。
func _ready() -> void:
	unit_data = UnitData.new()
	current_health = 0
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)

# 作用：兼容旧调用但不回满玩家 HP；没有参数，没有返回值。
func start_battle() -> void:
	active = false

# 作用：旧建筑不再接受普通攻击；参数仅兼容父类接口，返回未命中。
func get_hurt(_damage: int, _attacker: UnitBase = null, _counter: bool = true, _sound_profile: StringName = &"", _attack_floor: int = -1, _fixed_damage: bool = false, _damage_kind: StringName = &"normal", _defence_segments: int = 1) -> bool:
	return false

# 作用：旧建筑不再接受环境伤害；amount 为伤害，没有返回值。
func take_effect_damage(_amount: int, _source: UnitBase = null, _damage_kind: StringName = &"skill") -> void:
	pass

# 作用：旧建筑不再接受治疗；参数兼容父类，返回未治疗。
func get_heal(_damage: int, _healer: UnitBase = null) -> bool:
	return false

# 作用：旧建筑不会触发战斗失败；没有参数，没有返回值。
func die(_killer: UnitBase = null) -> void:
	pass

# 作用：Godot 物理回调不再执行建筑行为；delta 是帧间隔，没有返回值。
func _physics_process(_delta: float) -> void:
	pass
