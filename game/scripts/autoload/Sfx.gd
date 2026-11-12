extends Node
## Tiny procedural UI sound kit. Generated at runtime so the project has no audio assets.

var enabled: bool = true
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _streams: Dictionary = {}

func _ready() -> void:
	for i in range(6):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = -17.0
		add_child(p)
		_players.append(p)
	_streams["hover"] = _tone(1850.0, 0.018, 0.12, "sine")
	_streams["click"] = _tone(780.0, 0.045, 0.35, "square")
	_streams["confirm"] = _chord([520.0, 780.0], 0.11, 0.30)
	_streams["deny"] = _tone(150.0, 0.16, 0.30, "saw")
	_streams["dice"] = _noise(0.10, 0.22)
	_streams["type"] = _tone(1400.0, 0.012, 0.05, "sine")
	_streams["alert"] = _chord([300.0, 420.0], 0.22, 0.30)

func play(name: String) -> void:
	if not enabled:
		return
	var stream: AudioStream = _streams.get(name, null)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.play()

func toggle() -> void:
	enabled = not enabled

func _tone(freq: float, dur: float, vol: float, wave: String) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(rate)
		var env: float = minf(1.0, t / 0.004) * maxf(0.0, 1.0 - t / dur)
		var s := sin(TAU * freq * t)
		if wave == "square":
			s = 1.0 if s >= 0.0 else -1.0
		elif wave == "saw":
			s = fmod(t * freq, 1.0) * 2.0 - 1.0
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)

func _chord(freqs: Array, dur: float, vol: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(rate)
		var env: float = minf(1.0, t / 0.005) * maxf(0.0, 1.0 - t / dur)
		var s := 0.0
		for f in freqs:
			s += sin(TAU * float(f) * t)
		s /= float(maxi(1, freqs.size()))
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)

func _noise(dur: float, vol: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i in range(n):
		var t := float(i) / float(rate)
		var env: float = maxf(0.0, 1.0 - t / dur)
		data.encode_s16(i * 2, int(clampf(rng.randf_range(-1.0, 1.0) * env * vol, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)

func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
