extends Control
## Main screen: toolbar, HUD and the gameplay highway.

const RecState := SequenceRecorder.State
const Rating := TimingJudge.Rating
const RATING_SOUNDS := {
	Rating.PERFECT: &"perfect", Rating.GREAT: &"great", Rating.GOOD: &"good", Rating.MISS: &"miss",
}
## LOAD XML menu ids (files use their index).
const MENU_BROWSE := 10_000
const MENU_OPEN_FOLDER := 10_001

@onready var _gameplay: GameplayController = %Gameplay
@onready var _highway: Highway = %Highway
@onready var _settings_menu: SettingsMenu = %SettingsMenu
@onready var _load_menu: MenuButton = %LoadXmlButton
@onready var _record_button: Button = %RecordButton
@onready var _save_button: Button = %SaveXmlButton
@onready var _play_button: Button = %PlayButton
@onready var _best_score_label: Label = %BestScoreLabel
@onready var _match_label: Label = %MatchLabel
@onready var _best_label: Label = %BestLabel
@onready var _progress_label: Label = %ProgressLabel
@onready var _loop_label: Label = %LoopLabel
@onready var _counts_label: Label = %CountsLabel
@onready var _status_label: Label = %StatusLabel
@onready var _file_label: Label = %FileLabel
@onready var _time_label: Label = %TimeLabel
@onready var _frame_label: Label = %FrameLabel
@onready var _recording_label: Label = %RecordingLabel

var _load_dialog := FileDialog.new()
var _save_dialog := SaveSequenceDialog.new()
## Files listed in the LOAD XML menu, by menu id.
var _menu_files: Array[String] = []


func _ready() -> void:
	%SettingsButton.pressed.connect(_open_settings)
	_load_menu.about_to_popup.connect(_populate_load_menu)
	_load_menu.get_popup().id_pressed.connect(_on_load_menu_id_pressed)
	_record_button.pressed.connect(_toggle_record)
	_save_button.pressed.connect(_open_save_dialog)
	_play_button.pressed.connect(_toggle_play)
	SequenceManager.recording_state_changed.connect(_on_recording_state_changed)
	SequenceManager.sequence_changed.connect(_on_sequence_changed)
	_gameplay.state_changed.connect(_on_play_state_changed)
	_gameplay.best_score_changed.connect(_on_best_score_changed)
	_gameplay.note_judged.connect(func(target: TimingJudge.Target) -> void: Sfx.play(RATING_SOUNDS[target.rating]))
	_gameplay.hold_finished.connect(_on_hold_finished)
	_gameplay.extra_press.connect(func(_lane: TimingJudge.Lane) -> void: Sfx.play(&"extra"))
	_gameplay.loop_finished.connect(func(_rate: float, is_new_best: bool) -> void: Sfx.play(&"new_best" if is_new_best else &"loop_end"))
	_highway.setup(_gameplay)

	_setup_load_dialog()
	add_child(_save_dialog)
	_on_recording_state_changed(SequenceManager.get_recording_state())
	_on_sequence_changed()
	_on_play_state_changed(_gameplay.state)
	_on_best_score_changed(_gameplay.best_score)


func _process(_delta: float) -> void:
	if SequenceManager.is_recording_active():
		_show_time(SequenceManager.get_recording_elapsed())
	elif _gameplay.is_running():
		_show_time(maxf(_gameplay.get_time(), 0.0))
	_update_stats()


func _unhandled_input(event: InputEvent) -> void:
	if _settings_menu.visible or InputConfig.is_capturing:
		return
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


## Rescans the sequences folder every time the LOAD XML menu opens.
func _populate_load_menu() -> void:
	_stop_everything()
	var popup := _load_menu.get_popup()
	popup.clear()
	_menu_files = SequenceManager.list_sequence_files()
	if _menu_files.is_empty():
		popup.add_item("(no .xml files in %s)" % SequenceManager.sequences_dir())
		popup.set_item_disabled(-1, true)
	for i in _menu_files.size():
		popup.add_radio_check_item(_menu_files[i].get_file().get_basename(), i)
		popup.set_item_checked(-1, _menu_files[i] == SequenceManager.current_path)
	popup.add_separator()
	popup.add_item("Browse...", MENU_BROWSE)
	popup.add_item("Open Sequences folder", MENU_OPEN_FOLDER)


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
		_set_status("Loaded %s (%d notes). Press PLAY (Space / L3)." % [path.get_file(), SequenceManager.current_sequence.notes.size()])


func _open_save_dialog() -> void:
	_stop_everything()
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
	_play_button.text = "STOP" if state != GameplayController.State.STOPPED else "PLAY (START/STOP)"
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
			_record_button.text = "RECORD (START/STOP)"
			_recording_label.hide()
		RecState.ARMED:
			_record_button.text = "CANCEL RECORD"
			_recording_label.text = "ARMED\nfirst input starts recording"
			_recording_label.show()
			_show_time(0.0)
			_set_status("Recording armed. Your first direction or button press is t = 0.")
		RecState.RECORDING:
			_record_button.text = "STOP RECORD"
			_recording_label.text = "RECORDING..."
			_recording_label.show()


func _on_sequence_changed() -> void:
	var sequence := SequenceManager.current_sequence
	_save_button.disabled = sequence == null
	if sequence == null:
		_file_label.text = "FILE: -"
		_show_time(0.0)
		return
	var path := SequenceManager.current_path
	_file_label.text = "FILE: " + (path.get_file() if path else "(unsaved recording)")
	_show_time(sequence.duration)
	if not path:
		_set_status("Recorded %d notes (%.2f s). Press PLAY to practice or SAVE XML to keep it." % [
			sequence.notes.size(), sequence.duration,
		])


func _show_time(seconds: float) -> void:
	_time_label.text = "TIME: %.2f s" % seconds
	_frame_label.text = "FRAME: %d f" % InputNote.time_to_frame(seconds)


func _set_status(text: String) -> void:
	_status_label.text = text


static func _percent(value: float) -> String:
	return "--" if value < 0.0 else "%.1f%%" % value
