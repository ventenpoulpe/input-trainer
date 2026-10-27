class_name SettingsMenu
extends Control
## Modal overlay for rebinding controls and editing preferences.
##
## The bindings list shows the shared directions and shortcuts plus the
## buttons and combinations of the selected input mode (rebuilt on open).
##
## Changes apply right away so they can be tried out. Save writes everything
## to user://settings.cfg; Cancel (or Esc) goes back to the last saved state.

signal closed

## Seconds to wait for a key/button before giving up on a rebind.
const CAPTURE_TIMEOUT := 5.0
const Kind := InputConfig.Kind

@onready var _grid: GridContainer = %BindingGrid
@onready var _prefs_grid: GridContainer = %PrefsGrid
@onready var _use_stick: CheckBox = %UseStickCheck
@onready var _status: Label = %StatusLabel
@onready var _reset_button: Button = %ResetButton
@onready var _cancel_button: Button = %CancelButton
@onready var _save_button: Button = %SaveButton

## [kind][action] -> Button
var _bind_buttons := {Kind.KEYBOARD: {}, Kind.JOYPAD: {}}
var _capture_kind := Kind.KEYBOARD
var _capture_action := &""
var _capture_time_left := 0.0
var _dirty := false

var _volume_slider := HSlider.new()
var _volume_value := Label.new()
var _ui_sounds_check := CheckBox.new()
var _scroll_slider := HSlider.new()
var _scroll_value := Label.new()
var _side_option := OptionButton.new()


func _ready() -> void:
	hide()
	_build_preferences()
	UserSettings.preferences_changed.connect(_refresh_preferences)
	_use_stick.toggled.connect(_on_use_stick_toggled)
	_reset_button.pressed.connect(_on_reset_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	InputConfig.bindings_changed.connect(_refresh)


func open() -> void:
	_dirty = false
	_build_grid()
	_set_status("Click a binding, then press the new key or button.")
	_refresh()
	_refresh_preferences()
	show()
	_bind_buttons[Kind.KEYBOARD][InputConfig.DIRECTION_ACTIONS[0]].grab_focus()


func _process(delta: float) -> void:
	if not _is_capturing():
		return
	_capture_time_left -= delta
	if _capture_time_left <= 0.0:
		_end_capture()
		_set_status("Rebind timed out.")
	else:
		_capture_button().text = "Press... (%d)" % ceili(_capture_time_left)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if not _is_capturing():
		if event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()
			_on_cancel_pressed()
		return

	# While capturing, keep keys and controller input away from the UI.
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()

	if event is InputEventKey and (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE):
		if event.pressed:
			_end_capture()
			_set_status("Rebind cancelled.")
		return

	var binding := InputConfig.make_binding(_capture_kind, event)
	if binding == null:
		return

	var action := _capture_action
	var kind := _capture_kind
	_end_capture()
	var swapped := InputConfig.set_binding(kind, action, binding)
	_dirty = true

	var message := "%s → %s" % [InputConfig.action_label(action), InputConfig.event_to_text(binding)]
	if swapped != &"":
		message += " (swapped with %s)" % InputConfig.action_label(swapped)
	_set_status(message + ". Press Save to keep it.")


func _build_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_bind_buttons = {Kind.KEYBOARD: {}, Kind.JOYPAD: {}}

	var mode := InputConfig.active_mode
	_add_header_row(["DIRECTIONS", "KEYBOARD", "CONTROLLER"])
	for action in InputConfig.DIRECTION_ACTIONS:
		_add_binding_row(action)
	_add_header_row(["BUTTONS: " + InputMode.title(mode), "", ""])
	for button: Dictionary in InputMode.buttons(mode):
		_add_binding_row(button.action)
	_add_header_row(["COMBINATIONS", "", ""])
	for combo: Dictionary in InputMode.combos(mode):
		_add_binding_row(combo.action)
	_add_header_row(["SHORTCUTS", "", ""])
	for action in InputConfig.APP_ACTIONS:
		_add_binding_row(action)


func _add_header_row(titles: Array[String]) -> void:
	for title in titles:
		var label := Label.new()
		label.text = title
		label.add_theme_color_override(&"font_color", Color(0.6, 0.68, 0.8))
		_grid.add_child(label)


func _add_binding_row(action: StringName) -> void:
	var label := Label.new()
	label.text = InputConfig.action_label(action)
	_grid.add_child(label)
	for kind: Kind in [Kind.KEYBOARD, Kind.JOYPAD]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(200, 0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_binding_pressed.bind(kind, action))
		_grid.add_child(button)
		_bind_buttons[kind][action] = button


func _build_preferences() -> void:
	_volume_slider.min_value = 0
	_volume_slider.max_value = 100
	_volume_slider.step = 5
	_volume_slider.value_changed.connect(func(value: float) -> void: _set_pref("audio", "sfx_volume", value / 100.0))
	_add_pref_row("SFX volume", _slider_row(_volume_slider, _volume_value))

	_ui_sounds_check.text = "Button click sounds"
	_ui_sounds_check.toggled.connect(func(on: bool) -> void: _set_pref("audio", "ui_sounds", on))
	_add_pref_row("", _ui_sounds_check)

	# Seconds for an input to reach the hit line: lower = faster inputs.
	_scroll_slider.min_value = 0.5
	_scroll_slider.max_value = 2.5
	_scroll_slider.step = 0.1
	_scroll_slider.value_changed.connect(func(value: float) -> void: _set_pref("gameplay", "scroll_time", value))
	_add_pref_row("Input scroll time", _slider_row(_scroll_slider, _scroll_value))

	_side_option.add_item("Player 1 (facing right)")
	_side_option.add_item("Player 2 (facing left)")
	_side_option.item_selected.connect(func(index: int) -> void: _set_pref("gameplay", "facing_right", index == 0))
	_add_pref_row("Side", _side_option)


func _add_pref_row(label_text: String, control: Control) -> void:
	var label := Label.new()
	label.text = label_text
	_prefs_grid.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prefs_grid.add_child(control)


func _slider_row(slider: HSlider, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value_label.custom_minimum_size = Vector2(56, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(slider)
	row.add_child(value_label)
	return row


func _set_pref(section: String, key: String, value: Variant) -> void:
	UserSettings.set_pref(section, key, value)
	_dirty = true


func _refresh_preferences() -> void:
	var volume: float = UserSettings.get_pref("audio", "sfx_volume")
	var scroll_time: float = UserSettings.get_pref("gameplay", "scroll_time")
	_volume_slider.set_value_no_signal(volume * 100.0)
	_volume_value.text = "%d%%" % roundi(volume * 100.0)
	_ui_sounds_check.set_pressed_no_signal(UserSettings.get_pref("audio", "ui_sounds"))
	_scroll_slider.set_value_no_signal(scroll_time)
	_scroll_value.text = "%.1f s" % scroll_time
	_side_option.select(0 if UserSettings.get_pref("gameplay", "facing_right") else 1)


func _refresh() -> void:
	for kind: Kind in _bind_buttons:
		for action: StringName in _bind_buttons[kind]:
			var button: Button = _bind_buttons[kind][action]
			button.text = InputConfig.get_binding_text(kind, action)
	_use_stick.set_pressed_no_signal(InputConfig.use_left_stick)


func _on_binding_pressed(kind: Kind, action: StringName) -> void:
	# Clicking the button that is waiting cancels the rebind.
	if _is_capturing() and _capture_kind == kind and _capture_action == action:
		_end_capture()
		_set_status("Rebind cancelled.")
		return
	_end_capture()
	_capture_kind = kind
	_capture_action = action
	_capture_time_left = CAPTURE_TIMEOUT
	InputConfig.is_capturing = true
	var what := "a key" if kind == Kind.KEYBOARD else "a controller button or direction"
	_set_status("Press %s for %s. Esc to cancel." % [what, InputConfig.action_label(action)])
	_capture_button().text = "Press..."


func _is_capturing() -> bool:
	return _capture_action != &""


func _capture_button() -> Button:
	return _bind_buttons[_capture_kind][_capture_action]


func _end_capture() -> void:
	if not _is_capturing():
		return
	_capture_action = &""
	InputConfig.is_capturing = false
	_refresh()


func _on_use_stick_toggled(enabled: bool) -> void:
	InputConfig.set_use_left_stick(enabled)
	_dirty = true


func _on_reset_pressed() -> void:
	_end_capture()
	InputConfig.reset_to_defaults()
	UserSettings.reset_preferences()
	_dirty = true
	_set_status("Defaults restored for every input mode. Press Save to keep them.")


func _on_cancel_pressed() -> void:
	_end_capture()
	if _dirty:
		UserSettings.reload()
		InputConfig.load_bindings()
	_close()


func _on_save_pressed() -> void:
	_end_capture()
	var err := InputConfig.save_bindings()
	if err != OK:
		_set_status("Could not save: %s" % error_string(err))
		return
	_close()


func _close() -> void:
	hide()
	closed.emit()


func _set_status(text: String) -> void:
	_status.text = text
