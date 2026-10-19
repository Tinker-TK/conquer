# 事件插画索引与旧地图/存档的显示兼容；显式自定义插图优先，不改写事件奖励或存档数据。
@tool
extends RefCounted

const ROOT := "res://assets/ui/events/illustrations/"
const PATHS := {
	"forgotten_reliquary": ROOT + "forgotten-reliquary.png",
	"wandering_alchemist": ROOT + "wandering-alchemist.png",
	"crossroads_recruitment": ROOT + "crossroads-recruitment.png",
	"campfire": ROOT + "campfire.png",
	"abandoned_camp": ROOT + "abandoned-camp.png",
	"treasure_closed": ROOT + "treasure-closed.png",
	"treasure_open": ROOT + "treasure-open.png",
}
const LEGACY_RELIC := "res://assets/ui/events/relic_ruins.svg"
const LEGACY_POTION := "res://assets/ui/events/potion_sanctum.svg"
const LEGACY_CAMP := "res://assets/ui/events/recruit_camp.svg"


static func path_for(content: Dictionary) -> String:
	var explicit := str(content.get("illustration", ""))
	if not explicit.is_empty() and explicit not in [LEGACY_RELIC, LEGACY_POTION, LEGACY_CAMP]:
		return explicit
	# 篝火和援军曾共用同一张 SVG；按实际选项区分，不能仅替换文件名。
	var effects: Array[String] = []
	var heals := false
	var supplies := false
	for choice in content.get("choices", []):
		var effect: Dictionary = choice.get("effect", {})
		effects.append(str(effect.get("type", "")))
		heals = heals or float(choice.get("heal_percent", 0.0)) > 0 or int(choice.get("heal", 0)) > 0
		supplies = supplies or int(choice.get("gold", 0)) > 0
	if "train_unit" in effects or "enhance_card" in effects:
		return PATHS.campfire
	if "choose_cards" in effects or explicit == LEGACY_CAMP:
		return PATHS.crossroads_recruitment
	if "random_potion" in effects or explicit == LEGACY_POTION:
		return PATHS.wandering_alchemist
	if "random_relic" in effects or explicit == LEGACY_RELIC:
		return PATHS.forgotten_reliquary
	if heals:
		return PATHS.campfire
	return PATHS.abandoned_camp if supplies else PATHS.forgotten_reliquary


static func texture_for(content: Dictionary) -> Texture2D:
	var path := path_for(content)
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture != null:
			return texture
	return load(PATHS.forgotten_reliquary) as Texture2D
