extends Node
## Retakes the README screenshots in docs/screenshots/.
##
## Run from the project folder:
##   Godot.exe --path . --resolution 1600x900 res://tools/capture_screenshots.tscn
##
## It opens the main scene, sets up each shot (mode, sequence, edit mode,
## settings menu) and saves the PNGs. The two "playing" shots are played by a
## bot that presses the sequence's own inputs on time, so every hit is
## PERFECT. The selected input mode is restored at the end.

const OUT_DIR := "res://docs/screenshots/"
const SIZE := Vector2i(1600, 900)
const PlayState := GameplayController.State
## Sequences used in the shots, relative to the Sequences folder.
const DAIGO := "SF3/SF3-EVO2004-Daigo-Parry.xml"
const JEAN := "VF5R/VF5R-JEA-BNB-6K.xml"

var _main: Control
var _gameplay: GameplayController
## Bot: grid of the sequence being played, and the actions it holds down.
var _bot_grid: SequenceGrid
var _bot_held: Dictionary = {}
var _bot_press_frame: Dictionary = {}


func _ready() -> void:
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	_gameplay = _main.get_node("%Gameplay")
	var original_mode := InputConfig.active_mode
	var original_device := InputConfig.active_device
	# The shots show "Keyboard"; the bot's inputs work with any device.
	InputConfig.set_active_device(InputConfig.KEYBOARD_DEVICE)
	await _frames(10)

	# Still shots first, so no hit effects from a play are left on screen.

	# SC2 mode with nothing loaded.
	InputConfig.set_active_mode("SC2")
	await _frames(30)
	await _capture("mode_sc2")

	# Edit mode on the Daigo sequence, cursor on frame 140.
	InputConfig.set_active_mode("SF")
	_main._on_load_file_selected(_sequence(DAIGO))
	_main._toggle_edit()
	_main._editor.go_to(140)
	await _frames(10)
	await _capture("edit_mode")
	_main._toggle_edit()

	# Settings menu in VF mode.
	InputConfig.set_active_mode("VF")
	_main._on_load_file_selected(_sequence(JEAN))
	_main._open_settings()
	await _frames(10)
	await _capture("settings_vf")
	_main._settings_menu._on_cancel_pressed()

	# SF mode, playing the Daigo sequence.
	InputConfig.set_active_mode("SF")
	_main._on_load_file_selected(_sequence(DAIGO))
	await _play_until(1.15)
	await _capture("mode_sf")
	_stop_play()

	# VF mode, playing the Jean bread-and-butter.
	InputConfig.set_active_mode("VF")
	_main._on_load_file_selected(_sequence(JEAN))
	await _play_until(1.09)
	await _capture("playing_vf")
	_stop_play()

	InputConfig.set_active_mode(original_mode)
	InputConfig.set_active_device(original_device)
	get_tree().quit()


func _process(_delta: float) -> void:
	if _bot_grid and _gameplay.state == PlayState.PLAYING:
		_bot_update(floori(_gameplay.get_time() * SequenceInput.FPS))


# --- Shots -----------------------------------------------------------------------

## Full path of a sequence; quits with an error if it's missing.
func _sequence(relative_path: String) -> String:
	var path := SequenceManager.sequences_dir().path_join(relative_path)
	if not FileAccess.file_exists(path):
		push_error("Missing sequence %s: update the paths at the top of this script." % path)
		get_tree().quit(1)
	return path


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != SIZE:
		push_warning("Window is %s, resizing the shot to %s" % [image.get_size(), SIZE])
		image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	var path := ProjectSettings.globalize_path(OUT_DIR + file_name + ".png")
	var err := image.save_png(path)
	print("%s %s" % ["Saved" if err == OK else "FAILED", path])


## Starts playing the current sequence with the bot, and waits until the
## sequence clock reaches `seconds` in the first loop.
func _play_until(seconds: float) -> void:
	_bot_grid = SequenceGrid.from_sequence(SequenceManager.current_sequence)
	_main._toggle_play()
	var give_up := Time.get_ticks_msec() + 10_000
	while not (_gameplay.state == PlayState.PLAYING and _gameplay.get_time() >= seconds):
		if Time.get_ticks_msec() > give_up:
			push_error("The sequence didn't start playing.")
			get_tree().quit(1)
			return
		await get_tree().process_frame


func _stop_play() -> void:
	_bot_grid = null
	_bot_release_all()
	_main._toggle_play()


# --- Bot ---------------------------------------------------------------------------

## Holds exactly the direction and buttons the grid has on `frame`.
func _bot_update(frame: int) -> void:
	var wanted := {}
	for action in _direction_actions(_bot_grid.get_direction(frame)):
		wanted[action] = true
	var repress: Array[StringName] = []
	for button: Dictionary in InputMode.buttons(_bot_grid.mode):
		if _bot_grid.get_cell(button.id, frame) != SequenceGrid.Cell.NONE:
			wanted[button.action] = true
			# A new press right after another one needs a release in between.
			if _bot_grid.is_press(button.id, frame) and _bot_press_frame.get(button.action, -1) != frame \
					and _bot_held.has(button.action):
				repress.append(button.action)
	# Releases first, so a direction change doesn't pass through a diagonal.
	for action: StringName in _bot_held.keys():
		if not wanted.has(action) or action in repress:
			_send(action, false)
	for action: StringName in wanted:
		if not _bot_held.has(action):
			_send(action, true)
			_bot_press_frame[action] = frame


func _bot_release_all() -> void:
	for action: StringName in _bot_held.keys():
		_send(action, false)
	_bot_press_frame.clear()


func _send(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	if pressed:
		_bot_held[action] = true
	else:
		_bot_held.erase(action)


## dir_* actions for a direction (VF notation, facing-relative).
func _direction_actions(direction: String) -> Array[StringName]:
	var forward := &"dir_right" if SequenceManager.facing_right else &"dir_left"
	var back := &"dir_left" if SequenceManager.facing_right else &"dir_right"
	var actions: Array[StringName] = []
	if direction.begins_with("UP"):
		actions.append(&"dir_up")
	if direction.begins_with("DOWN"):
		actions.append(&"dir_down")
	if direction.ends_with("FORWARD"):
		actions.append(forward)
	if direction.ends_with("BACK"):
		actions.append(back)
	return actions
