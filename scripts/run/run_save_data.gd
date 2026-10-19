# 存档只含可持久化数据和资源副本，不保存场景节点、计时器或对象引用。
extends Resource
# 老存档可能省略等于默认值的 version；保留默认 1，新保存显式写入 2。
@export var version := 1
@export var state: Dictionary = {}
@export var card_definitions: Array[CardDefinition] = []
@export var card_states: Array[Dictionary] = []
@export var relics: Array[RelicDefinition] = []
@export var potions: Array[PotionDefinition] = []
