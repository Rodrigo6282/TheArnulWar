extends Node
## Sound effects: pooled 2D players for the player's own sounds, temporary 3D players for the world.

const NAMES := ["rifle", "pistol", "shotgun", "enemy", "empty", "mag_out", "mag_in", "rack", "hit", "kill", "hurt", "whiz", "click", "wave", "swish",
	"step1", "step2", "step3", "step4", "step5", "step6", "land",
	"smg", "lmg", "sniper", "bolt", "knife", "stab", "zgroan1", "zgroan2", "zgroan3", "zgroan4", "zgroan5",
	"zattack1", "zattack2", "zdie1", "zdie2", "buy", "deny", "powerup", "round", "medal", "door", "perk", "boom", "jet", "pin", "radar",
	"zgroan6", "zgroan7", "zgroan8", "zattack3", "zattack4", "zdie3", "zscream1", "zscream2",
	"zbreath1", "zbreath2", "zbreath3", "zdrag1", "zdrag2", "zdrag3"]
## Footstep sets (herramientas/Synth_sonidos.cs): st_<kind>1..4 + ld_<kind> (landing).
const SURFACES := ["conc", "dirt", "wood", "metal", "snow", "sand", "grass"]
## Texture / prop id keywords -> surface (first match wins); anything else is concrete / the map default.
const SURF_KEYS := [
	["wood", ["plank", "wood", "crate", "pallet", "bench", "cabinet", "table", "chair", "shelf", "barricade"]],
	["metal", ["metal", "corrugated", "plate", "iron", "container", "barrel", "jerrycan", "tank", "tool_chest", "desk", "generator",
		"car", "truck", "dumpster", "trash_can", "propane", "gas_", "hand_truck", "oil_tin"]],
	["snow", ["snow", "ice"]],
	["sand", ["sand", "desert"]],
	["grass", ["grass", "leaves", "forest", "moss"]],
	["dirt", ["mud", "dirt", "soil", "gravel", "trail", "hay"]],
	["conc", ["concrete", "asphalt", "brick", "stone", "tile", "cobble", "debris", "rock", "plaster", "stucco", "road", "jersey", "tyre", "tire"]],
]
## Ground of each map when nothing more specific is found under the feet.
const MAP_SURF := ["conc", "sand", "snow", "dirt", "conc", "snow", "grass"]
var streams := {}
var _surf_cache := {}
const WBS := preload("res://scripts/world.gd")
var pool: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# volume buses for the OPCIONES sliders: game sounds -> "Efectos", voice chat -> "Voz"
	for bn in ["Efectos", "Voz"]:
		if AudioServer.get_bus_index(bn) < 0:
			var bi := AudioServer.bus_count
			AudioServer.add_bus(bi)
			AudioServer.set_bus_name(bi, bn)
			AudioServer.set_bus_send(bi, "Master")
	for n in NAMES:
		streams[n] = load("res://assets/sfx/%s.wav" % n)
	for s in SURFACES:
		for k in 4:
			streams["st_%s%d" % [s, k + 1]] = load("res://assets/sfx/st_%s%d.wav" % [s, k + 1])
		streams["ld_" + s] = load("res://assets/sfx/ld_%s.wav" % s)
	streams["glass"] = _glass_sound()
	for i in 20:
		var p := AudioStreamPlayer.new()
		p.bus = "Efectos"
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


## World sound. pitch < 0 = small random variation. Behind a wall (no straight line from the camera)
## it comes out quieter and muffled, like through the building.
func play3d(name: String, pos: Vector3, vol_db := 0.0, pitch := -1.0, max_d := 140.0) -> void:
	var cam := get_viewport().get_camera_3d()
	var occluded := false
	if cam != null:
		var d := cam.global_position.distance_to(pos)
		if d > max_d:
			return
		if d > 2.0:
			var hit := cam.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, pos, 1))
			occluded = not hit.is_empty() and (hit.position as Vector3).distance_to(pos) > 0.6
	var p := AudioStreamPlayer3D.new()
	p.bus = "Efectos"
	p.stream = streams[name]
	p.volume_db = vol_db - (7.0 if occluded else 0.0)
	p.unit_size = 10.0
	p.max_distance = max_d
	p.pitch_scale = randf_range(0.92, 1.08) if pitch < 0.0 else pitch
	# air absorption with distance; a wall in between takes the highs away
	p.attenuation_filter_cutoff_hz = 1000.0 if occluded else 6000.0
	p.attenuation_filter_db = -18.0
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## Surface under a point (feet): texture / prop id of what the ray hits, else the map's ground.
func surface_at(pos: Vector3, map_i: int) -> String:
	var def: String = MAP_SURF[clampi(map_i, 0, MAP_SURF.size() - 1)]
	var vp := get_viewport()
	if vp == null or vp.world_3d == null:
		return def
	var hit := vp.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.3, 0), pos - Vector3(0, 0.6, 0), 1))
	if hit.is_empty():
		return def
	var col: Object = hit.collider
	# on the ground: painted overlays (asphalt, sidewalks, grass patches...) are on top of it
	if (hit.position as Vector3).y < 0.15:
		var best_y := -1.0
		var tagged := ""
		for g in WBS.ground_tags:
			if pos.x > g[0] and pos.x < g[2] and pos.z > g[1] and pos.z < g[3] and float(g[4]) > best_y:
				best_y = float(g[4])
				tagged = g[5]
		if tagged != "":
			var sg := _surf_of_tag(tagged)
			if sg != "":
				return "snow" if def == "snow" and sg in ["conc", "dirt", "grass"] else sg
	var key := col.get_instance_id()
	if _surf_cache.has(key):
		var c: String = _surf_cache[key]
		return def if c == "" else c
	var tag := ""
	if col.has_meta("tex"):
		tag = str(col.get_meta("tex"))
	elif col is Node:
		for ch in (col as Node).get_children():
			if ch is MeshInstance3D and (ch as MeshInstance3D).material_override != null and (ch as MeshInstance3D).material_override.has_meta("tex"):
				tag = str((ch as MeshInstance3D).material_override.get_meta("tex"))
				break
	var surf := _surf_of_tag(tag)
	# the outdoor ground of the snowy maps is under snow whatever its texture
	if surf in ["", "conc", "dirt", "grass"] and def == "snow" and pos.y < 0.4:
		surf = "snow"
	_surf_cache[key] = surf
	return def if surf == "" else surf


func _surf_of_tag(tag: String) -> String:
	tag = tag.to_lower()
	if tag == "":
		return ""
	for e in SURF_KEYS:
		for kw in e[1]:
			if kw in tag:
				return e[0]
	return ""


func clear_surface_cache() -> void:
	_surf_cache.clear()


## Footstep on surface s: a random one of its 4 variants (2D for the player, 3D for the others).
func step(s: String, vol_db: float, pos = null, last := -1) -> int:
	var k := randi() % 4
	if k == last:
		k = (k + 1) % 4
	var nm := "st_%s%d" % [s, k + 1]
	if pos == null:
		play(nm, vol_db, 0.07)
	else:
		play3d(nm, pos, vol_db, randf_range(0.9, 1.1), 40.0)
	return k


## Breaking window glass, synthesized once: a sharp crack, then many short bright "tinkles"
## (decaying high sine partials) as the shards fall, over a hiss of fine debris.
func _glass_sound() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 1.3)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var w := rng.randf_range(-1.0, 1.0)
		# crack: bright noise burst, ~40 ms
		var crack := (w - lp) * exp(-t * 70.0) * 1.3
		lp = lp * 0.6 + w * 0.4
		# shard hiss
		var hiss := (w - lp) * 0.18 * exp(-t * 3.2) * clampf(t * 20.0, 0.0, 1.0)
		buf[i] = crack + hiss
	# tinkles: each a few inharmonic partials with a fast decay
	for k in 46:
		var t0 := pow(rng.randf(), 1.6) * 1.05
		var f := rng.randf_range(2400.0, 7200.0)
		var amp := rng.randf_range(0.08, 0.28) * (1.0 - t0 * 0.6)
		var dec := rng.randf_range(25.0, 60.0)
		var i0 := int(t0 * rate)
		for j in int(rate * 0.12):
			var idx := i0 + j
			if idx >= n:
				break
			var tt := float(j) / rate
			var e := exp(-tt * dec) * amp
			buf[idx] += e * (sin(TAU * f * tt) + 0.5 * sin(TAU * f * 2.76 * tt) + 0.3 * sin(TAU * f * 5.4 * tt))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * 0.8, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st
