class_name InputSequence
extends RefCounted
## A recorded or loaded input sequence: inputs sorted by timestamp.

var name := ""
var author := ""
## InputMode id the sequence was recorded with ("VF", "SC2" or "SF").
var mode := InputMode.DEFAULT
## Length in seconds (time of the last direction or button change, at least the end of the last input).
var duration := 0.0
var inputs: Array[SequenceInput] = []


func get_frame_count() -> int:
	return SequenceInput.time_to_frame(duration)


func _to_string() -> String:
	return "%s by %s (%s), %d inputs, %.3fs" % [name, author, mode, inputs.size(), duration]
