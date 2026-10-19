# 焦草上叠加沿燃烧前沿卷起的橙红火焰，并保留实验室原火星。
extends "res://scripts/effects/pixel_burned_ground.gd"


func _init(area_radius: float = 45.0) -> void:
	name = "BurnGroundZone"
	radius = area_radius
	set_meta("effect_id", "pixel_burned_ground")
