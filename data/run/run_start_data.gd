# 这玩意儿是干嘛的（核心逻辑）：保存每局开场的数值和初始牌组配置。
# 数据是咋流动的（数据流向）：Inspector 修改资源 → RunManager 开新局读取 → 战斗和 HUD 共用。
# 为啥这么写（选型决策）：配置与本局变化的数据分开，上一局掉血不会改坏下一局初始值。
# 性能咋样（复杂度）：开局读取一次，小牌组不会带来明显开销。
extends Resource
class_name RunStartData

const DEFAULT_MAX_HP := 80

## 新开一局时玩家的最大生命值，作为治疗和生命上限增益的基础；不是战斗单位的生命。
@export var max_hp: int = DEFAULT_MAX_HP
## 新开一局时玩家的当前生命值，初始化时会限制在最大生命值以内。只影响新开局，不覆盖进行中的存档。
@export var starting_hp: int = DEFAULT_MAX_HP
## 新开一局时玩家持有的金币数量，用于商店购买、删牌等消耗；只在开局初始化时读取。
@export var starting_gold: int = 99
# 整局永久附加能量，不受基础上限限制。
## 新开局自带的本局永久附加能量，每轮与基础能量相加，且不受基础能量上限限制。
@export var bonus_energy_max: int = 0
# 允许混合放入旧的 UnitData 征召牌与新的 CardDefinition。
## 新开局的初始牌组，可混合 UnitData 征召牌与 CardDefinition 卡牌。重复放入同一资源会生成多张独立卡牌实例。
@export var cards: Array[Resource] = []
## 新开局直接获得的遗物资源列表；遗物效果按正常获取规则生效，相同遗物 ID 不重复叠加。
@export var starting_relics: Array[RelicDefinition] = []
## 新开局直接放入背包的药水资源列表。每项代表一瓶可消耗药水，可重复放入相同资源获得多瓶。
@export var starting_potions: Array[PotionDefinition] = []
