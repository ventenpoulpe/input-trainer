class_name SequenceXml
extends RefCounted
## Reads and writes InputSequence XML files:
##
##   <InputSequence name="..." author="..." duration="4.5">
##       <InputNote timestamp="0.30" frame="18">
##           <Direction hold="0.400" holdFrames="24">DOWN_FORWARD</Direction>
##           <Buttons><Button>P</Button><Button hold="0.300" holdFrames="18">G</Button></Buttons>
##       </InputNote>
##   </InputSequence>
##
## `hold` (seconds) is optional and marks a hold note; `holdFrames` is only
## written for readability. Files without holds use the original schema.

## Description of the last load/save failure.
static var last_error := ""


static func save_file(sequence: InputSequence, path: String) -> Error:
	last_error = ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		last_error = "Could not write %s: %s" % [path, error_string(err)]
		return err
	file.store_string(to_xml(sequence))
	file.close()
	return OK


static func to_xml(sequence: InputSequence) -> String:
	var lines := PackedStringArray()
	lines.append('<?xml version="1.0" encoding="utf-8"?>')
	lines.append('<InputSequence name="%s" author="%s" duration="%s">' % [
		sequence.name.xml_escape(true), sequence.author.xml_escape(true), _format_time(sequence.duration),
	])
	for note in sequence.notes:
		lines.append('    <InputNote timestamp="%s" frame="%d">' % [_format_time(note.timestamp), note.frame])
		lines.append("        <Direction%s>%s</Direction>" % [_hold_attributes(note.direction_hold), note.direction])
		if note.buttons.is_empty():
			lines.append("        <Buttons></Buttons>")
		else:
			lines.append("        <Buttons>")
			for button in note.buttons:
				lines.append("            <Button%s>%s</Button>" % [_hold_attributes(note.get_button_hold(button)), button])
			lines.append("        </Buttons>")
		lines.append("    </InputNote>")
	lines.append("</InputSequence>")
	return "\n".join(lines) + "\n"


## Returns null on failure; see `last_error`.
static func load_file(path: String) -> InputSequence:
	last_error = ""
	var parser := XMLParser.new()
	var err := parser.open(path)
	if err != OK:
		last_error = "Could not open %s: %s" % [path, error_string(err)]
		return null
	return _parse(parser, path.get_file().get_basename())


## Returns null on failure; see `last_error`.
static func parse_string(xml: String, fallback_name := "") -> InputSequence:
	last_error = ""
	var parser := XMLParser.new()
	var err := parser.open_buffer(xml.to_utf8_buffer())
	if err != OK:
		last_error = "Could not read XML: %s" % error_string(err)
		return null
	return _parse(parser, fallback_name)


static func _parse(parser: XMLParser, fallback_name: String) -> InputSequence:
	var sequence: InputSequence = null
	var note: InputNote = null
	var duration := -1.0
	var text_tag := ""  # "Direction" or "Button" while reading its text
	var text := ""
	var hold := 0.0

	while true:
		var err := parser.read()
		if err == ERR_FILE_EOF:
			break
		if err != OK:
			last_error = "Malformed XML near line %d." % parser.get_current_line()
			return null

		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := parser.get_node_name()
				match tag:
					"InputSequence":
						sequence = InputSequence.new()
						sequence.name = _attr(parser, "name", fallback_name)
						sequence.author = _attr(parser, "author", "")
						var duration_text := _attr(parser, "duration", "")
						if duration_text.is_valid_float():
							duration = duration_text.to_float()
					"InputNote":
						if sequence == null:
							last_error = "<InputNote> outside <InputSequence> (line %d)." % parser.get_current_line()
							return null
						note = _start_note(parser)
						if note == null:
							return null
						if parser.is_empty():
							sequence.notes.append(note)
							note = null
					"Direction", "Button":
						text_tag = tag
						text = ""
						var hold_text := _attr(parser, "hold", "")
						hold = maxf(hold_text.to_float(), 0.0) if hold_text.is_valid_float() else 0.0
						if parser.is_empty():
							_apply_text(note, tag, "", hold, parser.get_current_line())
							text_tag = ""
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				if text_tag:
					text += parser.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var tag := parser.get_node_name()
				match tag:
					"Direction", "Button":
						_apply_text(note, tag, text.strip_edges().xml_unescape(), hold, parser.get_current_line())
						text_tag = ""
					"InputNote":
						if note != null:
							note.buttons = InputNote.sort_buttons(note.buttons)
							sequence.notes.append(note)
							note = null

	if sequence == null:
		last_error = "No <InputSequence> element found."
		return null

	sequence.notes.sort_custom(func(a: InputNote, b: InputNote) -> bool: return a.timestamp < b.timestamp)
	var last_end := 0.0
	for each in sequence.notes:
		last_end = maxf(last_end, each.get_end_time())
	sequence.duration = maxf(duration, last_end)
	return sequence


static func _start_note(parser: XMLParser) -> InputNote:
	var time_text := _attr(parser, "timestamp", "")
	if not time_text.is_valid_float():
		last_error = "<InputNote> needs a numeric timestamp (line %d)." % parser.get_current_line()
		return null
	var note := InputNote.new(time_text.to_float())
	var frame_text := _attr(parser, "frame", "")
	if frame_text.is_valid_int():
		note.frame = frame_text.to_int()
	return note


static func _apply_text(note: InputNote, tag: String, value: String, hold: float, line: int) -> void:
	if note == null:
		return
	var token := value.to_upper()
	if tag == "Direction":
		if token in InputNote.DIRECTIONS:
			note.direction = token
			note.direction_hold = hold if token != InputNote.NEUTRAL else 0.0
		else:
			push_warning("Unknown direction '%s' on line %d, using NEUTRAL." % [value, line])
			note.direction = InputNote.NEUTRAL
	elif token in InputNote.BUTTONS:
		note.buttons.append(token)
		if hold > 0.0:
			note.button_holds[token] = hold
	else:
		push_warning("Unknown button '%s' on line %d, skipped." % [value, line])


static func _hold_attributes(hold: float) -> String:
	if hold <= 0.0:
		return ""
	return ' hold="%s" holdFrames="%d"' % [_format_time(hold), InputNote.time_to_frame(hold)]


static func _attr(parser: XMLParser, attribute: String, default: String) -> String:
	if not parser.has_attribute(attribute):
		return default
	return parser.get_named_attribute_value(attribute).xml_unescape()


static func _format_time(seconds: float) -> String:
	return "%.3f" % seconds
