class_name InputSequence
extends RefCounted
## A recorded or loaded input sequence: notes sorted by timestamp.

var name := ""
var author := ""
## Length in seconds (time of the last input change, at least the last note).
var duration := 0.0
var notes: Array[InputNote] = []


func get_frame_count() -> int:
	return InputNote.time_to_frame(duration)


func _to_string() -> String:
	return "%s by %s, %d notes, %.3fs" % [name, author, notes.size(), duration]
