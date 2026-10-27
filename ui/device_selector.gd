extends OptionButton
## "Active Device" dropdown: lists the keyboard and connected controllers.


func _ready() -> void:
	item_selected.connect(_on_item_selected)
	InputConfig.devices_changed.connect(_rebuild)
	InputConfig.active_device_changed.connect(_on_active_device_changed)
	_rebuild()


func _rebuild() -> void:
	clear()
	for device in InputConfig.get_devices():
		add_item(device.name)
		var index := item_count - 1
		set_item_metadata(index, device.id)
		if device.id == InputConfig.active_device:
			select(index)


func _on_active_device_changed(_device_id: int) -> void:
	_rebuild()


func _on_item_selected(index: int) -> void:
	InputConfig.set_active_device(get_item_metadata(index))
