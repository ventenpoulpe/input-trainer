extends Node
## All user settings in one ConfigFile: user://settings.cfg.
## Autoloaded first as `UserSettings` so other autoloads can read it.
##
## Sections:
##   [keyboard] / [joypad]  bindings (written by InputConfig)
##   [input]                use_left_stick, joy_guid (remembered controller)
##   [audio] / [gameplay]   preferences, see PREFERENCE_DEFAULTS
##
## Changes stay in memory until save(); reload() drops unsaved changes.

signal preferences_changed

const PATH := "user://settings.cfg"
const PREFERENCE_DEFAULTS := {
	"audio": {
		"sfx_volume": 0.8,  # 0..1
		"ui_sounds": true,
	},
	"gameplay": {
		"scroll_time": 1.2,  # seconds for an input to reach the hit line
		"facing_right": true,  # player 1 side
	},
}
## Files used before settings.cfg; imported once if settings.cfg is missing.
const OLD_CONTROLS_PATH := "user://controls.cfg"
const OLD_DEVICE_PATH := "user://device.cfg"

var _cfg := ConfigFile.new()


func _init() -> void:
	reload()


## Re-reads the file, dropping unsaved changes.
func reload() -> void:
	_cfg = ConfigFile.new()
	if _cfg.load(PATH) != OK:
		_import_old_files()
	preferences_changed.emit()


func save() -> Error:
	var err := _cfg.save(PATH)
	if err != OK:
		push_error("Could not save %s: %s" % [PATH, error_string(err)])
	return err


func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return _cfg.get_value(section, key, default)


func set_value(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)


func has_value(section: String, key: String) -> bool:
	return _cfg.has_section_key(section, key)


func get_pref(section: String, key: String) -> Variant:
	return _cfg.get_value(section, key, PREFERENCE_DEFAULTS[section][key])


func set_pref(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)
	preferences_changed.emit()


func reset_preferences() -> void:
	for section: String in PREFERENCE_DEFAULTS:
		for key: String in PREFERENCE_DEFAULTS[section]:
			_cfg.set_value(section, key, PREFERENCE_DEFAULTS[section][key])
	preferences_changed.emit()


func _import_old_files() -> void:
	var imported := false
	var controls := ConfigFile.new()
	if controls.load(OLD_CONTROLS_PATH) == OK:
		for section in ["keyboard", "joypad"]:
			if controls.has_section(section):
				for key in controls.get_section_keys(section):
					_cfg.set_value(section, key, controls.get_value(section, key))
		_cfg.set_value("input", "use_left_stick", controls.get_value("options", "use_left_stick", true))
		imported = true
	var device := ConfigFile.new()
	if device.load(OLD_DEVICE_PATH) == OK:
		_cfg.set_value("input", "joy_guid", device.get_value("device", "joy_guid", ""))
		imported = true
	if imported:
		save()
