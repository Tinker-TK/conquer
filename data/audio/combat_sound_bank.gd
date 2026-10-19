# 战斗音效配方和混音参数；所有音频随资源导出，运行中不访问网络。
extends Resource
class_name CombatSoundBank

@export_group("混音")
@export var enabled := true
## 战斗音效总音量，叠加主菜单的主音量。
@export_range(-40.0, 0.0, 0.5) var volume_db := -6.0
## 固定播放器池的上限；死亡声可以替换普通攻击声。
@export_range(4, 48, 1) var max_voices := 24
@export_range(500.0, 6000.0, 50.0) var max_distance := 2600.0
## 同类音效在全场的最短间隔，避免整队同时攻击时叠成噪声。
@export_range(0.0, 0.2, 0.005) var category_interval := 0.035
@export_range(0.0, 0.15, 0.005) var pitch_variation := 0.055

@export_group("攻击")
@export var melee: Array[AudioStream] = []
@export var sword: Array[AudioStream] = []
@export var axe: Array[AudioStream] = []
@export var spear: Array[AudioStream] = []
@export var charge: Array[AudioStream] = []
@export var staff: Array[AudioStream] = []
@export var heavy: Array[AudioStream] = []
@export var claw: Array[AudioStream] = []
@export var bite: Array[AudioStream] = []
@export var stone: Array[AudioStream] = []
@export var lightning: Array[AudioStream] = []
@export var bow: Array[AudioStream] = []
@export var fire: Array[AudioStream] = []
@export var ice: Array[AudioStream] = []
@export var magic: Array[AudioStream] = []
@export var beast: Array[AudioStream] = []
@export var slime: Array[AudioStream] = []
@export var heal: Array[AudioStream] = []
@export var summon: Array[AudioStream] = []

@export_group("受击")
@export var hit: Array[AudioStream] = []
@export var hit_bow: Array[AudioStream] = []
@export var hit_fire: Array[AudioStream] = []
@export var hit_ice: Array[AudioStream] = []
@export var hit_magic: Array[AudioStream] = []
@export var hit_armor: Array[AudioStream] = []
@export var hit_heavy: Array[AudioStream] = []
@export var hit_stone: Array[AudioStream] = []
@export var hit_lightning: Array[AudioStream] = []
@export var hit_undead: Array[AudioStream] = []
@export var hit_slime: Array[AudioStream] = []
@export var block: Array[AudioStream] = []

@export_group("死亡")
@export var death_human: Array[AudioStream] = []
@export var death_monster: Array[AudioStream] = []
@export var death_undead: Array[AudioStream] = []
@export var death_slime: Array[AudioStream] = []
