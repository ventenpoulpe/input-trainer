class_name Highway
extends Control
## Draws the perspective highway for a GameplayController: lanes,
## scrolling inputs and hold bars, the hit line with its receptors, and hit
## feedback (popup text, GPU spark particles, flashes).
##
## Everything is drawn in 2D with a simple perspective projection. Depth `u`
## runs from 0 at the hit line to 1 at the far end; negative is past the line.
##
## Lanes follow the selected input mode: the direction lane, then one lane per
## action button (VF: 4 lanes, SC2: 5, SF: 7).
##
## In edit mode (see SequenceEditor) the track shows one row per frame instead
## of the playing sequence, and the mouse edits cells and scrolls.

const DIRECTION_LANE := TimingJudge.DIRECTION_LANE
const Rating := TimingJudge.Rating
const HoldResult := TimingJudge.HoldResult
const PlayState := GameplayController.State

const DIRECTION_COLOR := Color(0.80, 0.85, 0.95)
## The track gets wider for modes with more than this many lanes.
const BASE_LANE_COUNT := 4
const RATING_COLORS := {
	Rating.PERFECT: Color(1.0, 0.88, 0.3),
	Rating.GREAT: Color(0.4, 1.0, 0.6),
	Rating.GOOD: Color(0.5, 0.8, 1.0),
	Rating.MISS: Color(1.0, 0.3, 0.3),
}
const HOLD_OK_COLOR := Color(0.5, 1.0, 0.9)
const MISSED_COLOR := Color(0.4, 0.4, 0.45)
## Screen angle of each direction's arrow when facing right (FORWARD = right).
const DIRECTION_ANGLES := {
	"FORWARD": 0.0,
	"DOWN_FORWARD": PI / 4.0,
	"DOWN": PI / 2.0,
	"DOWN_BACK": 3.0 * PI / 4.0,
	"BACK": PI,
	"UP_BACK": -3.0 * PI / 4.0,
	"UP": -PI / 2.0,
	"UP_FORWARD": -PI / 4.0,
}
## Arrow pointing right, in units of the arrow size.
const ARROW := [
	Vector2(-0.5, -0.17), Vector2(0.08, -0.17), Vector2(0.08, -0.42), Vector2(0.55, 0.0),
	Vector2(0.08, 0.42), Vector2(0.08, 0.17), Vector2(-0.5, 0.17),
]

## Highway width at the far end compared to the hit line.
const FAR_SCALE := 0.3
const TOP_MARGIN := 64.0  # room for the lane headers
const BRUSH_HINT := "Click to pick a direction →"
const BOTTOM_MARGIN := 48.0  # track continues below the hit line
const TILE_DEPTH := 0.045
## Hold bar width as a fraction of the lane width.
const HOLD_BAR_WIDTH := 0.4
const GRID_STEP := 0.25  # seconds between moving grid lines
const FLASH_TIME := 0.25
const EDIT_CELL := SequenceGrid.Cell
const END_COLOR := Color(1.0, 0.6, 0.2)

var controller: GameplayController
var editor: SequenceEditor

## Lanes of the selected mode; index 0 is the direction lane.
var _lane_count := 1
var _lane_colors: Array[Color] = [DIRECTION_COLOR]
var _lane_ids := PackedStringArray([""])
var _center_x := 0.0
var _half_width := 0.0
var _hit_y := 0.0
var _horizon_y := 0.0
var _bottom_u := -0.1
## One-shot burst per lane on hits, and a continuous stream while holding
## (created for the widest mode, so switching modes needs no new nodes).
var _burst_particles: Array[GPUParticles2D] = []
var _hold_particles: Array[GPUParticles2D] = []
var _flashes: Array[Dictionary] = []  # {lane, color, time_left}
## Latest popup per lane; a new one replaces it so they don't pile up.
var _popups: Array[Label] = []
var _ring := CountdownRing.new()
var _pause_text := ""
## Edit mode: cell under the mouse (lane, frame), or (-1, -1).
var _hover := Vector2i(-1, -1)
var _brush_menu := PopupMenu.new()


func _ready() -> void:
	clip_contents = true
	var spark_texture := _make_spark_texture()
	for lane in InputMode.max_lane_count():
		_burst_particles.append(_make_particles(spark_texture, true))
		_hold_particles.append(_make_particles(spark_texture, false))
		_popups.append(null)
	add_child(_ring)
	_ring.hide()
	for digit in [7, 8, 9, 4, 5, 6, 1, 2, 3]:
		_brush_menu.add_item("%d   %s" % [digit, SequenceEditor.NUMPAD_DIRECTIONS[digit]], digit)
	_brush_menu.id_pressed.connect(func(digit: int) -> void: editor.set_brush_numpad(digit))
	add_child(_brush_menu)
	InputConfig.mode_changed.connect(_setup_lanes)
	_setup_lanes(InputConfig.active_mode)


func _setup_lanes(mode: String) -> void:
	_lane_colors = [DIRECTION_COLOR]
	_lane_ids = PackedStringArray([""])
	for button: Dictionary in InputMode.buttons(mode):
		_lane_colors.append(button.color)
		_lane_ids.append(button.id)
	_lane_count = _lane_colors.size()
	_flashes.clear()
	for popup in _popups:
		if is_instance_valid(popup):
			popup.queue_free()
	queue_redraw()


func setup(p_controller: GameplayController, p_editor: SequenceEditor) -> void:
	editor = p_editor
	editor.active_changed.connect(_on_edit_active_changed)
	controller = p_controller
	controller.input_judged.connect(_on_input_judged)
	controller.hold_finished.connect(_on_hold_finished)
	controller.extra_press.connect(_on_extra_press)
	controller.loop_finished.connect(_on_loop_finished)


func _process(delta: float) -> void:
	for flash in _flashes:
		flash.time_left -= delta
	_flashes = _flashes.filter(func(flash: Dictionary) -> bool: return flash.time_left > 0.0)

	var playing := controller != null and controller.state == PlayState.PLAYING
	for lane in _hold_particles.size():
		var stream := _hold_particles[lane]
		var holding := playing and lane < _lane_count and controller.judge.is_holding(lane)
		if holding:
			stream.position = _project(_lane_center(lane), 0.0)
		if stream.emitting != holding:
			stream.emitting = holding

	var counting := controller != null and controller.state == PlayState.COUNTDOWN and not _editing()
	_ring.visible = counting
	if counting:
		_ring.progress = controller.get_phase_progress()
		_ring.position = (size - _ring.size) / 2.0
	queue_redraw()


# --- Projection ----------------------------------------------------------------

func _update_geometry() -> void:
	_hit_y = size.y - BOTTOM_MARGIN
	var lane_factor := maxf(1.0, float(_lane_count) / BASE_LANE_COUNT)
	# Edit mode leaves room on the left for the frame numbers.
	var max_half := size.x * 0.5 - (60.0 if _editing() else size.x * 0.02)
	_half_width = minf(max_half, (_hit_y - TOP_MARGIN) * 0.75 * lane_factor)
	_center_x = size.x / 2.0
	_horizon_y = (TOP_MARGIN - _hit_y * FAR_SCALE) / (1.0 - FAR_SCALE)
	# Depth at the bottom edge of the control.
	var bottom_scale := (size.y - _horizon_y) / (_hit_y - _horizon_y)
	_bottom_u = (1.0 / bottom_scale - 1.0) / (1.0 / FAR_SCALE - 1.0)


func _scale(u: float) -> float:
	return 1.0 / (1.0 + u * (1.0 / FAR_SCALE - 1.0))


## `x` runs from -1 (left edge) to 1 (right edge) of the highway.
func _project(x: float, u: float) -> Vector2:
	var s := _scale(u)
	return Vector2(_center_x + x * _half_width * s, _horizon_y + (_hit_y - _horizon_y) * s)


func _quad(x0: float, x1: float, u0: float, u1: float) -> PackedVector2Array:
	return PackedVector2Array([_project(x0, u0), _project(x1, u0), _project(x1, u1), _project(x0, u1)])


func _lane_edge(index: int) -> float:
	return index * 2.0 / _lane_count - 1.0


func _lane_center(lane: int) -> float:
	return _lane_edge(lane) + 1.0 / _lane_count


func _receptor_radius() -> float:
	return _half_width / _lane_count * 0.42


## Inputs fade in over the last part of the track.
static func _far_fade(u: float) -> float:
	return clampf((1.0 - u) / 0.12, 0.0, 1.0)


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	_update_geometry()
	if _hit_y - TOP_MARGIN < 40.0:
		return
	if _editing():
		_draw_track()
		_draw_editor()
		_draw_headers()
		return
	_draw_track()
	if controller and controller.state == PlayState.PLAYING:
		_draw_inputs(controller.get_time())
	_draw_hit_line()
	_draw_receptors()
	_draw_headers()
	_draw_message()


func _draw_track() -> void:
	draw_colored_polygon(_quad(-1.0, 1.0, _bottom_u, 1.0), Color(0.09, 0.1, 0.14))
	for lane in _lane_count:
		draw_colored_polygon(_quad(_lane_edge(lane), _lane_edge(lane + 1), _bottom_u, 1.0), Color(_lane_colors[lane], 0.05))
	for i in _lane_count + 1:
		var outer := i == 0 or i == _lane_count
		draw_line(_project(_lane_edge(i), _bottom_u), _project(_lane_edge(i), 1.0), Color(1, 1, 1, 0.3 if outer else 0.12), 3.0 if outer else 1.5, true)

	# Moving grid lines (every 0.25 s, brighter every second) show the speed.
	if controller and controller.state == PlayState.PLAYING:
		var time := controller.get_time()
		var step := ceili((time + _bottom_u * controller.lead_time) / GRID_STEP)
		while true:
			var u := (step * GRID_STEP - time) / controller.lead_time
			if u > 1.0:
				break
			var alpha := 0.12 if step % 4 == 0 else 0.04
			draw_line(_project(-1.0, u), _project(1.0, u), Color(1, 1, 1, alpha), 1.0)
			step += 1


func _draw_inputs(time: float) -> void:
	var targets := controller.judge.targets
	# Latest first, so nearer inputs are drawn on top.
	for i in range(targets.size() - 1, -1, -1):
		var target := targets[i]
		var u := (target.time - time) / controller.lead_time
		var tail_u := (target.end_time() - time) / controller.lead_time
		if u > 1.0 + TILE_DEPTH or tail_u < _bottom_u - TILE_DEPTH:
			continue
		if target.is_hold():
			_draw_hold_bar(target, u, tail_u)
		var hit := target.is_judged() and target.rating != Rating.MISS
		if not hit:
			_draw_input(target, u)


func _draw_hold_bar(target: TimingJudge.Target, u: float, tail_u: float) -> void:
	var color: Color = _lane_colors[target.lane]
	var start_u := u
	if target.holding:
		# Being held: the bar is eaten up at the hit line and glows.
		start_u = 0.0
		color = color.lightened(0.35)
	elif target.hold_result == HoldResult.OK:
		return
	elif target.hold_result == HoldResult.DROPPED:
		color = MISSED_COLOR
	color.a = 0.85 if target.holding else 0.5

	var u0 := maxf(start_u, _bottom_u)
	var u1 := minf(tail_u, 1.0)
	if u1 <= u0:
		return
	var half := HOLD_BAR_WIDTH / _lane_count
	var center := _lane_center(target.lane)
	var points := _quad(center - half, center + half, u0, u1)
	var near := Color(color, color.a * _far_fade(u0))
	var far := Color(color, color.a * _far_fade(u1))
	draw_polygon(points, PackedColorArray([near, near, far, far]))
	# End cap.
	if tail_u <= 1.0:
		draw_line(points[3], points[2], Color(color, far.a * 1.5), 3.0)


func _draw_input(target: TimingJudge.Target, u: float) -> void:
	var missed := target.rating == Rating.MISS
	var color: Color = MISSED_COLOR if missed else _lane_colors[target.lane]
	color.a = _far_fade(u) * (0.6 if missed else 1.0)

	var pad := 0.05
	var x0 := _lane_edge(target.lane) + pad
	var x1 := _lane_edge(target.lane + 1) - pad
	var quad := _quad(x0, x1, u - TILE_DEPTH / 2.0, u + TILE_DEPTH / 2.0)

	if target.lane == DIRECTION_LANE:
		draw_colored_polygon(quad, Color(0.14, 0.15, 0.2, color.a))
		var outline := quad.duplicate()
		outline.append(quad[0])
		draw_polyline(outline, color, 2.0, true)
		var width := _project(x1, u).x - _project(x0, u).x
		var height := quad[0].y - quad[3].y
		_draw_arrow(_project((x0 + x1) / 2.0, u), minf(width * 0.5, height * 1.3), target.direction, color)
	else:
		draw_colored_polygon(quad, color)
		draw_line(quad[3], quad[2], Color(color.lightened(0.5), color.a), 2.0)


## Arrows show the physical direction to press, so they flip on the P2 side.
func _draw_arrow(center: Vector2, arrow_size: float, direction: String, color: Color) -> void:
	var angle: float = DIRECTION_ANGLES.get(direction, 0.0)
	if not SequenceManager.facing_right:
		angle = PI - angle
	var points := PackedVector2Array()
	for point: Vector2 in ARROW:
		points.append(center + point.rotated(angle) * arrow_size)
	draw_colored_polygon(points, color)


func _draw_hit_line() -> void:
	draw_colored_polygon(_quad(-1.0, 1.0, -0.02, 0.02), Color(1, 1, 1, 0.1))
	draw_line(_project(-1.0, 0.0), _project(1.0, 0.0), Color(1, 1, 1, 0.5), 3.0)


func _draw_receptors() -> void:
	var direction := SequenceManager.read_direction()
	var held := SequenceManager.read_held_buttons()
	var radius := _receptor_radius()
	var font := get_theme_default_font()
	var playing := controller != null and controller.state == PlayState.PLAYING
	for lane in _lane_count:
		var center := _project(_lane_center(lane), 0.0)
		var color: Color = _lane_colors[lane]
		var pressed := direction != SequenceInput.NEUTRAL if lane == DIRECTION_LANE else held.has(_lane_ids[lane])
		if playing and controller.judge.is_holding(lane):
			# Pulsing glow while a hold is being kept.
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 60.0)
			draw_circle(center, radius * (1.15 + 0.1 * pulse), Color(color, 0.25 + 0.2 * pulse))
		draw_circle(center, radius, Color(color, 0.55 if pressed else 0.12))
		draw_arc(center, radius, 0.0, TAU, 48, color, 3.0, true)
		if lane == DIRECTION_LANE:
			if pressed:
				_draw_arrow(center, radius * 1.3, direction, Color.WHITE)
		else:
			var text := _lane_ids[lane]
			var font_size := int(radius * (0.9 if text.length() == 1 else 0.6))
			var at := Vector2(center.x - radius, center.y + font_size * 0.35)
			# Outlined so it stays readable on light lanes.
			draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, 4, Color(0, 0, 0, 0.5))
			draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, Color(1, 1, 1, 0.85))

	for flash in _flashes:
		var t: float = flash.time_left / FLASH_TIME
		var center := _project(_lane_center(flash.lane), 0.0)
		draw_arc(center, radius * (1.0 + (1.0 - t) * 0.9), 0.0, TAU, 48, Color(flash.color, t), 4.0, true)


func _draw_headers() -> void:
	var font := get_theme_default_font()
	var y := TOP_MARGIN - 30.0
	for lane in _lane_count:
		var center := Vector2(_project(_lane_center(lane), 1.0).x, y)
		var color: Color = _lane_colors[lane]
		if lane == DIRECTION_LANE:
			_draw_joystick_icon(center, color)
			if _editing():
				_draw_brush_hint(font, center)
		else:
			var text := _lane_ids[lane]
			var font_size := 20 if text.length() == 1 else 14
			draw_circle(center, 16.0, color)
			draw_string(font, Vector2(center.x - 16.0, center.y + font_size * 0.35), text,
					HORIZONTAL_ALIGNMENT_CENTER, 32.0, font_size, Color(0.05, 0.05, 0.08))


## Edit mode: tells users the joystick icon opens the direction brush menu.
## Drawn to its left, since the direction lane is always the leftmost one.
func _draw_brush_hint(font: Font, icon_center: Vector2) -> void:
	var width := icon_center.x - 28.0
	if width <= 0.0:
		return
	var font_size := 15
	var at := Vector2(0.0, icon_center.y + font_size * 0.35)
	draw_string_outline(font, at, BRUSH_HINT, HORIZONTAL_ALIGNMENT_RIGHT, width, font_size, 4, Color(0, 0, 0, 0.5))
	draw_string(font, at, BRUSH_HINT, HORIZONTAL_ALIGNMENT_RIGHT, width, font_size, Color(1, 1, 1, 0.7))


func _draw_joystick_icon(center: Vector2, color: Color) -> void:
	var base := PackedVector2Array([
		center + Vector2(-16, 16), center + Vector2(16, 16), center + Vector2(12, 8), center + Vector2(-12, 8),
	])
	draw_colored_polygon(base, color.darkened(0.3))
	draw_line(center + Vector2(0, 9), center + Vector2(0, -6), color, 4.0)
	draw_circle(center + Vector2(0, -10), 7.0, Color(1.0, 0.3, 0.3))


func _draw_message() -> void:
	var text := ""
	if controller == null or controller.state == PlayState.STOPPED:
		if SequenceManager.current_sequence == null:
			text = "Load or record a sequence"
		elif SequenceManager.is_mode_mismatch():
			text = "This sequence is for %s" % InputMode.title(SequenceManager.current_sequence.mode)
		else:
			text = "Press Play (%s) to practice" % InputConfig.get_shortcut_text(&"app_play_toggle")
	elif controller.state == PlayState.LOOP_PAUSE:
		text = _pause_text
	if text:
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, size.y * 0.42), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1, 1, 1, 0.85))


# --- Edit mode -------------------------------------------------------------------

func _editing() -> bool:
	return editor != null and editor.active


func _on_edit_active_changed(is_active: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if is_active else Control.MOUSE_FILTER_IGNORE
	_hover = Vector2i(-1, -1)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not _editing():
		return
	var button := event as InputEventMouseButton
	if button:
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var up := button.button_index == MOUSE_BUTTON_WHEEL_UP
			if button.ctrl_pressed:
				editor.zoom(0.85 if up else 1.0 / 0.85)
			else:
				editor.scroll((1 if up else -1) * (10 if button.shift_pressed else 1))
			_hover = _cell_at(button.position)
			accept_event()
		elif button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if button.pressed:
				if button.button_index == MOUSE_BUTTON_LEFT and _is_on_direction_header(button.position):
					_brush_menu.popup(Rect2i(Vector2i(global_position + button.position), Vector2i.ZERO))
				else:
					var cell := _cell_at(button.position)
					if cell.x >= 0:
						editor.begin_stroke(cell.x, cell.y, button.button_index == MOUSE_BUTTON_RIGHT)
			else:
				editor.end_stroke()
			accept_event()
	var motion := event as InputEventMouseMotion
	if motion:
		_hover = _cell_at(motion.position)
		if editor.is_stroking():
			var frame := _frame_at(motion.position.y)
			if frame >= 0:
				editor.continue_stroke(frame)


## Frame of the row at screen height `y`, or -1 outside the track.
func _frame_at(y: float) -> int:
	var depth := _depth_at(y)
	if is_nan(depth):
		return -1
	return maxi(-1, roundi(editor.view_frame + depth * editor.span_frames))


## Track depth `u` at screen height `y` (NAN above the far end).
func _depth_at(y: float) -> float:
	var s := (y - _horizon_y) / (_hit_y - _horizon_y)
	if s <= 0.0:
		return NAN
	var u := (1.0 / s - 1.0) / (1.0 / FAR_SCALE - 1.0)
	if u > 1.0:
		return NAN
	return maxf(u, _bottom_u)


## (lane, frame) of the cell at `pos`, or (-1, -1).
func _cell_at(pos: Vector2) -> Vector2i:
	var depth := _depth_at(pos.y)
	if is_nan(depth):
		return Vector2i(-1, -1)
	var x := (pos.x - _center_x) / (_half_width * _scale(depth))
	if x < -1.0 or x >= 1.0:
		return Vector2i(-1, -1)
	var frame := roundi(editor.view_frame + depth * editor.span_frames)
	if frame < 0:
		return Vector2i(-1, -1)
	return Vector2i(int((x + 1.0) / 2.0 * _lane_count), frame)


func _is_on_direction_header(pos: Vector2) -> bool:
	var center := Vector2(_project(_lane_center(DIRECTION_LANE), 1.0).x, TOP_MARGIN - 30.0)
	return pos.distance_to(center) < 22.0


## Row edges of `frame` as track depths.
func _row_depths(frame: int) -> Vector2:
	var view := float(editor.view_frame)
	return Vector2((frame - view - 0.5) / editor.span_frames, (frame - view + 0.5) / editor.span_frames)


func _draw_editor() -> void:
	var grid := editor.grid
	var view := editor.view_frame
	var span := editor.span_frames
	var font := get_theme_default_font()
	var first := maxi(0, floori(view + _bottom_u * span))
	var last := ceili(view + span)
	var ids := editor.lane_ids()
	var end_frame := SequenceInput.time_to_frame(SequenceManager.current_sequence.duration) if SequenceManager.current_sequence else 0

	for frame in range(first, last + 1):
		var depths := _row_depths(frame)
		var u0 := maxf(depths.x, _bottom_u)
		var u1 := minf(depths.y, 1.0)
		if u1 <= u0:
			continue
		var fade := _far_fade(u0)
		var row_height := _project(0.0, u0).y - _project(0.0, u1).y

		# Row lines: every frame when there is room, brighter every 10 frames.
		if frame % 10 == 0:
			draw_line(_project(-1.0, u0), _project(1.0, u0), Color(1, 1, 1, 0.22 * fade), 1.0)
			if row_height * 10.0 > 18.0 and u1 < 0.93:
				var at := _project(-1.0, (u0 + u1) / 2.0)
				draw_string(font, Vector2(at.x - 60.0, at.y + 5.0), str(frame), HORIZONTAL_ALIGNMENT_RIGHT, 50.0, 13, Color(1, 1, 1, 0.5 * fade))
		elif row_height > 5.0:
			draw_line(_project(-1.0, u0), _project(1.0, u0), Color(1, 1, 1, 0.06 * fade), 1.0)

		# Direction lane.
		var direction := grid.get_direction(frame)
		if direction != SequenceInput.NEUTRAL:
			var color := Color(DIRECTION_COLOR, fade)
			if direction != grid.get_direction(frame - 1):
				var quad := _cell_quad(DIRECTION_LANE, u0, u1, 0.05)
				draw_colored_polygon(quad, Color(0.14, 0.15, 0.2, fade))
				var outline := quad.duplicate()
				outline.append(quad[0])
				draw_polyline(outline, color, 2.0, true)
				var width := quad[1].x - quad[0].x
				_draw_arrow((quad[0] + quad[2]) / 2.0, minf(width * 0.45, row_height * 0.9), direction, color)
			else:
				_draw_hold_cell(DIRECTION_LANE, u0, u1, Color(color, 0.35 * fade), grid.direction_run(_direction_start(frame)) >= SequenceInput.HOLD_MIN_FRAMES)

		# Button lanes.
		for i in ids.size():
			var id := ids[i]
			var lane := i + 1
			var cell := grid.get_cell(id, frame)
			if cell == EDIT_CELL.NONE:
				continue
			var color: Color = _lane_colors[lane]
			if grid.is_press(id, frame):
				var quad := _cell_quad(lane, u0, u1, 0.05)
				draw_colored_polygon(quad, Color(color, fade))
				draw_line(quad[3], quad[2], Color(color.lightened(0.5), fade), 2.0)
			else:
				_draw_hold_cell(lane, u0, u1, Color(color, 0.6 * fade), grid.run_length(id, frame) >= SequenceInput.HOLD_MIN_FRAMES)

	# End of the sequence.
	var end_depths := _row_depths(end_frame)
	if end_depths.x >= _bottom_u and end_depths.x <= 1.0:
		draw_line(_project(-1.0, end_depths.x), _project(1.0, end_depths.x), END_COLOR, 2.0)
		var at := _project(1.0, end_depths.x)
		draw_string(font, Vector2(at.x + 8.0, at.y + 5.0), "END", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, END_COLOR)

	# Cursor row (the hit line) and hovered cell.
	var cursor := _row_depths(view)
	draw_polyline(_closed(_quad(-1.0, 1.0, maxf(cursor.x, _bottom_u), cursor.y)), Color(1, 1, 1, 0.7), 2.0, true)
	if _hover.x >= 0:
		var hover := _row_depths(_hover.y)
		if hover.y > _bottom_u and hover.x < 1.0:
			var quad := _cell_quad(_hover.x, maxf(hover.x, _bottom_u), minf(hover.y, 1.0), 0.0)
			draw_polyline(_closed(quad), Color(1, 0.9, 0.4, 0.9), 2.0, true)


## A narrow bar for a held cell. Holds too short to count are drawn dimmer.
func _draw_hold_cell(lane: int, u0: float, u1: float, color: Color, long_enough: bool) -> void:
	if not long_enough:
		color.a *= 0.45
	var half := HOLD_BAR_WIDTH / _lane_count
	var center := _lane_center(lane)
	draw_colored_polygon(_quad(center - half, center + half, u0, u1), color)


func _cell_quad(lane: int, u0: float, u1: float, pad: float) -> PackedVector2Array:
	return _quad(_lane_edge(lane) + pad, _lane_edge(lane + 1) - pad, u0, u1)


func _direction_start(frame: int) -> int:
	var grid := editor.grid
	var direction := grid.get_direction(frame)
	while frame > 0 and grid.get_direction(frame - 1) == direction:
		frame -= 1
	return frame


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	closed.append(points[0])
	return closed


# --- Feedback --------------------------------------------------------------------

func _on_input_judged(target: TimingJudge.Target) -> void:
	var rating: Rating = target.rating
	var text: String = TimingJudge.RATING_TEXT[rating]
	if rating != Rating.MISS:
		# Frames early (-) or late (+).
		var frames := roundi(target.offset * 60.0)
		if frames != 0:
			text += "\n%+df" % frames
		_burst(target.lane, RATING_COLORS[rating])
	_popup(target.lane, text, RATING_COLORS[rating])


func _on_hold_finished(target: TimingJudge.Target) -> void:
	if target.hold_result == HoldResult.OK:
		_burst(target.lane, HOLD_OK_COLOR)
		_popup(target.lane, "HOLD OK", HOLD_OK_COLOR)
	else:
		_popup(target.lane, "DROP", RATING_COLORS[Rating.MISS])


func _on_extra_press(lane: int) -> void:
	_popup(lane, "EXTRA", Color(0.7, 0.7, 0.75))


func _on_loop_finished(rate: float, is_new_best: bool) -> void:
	_pause_text = "LOOP %d: %.1f%%" % [controller.loop_number, rate]
	if is_new_best:
		_pause_text += "   NEW BEST!"


func _popup(lane: int, text: String, color: Color) -> void:
	if is_instance_valid(_popups[lane]):
		_popups[lane].queue_free()
	var at := _project(_lane_center(lane), 0.0)
	var label := Label.new()
	_popups[lane] = label
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 24)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.size = label.get_combined_minimum_size()
	label.pivot_offset = label.size / 2.0
	label.position = at - Vector2(label.size.x / 2.0, label.size.y + _receptor_radius() + 6.0)
	label.scale = Vector2.ONE * 1.3

	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, ^"scale", Vector2.ONE, 0.12)
	tween.tween_property(label, ^"position:y", label.position.y - 50.0, 0.6) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, ^"modulate:a", 0.0, 0.35).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


func _burst(lane: int, color: Color) -> void:
	var particles := _burst_particles[lane]
	particles.position = _project(_lane_center(lane), 0.0)
	(particles.process_material as ParticleProcessMaterial).color = color
	particles.restart()
	particles.emitting = true
	_flashes.append({"lane": lane, "color": color, "time_left": FLASH_TIME})


func _make_particles(texture: Texture2D, burst: bool) -> GPUParticles2D:
	var process := ParticleProcessMaterial.new()
	process.particle_flag_disable_z = true
	process.direction = Vector3(0, -1, 0)
	process.spread = 80.0 if burst else 35.0
	process.initial_velocity_min = 220.0 if burst else 120.0
	process.initial_velocity_max = 520.0 if burst else 280.0
	process.gravity = Vector3(0, 800, 0)
	process.scale_min = 0.25
	process.scale_max = 0.6 if burst else 0.4
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture

	var particles := GPUParticles2D.new()
	particles.process_material = process
	particles.texture = texture
	particles.amount = 40 if burst else 24
	particles.lifetime = 0.55 if burst else 0.35
	particles.one_shot = burst
	particles.explosiveness = 0.95 if burst else 0.0
	particles.fixed_fps = 60
	particles.emitting = false
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	particles.material = additive
	add_child(particles)
	return particles


## Soft round dot used for every spark.
static func _make_spark_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture
