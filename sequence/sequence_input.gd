class_name SequenceInput
extends RefCounted
## One moment in a sequence: the direction held at that moment plus the
## buttons newly pressed at that moment.
##
## `direction` is always the full held direction, so it can repeat between
## inputs (e.g. holding DOWN_FORWARD while pressing P, then K). Compare with
## the previous input to tell a new direction from a held one.
##
## Hold inputs: a direction or button kept down for at least HOLD_MIN_FRAMES gets a hold
## length (seconds) on the input where it was pressed: `direction_hold` for
## the direction, `button_holds["P"]` etc. for buttons. 0 = a normal tap.

const FPS := 60.0
const HOLD_MIN_FRAMES := 15
const HOLD_MIN_SECONDS := HOLD_MIN_FRAMES / FPS

const NEUTRAL := "NEUTRAL"
const DIRECTIONS := [
	"NEUTRAL", "UP", "DOWN", "FORWARD", "BACK",
	"UP_FORWARD", "UP_BACK", "DOWN_FORWARD", "DOWN_BACK",
]
## Canonical button order, used when saving.
const BUTTONS := ["P", "K", "G"]

var timestamp := 0.0
var frame := 0
var direction := NEUTRAL
var buttons := PackedStringArray()
var direction_hold := 0.0
## Button -> hold length in seconds (only for held buttons).
var button_holds := {}


func _init(p_timestamp := 0.0, p_direction := NEUTRAL, p_buttons := PackedStringArray()) -> void:
	timestamp = p_timestamp
	frame = time_to_frame(p_timestamp)
	direction = p_direction
	buttons = sort_buttons(p_buttons)


func get_button_hold(button: String) -> float:
	return button_holds.get(button, 0.0)


## Time the last direction or button of this input is released.
func get_end_time() -> float:
	var longest := direction_hold
	for button: String in button_holds:
		longest = maxf(longest, button_holds[button])
	return timestamp + longest


func _to_string() -> String:
	var parts := PackedStringArray()
	for button in buttons:
		parts.append(button + ("(hold %.3f)" % get_button_hold(button) if get_button_hold(button) > 0.0 else ""))
	var hold_text := " (hold %.3f)" % direction_hold if direction_hold > 0.0 else ""
	return "%.3fs f%d %s%s %s" % [timestamp, frame, direction, hold_text, "+".join(parts)]


static func time_to_frame(seconds: float) -> int:
	return roundi(seconds * FPS)


## VF-style direction from the four held directions. Opposite directions
## cancel out (left + right = neither). `facing_right` = player 1 side.
static func direction_from_state(up: bool, down: bool, left: bool, right: bool, facing_right := true) -> String:
	var vertical := int(up) - int(down)
	var horizontal := int(right) - int(left)
	if not facing_right:
		horizontal = -horizontal
	var v := "UP" if vertical > 0 else "DOWN" if vertical < 0 else ""
	var h := "FORWARD" if horizontal > 0 else "BACK" if horizontal < 0 else ""
	if v and h:
		return v + "_" + h
	if v:
		return v
	if h:
		return h
	return NEUTRAL


## Returns the known buttons from `list` in P, K, G order, without duplicates.
static func sort_buttons(list: PackedStringArray) -> PackedStringArray:
	var sorted := PackedStringArray()
	for button: String in BUTTONS:
		if list.has(button):
			sorted.append(button)
	return sorted
