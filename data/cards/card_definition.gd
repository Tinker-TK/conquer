# 这玩意儿是干嘛的（核心逻辑）：一张卡的配方，区分类别、目标、费用和效果列表。
# 数据是咋流动的（数据流向）：Inspector 配置 → CardInstance → 拖到战场 → CardBattleRuntime 执行。
# 为啥这么写（选型决策）：卡牌不是单位；强化与能力不需要伪造一份兵种数据。
# 性能咋样（复杂度）：资源可共享，只保存配方；运行中的牌和增益另行保存。
extends Resource
class_name CardDefinition

enum Category { RECRUIT, ENHANCEMENT, ABILITY }
enum Target { NONE, ALLY, ENEMY, ANY_UNIT, POSITION, HAND_CARD }
enum AfterUse { DISCARD, EXHAUST, PERSIST }
enum Rarity { COMMON, RARE }

## 卡牌的显示名称，用于手牌、牌堆和奖励选择界面；强化次数会在具体卡牌名称旁另外显示。
@export var card_name: String = "新卡牌"
## 基础卡牌说明，供配置预览及自定义效果使用。正式卡面按当前 Effects 数值统一生成，强化后自动更新；修改文案不会改变玩法。
@export_multiline var card_discription: String = ""
## 卡牌的主卡面图片，显示在 CardImage 区域；只控制外观。
@export var card_image: Texture2D
## 卡牌的第二层插图，显示在 CardImage2 区域；可用于单位立绘或额外卡面装饰。
@export var card_image_2: Texture2D
## 卡牌的基础能量费用。出牌时按具体卡牌实例的当前费用扣能量；本局临时加费不会改写此基础配置。
@export_range(0, 10, 1) var card_cost: int = 1
## 卡牌品质：COMMON 使用蓝色边框，RARE 使用金色边框；不改变卡牌费用或效果。
@export var rarity: Rarity = Rarity.COMMON
## 卡牌类别：征召生成指定单位，强化与能力卡按目标执行效果列表。类别影响出牌验证与卡面提示，不会自动生成效果。
@export var category: Category = Category.ENHANCEMENT
## 此牌所需的目标：无目标、友军、敌军、任意单位或战场位置。效果必须与目标类型匹配；征召牌还会检查实际可部署区域。
@export var target: Target = Target.ALLY
## 效果牌成功使用后的去向：DISCARD 进入弃牌堆，EXHAUST 进入本场消耗区，PERSIST 常驻到战斗结束。征召牌先关联场上单位，退场再按征召规则处理。
@export var after_use: AfterUse = AfterUse.DISCARD
## 固有：未使用的此牌在回合结束时保留于手牌；战斗结束仍正常回收，不影响使用后的消耗或弃置。
@export var retain_in_hand: bool = false
## 每场战斗首轮先将此牌从牌组发入手牌，然后再进行常规抽牌；不是额外生成卡牌，不计入抽牌触发。
@export var starts_in_hand: bool = false
# 征召时指定兵种；原有 UnitData 卡无需转换，也仍然能使用。
## 征召牌生成的 UnitData 资源，按其英文标识查找单位场景；只在征召类别下使用。旧 UnitData 单位牌可直接征召，无需转换。
@export var summon_unit: UnitData
@export_group('卡牌效果')
## 本局中每张此牌最多可在篝火强化的次数。0 表示不可强化；强化同时应用费用、效果数值和效果规则的升级配置。
@export_range(0, 99, 1) var max_upgrade_count: int = 1
## 每次强化对基础费用的增量；负数表示降费，强化后的基础费用最低为0，不影响本场退场加费。
@export_range(-10, 10, 1) var upgrade_cost_change: int = 0
## 成功出牌时按顺序执行的效果资源列表。每项独立配置效果类型、数值、期限与目标；空列表不会自动产生强化或能力效果。
@export var effects: Array[CardEffect] = []
