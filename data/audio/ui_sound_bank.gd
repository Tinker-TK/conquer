extends Resource
class_name UISoundBank

@export var enabled := true
@export_range(-40, 0, .5) var volume_db := -12.0
@export_range(2, 16, 1) var max_voices := 8
@export var click: Array[AudioStream] = []
@export var hover: Array[AudioStream] = []
@export var confirm: Array[AudioStream] = []
@export var cancel: Array[AudioStream] = []
@export var error: Array[AudioStream] = []
@export var card_draw: Array[AudioStream] = []
@export var card_play: Array[AudioStream] = []
@export var card_shuffle: Array[AudioStream] = []
@export var upgrade: Array[AudioStream] = []
