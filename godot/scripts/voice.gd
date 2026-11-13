extends Node
## Voice chat for multiplayer (node Net/Voice). The microphone plays into a silent "Mic" bus whose
## AudioEffectCapture hands us the samples; they are resampled to 16 kHz mono, packed as 8-bit
## μ-law (60 ms = 960 bytes per packet, ~16 KB/s while talking) and sent through net.gd
## (zzzz_voice RPC, host relays like any other RPC, so it works on LAN and online alike).
## Each talker plays through their own AudioStreamGenerator at 16 kHz.
## settings.voice: 0 = hold T to talk, 1 = open mic (noise gate), 2 = off.

const RATE := 16000
const CHUNK := 960                # 60 ms per packet
const GATE := 0.018               # open mic: RMS that opens the gate

var net
var mic: AudioStreamPlayer
var cap: AudioEffectCapture
var mic_on := false
var inbuf := PackedFloat32Array()  # mic samples at the mix rate (mono)
var pos := 0.0                    # resampler read position in inbuf
var pend := PackedFloat32Array()  # 16 kHz samples waiting to be sent
var talking := false              # the local player is transmitting
var gate_t := 0.0
var outs := {}                    # peer id -> {"pl": AudioStreamPlayer, "pb": playback}
var heard := {}                   # peer id -> msec of the last packet
var sent := 0                     # packets (stats / automated checks)
var received := 0
var test_tone := 0.0              # automated checks: seconds of synthetic voice to send
var _tone_ph := 0.0
var _dec := PackedFloat32Array()  # μ-law decode table


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dec.resize(256)
	for b in 256:
		var m := b / 127.5 - 1.0
		_dec[b] = signf(m) * (pow(256.0, absf(m)) - 1.0) / 255.0


func mode() -> int:
	return int(net.game.settings.get("voice", 0)) if net and net.game else 0


## Microphone through a silent bus with a capture effect (created on first use).
func _start_mic() -> void:
	if mic_on:
		return
	mic_on = true
	if mic == null:
		var bi := AudioServer.get_bus_index("Mic")
		if bi < 0:
			bi = AudioServer.bus_count
			AudioServer.add_bus(bi)
			AudioServer.set_bus_name(bi, "Mic")
			cap = AudioEffectCapture.new()
			cap.buffer_length = 0.5
			AudioServer.add_bus_effect(bi, cap)
			# effects run before the fader: we capture the voice without hearing ourselves
			AudioServer.set_bus_volume_db(bi, -80.0)
		mic = AudioStreamPlayer.new()
		mic.stream = AudioStreamMicrophone.new()
		mic.bus = "Mic"
		add_child(mic)
	mic.play()
	if cap:
		cap.clear_buffer()


func _stop_mic() -> void:
	if not mic_on:
		return
	mic_on = false
	if mic:
		mic.stop()
	talking = false
	pend.clear()
	inbuf.clear()
	pos = 0.0


## Leaving the game: stop everything and drop the talkers.
func reset() -> void:
	_stop_mic()
	for id in outs.keys():
		outs[id].pl.queue_free()
	outs.clear()
	heard.clear()


func _process(delta: float) -> void:
	if net == null or not net.active:
		if mic_on or not outs.is_empty():
			reset()
		return
	var m := mode()
	if m == 2:
		_stop_mic()
		return
	if test_tone > 0.0:
		_send_tone(delta)
		return
	_start_mic()
	if cap == null:
		return
	var n := cap.get_frames_available()
	if n <= 0:
		return
	var buf := cap.get_buffer(n)
	var want := false
	if m == 0:
		want = Input.is_physical_key_pressed(KEY_T) and _keys_free() and DisplayServer.window_is_focused()
	else:
		var e := 0.0
		for f in buf:
			e += f.x * f.x
		if sqrt(e / maxf(1.0, buf.size())) > GATE:
			gate_t = 0.45
		gate_t -= delta
		want = gate_t > 0.0
	talking = want
	if not want:
		inbuf.clear()
		pos = 0.0
		pend.clear()
		return
	# mono + resample (linear, with a 2-tap average as a cheap anti-alias filter)
	var base := inbuf.size()
	inbuf.resize(base + buf.size())
	var prev := 0.0
	for i in buf.size():
		var s := (buf[i].x + buf[i].y) * 0.5
		inbuf[base + i] = (s + prev) * 0.5
		prev = s
	var step := AudioServer.get_mix_rate() / float(RATE)
	while pos + 1.0 < inbuf.size():
		var k := int(pos)
		var fr := pos - k
		pend.append(lerpf(inbuf[k], inbuf[k + 1], fr) * 1.6)
		pos += step
	var used := int(pos)
	inbuf = inbuf.slice(used)
	pos -= used
	_flush()


## Not while typing in a text box (chat, name, code...).
func _keys_free() -> bool:
	var g = net.game
	if g.ui and g.ui.chat_open:
		return false
	var f := get_viewport().gui_get_focus_owner()
	return not (f is LineEdit)


func _flush() -> void:
	while pend.size() >= CHUNK:
		var pkt := PackedByteArray()
		pkt.resize(CHUNK)
		for i in CHUNK:
			var x := clampf(pend[i], -1.0, 1.0)
			var mm := signf(x) * log(1.0 + 255.0 * absf(x)) / log(256.0)
			pkt[i] = clampi(int(round((mm + 1.0) * 127.5)), 0, 255)
		pend = pend.slice(CHUNK)
		net.voice_send(pkt)
		sent += 1


func _send_tone(delta: float) -> void:
	test_tone -= delta
	talking = test_tone > 0.0
	var n := int(RATE * delta)
	for i in n:
		_tone_ph += TAU * 220.0 / RATE
		pend.append(sin(_tone_ph) * 0.3)
	_flush()


## Packet from a peer: decode into their generator.
func receive(id: int, pkt: PackedByteArray) -> void:
	if mode() == 2 or pkt.size() == 0:
		return
	received += 1
	heard[id] = Time.get_ticks_msec()
	var o: Dictionary = outs.get(id, {})
	if o.is_empty() or not is_instance_valid(o.pl):
		var pl := AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RATE
		gen.buffer_length = 0.5
		pl.stream = gen
		pl.volume_db = 2.0
		add_child(pl)
		pl.play()
		o = {"pl": pl, "pb": pl.get_stream_playback()}
		outs[id] = o
	var pb = o.pb
	if pb == null:
		return
	# buffer already long (sender's clock faster than ours, or a burst): drop to keep latency low
	if pb.get_frames_available() < pkt.size():
		return
	var frames := PackedVector2Array()
	frames.resize(pkt.size())
	for i in pkt.size():
		var v := _dec[pkt[i]]
		frames[i] = Vector2(v, v)
	pb.push_buffer(frames)


func drop(id: int) -> void:
	if outs.has(id):
		outs[id].pl.queue_free()
		outs.erase(id)
	heard.erase(id)


## Is this peer talking right now (for the mic icons)?
func is_talking(id: int) -> bool:
	if net and id == net.my_id():
		return talking
	return Time.get_ticks_msec() - int(heard.get(id, -100000)) < 300
