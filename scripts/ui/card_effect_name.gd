# 卡牌生效时的头顶名称：跟随单位，短暂停留后上浮淡出；随单位退树一起清理。
extends Node2D

const TEXT_COLOR := Color("#71e86a")
const FONT_SIZE := 22
const LINE_HEIGHT := 30.0
const HOLD_DURATION := 0.5
const DURATION := 1.4
const RISE_DISTANCE := 24.0
var card_name := ""
var anchor := Vector2.ZERO
var elapsed := 0.0
var stack_offset := 0.0
var label: Label


func _ready() -> void:
	add_to_group("card_effect_names")
	# 名称始终在地形和单位前方，颜色不受精灵选中、闪红和隐身材质影响。
	z_as_relative = false
	z_index = 4096
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = card_name
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", Color("#102518"))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	label.reset_size()
	label.position = Vector2(-label.size.x * 0.5, -label.size.y)
	position = anchor


func raise_line() -> void:
	stack_offset += LINE_HEIGHT
	_update_position()


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= DURATION:
		queue_free()
		return
	_update_position()
	modulate.a = 1.0 - clampf((elapsed - HOLD_DURATION) / (DURATION - HOLD_DURATION), 0.0, 1.0)


func _update_position() -> void:
	position = anchor - Vector2(0, stack_offset + RISE_DISTANCE * clampf(
		(elapsed - HOLD_DURATION) / (DURATION - HOLD_DURATION), 0.0, 1.0))
