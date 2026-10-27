class_name GameplayController
extends Node
## Runs the practice loop for the current sequence:
## STOPPED -> COUNTDOWN (1 s) -> PLAYING -> LOOP_PAUSE (0.5 s) -> PLAYING -> ...
##
## The clock is "sequence time": 0 is the first note. Each loop starts at
## -lead_time so the first notes have time to scroll down to the hit line.

signal state_changed(state: State)
signal loop_started(loop_number: int)
signal note_judged(target: TimingJudge.Target)
## A hold note was released or held to its end; see target.hold_result.
signal hold_finished(target: TimingJudge.Target)
## A button press that didn't match any note.
signal extra_press(lane: TimingJudge.Lane)
signal loop_finished(rate: float, is_new_best: bool)
## -1 means no best score yet.
signal best_score_changed(best: float)

enum State { STOPPED, COUNTDOWN, PLAYING, LOOP_PAUSE }

const COUNTDOWN_TIME := 1.0
const LOOP_PAUSE_TIME := 0.5

## Seconds a note takes to scroll from the far end to the hit line.
## Read from the "scroll_time" preference when a run starts.
var lead_time := 1.2
var state := State.STOPPED
var judge: TimingJudge
var sequence: InputSequence
var best_score := -1.0
var loop_number := 0
var last_rate := -1.0

var _state_start_usec := 0
var _loop_start_usec := 0
var _last_direction := InputNote.NEUTRAL
var _last_buttons := PackedStringArray()


func _ready() -> void:
	SequenceManager.sequence_replaced.connect(_on_sequence_replaced)
	SequenceManager.recording_state_changed.connect(_on_recording_state_changed)


func is_running() -> bool:
	return state != State.STOPPED


## Starts the loop with SequenceManager's current sequence.
## Returns an error message, or "" on success.
func start() -> String:
	var current := SequenceManager.current_sequence
	if current == null:
		return "Load or record a sequence first."
	var new_judge := TimingJudge.new(current)
	if new_judge.targets.is_empty():
		return "This sequence has no notes to play."
	sequence = current
	judge = new_judge
	lead_time = UserSettings.get_pref("gameplay", "scroll_time")
	loop_number = 0
	last_rate = -1.0
	_set_state(State.COUNTDOWN)
	return ""


func stop() -> void:
	if state != State.STOPPED:
		_set_state(State.STOPPED)


## Current sequence time in seconds (-lead_time before the first note scrolls in).
func get_time() -> float:
	if state != State.PLAYING:
		return -lead_time
	return _time_at(Time.get_ticks_usec())


## 0..1 progress of the countdown or the loop pause.
func get_phase_progress() -> float:
	var length := COUNTDOWN_TIME if state == State.COUNTDOWN else LOOP_PAUSE_TIME
	return clampf(_state_elapsed() / length, 0.0, 1.0)


## 0..1 progress through the current loop.
func get_loop_progress() -> float:
	if judge == null or state == State.STOPPED or state == State.COUNTDOWN:
		return 0.0
	if state == State.LOOP_PAUSE:
		return 1.0
	return clampf(get_time() / judge.end_time, 0.0, 1.0)


func _process(_delta: float) -> void:
	match state:
		State.COUNTDOWN:
			if _state_elapsed() >= COUNTDOWN_TIME:
				_begin_loop()
		State.LOOP_PAUSE:
			if _state_elapsed() >= LOOP_PAUSE_TIME:
				_begin_loop()
		State.PLAYING:
			var time := get_time()
			for target in judge.update_misses(time):
				note_judged.emit(target)
			for target in judge.update_holds(time):
				hold_finished.emit(target)
			if time >= judge.end_time:
				_finish_loop()


func _input(event: InputEvent) -> void:
	if state != State.PLAYING or not _is_game_event(event):
		return
	var time := _time_at(Time.get_ticks_usec())

	var direction := SequenceManager.read_direction()
	if direction != _last_direction:
		_last_direction = direction
		# Leaving a direction ends its hold before the new one is judged.
		_emit_release(judge.release(TimingJudge.Lane.DIRECTION, time))
		if direction != InputNote.NEUTRAL:
			var hit := judge.press_direction(direction, time)
			if hit:
				note_judged.emit(hit)

	var held := SequenceManager.read_held_buttons()
	for button in _last_buttons:
		if not held.has(button):
			_emit_release(judge.release(TimingJudge.BUTTON_LANES[button], time))
	for button in held:
		if _last_buttons.has(button):
			continue
		var lane: TimingJudge.Lane = TimingJudge.BUTTON_LANES[button]
		var hit := judge.press_button(lane, time)
		if hit:
			note_judged.emit(hit)
		else:
			extra_press.emit(lane)
	_last_buttons = held


func _emit_release(target: TimingJudge.Target) -> void:
	if target:
		hold_finished.emit(target)


func _begin_loop() -> void:
	judge.reset()
	loop_number += 1
	# Inputs already held when the loop starts don't count as presses.
	_last_direction = SequenceManager.read_direction()
	_last_buttons = SequenceManager.read_held_buttons()
	_set_state(State.PLAYING)
	_loop_start_usec = _state_start_usec
	loop_started.emit(loop_number)


func _finish_loop() -> void:
	last_rate = maxf(judge.get_rate(), 0.0)
	var is_new_best := last_rate > best_score
	if is_new_best:
		best_score = last_rate
		best_score_changed.emit(best_score)
	_set_state(State.LOOP_PAUSE)
	loop_finished.emit(last_rate, is_new_best)


func _set_state(new_state: State) -> void:
	state = new_state
	_state_start_usec = Time.get_ticks_usec()
	state_changed.emit(state)


func _state_elapsed() -> float:
	return (Time.get_ticks_usec() - _state_start_usec) / 1_000_000.0


func _time_at(usec: int) -> float:
	return (usec - _loop_start_usec) / 1_000_000.0 - lead_time


static func _is_game_event(event: InputEvent) -> bool:
	for action in InputConfig.GAME_ACTIONS:
		if event.is_action(action):
			return true
	return false


func _reset_best() -> void:
	best_score = -1.0
	best_score_changed.emit(best_score)


func _on_sequence_replaced() -> void:
	stop()
	_reset_best()


func _on_recording_state_changed(recording_state: SequenceRecorder.State) -> void:
	if recording_state == SequenceRecorder.State.RECORDING:
		_reset_best()
