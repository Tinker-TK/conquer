extends Control
func _ready() -> void:
	var event: Resource = load("user://event_editor_preview.tres")
	if not event is EventDefinition:
		return
	var panel: EventPanel = $EventPanel
	panel.resolved.connect(func(_index): panel.open_content(event.to_content(), null, true))
	panel.open_content(event.to_content(), null, true)
