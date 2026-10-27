extends Node
## Control bindings and the active input device. Autoloaded as `InputConfig`.
##
## Each action has one keyboard binding and one controller binding. Only the
## active device drives the game inputs (directions + P/K/G). App shortcuts
## (record/play) also accept the keyboard while a controller is active.

signal bindings_changed
signal active_device_changed(device_id: int)
signal devices_changed

enum Kind { KEYBOARD, JOYPAD }

## Device id used for the keyboard in the device list (controllers use 0+).
const KEYBOARD_DEVICE := -1
## InputMap device id that matches events from any device.
const ALL_DEVICES := -1

const ACTION_DEADZONE := 0.5
## How far a stick/trigger must move to count when rebinding.
const CAPTURE_AXIS_THRESHOLD := 0.6

const GAME_ACTIONS: Array[StringName] = [
	&"vf_up", &"vf_down", &"vf_left", &"vf_right", &"vf_punch", &"vf_kick", &"vf_guard",
]
const APP_ACTIONS: Array[StringName] = [&"app_record_toggle", &"app_play_toggle"]

const ACTION_LABELS := {
	&"vf_up": "Up",
	&"vf_down": "Down",
	&"vf_left": "Left",
	&"vf_right": "Right",
	&"vf_punch": "Punch (P)",
	&"vf_kick": "Kick (K)",
	&"vf_guard": "Guard (G)",
	&"app_record_toggle": "Record Toggle",
	&"app_play_toggle": "Play Toggle",
}

const DEFAULT_KEYS := {
	&"vf_up": KEY_W,
	&"vf_down": KEY_S,
	&"vf_left": KEY_A,
	&"vf_right": KEY_D,
	&"vf_punch": KEY_Y,
	&"vf_kick": KEY_U,
	&"vf_guard": KEY_G,
	&"app_record_toggle": KEY_BACKSPACE,
	&"app_play_toggle": KEY_SPACE,
}

const DEFAULT_JOY_BUTTONS := {
	&"vf_up": JOY_BUTTON_DPAD_UP,
	&"vf_down": JOY_BUTTON_DPAD_DOWN,
	&"vf_left": JOY_BUTTON_DPAD_LEFT,
	&"vf_right": JOY_BUTTON_DPAD_RIGHT,
	&"vf_punch": JOY_BUTTON_X,
	&"vf_kick": JOY_BUTTON_Y,
	&"vf_guard": JOY_BUTTON_A,
	&"app_record_toggle": JOY_BUTTON_RIGHT_STICK,
	&"app_play_toggle": JOY_BUTTON_LEFT_STICK,
}

## Left stick directions, added on top of the controller bindings when
## `use_left_stick` is on. Value is [axis, direction sign].
const LEFT_STICK := {
	&"vf_up": [JOY_AXIS_LEFT_Y, -1.0],
	&"vf_down": [JOY_AXIS_LEFT_Y, 1.0],
	&"vf_left": [JOY_AXIS_LEFT_X, -1.0],
	&"vf_right": [JOY_AXIS_LEFT_X, 1.0],
}

## Xbox-style names (Godot uses the SDL layout: A = bottom face button).
const JOY_BUTTON_NAMES := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-Pad Up",
	JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
	JOY_BUTTON_MISC1: "Share",
	JOY_BUTTON_PADDLE1: "Paddle 1",
	JOY_BUTTON_PADDLE2: "Paddle 2",
	JOY_BUTTON_PADDLE3: "Paddle 3",
	JOY_BUTTON_PADDLE4: "Paddle 4",
	JOY_BUTTON_TOUCHPAD: "Touchpad",
}

var use_left_stick := true
var active_device := KEYBOARD_DEVICE
## Set by the settings menu while it waits for a key press, so gameplay can
## ignore that press.
var is_capturing := false

var _bindings := {Kind.KEYBOARD: {}, Kind.JOYPAD: {}}
## Remembered controller, so it is picked again when it reconnects.
var _preferred_joy_guid := ""


func _ready() -> void:
	for action in all_actions():
		if not InputMap.has_action(action):
			InputMap.add_action(action, ACTION_DEADZONE)
	load_bindings()
	_load_device()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


static func all_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	actions.append_array(GAME_ACTIONS)
	actions.append_array(APP_ACTIONS)
	return actions


# --- Bindings ---------------------------------------------------------------

func get_binding(kind: Kind, action: StringName) -> InputEvent:
	return _bindings[kind].get(action)


func get_binding_text(kind: Kind, action: StringName) -> String:
	return event_to_text(get_binding(kind, action))


## Binds `event` to `action`. If another action already used that input, the
## two swap bindings; the other action's name is returned (or &"" if none).
func set_binding(kind: Kind, action: StringName, event: InputEvent) -> StringName:
	var table: Dictionary = _bindings[kind]
	var swapped := &""
	if event != null:
		for other: StringName in table:
			if other != action and events_equal(table[other], event):
				table[other] = table.get(action)
				swapped = other
				break
	table[action] = event
	_apply()
	bindings_changed.emit()
	return swapped


func set_use_left_stick(enabled: bool) -> void:
	use_left_stick = enabled
	_apply()
	bindings_changed.emit()


## Restores default bindings in memory. Call save_bindings() to keep them.
## (Saving the device choice writes the file too, but only the last saved
## bindings, since unsaved ones live here, not in UserSettings.)
func reset_to_defaults() -> void:
	_set_defaults()
	_apply()
	bindings_changed.emit()


## Loads bindings from UserSettings, falling back to defaults for anything
## missing. Returns false if no bindings were saved.
func load_bindings() -> bool:
	_set_defaults()
	var loaded := false
	use_left_stick = UserSettings.get_value("input", "use_left_stick", true)
	for kind: Kind in [Kind.KEYBOARD, Kind.JOYPAD]:
		var section := _section(kind)
		for action in all_actions():
			if UserSettings.has_value(section, action):
				_bindings[kind][action] = dict_to_event(UserSettings.get_value(section, action))
				loaded = true
	_apply()
	bindings_changed.emit()
	return loaded


## Writes the bindings into UserSettings and saves the settings file.
func save_bindings() -> Error:
	UserSettings.set_value("input", "use_left_stick", use_left_stick)
	for kind: Kind in [Kind.KEYBOARD, Kind.JOYPAD]:
		for action in all_actions():
			UserSettings.set_value(_section(kind), action, event_to_dict(get_binding(kind, action)))
	return UserSettings.save()


func _set_defaults() -> void:
	use_left_stick = true
	for action in all_actions():
		_bindings[Kind.KEYBOARD][action] = _make_key(DEFAULT_KEYS[action])
		_bindings[Kind.JOYPAD][action] = _make_button(DEFAULT_JOY_BUTTONS[action])


## Rebuilds the InputMap from the bindings and the active device.
func _apply() -> void:
	var joy_active := active_device != KEYBOARD_DEVICE
	for action in all_actions():
		InputMap.action_erase_events(action)
		if action in APP_ACTIONS or not joy_active:
			_add_event(action, get_binding(Kind.KEYBOARD, action), ALL_DEVICES)
		if joy_active:
			_add_event(action, get_binding(Kind.JOYPAD, action), active_device)
			if use_left_stick and LEFT_STICK.has(action):
				var stick: Array = LEFT_STICK[action]
				_add_event(action, _make_axis(stick[0], stick[1]), active_device)
		# Don't leave an action stuck "pressed" after its inputs changed.
		Input.action_release(action)


static func _add_event(action: StringName, event: InputEvent, device: int) -> void:
	if event == null:
		return
	var copy: InputEvent = event.duplicate()
	copy.device = device
	InputMap.action_add_event(action, copy)


static func _section(kind: Kind) -> String:
	return "keyboard" if kind == Kind.KEYBOARD else "joypad"


# --- Devices ----------------------------------------------------------------

## The keyboard first, then every connected controller: [{id, name}, ...].
func get_devices() -> Array[Dictionary]:
	var devices: Array[Dictionary] = [{"id": KEYBOARD_DEVICE, "name": "Keyboard"}]
	for id in Input.get_connected_joypads():
		devices.append({"id": id, "name": "%s (#%d)" % [Input.get_joy_name(id), id + 1]})
	return devices


func set_active_device(device_id: int) -> void:
	if device_id != KEYBOARD_DEVICE and device_id not in Input.get_connected_joypads():
		device_id = KEYBOARD_DEVICE
	_preferred_joy_guid = "" if device_id == KEYBOARD_DEVICE else Input.get_joy_guid(device_id)
	_save_device()
	_set_active(device_id)


func _set_active(device_id: int) -> void:
	active_device = device_id
	_apply()
	active_device_changed.emit(device_id)


func _load_device() -> void:
	_preferred_joy_guid = UserSettings.get_value("input", "joy_guid", "")
	for id in Input.get_connected_joypads():
		if _is_preferred(id):
			_set_active(id)
			return


func _save_device() -> void:
	UserSettings.set_value("input", "joy_guid", _preferred_joy_guid)
	UserSettings.save()


func _is_preferred(joy_id: int) -> bool:
	return _preferred_joy_guid != "" and Input.get_joy_guid(joy_id) == _preferred_joy_guid


func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		if active_device == KEYBOARD_DEVICE and _is_preferred(device_id):
			_set_active(device_id)
	elif device_id == active_device:
		# Fall back to the keyboard but keep the controller remembered.
		_set_active(KEYBOARD_DEVICE)
	devices_changed.emit()


# --- Event helpers ----------------------------------------------------------

## Turns a raw input event into a clean binding for `kind`, or null if the
## event can't be used (wrong device type, release, small stick movement...).
static func make_binding(kind: Kind, event: InputEvent) -> InputEvent:
	if kind == Kind.KEYBOARD:
		var key := event as InputEventKey
		if key and key.pressed and not key.echo:
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			if code != KEY_NONE:
				return _make_key(code)
	else:
		var button := event as InputEventJoypadButton
		if button and button.pressed:
			return _make_button(button.button_index)
		var motion := event as InputEventJoypadMotion
		if motion and absf(motion.axis_value) >= CAPTURE_AXIS_THRESHOLD:
			return _make_axis(motion.axis, signf(motion.axis_value))
	return null


static func event_to_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var physical: Key = event.physical_keycode
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(physical))
	if event is InputEventJoypadButton:
		return JOY_BUTTON_NAMES.get(event.button_index, "Button %d" % event.button_index)
	if event is InputEventJoypadMotion:
		return _axis_text(event.axis, event.axis_value)
	return "Unbound"


static func _axis_text(axis: JoyAxis, value: float) -> String:
	var positive := value > 0.0
	match axis:
		JOY_AXIS_LEFT_X:
			return "Left Stick " + ("Right" if positive else "Left")
		JOY_AXIS_LEFT_Y:
			return "Left Stick " + ("Down" if positive else "Up")
		JOY_AXIS_RIGHT_X:
			return "Right Stick " + ("Right" if positive else "Left")
		JOY_AXIS_RIGHT_Y:
			return "Right Stick " + ("Down" if positive else "Up")
		JOY_AXIS_TRIGGER_LEFT:
			return "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "RT"
	return "Axis %d%s" % [axis, "+" if positive else "-"]


static func events_equal(a: InputEvent, b: InputEvent) -> bool:
	return a != null and b != null and event_to_dict(a) == event_to_dict(b)


static func event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type": "key", "code": event.physical_keycode}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "button": event.button_index}
	if event is InputEventJoypadMotion:
		return {"type": "joy_axis", "axis": event.axis, "dir": signf(event.axis_value)}
	return {}


static func dict_to_event(data: Variant) -> InputEvent:
	if not data is Dictionary:
		return null
	match data.get("type", ""):
		"key":
			return _make_key(data.get("code", KEY_NONE))
		"joy_button":
			return _make_button(data.get("button", JOY_BUTTON_INVALID))
		"joy_axis":
			return _make_axis(data.get("axis", JOY_AXIS_INVALID), data.get("dir", 1.0))
	return null


static func _make_key(physical: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	return event


static func _make_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


static func _make_axis(axis: JoyAxis, direction: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = direction
	return event
