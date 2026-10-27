class_name InputSequence
extends RefCounted
## A recorded or loaded input sequence: inputs sorted by timestamp.

var name := ""
var author := ""
## Length in seconds (time of the last direction or button change, at least the end of the last input).
var duration := 0.0
var inputs: Array[SequenceInput] = []


func get_frame_count() -> int:
	return SequenceInput.time_to_frame(duration)


func _to_string() -> String:
	return "%s by %s, %d inputs, %.3fs" % [name, author, inputs.size(), duration]
