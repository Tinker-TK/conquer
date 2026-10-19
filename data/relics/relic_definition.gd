# 这玩意儿是干嘛的（核心逻辑）：保存一件遗物的配置，不保存本局累计次数。
# 数据是咋流动的（数据流向）：资源配置 → RunManager 获得 → 玩家血量、能量、抽牌或开战钩子触发。
# 为啥这么写（选型决策）：配置与进度分离，重复获取同 ID 不会重复叠加。
# 性能咋样（复杂度）：仅事件触发时读取，不逐帧执行。
extends Resource
class_name RelicDefinition

# 旧枚举值保持兼容；BASE_HEALTH 改为玩家生命，BASE_DEFENCE 已停用；新能量类型追加到末尾。
enum Kind { DRAW_ENERGY, BASE_HEALTH, BASE_DEFENCE, OPENING_DEFENCE, MAX_ENERGY, NONE }
enum Trigger {
	NONE, RUN_START, BATTLE_START, ROUND_START, AFTER_DRAW, SHUFFLE,
	CARD_PLAYED, CARD_DISCARDED, UNIT_DEPLOYED, UNIT_DIED, UNIT_KILL,
	UNIT_HIT, UNIT_HURT, UNIT_HEALED, DOT_TICK, COUNTER, ROUND_END, ROUND_SETTLED,
	BATTLE_WON, POTION_USED, SHOP_OPEN, RELIC_GAINED
}
enum Rarity { COMMON, RARE, BOSS }

@export var rarity: Rarity = Rarity.COMMON
@export var tags: Array[StringName] = []
@export var trigger: Trigger = Trigger.NONE
@export var handler: StringName = &""
@export_range(0, 99, 1) var max_per_battle: int = 0
@export_range(0, 99, 1) var max_per_round: int = 0
@export_range(0.0, 10.0, 0.05) var cooldown_seconds: float = 0.0
## 同一触发点先结算资源，再结算属性、状态、伤害治疗，最后抽牌。
@export_range(0, 4, 1) var priority: int = 1

func rarity_name() -> String:
	return ["普通", "稀有", "首领"][rarity]

func school_name() -> String:
	var names := {&"wide": "军团铺场", &"tall": "单核养成", &"death": "亡语献祭",
		&"dot": "毒火持续", &"control": "控制压制", &"cycle": "循环连招",
		&"guard": "防守续航", &"ranged": "远程风筝", &"economy": "经济补给", &"neutral": "中立通用"}
	var result: PackedStringArray = []
	for tag in tags:
		result.append(names.get(tag, String(tag)))
	return " / ".join(result)
## 遗物的唯一标识。获取和持有判重使用此 ID，相同 ID 的遗物不会重复叠加；不同遗物应使用不同 ID。
@export var id: StringName
## 遗物的显示名称，用于背包、奖励和增益来源提示；实际身份由 ID 区分。
@export var display_name := ""
## 遗物说明文案。旧遗物由 Kind 决定机制，新遗物由 Trigger / Handler 决定机制；修改文案不会自动修改玩法。
@export_multiline var description := ""
## 遗物在背包 HUD 和奖励界面中使用的图标资源；只控制外观。
@export var icon: Texture2D
## 遗物机制：累计抽牌获永久能量、增加玩家生命上限、开战防御或永久能量。BASE_DEFENCE 是已停用的旧类型，不能作为有效新遗物使用。
@export var kind: Kind = Kind.DRAW_ENERGY
## 遗物效果的数值：抽牌获能量为每次达标增加的永久能量，生命类型为增加的最大及当前生命，开战防御为防御增量，MAX_ENERGY 为永久能量增量。
@export var amount: int = 1
## 抽牌获能量遗物每累计抽入多少张牌触发一次。剩余计数继续保留，单次大量抽牌可多次触发；只在 DRAW_ENERGY 类型下使用。
@export_range(1, 100, 1) var draw_threshold: int = 10
## 开战防御遗物所加防御的有效回合数，到期后撤销；只在 OPENING_DEFENCE 类型下使用。
@export_range(1, 99, 1) var rounds: int = 3
