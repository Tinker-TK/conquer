# 事件配方：编辑器保存资源，地图读取可导出的内容字典，结算状态留在运行时。
@tool
extends Resource
class_name EventDefinition
enum Template { RANDOM_RELIC, RANDOM_POTION, CHOOSE_CARDS, CAMPFIRE, CUSTOM }
## 事件资源的唯一编号，用于地图事件关联。使用 1～80 个字母、数字、下划线或短横线；需与引用此事件的编号一致。
@export var id: String = "new_event"
## 事件面板的标题，需填写 1～80 个字符；不决定事件实际奖励。
@export var title: String = "新的奇遇"
## 进入事件时显示的多行剧情说明。实际选项与奖励由 Template 和资源池决定。
@export_multiline var description: String = ""
## 事件面板显示的插图资源；显式图片优先，留空时按事件选项选用项目内对应主题的插画。
@export var illustration: Texture2D
## 事件模板：随机遗物、随机药水、选择卡牌或篝火。决定生成哪些交互选项以及读取哪个奖励池。
@export var template: Template = Template.RANDOM_RELIC
## 非篝火事件的主要交互按钮文案，如接受馈赠；篝火的休憩、训练、强化按钮由模板固定生成。
@export var option_text: String = "接受馈赠"
## 离开事件按钮的显示文字；篝火模板也使用此文案。
@export var leave_text: String = "离开"
## 完成事件主要选择后的结果文案；只改变剧情显示，不改变奖励数量。
@export_multiline var result_text: String = "你收好这份馈赠，继续踏上征途。"
## 篝火休憩回复的玩家最大生命百分比，30 表示回复最大生命的 30%；只在 CAMPFIRE 模板下使用，回复不超过生命上限。
@export_range(0, 100, 0.1) var rest_heal_percent: float = 30.0
# 留空使用项目全部可用资源；两组各抽五种不同卡牌。
## 随机遗物事件的候选遗物资源列表；留空使用项目全部有效遗物，已持有的遗物会按获取规则排除。其它模板不读取此池。
@export var relic_pool: Array[Resource] = []
## 随机药水事件的候选药水资源列表；留空使用项目全部有效药水。只在随机药水模板下读取。
@export var potion_pool: Array[Resource] = []
## 选卡事件的候选兵种卡资源列表；留空使用项目全部可用兵种。选卡模板从兵种组与效果牌组分别生成候选。
@export var unit_pool: Array[Resource] = []
## 选卡事件的候选效果牌资源列表；留空使用项目全部可用效果牌。不会改变卡牌自身的效果数值。
@export var effect_pool: Array[Resource] = []
## 自定义路线事件选项；支持 cost、effect / effects、逐选项结果文案。
@export var choices: Array[Dictionary] = []
## 随机池楼层范围、稀有度与条件；只影响投放，不显示在面板正文。
@export var min_floor: int = 2
@export var max_floor: int = 9
@export_enum("common", "rare", "gamble", "story") var rarity: String = "common"
@export var tags: Array[String] = []
@export var requires: Array[String] = []

func to_content() -> Dictionary:
	if template == Template.CUSTOM:
		return {"id": id, "title": title, "description": description,
			"illustration": illustration.resource_path if illustration != null else "",
			"result_text": result_text, "choices": choices.duplicate(true),
			"min_floor": min_floor, "max_floor": max_floor, "rarity": rarity,
			"tags": tags.duplicate(), "requires": requires.duplicate()}
	if template == Template.CAMPFIRE:
		return {"title": title, "description": description,
			"illustration": illustration.resource_path if illustration != null else "",
			"result_text": result_text, "choices": [
				{"text": "休憩整备", "heal": 0, "heal_percent": rest_heal_percent, "gold": 0},
				{"text": "训练", "heal": 0, "gold": 0, "effect": {"type": "train_unit"}},
				{"text": "强化", "heal": 0, "gold": 0, "effect": {"type": "enhance_card"}},
				{"text": leave_text, "heal": 0, "gold": 0, "leave": true}]}
	var effect := {"type": ["random_relic", "random_potion", "choose_cards"][template]}
	match template:
		Template.RANDOM_RELIC:
			effect.pool = _paths(relic_pool)
		Template.RANDOM_POTION:
			effect.pool = _paths(potion_pool)
		Template.CHOOSE_CARDS:
			effect.unit_pool = _paths(unit_pool)
			effect.effect_pool = _paths(effect_pool)
	return {"title": title, "description": description,
		"illustration": illustration.resource_path if illustration != null else "",
		"result_text": result_text, "choices": [
			{"text": option_text, "heal": 0, "gold": 0, "effect": effect},
			{"text": leave_text, "heal": 0, "gold": 0}]}

func _paths(resources: Array[Resource]) -> Array[String]:
	var paths: Array[String] = []
	for resource in resources:
		paths.append(resource.resource_path if resource != null else "")
	return paths

func validate() -> String:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]{1,80}$")
	if pattern.search(id) == null:
		return "事件编号只能使用字母、数字、下划线和短横线。"
	if title.strip_edges().is_empty() or title.length() > 80:
		return "请填写 1–80 字的事件标题。"
	if template < 0 or template > Template.CUSTOM:
		return "事件模板无效。"
	if min_floor < 1 or max_floor < min_floor or max_floor > 30:
		return "事件楼层范围无效。"
	return preload("res://scripts/map/fixed_map_config.gd").event_error(to_content())
