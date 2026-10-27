class_name SequenceEditor
extends Node
## Frame-by-frame editing of SequenceManager's current sequence.
##
## The editor keeps a SequenceGrid and writes every change straight back to
## the current sequence (unsaved until the user saves). The highway shows the
## grid: the frame at the hit line is `view_frame`, and `span_frames` frames
## are visible up to the far end.
##
## Button cells cycle NONE -> PRESS -> HOLD on click; dragging after that
## paints HOLD (or NONE when clearing). Direction cells paint the current
## direction brush (or NEUTRAL when it is already there).

signal active_changed(active: bool)
signal brush_changed(direction: String)

const Cell := SequenceGrid.Cell
const NEUTRAL := SequenceInput.NEUTRAL
const MIN_SPAN := 15.0
const MAX_SPAN := 180.0
const DEFAULT_SPAN := 40.0
const UNDO_LIMIT := 200
## Numpad notation (facing-relative, like the directions themselves).
const NUMPAD_DIRECTIONS := {
	1: "DOWN_BACK", 2: "DOWN", 3: "DOWN_FORWARD",
	4: "BACK", 5: "NEUTRAL", 6: "FORWARD",
	7: "UP_BACK", 8: "UP", 9: "UP_FORWARD",
}

var active := false
var grid: SequenceGrid
var view_frame := 0
var span_frames := DEFAULT_SPAN
var brush := "FORWARD"

var _undo: Array[SequenceGrid] = []
var _redo: Array[SequenceGrid] = []
## Current mouse stroke: lane, value painted on the next frames, last frame.
var _stroke_lane := -1
var _stroke_value: Variant = null
var _stroke_frame := 0


func _ready() -> void:
	SequenceManager.sequence_replaced.connect(_on_sequence_replaced)
	InputConfig.mode_changed.connect(func(_mode: String) -> void: stop())


## Starts editing the current sequence, or a new empty one for the selected
## mode. Returns an error message, or "" on success.
func start() -> String:
	if active:
		return ""
	if SequenceManager.is_mode_mismatch():
		return "This sequence is for %s. Select that input mode to edit it." % InputMode.title(SequenceManager.current_sequence.mode)
	if SequenceManager.current_sequence == null:
		SequenceManager.new_sequence(InputConfig.active_mode)
	_load_grid()
	view_frame = 0
	active = true
	active_changed.emit(true)
	return ""


func stop() -> void:
	if not active:
		return
	end_stroke()
	active = false
	grid = null
	_undo.clear()
	_redo.clear()
	active_changed.emit(false)


func lane_ids() -> PackedStringArray:
	return InputMode.button_ids(grid.mode) if grid else PackedStringArray()


# --- View ---------------------------------------------------------------------

func scroll(frames: int) -> void:
	view_frame = maxi(0, view_frame + frames)


func go_to(frame: int) -> void:
	view_frame = maxi(0, frame)


## factor > 1 shows more frames.
func zoom(factor: float) -> void:
	span_frames = clampf(span_frames * factor, MIN_SPAN, MAX_SPAN)


func set_brush(direction: String) -> void:
	brush = direction
	brush_changed.emit(direction)


func set_brush_numpad(digit: int) -> void:
	if NUMPAD_DIRECTIONS.has(digit):
		set_brush(NUMPAD_DIRECTIONS[digit])


# --- Editing --------------------------------------------------------------------

## Starts a mouse stroke on a cell. `clear` is the right mouse button.
## Lane 0 is the direction lane, then the mode's buttons.
func begin_stroke(lane: int, frame: int, clear: bool) -> void:
	if not active or frame < 0:
		return
	_push_undo()
	_stroke_lane = lane
	_stroke_frame = frame
	if lane == 0:
		var current := grid.get_direction(frame)
		var value := NEUTRAL if clear or current == brush else brush
		grid.set_direction(frame, value)
		_stroke_value = value
	else:
		var id := lane_ids()[lane - 1]
		var value: int
		if clear:
			value = Cell.NONE
		else:
			value = (grid.get_cell(id, frame) + 1) % 3  # NONE -> PRESS -> HOLD -> NONE
		grid.set_cell(id, frame, value)
		# Dragging on from a press or hold extends it as a hold.
		_stroke_value = Cell.NONE if value == Cell.NONE else Cell.HOLD
	_commit()


## Continues the stroke to `frame`, filling every frame in between.
func continue_stroke(frame: int) -> void:
	if _stroke_lane < 0 or frame < 0 or frame == _stroke_frame:
		return
	var step := 1 if frame > _stroke_frame else -1
	var f := _stroke_frame + step
	while true:
		if _stroke_lane == 0:
			grid.set_direction(f, _stroke_value)
		else:
			grid.set_cell(lane_ids()[_stroke_lane - 1], f, _stroke_value)
		if f == frame:
			break
		f += step
	_stroke_frame = frame
	_commit()


func end_stroke() -> void:
	_stroke_lane = -1
	_stroke_value = null


func is_stroking() -> bool:
	return _stroke_lane >= 0


## Moves the end of the sequence to `frame` (it can't end before its last input).
func set_end(frame: int) -> void:
	if not active:
		return
	_push_undo()
	grid.end_frame = maxi(0, frame)
	_commit()


func undo() -> void:
	if not active or _undo.is_empty():
		return
	_redo.append(grid)
	grid = _undo.pop_back()
	_commit()


func redo() -> void:
	if not active or _redo.is_empty():
		return
	_undo.append(grid)
	grid = _redo.pop_back()
	_commit()


func _push_undo() -> void:
	_undo.append(grid.duplicate_grid())
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()


## Writes the grid back to the current sequence, keeping its name and author.
func _commit() -> void:
	var sequence := grid.to_sequence()
	var current := SequenceManager.current_sequence
	if current:
		sequence.name = current.name
		sequence.author = current.author
	SequenceManager.apply_edit(sequence)


func _load_grid() -> void:
	grid = SequenceGrid.from_sequence(SequenceManager.current_sequence)
	_undo.clear()
	_redo.clear()


## Another sequence was loaded or recorded while editing: edit that one instead.
func _on_sequence_replaced() -> void:
	if not active:
		return
	if SequenceManager.is_mode_mismatch() or SequenceManager.current_sequence == null:
		stop()
		return
	end_stroke()
	_load_grid()
	view_frame = 0
