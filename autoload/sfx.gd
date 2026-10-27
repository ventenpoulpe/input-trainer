extends Node
## Sound effects, synthesized at startup so no audio files are needed.
## Autoloaded as `Sfx`. Call Sfx.play(&"perfect").
##
## Every button in the app gets a click automatically (if the "ui_sounds"
## preference is on). Volume follows the "sfx_volume" preference through
## the SFX audio bus. To use real sounds, replace a stream in _ready() with
## load("res://...wav").

const BUS := &"SFX"
const MIX_RATE := 22050

var _players := {}  # StringName -> AudioStreamPlayer


func _ready() -> void:
	_ensure_bus()
	_add(&"click", _synth([1800.0], 0.035, 0.2, 110.0, true))
	_add(&"perfect", _synth([1318.5, 1975.5], 0.16, 0.35, 22.0))
	_add(&"great", _synth([1046.5, 1568.0], 0.13, 0.32, 26.0))
	_add(&"good", _synth([784.0], 0.11, 0.3, 30.0))
	_add(&"miss", _synth([98.0, 103.8], 0.2, 0.3, 14.0, true))
	_add(&"extra", _synth([180.0], 0.07, 0.22, 40.0, true))
	_add(&"hold_ok", _synth([1568.0, 2093.0, 2637.0], 0.22, 0.28, 16.0))
	_add(&"hold_drop", _synth([330.0], 0.18, 0.28, 12.0, true, -0.5))
	_add(&"ready", _synth([660.0], 0.12, 0.3, 20.0))
	_add(&"loop_end", _synth([523.3, 659.3, 784.0], 0.3, 0.25, 10.0))
	_add(&"new_best", _arpeggio([784.0, 987.8, 1174.7, 1568.0], 0.08, 0.3))
	UserSettings.preferences_changed.connect(_apply_volume)
	_apply_volume()
	get_tree().node_added.connect(_on_node_added)


func play(sound: StringName, pitch := 1.0) -> void:
	var player: AudioStreamPlayer = _players.get(sound)
	if player == null:
		push_warning("Unknown sound: %s" % sound)
		return
	player.pitch_scale = pitch
	player.play()


func _add(sound: StringName, stream: AudioStream) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS
	player.max_polyphony = 6
	add_child(player)
	_players[sound] = player


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS)
	AudioServer.set_bus_send(index, &"Master")


func _apply_volume() -> void:
	var index := AudioServer.get_bus_index(BUS)
	var volume: float = UserSettings.get_pref("audio", "sfx_volume")
	AudioServer.set_bus_mute(index, volume <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(_on_ui_pressed)


func _on_ui_pressed() -> void:
	if UserSettings.get_pref("audio", "ui_sounds"):
		play(&"click")


## A short tone: mixed sine (or square) waves with a fast attack and an
## exponential decay. `sweep` bends the pitch over the sound (-0.5 = down).
static func _synth(freqs: Array, length: float, volume: float, decay: float, square := false, sweep := 0.0) -> AudioStreamWAV:
	var count := int(length * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phases := PackedFloat64Array()
	phases.resize(freqs.size())
	for i in count:
		var t := float(i) / MIX_RATE
		var envelope := exp(-t * decay) * minf(1.0, t * 500.0) * minf(1.0, (length - t) * 200.0)
		var sample := 0.0
		for f in freqs.size():
			var freq: float = freqs[f] * (1.0 + sweep * t / length)
			phases[f] = fmod(phases[f] + freq / MIX_RATE, 1.0)
			var wave := sin(TAU * phases[f])
			sample += signf(wave) * 0.6 if square else wave
		sample = sample / freqs.size() * volume * envelope
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wav(data)


static func _arpeggio(freqs: Array, note_length: float, volume: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	for i in freqs.size():
		var length := note_length * (3.0 if i == freqs.size() - 1 else 1.0)
		data.append_array(_synth([freqs[i]], length, volume, 8.0).data)
	return _wav(data)


static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
