class_name SaveSequenceDialog
extends ConfirmationDialog
## Asks for a file name and author, then saves the current sequence.

var _name_edit := LineEdit.new()
var _author_edit := LineEdit.new()
var _hint := Label.new()


func _init() -> void:
	title = "Save Sequence"
	ok_button_text = "Save"
	dialog_hide_on_ok = false

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 12)
	_add_field(grid, "File name:", _name_edit, "e.g. Jean_Kujo_BnB01")
	_add_field(grid, "Author:", _author_edit, SequenceManager.DEFAULT_AUTHOR)

	_hint.add_theme_color_override(&"font_color", Color(0.6, 0.68, 0.8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	box.add_child(grid)
	box.add_child(_hint)
	add_child(box)

	register_text_enter(_name_edit)
	register_text_enter(_author_edit)
	_name_edit.text_changed.connect(_update_hint)
	confirmed.connect(_on_confirmed)


func open() -> void:
	var sequence := SequenceManager.current_sequence
	_name_edit.text = sequence.name if sequence else ""
	_author_edit.text = sequence.author if sequence else SequenceManager.DEFAULT_AUTHOR
	_update_hint()
	popup_centered()
	_name_edit.grab_focus()
	_name_edit.select_all()


func _add_field(grid: GridContainer, label_text: String, edit: LineEdit, placeholder: String) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(300, 0)
	grid.add_child(edit)


func _update_hint(_text := "") -> void:
	var file_name := SequenceManager.sanitize_file_name(_name_edit.text)
	get_ok_button().disabled = file_name.is_empty()
	if file_name.is_empty():
		_hint.text = "Saves to %s/" % SequenceManager.sequences_dir()
		return
	var path := SequenceManager.path_for(file_name)
	_hint.text = ("Overwrites %s" if FileAccess.file_exists(path) else "Saves to %s") % path


func _on_confirmed() -> void:
	if get_ok_button().disabled:
		return
	var error := SequenceManager.save_current(_name_edit.text, _author_edit.text)
	if error:
		_hint.text = error
		return
	hide()
