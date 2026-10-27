class_name SequenceRecorder
extends RefCounted
## Turns a stream of input states into an InputSequence.
##
## arm() waits for the first new press; that press is t = 0.0 s / frame 0.
## After that, every direction change or new button press becomes a note.
## Changes less than one frame apart are merged into one note, so a diagonal
## or a P+G pressed "together" is recorded as a single note.
## Inputs held for at least InputNote.HOLD_MIN_FRAMES become hold notes.

enum State { IDLE, ARMED, RECORDING }

const MERGE_WINDOW_USEC := 16_667  # one frame at 60 FPS

var state := State.IDLE
var notes: Array[InputNote] = []

var _start_usec := 0
var _last_note_usec := 0
var _last_change_usec := 0
var _direction := InputNote.NEUTRAL
var _held := PackedStringArray()
## Button -> the note it was pressed on, while it is held.
var _held_button_notes := {}
## The note where the current (non-neutral) direction started, or null.
var _direction_note: InputNote = null


## Starts waiting for the first press. Pass what is currently held so inputs
## that were already down don't count as presses.
func arm(direction: String, held_buttons: PackedStringArray) -> void:
	state = State.ARMED
	notes = []
	_direction = direction
	_held = held_buttons
	_held_button_notes.clear()
	_direction_note = null


## Feeds the current input state. Call whenever an input changes.
func update(direction: String, held_buttons: PackedStringArray, now_usec: int) -> void:
	if state == State.IDLE:
		return

	var pressed := PackedStringArray()
	for button in held_buttons:
		if not _held.has(button):
			pressed.append(button)
	var released := PackedStringArray()
	for button in _held:
		if not held_buttons.has(button):
			released.append(button)
	var direction_changed := direction != _direction
	_direction = direction
	_held = held_buttons

	var starting := false
	if state == State.ARMED:
		# Only a press starts the clock, not letting go of something held.
		var is_press := not pressed.is_empty() or (direction_changed and direction != InputNote.NEUTRAL)
		if not is_press:
			return
		state = State.RECORDING
		_start_usec = now_usec
		starting = true
	else:
		for button in released:
			_end_button_hold(button, now_usec)
		if direction_changed:
			_end_direction_hold(now_usec)
		if not direction_changed and pressed.is_empty():
			if not released.is_empty():
				_last_change_usec = now_usec
			return

	_last_change_usec = now_usec
	var note := _add_note(direction, pressed, now_usec)
	for button in pressed:
		_held_button_notes[button] = note
	if direction != InputNote.NEUTRAL and (direction_changed or starting):
		_direction_note = note


## Seconds since the first press (0 while armed or idle).
func elapsed_seconds(now_usec: int) -> float:
	return _seconds(now_usec) if state == State.RECORDING else 0.0


## Ends recording; inputs still held end now. Returns the sequence, or null
## if nothing was pressed.
func stop(now_usec := -1) -> InputSequence:
	if now_usec < 0:
		now_usec = Time.get_ticks_usec()
	var was_recording := state == State.RECORDING
	state = State.IDLE
	if not was_recording or notes.is_empty():
		notes = []
		return null

	for button: String in _held_button_notes.keys():
		_end_button_hold(button, now_usec)
	_end_direction_hold(now_usec)

	var sequence := InputSequence.new()
	sequence.notes = notes
	sequence.duration = _seconds(_last_change_usec)
	for note in notes:
		sequence.duration = maxf(sequence.duration, note.get_end_time())
	notes = []
	return sequence


func _add_note(direction: String, pressed: PackedStringArray, now_usec: int) -> InputNote:
	if not notes.is_empty() and now_usec - _last_note_usec < MERGE_WINDOW_USEC:
		var last := notes[-1]
		last.direction = direction
		last.buttons = InputNote.sort_buttons(last.buttons + pressed)
		return last
	var note := InputNote.new(_seconds(now_usec), direction, pressed)
	notes.append(note)
	_last_note_usec = now_usec
	return note


func _end_button_hold(button: String, now_usec: int) -> void:
	var note: InputNote = _held_button_notes.get(button)
	_held_button_notes.erase(button)
	if note == null:
		return
	var length := _seconds(now_usec) - note.timestamp
	if length >= InputNote.HOLD_MIN_SECONDS:
		note.button_holds[button] = length


func _end_direction_hold(now_usec: int) -> void:
	var note := _direction_note
	_direction_note = null
	if note == null:
		return
	var length := _seconds(now_usec) - note.timestamp
	if length >= InputNote.HOLD_MIN_SECONDS:
		note.direction_hold = length


func _seconds(now_usec: int) -> float:
	return (now_usec - _start_usec) / 1_000_000.0
