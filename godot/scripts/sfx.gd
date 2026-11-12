extends Node
## Sound effects: pooled 2D players for the player's own sounds, temporary 3D players for the world.

const NAMES := ["rifle", "pistol", "shotgun", "enemy", "empty", "mag_out", "mag_in", "rack", "hit", "kill", "hurt", "whiz", "step", "click", "wave", "swish",
	"smg", "lmg", "sniper", "bolt", "knife", "stab", "zgroan1", "zgroan2", "zgroan3", "zattack", "zdie", "buy", "deny", "powerup", "round", "medal", "door", "perk", "boom", "jet", "pin", "radar"]
var streams := {}
var pool: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		streams[n] = load("res://assets/sfx/%s.wav" % n)
	for i in 20:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)


func play(name: String, vol_db := 0.0, pitch_var := 0.05) -> void:
	for p in pool:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = vol_db
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.play()
			return


func play3d(name: String, pos: Vector3, vol_db := 0.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[name]
	p.volume_db = vol_db
	p.unit_size = 10.0
	p.max_distance = 140.0
	p.pitch_scale = randf_range(0.92, 1.08)
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
