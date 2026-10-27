class_name InputMode
extends RefCounted
## The input modes: which action buttons each game uses, their lane colors and
## default bindings, and the button combinations (one binding that presses
## several buttons at once).
##
## Directions and app shortcuts are the same in every mode (see InputConfig).
## Button ids ("P", "LK"...) are what sequence files store. Lanes follow the
## order of `buttons`, after the direction lane.

const DEFAULT := "VF"
const IDS: Array[String] = ["VF", "SC2", "SF"]

## Controller triggers, used as defaults: [axis, direction].
const LT := [JOY_AXIS_TRIGGER_LEFT, 1.0]
const RT := [JOY_AXIS_TRIGGER_RIGHT, 1.0]

const GREEN := Color(0.20, 0.85, 0.40)
const BLUE := Color(0.25, 0.55, 1.00)
const RED := Color(1.00, 0.30, 0.25)
const WHITE := Color(0.92, 0.93, 0.96)
const LIGHT_BLUE := Color(0.50, 0.82, 1.00)
const YELLOW := Color(1.00, 0.85, 0.20)

## Per mode:
##   title    short name, e.g. in the main title ("INPUT TRAINER: VF MODE")
##   game     the game it is meant for
##   buttons  id, action, label, color, default key, default controller input
##   combos   buttons pressed together, action, default key, default controller input
## A controller default is a JoyButton, or LT / RT for a trigger.
const MODES := {
	"VF": {
		"title": "VF MODE",
		"game": "Virtua Fighter",
		"buttons": [
			{"id": "G", "action": &"vf_guard", "label": "Guard (G)", "color": GREEN, "key": KEY_G, "joy": JOY_BUTTON_A},
			{"id": "P", "action": &"vf_punch", "label": "Punch (P)", "color": BLUE, "key": KEY_Y, "joy": JOY_BUTTON_X},
			{"id": "K", "action": &"vf_kick", "label": "Kick (K)", "color": RED, "key": KEY_U, "joy": JOY_BUTTON_Y},
		],
		"combos": [
			{"buttons": ["P", "K"], "action": &"vf_pk", "key": KEY_I, "joy": JOY_BUTTON_RIGHT_SHOULDER},
			{"buttons": ["K", "G"], "action": &"vf_kg", "key": KEY_J, "joy": RT},
			{"buttons": ["G", "P", "K"], "action": &"vf_gpk", "key": KEY_H, "joy": JOY_BUTTON_B},
		],
	},
	"SC2": {
		"title": "SC2 MODE",
		"game": "Soul Calibur 2",
		"buttons": [
			{"id": "G", "action": &"sc2_g", "label": "Guard (G)", "color": GREEN, "key": KEY_G, "joy": JOY_BUTTON_A},
			{"id": "A", "action": &"sc2_a", "label": "Horizontal (A)", "color": WHITE, "key": KEY_Y, "joy": JOY_BUTTON_X},
			{"id": "B", "action": &"sc2_b", "label": "Vertical (B)", "color": WHITE, "key": KEY_U, "joy": JOY_BUTTON_Y},
			{"id": "K", "action": &"sc2_k", "label": "Kick (K)", "color": RED, "key": KEY_H, "joy": JOY_BUTTON_B},
		],
		"combos": [
			{"buttons": ["A", "B"], "action": &"sc2_ab", "key": KEY_I, "joy": JOY_BUTTON_RIGHT_SHOULDER},
			{"buttons": ["A", "G"], "action": &"sc2_ag", "key": KEY_T, "joy": JOY_BUTTON_LEFT_SHOULDER},
			{"buttons": ["B", "K"], "action": &"sc2_bk", "key": KEY_J, "joy": RT},
			{"buttons": ["G", "B"], "action": &"sc2_gb", "key": KEY_K, "joy": LT},
		],
	},
	"SF": {
		"title": "SF MODE",
		"game": "Street Fighter (classic 6 buttons)",
		"buttons": [
			{"id": "LP", "action": &"sf_lp", "label": "Light Punch (LP)", "color": LIGHT_BLUE, "key": KEY_Y, "joy": JOY_BUTTON_X},
			{"id": "LK", "action": &"sf_lk", "label": "Light Kick (LK)", "color": LIGHT_BLUE, "key": KEY_H, "joy": JOY_BUTTON_A},
			{"id": "MP", "action": &"sf_mp", "label": "Medium Punch (MP)", "color": YELLOW, "key": KEY_U, "joy": JOY_BUTTON_Y},
			{"id": "MK", "action": &"sf_mk", "label": "Medium Kick (MK)", "color": YELLOW, "key": KEY_J, "joy": JOY_BUTTON_B},
			{"id": "HP", "action": &"sf_hp", "label": "Heavy Punch (HP)", "color": RED, "key": KEY_I, "joy": JOY_BUTTON_RIGHT_SHOULDER},
			{"id": "HK", "action": &"sf_hk", "label": "Heavy Kick (HK)", "color": RED, "key": KEY_K, "joy": RT},
		],
		"combos": [
			{"buttons": ["MP", "MK"], "action": &"sf_mp_mk", "key": KEY_G, "joy": JOY_BUTTON_LEFT_SHOULDER},
			{"buttons": ["HP", "HK"], "action": &"sf_hp_hk", "key": KEY_L, "joy": LT},
		],
	},
}


static func is_valid(mode: String) -> bool:
	return MODES.has(mode)


static func title(mode: String) -> String:
	return MODES[mode].title


static func game(mode: String) -> String:
	return MODES[mode].game


## [{id, action, label, color, key, joy}, ...] in lane order.
static func buttons(mode: String) -> Array:
	return MODES[mode].buttons


## [{buttons, action, key, joy}, ...]
static func combos(mode: String) -> Array:
	return MODES[mode].combos


## Button ids in lane order, e.g. ["G", "P", "K"].
static func button_ids(mode: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for button: Dictionary in buttons(mode):
		ids.append(button.id)
	return ids


## The mode's button actions, then its combination actions.
static func actions(mode: String) -> Array[StringName]:
	var list: Array[StringName] = []
	for button: Dictionary in buttons(mode):
		list.append(button.action)
	for combo: Dictionary in combos(mode):
		list.append(combo.action)
	return list


## Every button and combination of every mode (each has action, key, joy).
static func all_definitions() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for mode: String in IDS:
		for button: Dictionary in buttons(mode):
			list.append(button)
		for combo: Dictionary in combos(mode):
			list.append(combo)
	return list


## The mode an action belongs to, or "" for shared actions (directions, shortcuts).
static func mode_of(action: StringName) -> String:
	for mode: String in IDS:
		if action in actions(mode):
			return mode
	return ""


## Display name for one of the modes' actions: "Punch (P)", "P+K"...
static func action_label(action: StringName) -> String:
	for mode: String in IDS:
		for button: Dictionary in buttons(mode):
			if button.action == action:
				return button.label
		for combo: Dictionary in combos(mode):
			if combo.action == action:
				return combo_label(combo)
	return String(action)


static func combo_label(combo: Dictionary) -> String:
	return "+".join(PackedStringArray(combo.buttons))


## Lanes in the widest mode, direction lane included.
static func max_lane_count() -> int:
	var most := 0
	for mode: String in IDS:
		most = maxi(most, buttons(mode).size())
	return most + 1


## Returns the buttons of `list` that exist in `mode`, in lane order, without duplicates.
static func sort_buttons(list: PackedStringArray, mode: String) -> PackedStringArray:
	var sorted := PackedStringArray()
	for id in button_ids(mode):
		if list.has(id):
			sorted.append(id)
	return sorted
