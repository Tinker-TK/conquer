# 这玩意儿是干嘛的（核心逻辑）：一份可重复使用的战斗关卡配置，不保存本局运行状态。
# 数据是咋流动的（数据流向）：地图节点绑定资源 → GameSession 选择场景 → 入树前配置波次和参数。
# 为啥这么写（选型决策）：地形放场景、数值放资源，复制关卡不必复制战斗代码。
# 性能咋样（复杂度）：地图编辑时可校验资源，进入战斗时读取一次，波次场景在对应回合才实例化。
@tool
extends Resource
class_name BattleLevelConfig

const DEFAULT_ENEMY_MAX_HP := 45
const BASE_START_ENERGY := 3
const ENERGY_PER_ROUND := 1
const BASE_MAX_ENERGY := 10

## 战斗关卡的显示名称，用于配置选择与关卡识别；不会改变地图节点的唯一编号。
@export var level_name: String = "新关卡"
## 给关卡设计者记录用途和调参备注的多行文字；不参与战斗规则。
@export_multiline var notes: String = ""
## 此关加载的战场场景，需包含项目战斗场景要求的波次、回合、手牌和实体节点；地形与场景布局由该场景提供。
@export var battle_scene: PackedScene
# 数组第一个元素对应第 1 回合，空元素表示该回合不刷新敌人。
## 敌方波次场景列表，第一个元素对应第 1 回合。每轮实例化对应波次；空元素表示该轮不生成新敌人。
@export var waves: Array[PackedScene] = []
## 到达波次末尾后是否继续循环。开启时按 Repeat Start～Repeat End 指定的波次区间重复，并继续累计回合数。
@export var repeat_waves: bool = false
# 一基波次号；旧资源默认循环整个数组，结束波 0 会自动跟随数组末尾。
## 循环区间的起始波次编号，从 1 开始；仅在 Repeat Waves 开启时使用，必须落在 Waves 数组范围内。
@export_range(1, 9999, 1) var repeat_start: int = 1
## 循环区间的结束波次编号，包含此波次；0 表示自动使用 Waves 数组末尾。仅在循环开启时使用，不能早于起始波次。
@export_range(0, 9999, 1) var repeat_end: int = 0
## 兼容旧配置的交锋时长字段，单位为秒；当前战斗不再按此值强制结束，而在一方单位全部阵亡后结算。现有配置校验仍要求至少 1 秒。
@export_range(1, 300, 1) var battle_duration: float = 10.0
# 旧字段继续作为首轮基础能量；交锋不再按 battle_duration 强制结束。
## 第 1 回合的基础可用能量；后续回合在此基础上按 Energy Growth 增长，并受 Base Energy Cap 限制。本局永久附加能量另外相加。
@export_range(0, 20, 1) var energy_per_round: int = BASE_START_ENERGY
## 每推进 1 回合增加的基础能量，0 表示不随回合增长；达到基础能量上限后停止增长。
@export_range(0, 20, 1) var energy_growth: int = ENERGY_PER_ROUND
## 随回合增长的基础能量上限，不能低于首轮基础能量。本局永久附加能量不受此上限限制。
@export_range(1, 100, 1) var base_energy_cap: int = BASE_MAX_ENERGY
## 进入本关时敌方玩家的初始及最大生命值，用于回合败方扣血与胜负判断；不改变敌方单位的生命。
@export_range(1, 9999, 1) var enemy_max_hp: int = DEFAULT_ENEMY_MAX_HP
## 每轮常规抽牌数量。0 表示不进行常规抽牌；禁抽效果和剩余牌数可能使实际抽入数量减少。
@export_range(0, 10, 1) var cards_per_round: int = 5
@export_group("战斗胜利奖励")
## 地图节点可以加载另一份配置或单独覆盖数值；空值使用普通战斗奖励。
@export var victory_rewards: BattleRewardConfig
@export_group("天气")
## 本关的雨天天气配置。空值沿用战场 RainWeather 节点的预设，基础战场默认晴天；也可显式指定 weather_clear.tres。雪天开启时优先使用雪天效果。
@export var weather_settings: RainWeatherSettings
## 本关的雪天天气配置，可选择小雪、正常雪或暴雪预设，并展开调整雪花、积雪与物体覆雪参数。空值沿用战场 SnowWeather 的设置；雪天开启时会自动关闭雨天。
@export var snow_weather_settings: SnowWeatherSettings
@export_group("河流")
## 空值沿用各 DynamicRiver 节点自己的资源；指定时统一覆盖本关所有河流。
@export var river_settings: RiverSettings


# 作用：进入关卡前验证配置；没有参数，返回空串表示可用，否则返回原因。
func validate() -> String:
	if victory_rewards != null:
		var reward_error := victory_rewards.validate()
		if not reward_error.is_empty():
			return reward_error
	var range_error := preload("res://scripts/battle/wave_sequence.gd").validate_range(waves.size(), repeat_waves, repeat_start, repeat_end)
	if not range_error.is_empty():
		return range_error
	if enemy_max_hp <= 0 or energy_growth < 0 or base_energy_cap < energy_per_round:
		return "敌方生命必须大于零，能量成长不能为负，基础上限不能低于首轮能量。"
	if battle_duration < 1 or not is_finite(battle_duration) or energy_per_round < 0 or cards_per_round < 0:
		return "战斗时长至少 1 秒，能量和抽牌数不能小于零。"
	for wave in waves:
		if wave != null:
			return ""
	return "关卡至少需要一个非空波次场景。"
