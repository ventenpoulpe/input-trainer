class_name TimingJudge
extends RefCounted
## Turns a sequence into per-lane targets and judges presses against them.
##
## Lanes: direction, G, P, K. A direction target is created when an input's
## direction differs from the previous input's (NEUTRAL is never a target, but
## it still counts as "different", so FORWARD, NEUTRAL, FORWARD = 2 targets).
## A button target is created for each button pressed in an input.
##
## Hold targets (hold > 0) are scored twice: the press like any input, then
## the release. Letting go before the end (minus HOLD_RELEASE_GRACE) drops it.
##
## Match rate = points earned / (items judged + extra button presses).
## Extra presses (a button with no target in reach) count against the rate so
## mashing doesn't score; extra direction changes don't, since moving between
## directions naturally passes through others.

enum Lane { DIRECTION, GUARD, PUNCH, KICK }
enum Rating { PERFECT, GREAT, GOOD, MISS }
enum HoldResult { NONE = -1, OK, DROPPED }

const FRAME := 1.0 / 60.0
## Max distance from the input time (seconds) for each rating.
const PERFECT_WINDOW := 2.0 * FRAME
const GREAT_WINDOW := 4.0 * FRAME
const GOOD_WINDOW := 6.0 * FRAME
## A hold may be released this early and still count as complete.
const HOLD_RELEASE_GRACE := GOOD_WINDOW

const RATING_POINTS := {Rating.PERFECT: 1.0, Rating.GREAT: 0.75, Rating.GOOD: 0.5, Rating.MISS: 0.0}
const RATING_TEXT := {Rating.PERFECT: "PERFECT!", Rating.GREAT: "GREAT", Rating.GOOD: "GOOD", Rating.MISS: "MISS"}
const BUTTON_LANES := {"G": Lane.GUARD, "P": Lane.PUNCH, "K": Lane.KICK}


class Target:
	var lane: Lane
	var time: float
	## Hold length in seconds; 0 for a normal input.
	var hold := 0.0
	## Only used in the direction lane.
	var direction := ""
	## -1 until judged, then a Rating.
	var rating := -1
	## Press time minus target time (negative = early).
	var offset := 0.0
	## True while a hit hold input is being held.
	var holding := false
	var hold_result := HoldResult.NONE

	func _init(p_lane: Lane, p_time: float, p_hold := 0.0, p_direction := "") -> void:
		lane = p_lane
		time = p_time
		hold = p_hold
		direction = p_direction

	func is_judged() -> bool:
		return rating != -1

	func is_hold() -> bool:
		return hold > 0.0

	func end_time() -> float:
		return time + hold


## Sorted by time.
var targets: Array[Target] = []
## Loop length: the sequence duration, or long enough to judge the last input.
var end_time := 0.0
var earned := 0.0
var judged := 0
var extras := 0
var counts := {}
var holds_ok := 0
var holds_dropped := 0

var _holding: Array[Target] = []


func _init(sequence: InputSequence) -> void:
	targets = build_targets(sequence)
	end_time = sequence.duration
	for target in targets:
		end_time = maxf(end_time, target.end_time() + GOOD_WINDOW)
	reset()


static func build_targets(sequence: InputSequence) -> Array[Target]:
	var list: Array[Target] = []
	var previous_direction := SequenceInput.NEUTRAL
	for input in sequence.inputs:
		if input.direction != previous_direction and input.direction != SequenceInput.NEUTRAL:
			list.append(Target.new(Lane.DIRECTION, input.timestamp, input.direction_hold, input.direction))
		previous_direction = input.direction
		for button in input.buttons:
			if BUTTON_LANES.has(button):
				list.append(Target.new(BUTTON_LANES[button], input.timestamp, input.get_button_hold(button)))
	list.sort_custom(func(a: Target, b: Target) -> bool: return a.time < b.time)
	return list


## Number of scored items: every target, plus one per hold for its release.
func get_item_count() -> int:
	var count := targets.size()
	for target in targets:
		if target.is_hold():
			count += 1
	return count


## Clears all judgments for a new loop.
func reset() -> void:
	for target in targets:
		target.rating = -1
		target.offset = 0.0
		target.holding = false
		target.hold_result = HoldResult.NONE
	_holding.clear()
	earned = 0.0
	judged = 0
	extras = 0
	holds_ok = 0
	holds_dropped = 0
	for rating: Rating in RATING_POINTS:
		counts[rating] = 0


## A new direction was entered at `time`. Returns the target it hit, or null.
func press_direction(direction: String, time: float) -> Target:
	var target := _closest_open_target(Lane.DIRECTION, time, direction)
	if target:
		_judge(target, time - target.time)
	return target


## A button lane was pressed at `time`. Returns the target it hit, or null
## (an extra press, which lowers the match rate).
func press_button(lane: Lane, time: float) -> Target:
	var target := _closest_open_target(lane, time)
	if target:
		_judge(target, time - target.time)
	else:
		extras += 1
	return target


## The input of `lane` was let go at `time`. Returns the hold it finished
## (check its hold_result), or null if nothing was being held.
func release(lane: Lane, time: float) -> Target:
	for target in _holding:
		if target.lane == lane:
			_finish_hold(target, HoldResult.OK if time >= target.end_time() - HOLD_RELEASE_GRACE else HoldResult.DROPPED)
			return target
	return null


func is_holding(lane: int) -> bool:
	for target in _holding:
		if target.lane == lane:
			return true
	return false


## Completes holds that were held to their end. Returns them.
func update_holds(time: float) -> Array[Target]:
	var finished: Array[Target] = []
	for target in _holding.duplicate():
		if time >= target.end_time():
			_finish_hold(target, HoldResult.OK)
			finished.append(target)
	return finished


## Marks targets that can no longer be hit as MISS. Returns them.
## A missed hold also loses its release point.
func update_misses(time: float) -> Array[Target]:
	var missed: Array[Target] = []
	for target in targets:
		if target.time > time - GOOD_WINDOW:
			break
		if not target.is_judged():
			target.rating = Rating.MISS
			target.offset = 0.0
			judged += 1
			counts[Rating.MISS] += 1
			if target.is_hold():
				target.hold_result = HoldResult.DROPPED
				judged += 1
				holds_dropped += 1
			missed.append(target)
	return missed


## Current match rate in percent, or -1 if nothing has been judged yet.
func get_rate() -> float:
	var total := judged + extras
	return -1.0 if total == 0 else earned / total * 100.0


static func rating_for_offset(offset: float) -> Rating:
	var distance := absf(offset)
	if distance <= PERFECT_WINDOW:
		return Rating.PERFECT
	if distance <= GREAT_WINDOW:
		return Rating.GREAT
	if distance <= GOOD_WINDOW:
		return Rating.GOOD
	return Rating.MISS


func _closest_open_target(lane: Lane, time: float, direction := "") -> Target:
	var best: Target = null
	for target in targets:
		if target.time > time + GOOD_WINDOW:
			break
		if target.lane != lane or target.is_judged() or target.time < time - GOOD_WINDOW:
			continue
		if direction and target.direction != direction:
			continue
		if best == null or absf(target.time - time) < absf(best.time - time):
			best = target
	return best


func _judge(target: Target, offset: float) -> void:
	target.offset = offset
	target.rating = rating_for_offset(offset)
	earned += RATING_POINTS[target.rating]
	judged += 1
	counts[target.rating] += 1
	if target.is_hold():
		target.holding = true
		_holding.append(target)


func _finish_hold(target: Target, result: HoldResult) -> void:
	target.holding = false
	target.hold_result = result
	_holding.erase(target)
	judged += 1
	if result == HoldResult.OK:
		earned += 1.0
		holds_ok += 1
	else:
		holds_dropped += 1
