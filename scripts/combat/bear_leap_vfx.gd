extends "res://scripts/combat/unit_dash_vfx.gd"


func movement_recipe(id: String, seconds: float) -> Dictionary:
	var recipe := super.movement_recipe(id, seconds)
	# 熊人自身的动画已完成起手；只采用原配方跳跃残影，不附加原技能的减速。
	recipe.cast_seconds = 0.0
	for action: Dictionary in recipe.actions:
		action.on_hit = []
	return recipe
