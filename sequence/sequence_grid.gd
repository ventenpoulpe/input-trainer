class_name SequenceGrid
extends RefCounted
## A sequence as one row per frame (60 FPS), for frame-by-frame editing.
##
## Each frame has the direction held on it and, for each button of the mode,
## one cell: NONE (up), PRESS (pressed on this frame) or HOLD (still down from
## an earlier press). A HOLD right after NONE counts as a press.
##
## Converting back (to_sequence) creates an input on every frame where the
## direction changes or a button is pressed. A direction or button kept down
## for at least SequenceInput.HOLD_MIN_FRAMES frames becomes a hold input;
## shorter presses are plain taps (sequences don't store tap lengths).
##
## `end_frame` keeps the sequence length (it can run past the last input, e.g.
## to the release of a tap). The sequence never ends before its last input.

enum Cell { NONE, PRESS, HOLD }

const FPS := SequenceInput.FPS
const NEUTRAL := SequenceInput.NEUTRAL

var mode := InputMode.DEFAULT
var end_frame := 0
var directions := PackedStringArray()
## Button id -> PackedByteArray of Cell values, one per frame.
var cells := {}

## Button id -> PackedInt32Array: length of the down run each frame belongs to
## (0 when up). Rebuilt on demand after an edit.
var _run_lengths := {}


func _init(p_mode := InputMode.DEFAULT) -> void:
	mode = p_mode
	for id in InputMode.button_ids(mode):
		cells[id] = PackedByteArray()


static func from_sequence(sequence: InputSequence) -> SequenceGrid:
	var grid := SequenceGrid.new(sequence.mode)
	grid.end_frame = SequenceInput.time_to_frame(sequence.duration)
	var inputs := sequence.inputs
	var size := SequenceInput.time_to_frame(sequence.duration) + 1
	for input in inputs:
		size = maxi(size, SequenceInput.time_to_frame(input.get_end_time()) + 1)
	grid.ensure_frames(size)

	# A direction lasts until the next input. The last one lasts for its hold,
	# or until the end of the sequence (at least one frame).
	var end_frame := SequenceInput.time_to_frame(sequence.duration)
	for i in inputs.size():
		var input := inputs[i]
		var start := SequenceInput.time_to_frame(input.timestamp)
		var stop: int
		if i + 1 < inputs.size():
			stop = SequenceInput.time_to_frame(inputs[i + 1].timestamp)
		elif input.direction_hold > 0.0:
			stop = start + SequenceInput.time_to_frame(input.direction_hold)
		else:
			stop = maxi(end_frame, start + 1)
		grid.ensure_frames(stop + 1)
		for frame in range(start, stop):
			grid.directions[frame] = input.direction

	for input in inputs:
		var start := SequenceInput.time_to_frame(input.timestamp)
		for id in input.buttons:
			if not grid.cells.has(id):
				continue
			var length := maxi(1, SequenceInput.time_to_frame(input.get_button_hold(id)))
			grid.ensure_frames(start + length + 1)
			var column: PackedByteArray = grid.cells[id]
			column[start] = Cell.PRESS
			for frame in range(start + 1, start + length):
				if column[frame] == Cell.NONE:
					column[frame] = Cell.HOLD
			grid.cells[id] = column
	return grid


func to_sequence() -> InputSequence:
	var sequence := InputSequence.new()
	sequence.mode = mode
	var ids := InputMode.button_ids(mode)
	var previous := NEUTRAL
	var last_event := 0
	for frame in frame_count():
		var direction := directions[frame]
		var changed := direction != previous
		var pressed := PackedStringArray()
		for id in ids:
			if is_press(id, frame):
				pressed.append(id)
		if changed or not pressed.is_empty():
			var input := SequenceInput.new(frame / FPS, direction, pressed)
			input.frame = frame
			if changed:
				last_event = maxi(last_event, frame)
				if direction != NEUTRAL:
					var run := direction_run(frame)
					if run >= SequenceInput.HOLD_MIN_FRAMES:
						input.direction_hold = run / FPS
			for id in pressed:
				var length := run_length(id, frame)
				if length >= SequenceInput.HOLD_MIN_FRAMES:
					input.button_holds[id] = length / FPS
				last_event = maxi(last_event, frame + length)
			sequence.inputs.append(input)
		previous = direction
	# A direction still held on the last frame is released right after it.
	if previous != NEUTRAL:
		var release := SequenceInput.new(frame_count() / FPS, NEUTRAL)
		release.frame = frame_count()
		sequence.inputs.append(release)
		last_event = maxi(last_event, frame_count())
	sequence.duration = maxi(end_frame, last_event) / FPS
	return sequence


func duplicate_grid() -> SequenceGrid:
	var copy := SequenceGrid.new(mode)
	copy.end_frame = end_frame
	copy.directions = directions.duplicate()
	for id: String in cells:
		copy.cells[id] = (cells[id] as PackedByteArray).duplicate()
	return copy


func frame_count() -> int:
	return directions.size()


## Grows the grid to at least `count` frames (new frames are neutral and up).
func ensure_frames(count: int) -> void:
	var old := directions.size()
	if count <= old:
		return
	directions.resize(count)
	for frame in range(old, count):
		directions[frame] = NEUTRAL
	for id: String in cells:
		var column: PackedByteArray = cells[id]
		column.resize(count)  # new bytes are 0 = NONE
		cells[id] = column
	_run_lengths.clear()


# --- Reading ----------------------------------------------------------------

## Frames outside the grid are neutral.
func get_direction(frame: int) -> String:
	if frame < 0 or frame >= directions.size():
		return NEUTRAL
	return directions[frame]


func get_cell(id: String, frame: int) -> int:
	var column: PackedByteArray = cells[id]
	if frame < 0 or frame >= column.size():
		return Cell.NONE
	return column[frame]


## True if the button goes down on this frame.
func is_press(id: String, frame: int) -> bool:
	var cell := get_cell(id, frame)
	return cell == Cell.PRESS or (cell == Cell.HOLD and get_cell(id, frame - 1) == Cell.NONE)


## Frames the direction stays the same, starting at `frame`.
func direction_run(frame: int) -> int:
	var direction := get_direction(frame)
	var end := frame
	while end < directions.size() and directions[end] == direction:
		end += 1
	return end - frame


## Length of the down run (press + holds) that `frame` belongs to, 0 if up.
func run_length(id: String, frame: int) -> int:
	if frame < 0 or frame >= frame_count():
		return 0
	if not _run_lengths.has(id):
		_run_lengths[id] = _compute_runs(id)
	return (_run_lengths[id] as PackedInt32Array)[frame]


func _compute_runs(id: String) -> PackedInt32Array:
	var runs := PackedInt32Array()
	runs.resize(frame_count())
	var frame := 0
	while frame < frame_count():
		if get_cell(id, frame) == Cell.NONE:
			frame += 1
			continue
		var end := frame + 1
		while end < frame_count() and get_cell(id, end) == Cell.HOLD:
			end += 1
		for i in range(frame, end):
			runs[i] = end - frame
		frame = end
	return runs


# --- Editing ----------------------------------------------------------------

func set_cell(id: String, frame: int, cell: int) -> void:
	if frame < 0 or not cells.has(id):
		return
	ensure_frames(frame + 1)
	var column: PackedByteArray = cells[id]
	column[frame] = cell
	cells[id] = column
	_run_lengths.erase(id)


func set_direction(frame: int, direction: String) -> void:
	if frame < 0:
		return
	ensure_frames(frame + 1)
	directions[frame] = direction
