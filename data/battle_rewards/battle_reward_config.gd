# 战斗胜利奖励模板；地图节点加载后可保留一份独立数值快照。
@tool
extends Resource
class_name BattleRewardConfig

## 战斗胜利奖励模板的显示名称，用于选择和辨认预设；奖励内容由金币和掉落概率决定。
@export var display_name: String = "普通战斗奖励"
@export_group("必定奖励")
## 每场胜利可领取的固定金币数量，单位为金币点数；同时固定提供一次卡牌三选一。节点可独立覆盖此数值，不修改共享奖励模板。
@export_range(1, 9999, 1) var gold: int = 35
@export_group("随机奖励（百分比）")
## 胜利后额外提供随机药水奖励的概率，按百分数填写；25 表示 25%，0 不掉落，100 必定掉落。
@export_range(0, 100, 0.1) var potion_chance: float = 35.0
## 胜利后额外提供随机遗物奖励的概率，按百分数填写；0 不掉落，100 必定尝试掉落。只从当前未持有的有效遗物中抽取，候选池为空时不提供遗物。
@export_range(0, 100, 0.1) var relic_chance: float = 12.0

func to_content() -> Dictionary:
	return {"gold": gold, "potion_chance": potion_chance, "relic_chance": relic_chance}

static func content_error(value: Variant) -> String:
	if not value is Dictionary:
		return "战斗奖励必须是包含金币和掉落概率的配置。"
	var amount: Variant = value.get("gold")
	if not (amount is int or amount is float) or not is_finite(float(amount)) or amount != floor(float(amount)) or amount < 1 or amount > 9999:
		return "胜利金币必须是 1–9999 的整数。"
	for key in ["potion_chance", "relic_chance"]:
		var chance: Variant = value.get(key)
		if not (chance is int or chance is float) or not is_finite(float(chance)) or chance < 0 or chance > 100:
			return "药水和遗物奖励概率必须是 0–100 的百分比。"
	return ""

func validate() -> String:
	return content_error(to_content())
