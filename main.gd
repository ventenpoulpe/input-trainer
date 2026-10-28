extends Control
## Main screen: toolbar, HUD and the gameplay highway.

const RecState := SequenceRecorder.State
const Rating := TimingJudge.Rating
const RATING_SOUNDS := {
	Rating.PERFECT: &"perfect", Rating.GREAT: &"great", Rating.GOOD: &"good", Rating.MISS: &"miss",
}
## Toolbar icons that change with the record and play state.
const ICON_RECORD := preload("res://ui/icons/record.svg")
const ICON_RECORD_CANCEL := preload("res://ui/icons/record_cancel.svg")
const ICON_RECORD_STOP := preload("res://ui/icons/record_stop.svg")
const ICON_PLAY := preload("res://ui/icons/play.svg")
const ICON_STOP := preload("res://ui/icons/stop.svg")
## Load menu ids (files use their index).
const MENU_BROWSE := 10_000
const MENU_OPEN_FOLDER := 10_001

@onready var _gameplay: GameplayController = %Gameplay
@onready var _editor: SequenceEditor = %Editor
@onready var _highway: Highway = %Highway
@onready var _settings_menu: SettingsMenu = %SettingsMenu
@onready var _load_menu: MenuButton = %LoadXmlButton
@onready var _record_button: Button = %RecordButton
@onready var _save_button: Button = %SaveButton
@onready var _save_as_button: Button = %SaveAsButton
@onready var _edit_button: Button = %EditButton
@onready var _clear_button: Button = %ClearButton
@onready var _edit_label: Label = %EditLabel
@onready var _edit_help_label: Label = %EditHelpLabel
@onready var _play_button: Button = %PlayButton
@onready var _best_score_label: Label = %BestScoreLabel
@onready var _match_label: Label = %MatchLabel
@onready var _best_label: Label = %BestLabel
@onready var _progress_label: Label = %ProgressLabel
@onready var _loop_label: Label = %LoopLabel
@onready var _counts_label: Label = %CountsLabel
@onready var _status_label: Label = %StatusLabel
@onready var _time_label: Label = %TimeLabel
@onready var _frame_label: Label = %FrameLabel
@onready var _recording_label: Label = %RecordingLabel
@onready var _mode_warning_label: Label = %ModeWarningLabel
@onready var _title_label: Label = %Title

var _load_dialog := FileDialog.new()
var _save_dialog := SaveSequenceDialog.new()
## Files listed in the load menu, by menu id.
var _menu_files: Array[String] = []


func _ready() -> void:
	%SettingsButton.pressed.connect(_open_settings)
	_load_menu.about_to_popup.connect(_populate_load_menu)
	_load_menu.get_popup().id_pressed.connect(_on_load_menu_id_pressed)
	_record_button.pressed.connect(_toggle_record)
	_save_button.pressed.connect(_save)
	_save_as_button.pressed.connect(_open_save_dialog)
	_edit_button.pressed.connect(_toggle_edit)
	_clear_button.pressed.connect(_clear_inputs)
	_editor.active_changed.connect(_on_edit_active_changed)
	_editor.brush_changed.connect(func(_direction: String) -> void: _update_edit_help())
	SequenceManager.sequence_edited.connect(_update_title)
	_play_button.pressed.connect(_toggle_play)
	SequenceManager.recording_state_changed.connect(_on_recording_state_changed)
	SequenceManager.sequence_changed.connect(_on_sequence_changed)
	InputConfig.mode_changed.connect(_on_mode_changed)
	InputConfig.bindings_changed.connect(_update_record_play_buttons)
	_gameplay.state_changed.connect(_on_play_state_changed)
	_gameplay.best_score_changed.connect(_on_best_score_changed)
	_gameplay.input_judged.connect(func(target: TimingJudge.Target) -> void: Sfx.play(RATING_SOUNDS[target.rating]))
	_gameplay.hold_finished.connect(_on_hold_finished)
	_gameplay.extra_press.connect(func(_lane: int) -> void: Sfx.play(&"extra"))
	_gameplay.loop_finished.connect(func(_rate: float, is_new_best: bool) -> void: Sfx.play(&"new_best" if is_new_best else &"loop_end"))
	_highway.setup(_gameplay, _editor)

	_setup_load_dialog()
	add_child(_save_dialog)
	_on_recording_state_changed(SequenceManager.get_recording_state())
	_on_sequence_changed()
	_on_play_state_changed(_gameplay.state)
	_update_record_play_buttons()
	_on_best_score_changed(_gameplay.best_score)
	_on_mode_changed(InputConfig.active_mode)
	_on_edit_active_changed(false)


func _process(_delta: float) -> void:
	if _editor.active:
		_show_time(_editor.view_frame / SequenceInput.FPS)
	elif SequenceManager.is_recording_active():
		_show_time(SequenceManager.get_recording_elapsed())
	elif _gameplay.is_running():
		_show_time(maxf(_gameplay.get_time(), 0.0))
	_update_stats()


## Edit mode keys are read before the UI so focused buttons don't take the
## arrow keys. They are ignored while a dialog or text field is in use.
func _input(event: InputEvent) -> void:
	if not _editor.active or not event is InputEventKey:
		return
	if _settings_menu.visible or _save_dialog.visible or _load_dialog.visible:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if _handle_edit_key(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _settings_menu.visible or InputConfig.is_capturing:
		return
	if _editor.active:
		return  # play/record shortcuts are off while editing
	if event.is_action_pressed(&"app_record_toggle"):
		get_viewport().set_input_as_handled()
		_toggle_record()
	elif event.is_action_pressed(&"app_play_toggle"):
		get_viewport().set_input_as_handled()
		_toggle_play()


# --- Toolbar -----------------------------------------------------------------

func _toggle_play() -> void:
	if _gameplay.is_running():
		_gameplay.stop()
		_set_status("Stopped.")
		return
	if SequenceManager.is_recording_active():
		_set_status("Stop recording first (Backspace / R3).")
		return
	var error := _gameplay.start()
	_set_status(error if error else "Get ready...")


func _toggle_record() -> void:
	_gameplay.stop()
	SequenceManager.toggle_recording()


## Edit mode is only toggled from its toolbar button.
func _toggle_edit() -> void:
	if _editor.active:
		_editor.stop()
		_set_status("Left edit mode.")
		return
	_stop_everything()
	var error := _editor.start()
	_set_status(error if error else "Edit mode: click the lanes to change inputs. Save to keep the changes.")
	_edit_button.set_pressed_no_signal(_editor.active)


func _save() -> void:
	if SequenceManager.current_sequence == null:
		return
	if SequenceManager.current_path.is_empty():
		_open_save_dialog()
		return
	_gameplay.stop()
	var error := SequenceManager.save_in_place()
	_set_status(error if error else "Saved %s." % SequenceManager.current_path.get_file())


func _open_settings() -> void:
	_stop_everything()
	_settings_menu.open()


func _setup_load_dialog() -> void:
	var dir := SequenceManager.sequences_dir()
	_load_dialog.title = "Load Sequence"
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.access = FileDialog.ACCESS_RESOURCES if dir.begins_with("res://") else FileDialog.ACCESS_FILESYSTEM
	_load_dialog.filters = PackedStringArray(["*.xml ; Input sequences"])
	_load_dialog.size = Vector2i(720, 480)
	_load_dialog.file_selected.connect(_on_load_file_selected)
	add_child(_load_dialog)


## Rescans the sequences folder every time the load menu opens.
## Subfolders of the sequences folder become submenus, at any depth.
func _populate_load_menu() -> void:
	_stop_everything()
	var popup := _load_menu.get_popup()
	popup.clear(true)  # also frees the folder submenus
	_menu_files.clear()
	_add_sequence_items(popup, SequenceManager.sequence_tree())
	if _menu_files.is_empty():
		popup.add_item("(no .xml files in %s)" % SequenceManager.sequences_dir())
		popup.set_item_disabled(-1, true)
	popup.add_separator()
	popup.add_item("Browse...", MENU_BROWSE)
	popup.add_item("Open Sequences folder", MENU_OPEN_FOLDER)


## Adds a folder's subfolders (as submenus) then its files to `menu`.
## Item ids are indexes into _menu_files.
func _add_sequence_items(menu: PopupMenu, tree: Dictionary) -> void:
	for folder: Dictionary in tree.folders:
		var submenu := PopupMenu.new()
		submenu.id_pressed.connect(_on_load_menu_id_pressed)
		_add_sequence_items(submenu, folder)
		menu.add_submenu_node_item(folder.name, submenu)
	for path: String in tree.files:
		menu.add_radio_check_item(path.get_file().get_basename(), _menu_files.size())
		menu.set_item_checked(-1, path == SequenceManager.current_path)
		_menu_files.append(path)


func _on_load_menu_id_pressed(id: int) -> void:
	match id:
		MENU_BROWSE:
			_load_dialog.current_dir = SequenceManager.sequences_dir()
			_load_dialog.popup_centered()
		MENU_OPEN_FOLDER:
			OS.shell_open(ProjectSettings.globalize_path(SequenceManager.sequences_dir()))
		_:
			if id >= 0 and id < _menu_files.size():
				_on_load_file_selected(_menu_files[id])


func _on_load_file_selected(path: String) -> void:
	var error := SequenceManager.load_sequence(path)
	if error:
		_set_status(error)
	else:
		_set_status("Loaded %s (%d inputs). Press Play (%s)." % [
				path.get_file(), SequenceManager.current_sequence.inputs.size(), InputConfig.get_shortcut_text(&"app_play_toggle")])


func _open_save_dialog() -> void:
	_stop_everything()
	_editor.end_stroke()
	if SequenceManager.current_sequence:
		_save_dialog.open()


## Stops playback, and stops a recording in progress so it isn't lost
## (or cancels it if it was only armed).
func _stop_everything() -> void:
	_gameplay.stop()
	if SequenceManager.get_recording_state() == RecState.RECORDING:
		SequenceManager.stop_recording()
	else:
		SequenceManager.cancel_recording()


# --- Display -----------------------------------------------------------------

func _update_stats() -> void:
	var judge := _gameplay.judge
	var active := judge != null and _gameplay.is_running()
	_match_label.text = "MATCH: " + _percent(judge.get_rate() if active else -1.0)
	_progress_label.text = "CURRENT LOOP PROGRESS: %d%%" % roundi(_gameplay.get_loop_progress() * 100.0)
	_loop_label.text = "LOOP: %d" % _gameplay.loop_number if active else "LOOP: -"
	if active:
		var counts := judge.counts
		_counts_label.text = "PERFECT %d   GREAT %d\nGOOD %d   MISS %d   EXTRA %d" % [
			counts[Rating.PERFECT], counts[Rating.GREAT], counts[Rating.GOOD], counts[Rating.MISS], judge.extras,
		]
		if judge.holds_ok + judge.holds_dropped > 0 or judge.get_item_count() > judge.targets.size():
			_counts_label.text += "\nHOLD OK %d   DROP %d" % [judge.holds_ok, judge.holds_dropped]
	else:
		_counts_label.text = ""


func _on_play_state_changed(state: GameplayController.State) -> void:
	_update_record_play_buttons()
	if state == GameplayController.State.COUNTDOWN:
		Sfx.play(&"ready")


func _on_hold_finished(target: TimingJudge.Target) -> void:
	Sfx.play(&"hold_ok" if target.hold_result == TimingJudge.HoldResult.OK else &"hold_drop")


func _on_best_score_changed(best: float) -> void:
	_best_label.text = "BEST: " + _percent(best)
	_best_score_label.text = "BEST MATCH SCORE: " + _percent(best)


func _on_recording_state_changed(state: SequenceRecorder.State) -> void:
	match state:
		RecState.IDLE:
			_recording_label.hide()
		RecState.ARMED:
			_recording_label.text = "ARMED\nfirst input starts recording"
			_recording_label.show()
			_show_time(0.0)
			_set_status("Recording armed. Your first direction or button press is t = 0.")
		RecState.RECORDING:
			_recording_label.text = "RECORDING..."
			_recording_label.show()
	_update_record_play_buttons()


## Icons and tooltips (with the current shortcuts) of the record and play buttons.
func _update_record_play_buttons() -> void:
	var record_keys := InputConfig.get_shortcut_text(&"app_record_toggle")
	match SequenceManager.get_recording_state():
		RecState.ARMED:
			_record_button.icon = ICON_RECORD_CANCEL
			_record_button.tooltip_text = "Cancel recording (%s)" % record_keys
		RecState.RECORDING:
			_record_button.icon = ICON_RECORD_STOP
			_record_button.tooltip_text = "Stop recording (%s)" % record_keys
		_:
			_record_button.icon = ICON_RECORD
			_record_button.tooltip_text = "Record (%s)" % record_keys
	var playing := _gameplay.state != GameplayController.State.STOPPED
	_play_button.icon = ICON_STOP if playing else ICON_PLAY
	_play_button.tooltip_text = "%s (%s)" % ["Stop" if playing else "Play", InputConfig.get_shortcut_text(&"app_play_toggle")]


func _on_mode_changed(_mode: String) -> void:
	_update_mode_warning()


## Shown for as long as the current sequence and the selected mode differ.
func _update_mode_warning() -> void:
	var mismatch := SequenceManager.is_mode_mismatch()
	_mode_warning_label.visible = mismatch
	if mismatch:
		_mode_warning_label.text = "Incompatible input mode, either update the correct one or load a sequence file that matches with it!\n(file: %s, selected: %s)" % [
			InputMode.title(SequenceManager.current_sequence.mode), InputMode.title(InputConfig.active_mode),
		]


func _on_sequence_changed() -> void:
	_update_mode_warning()
	_update_title()
	var sequence := SequenceManager.current_sequence
	if sequence == null:
		_show_time(0.0)
		return
	if not _editor.active:
		_show_time(sequence.duration)
	if not SequenceManager.current_path:
		if sequence.inputs.is_empty():
			_set_status("New empty %s sequence: click the lanes to add inputs." % InputMode.title(sequence.mode))
		else:
			_set_status("Recorded %d inputs (%.2f s). Press Play to practice or Save as to keep it." % [
				sequence.inputs.size(), sequence.duration,
			])


## Title: the current file name, with a * when there are unsaved edits.
func _update_title() -> void:
	var sequence := SequenceManager.current_sequence
	_save_button.disabled = sequence == null
	_save_as_button.disabled = sequence == null
	if sequence == null:
		_title_label.text = "No sequence loaded"
		return
	var path := SequenceManager.current_path
	if path:
		_title_label.text = path.get_file().get_basename() + (" *" if SequenceManager.has_unsaved_edits else "")
	elif SequenceManager.has_unsaved_edits or sequence.inputs.is_empty():
		_title_label.text = "Unsaved sequence"
	else:
		_title_label.text = "Unsaved recording"


# --- Edit mode -----------------------------------------------------------------

func _on_edit_active_changed(is_active: bool) -> void:
	_edit_button.set_pressed_no_signal(is_active)
	_edit_label.visible = is_active
	_edit_help_label.visible = is_active
	_record_button.disabled = is_active
	_play_button.disabled = is_active
	_clear_button.disabled = not is_active
	_update_edit_help()
	if not is_active and SequenceManager.current_sequence:
		_show_time(SequenceManager.current_sequence.duration)


func _clear_inputs() -> void:
	_editor.clear_all()
	_set_status("Cleared all inputs. Ctrl+Z to undo, Save to keep it.")


func _update_edit_help() -> void:
	var digit: int = SequenceEditor.NUMPAD_DIRECTIONS.find_key(_editor.brush)
	_edit_help_label.text = "\n".join([
		"Click a cell: press → hold → empty",
		"Drag: hold over several frames",
		"Right-click (drag): clear",
		"Direction lane: click paints the brush, click again for neutral",
		"Brush: %d %s (keys 1-9 or click the joystick icon)" % [digit, _editor.brush],
		"Wheel / Up / Down: scroll (Shift / PgUp / PgDn: 10 frames)",
		"Ctrl+Wheel: zoom   Home / End: start / end",
		"E: end the sequence at the cursor frame",
		"Ctrl+Z / Ctrl+Y: undo / redo",
	])


## Keyboard keys of edit mode. Returns true if the event was used.
func _handle_edit_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return false
	if key.ctrl_pressed:
		if key.keycode == KEY_Z:
			if key.shift_pressed:
				_editor.redo()
			else:
				_editor.undo()
			return true
		if key.keycode == KEY_Y:
			_editor.redo()
			return true
		return false
	# Top-row digits by physical key (works on any layout), or the numpad.
	if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_9:
		_editor.set_brush_numpad(key.physical_keycode - KEY_0)
		return true
	if key.keycode >= KEY_KP_1 and key.keycode <= KEY_KP_9:
		_editor.set_brush_numpad(key.keycode - KEY_KP_0)
		return true
	match key.keycode:
		KEY_UP:
			_editor.scroll(1)
		KEY_DOWN:
			_editor.scroll(-1)
		KEY_PAGEUP:
			_editor.scroll(10)
		KEY_PAGEDOWN:
			_editor.scroll(-10)
		KEY_HOME:
			_editor.go_to(0)
		KEY_E:
			_editor.set_end(_editor.view_frame)
		KEY_END:
			var sequence := SequenceManager.current_sequence
			_editor.go_to(SequenceInput.time_to_frame(sequence.duration) if sequence else 0)
		_:
			return false
	return true


func _show_time(seconds: float) -> void:
	_time_label.text = "TIME: %.2f s" % seconds
	_frame_label.text = "FRAME: %d f" % SequenceInput.time_to_frame(seconds)


func _set_status(text: String) -> void:
	_status_label.text = text


static func _percent(value: float) -> String:
	return "--" if value < 0.0 else "%.1f%%" % value
