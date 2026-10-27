extends Node
## Owns the current sequence and the recorder. Autoloaded as `SequenceManager`.
##
## Record flow: toggle_recording() arms the recorder; the first game input
## starts the clock; toggling again stops it and makes the recording the
## current sequence (unsaved until save_current() is called). A recording
## uses the input mode that was active when it was armed.

signal recording_state_changed(state: SequenceRecorder.State)
## The current sequence or its file changed (loaded, recorded or saved).
signal sequence_changed
## A different sequence became current (loaded, recorded or new, not saved).
signal sequence_replaced
## The current sequence was changed in the frame editor (not saved yet).
signal sequence_edited

const DEFAULT_AUTHOR := "Player1"

## VF notation is relative to facing: true = player 1 side (facing right).
## Comes from the "facing_right" preference.
var facing_right: bool:
	get:
		return UserSettings.get_pref("gameplay", "facing_right")
var current_sequence: InputSequence
## File the current sequence was loaded from or saved to. Empty if unsaved.
var current_path := ""
## True when the current sequence was edited since it was loaded or saved.
var has_unsaved_edits := false

var _recorder := SequenceRecorder.new()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(sequences_dir())
	InputConfig.mode_changed.connect(_on_mode_changed)


## True when the current sequence was made for another input mode than the
## selected one. It can't be played until the user fixes that.
func is_mode_mismatch() -> bool:
	return current_sequence != null and current_sequence.mode != InputConfig.active_mode


## res://Sequences/ when run from the editor. Exported games can't write to
## res://, so they use a Sequences folder next to the executable instead.
func sequences_dir() -> String:
	if OS.has_feature("editor"):
		return "res://Sequences"
	return OS.get_executable_path().get_base_dir().path_join("Sequences")


func path_for(file_name: String) -> String:
	return sequences_dir().path_join(sanitize_file_name(file_name) + ".xml")


## Full paths of every .xml file in the sequences folder, sorted by name.
func list_sequence_files() -> Array[String]:
	var dir := sequences_dir()
	var files: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.get_extension().to_lower() == "xml":
			files.append(dir.path_join(file))
	files.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return files


## Strips a trailing .xml and replaces characters not allowed in file names.
func sanitize_file_name(raw: String) -> String:
	var file_name := raw.strip_edges()
	if file_name.get_extension().to_lower() == "xml":
		file_name = file_name.get_basename()
	return file_name.validate_filename()


# --- Recording ---------------------------------------------------------------

func get_recording_state() -> SequenceRecorder.State:
	return _recorder.state


func is_recording_active() -> bool:
	return _recorder.state != SequenceRecorder.State.IDLE


func get_recording_elapsed() -> float:
	return _recorder.elapsed_seconds(Time.get_ticks_usec())


## Idle -> armed, armed -> cancelled, recording -> stopped.
func toggle_recording() -> void:
	match _recorder.state:
		SequenceRecorder.State.IDLE:
			start_recording()
		SequenceRecorder.State.ARMED:
			cancel_recording()
		SequenceRecorder.State.RECORDING:
			stop_recording()


func start_recording() -> void:
	_recorder.arm(read_direction(), read_held_buttons(), InputConfig.active_mode)
	recording_state_changed.emit(_recorder.state)


## Returns false if nothing was recorded (the current sequence is kept).
func stop_recording() -> bool:
	var sequence := _recorder.stop()
	recording_state_changed.emit(_recorder.state)
	if sequence == null:
		return false
	sequence.author = DEFAULT_AUTHOR
	_set_current(sequence, "")
	return true


func cancel_recording() -> void:
	if not is_recording_active():
		return
	_recorder.stop()
	recording_state_changed.emit(_recorder.state)


func _input(event: InputEvent) -> void:
	if not is_recording_active() or InputConfig.is_capturing or not InputConfig.is_game_event(event):
		return
	# Input's action state is already updated for this event, so read it back.
	var before := _recorder.state
	_recorder.update(read_direction(), read_held_buttons(), Time.get_ticks_usec())
	if _recorder.state != before:
		recording_state_changed.emit(_recorder.state)


## The direction currently held, in VF notation.
func read_direction() -> String:
	return SequenceInput.direction_from_state(
		Input.is_action_pressed(&"dir_up"),
		Input.is_action_pressed(&"dir_down"),
		Input.is_action_pressed(&"dir_left"),
		Input.is_action_pressed(&"dir_right"),
		facing_right,
	)


## The active mode's buttons currently held, in lane order. A held button
## combination counts as holding each of its buttons.
func read_held_buttons() -> PackedStringArray:
	var mode := InputConfig.active_mode
	var from_combos := PackedStringArray()
	for combo: Dictionary in InputMode.combos(mode):
		if Input.is_action_pressed(combo.action):
			from_combos.append_array(PackedStringArray(combo.buttons))
	var held := PackedStringArray()
	for button: Dictionary in InputMode.buttons(mode):
		if Input.is_action_pressed(button.action) or from_combos.has(button.id):
			held.append(button.id)
	return held


# --- Files --------------------------------------------------------------------

## Returns an error message, or "" on success.
func load_sequence(path: String) -> String:
	cancel_recording()
	var sequence := SequenceXml.load_file(path)
	if sequence == null:
		return SequenceXml.last_error
	_set_current(sequence, path)
	return ""


## Starts a new, empty sequence for `mode` (used by the frame editor).
func new_sequence(mode: String) -> void:
	cancel_recording()
	var sequence := InputSequence.new()
	sequence.mode = mode
	sequence.author = DEFAULT_AUTHOR
	_set_current(sequence, "")


## Replaces the current sequence with an edited version, keeping its file.
func apply_edit(sequence: InputSequence) -> void:
	current_sequence = sequence
	has_unsaved_edits = true
	sequence_edited.emit()


## Overwrites the file the current sequence came from.
## Returns an error message, or "" on success.
func save_in_place() -> String:
	if current_sequence == null:
		return "Nothing to save yet: record or load a sequence first."
	if current_path.is_empty():
		return "This sequence has no file yet: use SAVE AS."
	if SequenceXml.save_file(current_sequence, current_path) != OK:
		return SequenceXml.last_error
	has_unsaved_edits = false
	sequence_changed.emit()
	return ""


## Saves the current sequence as <sequences dir>/<file_name>.xml.
## Returns an error message, or "" on success.
func save_current(file_name: String, author: String) -> String:
	if current_sequence == null:
		return "Nothing to save yet: record or load a sequence first."
	var clean_name := sanitize_file_name(file_name)
	if clean_name.is_empty():
		return "Enter a file name."
	var path := path_for(clean_name)
	current_sequence.name = clean_name
	current_sequence.author = author.strip_edges() if not author.strip_edges().is_empty() else DEFAULT_AUTHOR
	if SequenceXml.save_file(current_sequence, path) != OK:
		return SequenceXml.last_error
	current_path = path
	has_unsaved_edits = false
	sequence_changed.emit()
	return ""


## Changing mode ends a recording: it is kept if it started, cancelled if armed.
func _on_mode_changed(_mode: String) -> void:
	if get_recording_state() == SequenceRecorder.State.RECORDING:
		stop_recording()
	else:
		cancel_recording()


func _set_current(sequence: InputSequence, path: String) -> void:
	current_sequence = sequence
	current_path = path
	has_unsaved_edits = false
	sequence_replaced.emit()
	sequence_changed.emit()
