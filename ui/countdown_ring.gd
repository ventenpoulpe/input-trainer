class_name CountdownRing
extends Control
## A circle that fills clockwise as `progress` goes from 0 to 1.

const RADIUS := 52.0
const WIDTH := 10.0
const FILL_COLOR := Color(0.3, 0.85, 1.0)

var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()
var label := "READY"


func _init() -> void:
	custom_minimum_size = Vector2.ONE * (RADIUS + WIDTH) * 2.0
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size / 2.0
	draw_circle(center, RADIUS + WIDTH, Color(0, 0, 0, 0.6))
	draw_arc(center, RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.15), WIDTH, true)
	if progress > 0.0:
		draw_arc(center, RADIUS, -PI / 2.0, -PI / 2.0 + TAU * progress, 64, FILL_COLOR, WIDTH, true)
	var font := get_theme_default_font()
	draw_string(font, Vector2(0, center.y + 7), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20)
