class_name SequenceRecorder
extends RefCounted
## Turns a stream of input states into an InputSequence.
##
## arm() waits for the first new press; that press is t = 0.0 s / frame 0.
## After that, every direction change or new button press becomes an input.
## Changes less than one frame apart are merged into one input, so a diagonal
## or a P+G pressed "together" is recorded as a single input.
## Directions or buttons held for at least SequenceInput.HOLD_MIN_FRAMES become hold inputs.

enum State { IDLE, ARMED, RECORDING }

const MERGE_WINDOW_USEC := 16_667  # one frame at 60 FPS

var state := State.IDLE
var inputs: Array[SequenceInput] = []

var _start_usec := 0
var _last_input_usec := 0
var _last_change_usec := 0
var _direction := SequenceInput.NEUTRAL
var _held := PackedStringArray()
## Button -> the input it was pressed on, while it is held.
var _held_button_inputs := {}
## The input where the current (non-neutral) direction started, or null.
var _direction_input: SequenceInput = null


## Starts waiting for the first press. Pass what is currently held so inputs
## that were already down don't count as presses.
func arm(direction: String, held_buttons: PackedStringArray) -> void:
	state = State.ARMED
	inputs = []
	_direction = direction
	_held = held_buttons
	_held_button_inputs.clear()
	_direction_input = null


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
		var is_press := not pressed.is_empty() or (direction_changed and direction != SequenceInput.NEUTRAL)
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
	var input := _add_input(direction, pressed, now_usec)
	for button in pressed:
		_held_button_inputs[button] = input
	if direction != SequenceInput.NEUTRAL and (direction_changed or starting):
		_direction_input = input


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
	if not was_recording or inputs.is_empty():
		inputs = []
		return null

	for button: String in _held_button_inputs.keys():
		_end_button_hold(button, now_usec)
	_end_direction_hold(now_usec)

	var sequence := InputSequence.new()
	sequence.inputs = inputs
	sequence.duration = _seconds(_last_change_usec)
	for input in inputs:
		sequence.duration = maxf(sequence.duration, input.get_end_time())
	inputs = []
	return sequence


func _add_input(direction: String, pressed: PackedStringArray, now_usec: int) -> SequenceInput:
	if not inputs.is_empty() and now_usec - _last_input_usec < MERGE_WINDOW_USEC:
		var last := inputs[-1]
		last.direction = direction
		last.buttons = SequenceInput.sort_buttons(last.buttons + pressed)
		return last
	var input := SequenceInput.new(_seconds(now_usec), direction, pressed)
	inputs.append(input)
	_last_input_usec = now_usec
	return input


func _end_button_hold(button: String, now_usec: int) -> void:
	var input: SequenceInput = _held_button_inputs.get(button)
	_held_button_inputs.erase(button)
	if input == null:
		return
	var length := _seconds(now_usec) - input.timestamp
	if length >= SequenceInput.HOLD_MIN_SECONDS:
		input.button_holds[button] = length


func _end_direction_hold(now_usec: int) -> void:
	var input := _direction_input
	_direction_input = null
	if input == null:
		return
	var length := _seconds(now_usec) - input.timestamp
	if length >= SequenceInput.HOLD_MIN_SECONDS:
		input.direction_hold = length


func _seconds(now_usec: int) -> float:
	return (now_usec - _start_usec) / 1_000_000.0
