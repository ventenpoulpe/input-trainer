class_name Highway
extends Control
## Draws the 4-lane perspective highway for a GameplayController: lanes,
## scrolling notes and hold bars, the hit line with its receptors, and hit
## feedback (popup text, GPU spark particles, flashes).
##
## Everything is drawn in 2D with a simple perspective projection. Depth `u`
## runs from 0 at the hit line to 1 at the far end; negative is past the line.

const Lane := TimingJudge.Lane
const Rating := TimingJudge.Rating
const HoldResult := TimingJudge.HoldResult
const PlayState := GameplayController.State

const LANE_COUNT := 4
## Direction, G, P, K.
const LANE_COLORS := [
	Color(0.80, 0.85, 0.95),
	Color(0.20, 0.85, 0.40),
	Color(0.25, 0.55, 1.00),
	Color(1.00, 0.45, 0.20),
]
const LANE_LETTERS := ["", "G", "P", "K"]
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
const BOTTOM_MARGIN := 48.0  # track continues below the hit line
const TILE_DEPTH := 0.045
## Hold bar width as a fraction of the lane width.
const HOLD_BAR_WIDTH := 0.4
const GRID_STEP := 0.25  # seconds between moving grid lines
const FLASH_TIME := 0.25

var controller: GameplayController

var _center_x := 0.0
var _half_width := 0.0
var _hit_y := 0.0
var _horizon_y := 0.0
var _bottom_u := -0.1
## One-shot burst per lane on hits, and a continuous stream while holding.
var _burst_particles: Array[GPUParticles2D] = []
var _hold_particles: Array[GPUParticles2D] = []
var _flashes: Array[Dictionary] = []  # {lane, color, time_left}
## Latest popup per lane; a new one replaces it so they don't pile up.
var _popups: Array[Label] = [null, null, null, null]
var _ring := CountdownRing.new()
var _pause_text := ""


func _ready() -> void:
	clip_contents = true
	var spark_texture := _make_spark_texture()
	for lane in LANE_COUNT:
		_burst_particles.append(_make_particles(spark_texture, true))
		_hold_particles.append(_make_particles(spark_texture, false))
	add_child(_ring)
	_ring.hide()


func setup(p_controller: GameplayController) -> void:
	controller = p_controller
	controller.note_judged.connect(_on_note_judged)
	controller.hold_finished.connect(_on_hold_finished)
	controller.extra_press.connect(_on_extra_press)
	controller.loop_finished.connect(_on_loop_finished)


func _process(delta: float) -> void:
	for flash in _flashes:
		flash.time_left -= delta
	_flashes = _flashes.filter(func(flash: Dictionary) -> bool: return flash.time_left > 0.0)

	var playing := controller != null and controller.state == PlayState.PLAYING
	for lane in LANE_COUNT:
		var stream := _hold_particles[lane]
		var holding := playing and controller.judge.is_holding(lane)
		if holding:
			stream.position = _project(_lane_center(lane), 0.0)
		if stream.emitting != holding:
			stream.emitting = holding

	var counting := controller != null and controller.state == PlayState.COUNTDOWN
	_ring.visible = counting
	if counting:
		_ring.progress = controller.get_phase_progress()
		_ring.position = (size - _ring.size) / 2.0
	queue_redraw()


# --- Projection ----------------------------------------------------------------

func _update_geometry() -> void:
	_hit_y = size.y - BOTTOM_MARGIN
	_half_width = minf(size.x * 0.48, (_hit_y - TOP_MARGIN) * 0.75)
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


static func _lane_edge(index: int) -> float:
	return index * 2.0 / LANE_COUNT - 1.0


static func _lane_center(lane: int) -> float:
	return _lane_edge(lane) + 1.0 / LANE_COUNT


func _receptor_radius() -> float:
	return _half_width / LANE_COUNT * 0.42


## Notes fade in over the last part of the track.
static func _far_fade(u: float) -> float:
	return clampf((1.0 - u) / 0.12, 0.0, 1.0)


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	_update_geometry()
	if _hit_y - TOP_MARGIN < 40.0:
		return
	_draw_track()
	if controller and controller.state == PlayState.PLAYING:
		_draw_notes(controller.get_time())
	_draw_hit_line()
	_draw_receptors()
	_draw_headers()
	_draw_message()


func _draw_track() -> void:
	draw_colored_polygon(_quad(-1.0, 1.0, _bottom_u, 1.0), Color(0.09, 0.1, 0.14))
	for lane in LANE_COUNT:
		draw_colored_polygon(_quad(_lane_edge(lane), _lane_edge(lane + 1), _bottom_u, 1.0), Color(LANE_COLORS[lane], 0.05))
	for i in LANE_COUNT + 1:
		var outer := i == 0 or i == LANE_COUNT
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


func _draw_notes(time: float) -> void:
	var targets := controller.judge.targets
	# Latest first, so nearer notes are drawn on top.
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
			_draw_note(target, u)


func _draw_hold_bar(target: TimingJudge.Target, u: float, tail_u: float) -> void:
	var color: Color = LANE_COLORS[target.lane]
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
	var half := HOLD_BAR_WIDTH / LANE_COUNT
	var center := _lane_center(target.lane)
	var points := _quad(center - half, center + half, u0, u1)
	var near := Color(color, color.a * _far_fade(u0))
	var far := Color(color, color.a * _far_fade(u1))
	draw_polygon(points, PackedColorArray([near, near, far, far]))
	# End cap.
	if tail_u <= 1.0:
		draw_line(points[3], points[2], Color(color, far.a * 1.5), 3.0)


func _draw_note(target: TimingJudge.Target, u: float) -> void:
	var missed := target.rating == Rating.MISS
	var color: Color = MISSED_COLOR if missed else LANE_COLORS[target.lane]
	color.a = _far_fade(u) * (0.6 if missed else 1.0)

	var pad := 0.05
	var x0 := _lane_edge(target.lane) + pad
	var x1 := _lane_edge(target.lane + 1) - pad
	var quad := _quad(x0, x1, u - TILE_DEPTH / 2.0, u + TILE_DEPTH / 2.0)

	if target.lane == Lane.DIRECTION:
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
	for lane in LANE_COUNT:
		var center := _project(_lane_center(lane), 0.0)
		var color: Color = LANE_COLORS[lane]
		var pressed := direction != InputNote.NEUTRAL if lane == Lane.DIRECTION else held.has(LANE_LETTERS[lane])
		if playing and controller.judge.is_holding(lane):
			# Pulsing glow while a hold is being kept.
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 60.0)
			draw_circle(center, radius * (1.15 + 0.1 * pulse), Color(color, 0.25 + 0.2 * pulse))
		draw_circle(center, radius, Color(color, 0.55 if pressed else 0.12))
		draw_arc(center, radius, 0.0, TAU, 48, color, 3.0, true)
		if lane == Lane.DIRECTION:
			if pressed:
				_draw_arrow(center, radius * 1.3, direction, Color.WHITE)
		else:
			var font_size := int(radius * 0.9)
			draw_string(font, Vector2(center.x - radius, center.y + font_size * 0.35), LANE_LETTERS[lane],
					HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, Color(1, 1, 1, 0.8))

	for flash in _flashes:
		var t: float = flash.time_left / FLASH_TIME
		var center := _project(_lane_center(flash.lane), 0.0)
		draw_arc(center, radius * (1.0 + (1.0 - t) * 0.9), 0.0, TAU, 48, Color(flash.color, t), 4.0, true)


func _draw_headers() -> void:
	var font := get_theme_default_font()
	var y := TOP_MARGIN - 30.0
	for lane in LANE_COUNT:
		var center := Vector2(_project(_lane_center(lane), 1.0).x, y)
		var color: Color = LANE_COLORS[lane]
		if lane == Lane.DIRECTION:
			_draw_joystick_icon(center, color)
		else:
			draw_circle(center, 16.0, color)
			draw_string(font, Vector2(center.x - 16.0, center.y + 7.0), LANE_LETTERS[lane],
					HORIZONTAL_ALIGNMENT_CENTER, 32.0, 20, Color(0.05, 0.05, 0.08))


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
		else:
			text = "Press PLAY (Space / L3) to practice"
	elif controller.state == PlayState.LOOP_PAUSE:
		text = _pause_text
	if text:
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, size.y * 0.42), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1, 1, 1, 0.85))


# --- Feedback --------------------------------------------------------------------

func _on_note_judged(target: TimingJudge.Target) -> void:
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


func _on_extra_press(lane: Lane) -> void:
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
