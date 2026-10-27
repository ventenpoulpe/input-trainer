extends OptionButton
## "Mode" dropdown: picks the input mode (VF, SC2 or SF).


func _ready() -> void:
	for mode in InputMode.IDS:
		add_item(InputMode.title(mode))
		var index := item_count - 1
		set_item_metadata(index, mode)
		set_item_tooltip(index, InputMode.game(mode))
	item_selected.connect(func(index: int) -> void: InputConfig.set_active_mode(get_item_metadata(index)))
	InputConfig.mode_changed.connect(_select_mode)
	_select_mode(InputConfig.active_mode)


func _select_mode(mode: String) -> void:
	for index in item_count:
		if get_item_metadata(index) == mode:
			select(index)
			tooltip_text = InputMode.game(mode)
