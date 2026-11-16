extends Node3D
## Killstreak aircraft: UAV (circles high, marks enemies), bomber (flies over and carpet-bombs
## a line), stealth helicopter (orbits the player and shoots visible enemies by itself), mortar
## barrage, kamikaze drone and gunship. The player picks 3 streaks in the ARMERO (`DEFS`, saved in
## settings.streaks); the nuke (30 kills) is always there outside co-op zombies.

const SHP := preload("res://scripts/shapes.gd")
const DEFS := {
	"uav": {"name": "UAV", "kills": 3, "desc": "Dron de reconocimiento: marca a los enemigos en el radar durante 30 segundos."},
	"supply": {"name": "Suministros", "kills": 4, "desc": "Una caja con munición y granadas cae a tu lado y te cura del todo."},
	"mortar": {"name": "Mortero", "kills": 5, "desc": "Seis proyectiles de mortero caen donde estés apuntando."},
	"bomber": {"name": "Bombardero", "kills": 6, "desc": "Bombardeo en alfombra en la dirección en la que miras."},
	"drone": {"name": "Dron kamikaze", "kills": 7, "desc": "Un dron busca al enemigo visible más cercano y explota contra él."},
	"heli": {"name": "Helicóptero furtivo", "kills": 8, "desc": "Helicóptero que te sigue y dispara solo a los enemigos durante 35 segundos."},
	"gunship": {"name": "Cañonero", "kills": 12, "desc": "Avión artillado que da vueltas sobre el mapa y dispara proyectiles explosivos durante 30 segundos."},
	"nuke": {"name": "Nuclear", "kills": 30, "desc": "Termina la partida: quien la lanza la gana."},
}
const DEFAULT := ["uav", "bomber", "heli"]
const NUKE_KILLS := 30


## The 3 streaks chosen in the ARMERO (always 3 valid, different ones).
static func chosen(settings: Dictionary) -> Array:
	var out := []
	for id in settings.get("streaks", DEFAULT):
		if DEFS.has(id) and id != "nuke" and not (id in out) and out.size() < 3:
			out.append(id)
	for id in DEFAULT:
		if out.size() < 3 and not (id in out):
			out.append(id)
	return out


## kills needed -> streak id for this player (the nuke only where a match can end: not co-op zombies).
static func table(settings: Dictionary, with_nuke: bool) -> Dictionary:
	var t := {}
	for id in chosen(settings):
		t[int(DEFS[id].kills)] = id
	if with_nuke:
		t[NUKE_KILLS] = "nuke"
	return t

var game
var craft: Array = []      # {node, kind, t, ...}
var bombs: Array = []      # {node, v}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


static func _mat(c: Color, rough := 0.6, metal := 0.3, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cap(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 16
	return c


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 14
	return c


# ---------------------------------------------------------------- models (nose points to -Z)
func _bomber_model() -> Node3D:
	var n := Node3D.new()
	var body := _mat(Color(0.2, 0.22, 0.24), 0.55, 0.4)
	var dark := _mat(Color(0.08, 0.08, 0.09), 0.4, 0.5)
	_mi(n, _cap(1.3, 18.0), body, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	_mi(n, _cap(0.9, 2.6), _mat(Color(0.05, 0.07, 0.1), 0.05, 0.9), Vector3(0, 0.55, -7.2), Vector3(PI / 2 - 0.25, 0, 0))
	for sd in [-1.0, 1.0]:
		var wing := _mi(n, SHP.rbox(Vector3(13.0, 0.35, 4.2), 0.12, 2), body, Vector3(sd * 7.4, -0.2, 0.6), Vector3(0, sd * 0.42, 0))
		wing.scale = Vector3(1, 1, 1)
		for k in 2:
			var ex: float = sd * (4.0 + k * 4.5)
			_mi(n, _cyl(0.55, 3.2), dark, Vector3(ex, -0.9, -0.2 + absf(ex) * 0.42), Vector3(PI / 2, 0, 0))
			_mi(n, _cyl(0.4, 0.1), _mat(Color(1.0, 0.45, 0.15), 0.5, 0.0, 4.0), Vector3(ex, -0.9, 1.45 + absf(ex) * 0.42), Vector3(PI / 2, 0, 0))
		_mi(n, SHP.rbox(Vector3(5.0, 0.25, 2.0), 0.08, 2), body, Vector3(sd * 2.8, 0.3, 8.2), Vector3(0, sd * 0.35, 0))
	_mi(n, SHP.rbox(Vector3(0.3, 4.0, 3.0), 0.1, 2), body, Vector3(0, 2.2, 8.0), Vector3(-0.35, 0, 0))
	for sd in [-1.0, 1.0]:
		_mi(n, _cyl(0.12, 0.1), _mat(Color(1, 0.1, 0.1) if sd < 0 else Color(0.1, 1, 0.2), 0.5, 0.0, 6.0), Vector3(sd * 13.0, -0.2, 2.6), Vector3(0, 0, PI / 2))
	return n


func _uav_model() -> Node3D:
	var n := Node3D.new()
	var grey := _mat(Color(0.55, 0.57, 0.6), 0.5, 0.3)
	_mi(n, _cap(0.35, 5.0), grey, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	_mi(n, SHP.rbox(Vector3(10.0, 0.08, 0.7), 0.03, 1), grey, Vector3(0, 0.1, 0.2))
	for sd in [-1.0, 1.0]:
		_mi(n, SHP.rbox(Vector3(1.6, 0.06, 0.5), 0.02, 1), grey, Vector3(sd * 0.6, 0.4, 2.2), Vector3(0, 0, sd * 0.6))
	var prop := Node3D.new()
	prop.position = Vector3(0, 0, 2.6)
	n.add_child(prop)
	_mi(prop, SHP.rbox(Vector3(1.3, 0.1, 0.03), 0.02, 1), _mat(Color(0.1, 0.1, 0.1)), Vector3.ZERO)
	n.set_meta("prop", prop)
	_mi(n, _cyl(0.08, 0.05), _mat(Color(1, 0.2, 0.1), 0.5, 0.0, 6.0), Vector3(0, -0.38, -0.5))
	return n


func _heli_model() -> Node3D:
	var n := Node3D.new()
	var matte := _mat(Color(0.1, 0.11, 0.12), 0.75, 0.2)
	var glass := _mat(Color(0.03, 0.05, 0.06), 0.05, 0.9)
	_mi(n, SHP.rbox(Vector3(2.2, 1.7, 5.6), 0.45, 3), matte, Vector3(0, 0, 0))
	_mi(n, SHP.rbox(Vector3(1.8, 0.9, 2.0), 0.4, 3), glass, Vector3(0, 0.25, -2.2), Vector3(0.25, 0, 0))
	_mi(n, SHP.rbox(Vector3(0.7, 0.7, 5.5), 0.2, 2), matte, Vector3(0, 0.35, 5.2))
	_mi(n, _cyl(0.9, 0.35), matte, Vector3(0.0, 0.7, 7.9), Vector3(0, 0, PI / 2))
	_mi(n, SHP.rbox(Vector3(2.6, 0.12, 0.8), 0.05, 1), matte, Vector3(0, 0.5, 6.6))
	for sd in [-1.0, 1.0]:
		_mi(n, _cyl(0.06, 3.6), matte, Vector3(sd * 0.95, -1.2, -0.2), Vector3(PI / 2, 0, 0))
		_mi(n, SHP.rbox(Vector3(1.1, 0.35, 0.9), 0.12, 2), matte, Vector3(sd * 1.35, 0.1, 0.3))
	var gun := Node3D.new()
	gun.position = Vector3(0, -1.0, -2.4)
	n.add_child(gun)
	_mi(gun, SHP.rbox(Vector3(0.5, 0.4, 0.5), 0.12, 2), matte, Vector3.ZERO)
	_mi(gun, _cyl(0.06, 1.0), _mat(Color(0.05, 0.05, 0.05), 0.4, 0.6), Vector3(0, -0.05, -0.6), Vector3(PI / 2, 0, 0))
	n.set_meta("gun", gun)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 1.25, 0)
	n.add_child(rotor)
	_mi(rotor, _cyl(0.25, 0.4), matte, Vector3.ZERO)
	for k in 4:
		_mi(rotor, SHP.rbox(Vector3(0.35, 0.05, 7.4), 0.02, 1), matte, Vector3.ZERO, Vector3(0, k * PI / 2, 0)).position = Vector3(0, 0.2, 0)
	n.set_meta("rotor", rotor)
	var tr := Node3D.new()
	tr.position = Vector3(0.0, 0.7, 7.9)
	n.add_child(tr)
	for k in 6:
		_mi(tr, SHP.rbox(Vector3(0.05, 1.5, 0.12), 0.02, 1), matte, Vector3.ZERO, Vector3(k * PI / 6, 0, 0))
	n.set_meta("tail", tr)
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.2, 0.1)
	l.light_energy = 0.0
	l.omni_range = 10.0
	l.position = Vector3(0, -1.1, -3.4)
	n.add_child(l)
	n.set_meta("flash", l)
	return n


# ---------------------------------------------------------------- streak calls
func uav(duration: float) -> void:
	var n := _uav_model()
	add_child(n)
	craft.append({"node": n, "kind": "uav", "t": duration, "a": randf() * TAU})


func bomber(center: Vector3, dir: Vector3) -> void:
	var n := _bomber_model()
	add_child(n)
	var start := center - dir * 150.0 + Vector3(0, 48, 0)
	n.global_position = start
	n.look_at(start + dir, Vector3.UP)
	var drops := []
	for i in 9:
		drops.append(center + dir * (i - 4) * 5.0)
	craft.append({"node": n, "kind": "bomber", "t": 6.0, "dir": dir, "drops": drops, "speed": 55.0})
	game.sfx.play("jet", 2.0)


func heli(duration: float) -> void:
	var n := _heli_model()
	add_child(n)
	var pp: Vector3 = game.player.global_position
	n.global_position = pp + Vector3(80, 30, 0)
	craft.append({"node": n, "kind": "heli", "t": duration, "a": 0.0, "fire": 0.0, "burst": 0, "target": null, "scan": 0.0})


## Mortar barrage: shells whistle down around `center` one after another.
func mortar(center: Vector3) -> void:
	var n := Node3D.new()
	add_child(n)
	var shells := []
	for k in 6:
		shells.append({"t": 1.4 + k * 0.45, "at": center + Vector3(randf_range(-6.5, 6.5), 0, randf_range(-6.5, 6.5))})
	craft.append({"node": n, "kind": "mortar", "t": 8.0, "shells": shells})


func _drone_model() -> Node3D:
	var n := Node3D.new()
	var dark := _mat(Color(0.12, 0.13, 0.12), 0.5, 0.4)
	_mi(n, SHP.rbox(Vector3(0.32, 0.12, 0.45), 0.04, 2), dark, Vector3.ZERO)
	_mi(n, SHP.rbox(Vector3(0.2, 0.1, 0.16), 0.03, 1), _mat(Color(0.35, 0.37, 0.3), 0.6, 0.1), Vector3(0, -0.1, 0.02))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mi(n, SHP.rbox(Vector3(0.36, 0.03, 0.04), 0.01, 1), dark, Vector3(sx * 0.16, 0.02, sz * 0.16), Vector3(0, sx * sz * 0.8, 0))
			var r := _mi(n, _cyl(0.13, 0.01), _mat(Color(0.2, 0.2, 0.2), 0.5, 0.0), Vector3(sx * 0.3, 0.07, sz * 0.3))
			r.transparency = 0.5
	_mi(n, _cyl(0.03, 0.03), _mat(Color(1, 0.15, 0.1), 0.5, 0.0, 8.0), Vector3(0, 0.08, -0.2))
	return n


## Kamikaze drone: takes off in front of the player and dives into the nearest visible enemy.
func drone() -> void:
	var pl = game.player
	if pl == null:
		return
	var n := _drone_model()
	add_child(n)
	var cam: Camera3D = pl.camera
	var fwd := -cam.global_transform.basis.z
	n.global_position = cam.global_position + fwd * 1.2 + Vector3(0, 0.4, 0)
	craft.append({"node": n, "kind": "drone", "t": 14.0, "life": 0.0, "target": null, "scan": 0.0, "v": (fwd + Vector3(0, 0.25, 0)) * 9.0})
	game.sfx.play3d("swish", n.global_position, -4.0)


## Gunship: big plane circling high over the player, explosive shells at visible enemies.
func gunship(duration: float) -> void:
	var n := _bomber_model()
	n.scale = Vector3.ONE * 0.55
	add_child(n)
	var gun := Node3D.new()
	gun.position = Vector3(-1.6, -1.4, -2.0)
	n.add_child(gun)
	n.set_meta("gun", gun)
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.6, 0.3)
	l.light_energy = 0.0
	l.omni_range = 18.0
	gun.add_child(l)
	n.set_meta("flash", l)
	var pp: Vector3 = game.player.global_position if game.player else Vector3.ZERO
	n.global_position = pp + Vector3(90, 58, 0)
	craft.append({"node": n, "kind": "gunship", "t": duration, "a": 0.0, "fire": 2.0, "target": null, "scan": 0.0})
	game.sfx.play("jet", 0.0)


## Nearest enemy visible from `from` (same rules as the helicopter: no teammates, no rising zombies).
func _find_target(from: Vector3, max_d: float):
	var best := max_d
	var tgt = null
	var space := get_world_3d().direct_space_state
	for e in game.enemies:
		if not is_instance_valid(e) or e.dead or (e.get("rise_t") != null and e.rise_t > 0.0):
			continue
		if e.get("puppet") == true and game.net.is_ally(e.peer_id):
			continue
		var ep: Vector3 = e.global_position + Vector3(0, 1.2, 0)
		var d := ep.distance_to(from)
		if d >= best:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, ep, 1)
		if space.intersect_ray(q).is_empty():
			best = d
			tgt = e
	return tgt


func _update_drone(c: Dictionary, n: Node3D, delta: float) -> void:
	c.life += delta
	c.scan -= delta
	var tgt = c.target
	if tgt != null and (not is_instance_valid(tgt) or tgt.dead):
		tgt = null
		c.target = null
	if c.scan <= 0.0 and c.life > 0.4:
		c.scan = 0.3
		if tgt == null:
			c.target = _find_target(n.global_position, 90.0)
			tgt = c.target
	var v: Vector3 = c.v
	if tgt != null:
		var aim: Vector3 = tgt.global_position + Vector3(0, 1.0, 0)
		var want := (aim - n.global_position).normalized() * 19.0
		v = v.lerp(want, minf(1.0, delta * 3.5))
	else:
		var flat := Vector3(v.x, 0.0, v.z)
		if flat.length() < 0.1:
			flat = Vector3(0, 0, -1)
		v = v.lerp(flat.normalized() * 12.0 + Vector3(0, 0.6, 0), minf(1.0, delta * 1.5))
	c.v = v
	var from := n.global_position
	var to := from + v * delta
	var boom: bool = c.t <= 0.0
	if tgt != null and to.distance_to(tgt.global_position + Vector3(0, 1.0, 0)) < 1.6:
		boom = true
	if c.life > 0.5:
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
		if not hit.is_empty():
			to = hit.position
			boom = true
	n.global_position = to
	if v.length() > 0.1:
		n.look_at(to + v, Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.RIGHT)
	if boom:
		game.explode(n.global_position, 320.0, 6.5, "air")
		n.queue_free()
		craft.erase(c)


func _update_gunship(c: Dictionary, n: Node3D, delta: float, pl) -> void:
	var flash: OmniLight3D = n.get_meta("flash")
	flash.light_energy = maxf(0.0, flash.light_energy - delta * 30.0)
	var center: Vector3 = pl.global_position if pl and is_instance_valid(pl) else Vector3.ZERO
	center.y = 0.0
	c.a += delta * 0.16
	var tangent := Vector3(-sin(c.a), 0, cos(c.a))
	if c.t <= 0.0:
		# leaving: straight on along the circle's tangent
		n.global_position += -n.global_transform.basis.z * 60.0 * delta
		if c.t < -6.0:
			n.queue_free()
			craft.erase(c)
		return
	var p := center + Vector3(cos(c.a) * 48.0, 58.0, sin(c.a) * 48.0)
	n.global_position = n.global_position.lerp(p, minf(1.0, delta * 1.2))
	n.look_at(n.global_position + tangent, Vector3.UP)
	n.rotate_object_local(Vector3.FORWARD, 0.4)
	var gun: Node3D = n.get_meta("gun")
	c.scan -= delta
	if c.scan <= 0.0:
		c.scan = 0.6
		c.target = _find_target(gun.global_position, 160.0)
	c.fire -= delta
	if c.fire <= 0.0 and c.target != null and is_instance_valid(c.target) and not c.target.dead:
		c.fire = 1.1
		var aim: Vector3 = c.target.global_position + Vector3(randf_range(-1.6, 1.6), 0.2, randf_range(-1.6, 1.6))
		game.fx.tracer(gun.global_position, aim)
		flash.light_energy = 8.0
		game.sfx.play3d("sniper", gun.global_position, 4.0)
		game.explode(aim, 150.0, 4.2, "air")


func clear() -> void:
	for c in craft:
		if is_instance_valid(c.node):
			c.node.queue_free()
	craft.clear()
	for b in bombs:
		if is_instance_valid(b.node):
			b.node.queue_free()
	bombs.clear()


# ---------------------------------------------------------------- update
func _process(delta: float) -> void:
	if game.state != "playing":
		return
	var pl = game.player
	for c in craft.duplicate():
		var n: Node3D = c.node
		if not is_instance_valid(n):
			craft.erase(c)
			continue
		c.t -= delta
		match c.kind:
			"uav":
				c.a += delta * 0.22
				var p := Vector3(cos(c.a) * 45.0, 62.0, sin(c.a) * 45.0)
				n.global_position = p
				n.look_at(p + Vector3(-sin(c.a), 0, cos(c.a)), Vector3.UP)
				n.rotate_object_local(Vector3.FORWARD, -0.35)
				(n.get_meta("prop") as Node3D).rotation.z += delta * 60.0
				if c.t <= 0.0:
					n.queue_free()
					craft.erase(c)
			"bomber":
				var d: Vector3 = c.dir
				n.global_position += d * c.speed * delta
				var pos := n.global_position
				for target in c.drops.duplicate():
					var to: Vector3 = target - Vector3(pos.x, 0, pos.z)
					if to.dot(d) < 22.0:
						c.drops.erase(target)
						_drop_bomb(pos + Vector3(0, -1.5, 0), d * c.speed * 0.6, target)
				if c.t <= 0.0:
					n.queue_free()
					craft.erase(c)
			"heli":
				_update_heli(c, n, delta, pl)
			"drone":
				_update_drone(c, n, delta)
			"gunship":
				_update_gunship(c, n, delta, pl)
			"mortar":
				for sh in c.shells.duplicate():
					sh.t -= delta
					if sh.t <= 0.0:
						c.shells.erase(sh)
						_drop_shell(sh.at)
				if c.shells.is_empty() or c.t <= 0.0:
					n.queue_free()
					craft.erase(c)
	for b in bombs.duplicate():
		var bn: Node3D = b.node
		if not is_instance_valid(bn):
			bombs.erase(b)
			continue
		b.v += Vector3(0, -22.0, 0) * delta
		bn.global_position += b.v * delta
		bn.look_at(bn.global_position + b.v, Vector3.UP if absf(b.v.normalized().y) < 0.99 else Vector3.RIGHT)
		if bn.global_position.y <= 0.3:
			game.explode(Vector3(bn.global_position.x, 0.0, bn.global_position.z), float(b.get("dmg", 250.0)), float(b.get("r", 8.0)), "air")
			bn.queue_free()
			bombs.erase(b)


func _drop_bomb(from: Vector3, v: Vector3, target: Vector3) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = from
	_mi(n, _cap(0.22, 1.4), _mat(Color(0.25, 0.27, 0.22), 0.5, 0.4), Vector3.ZERO, Vector3(PI / 2, 0, 0))
	# aim the horizontal velocity so the bomb lands on its target
	var fall_t := sqrt(2.0 * from.y / 22.0)
	var hv := (target - Vector3(from.x, 0, from.z)) / fall_t
	bombs.append({"node": n, "v": Vector3(hv.x, 0.0, hv.z)})


## Mortar shell: falls almost straight down onto `at` (whistle on the way).
func _drop_shell(at: Vector3) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at + Vector3(randf_range(-2, 2), 45.0, randf_range(-2, 2))
	_mi(n, _cap(0.09, 0.5), _mat(Color(0.3, 0.32, 0.26), 0.5, 0.4), Vector3.ZERO, Vector3(PI / 2, 0, 0))
	var fall_t := 45.0 / 70.0
	var hv := (at - Vector3(n.global_position.x, 0, n.global_position.z)) / fall_t
	bombs.append({"node": n, "v": Vector3(hv.x, -70.0, hv.z), "dmg": 200.0, "r": 6.5})
	game.sfx.play3d("whiz", at + Vector3(0, 4, 0), 2.0)


func _update_heli(c: Dictionary, n: Node3D, delta: float, pl) -> void:
	(n.get_meta("rotor") as Node3D).rotation.y += delta * 28.0
	(n.get_meta("tail") as Node3D).rotation.x += delta * 40.0
	var flash: OmniLight3D = n.get_meta("flash")
	flash.light_energy = maxf(0.0, flash.light_energy - delta * 40.0)
	var center: Vector3 = pl.global_position if pl and is_instance_valid(pl) else Vector3.ZERO
	var leaving: bool = c.t <= 0.0
	c.a += delta * 0.32
	var goal := center + Vector3(cos(c.a) * 20.0, 22.0, sin(c.a) * 20.0)
	if leaving:
		goal = n.global_position + Vector3(0, 6, 0) + (n.global_position - center).normalized() * 60.0
	var vel := (goal - n.global_position) * minf(1.0, delta * 1.4)
	n.global_position += vel
	# face the target (or flight direction) and bank with speed
	var look_at_p: Vector3 = n.global_position + Vector3(vel.x, 0, vel.z) * 10.0 + Vector3(0.001, 0, 0)
	var tgt = c.target
	if tgt != null and (not is_instance_valid(tgt) or tgt.dead):
		tgt = null
		c.target = null
	if tgt != null:
		look_at_p = Vector3(tgt.global_position.x, n.global_position.y, tgt.global_position.z)
	var want := Basis.looking_at(look_at_p - n.global_position, Vector3.UP)
	n.basis = n.basis.slerp(want, minf(1.0, delta * 2.5)).orthonormalized()
	if leaving:
		if c.t < -5.0:
			n.queue_free()
			craft.erase(c)
		return
	# targeting: nearest enemy it can see
	c.scan -= delta
	if c.scan <= 0.0:
		c.scan = 0.4
		var best := 70.0
		c.target = null
		var space := n.get_world_3d().direct_space_state
		for e in game.enemies:
			if not is_instance_valid(e) or e.dead or (e.get("rise_t") != null and e.rise_t > 0.0):
				continue
			# never target teammates (co-op zombies / team deathmatch)
			if e.get("puppet") == true and game.net.is_ally(e.peer_id):
				continue
			var ep: Vector3 = e.global_position + Vector3(0, 1.2, 0)
			var d := ep.distance_to(n.global_position)
			if d >= best:
				continue
			var q := PhysicsRayQueryParameters3D.create(n.global_position + Vector3(0, -1.5, 0), ep, 1)
			if space.intersect_ray(q).is_empty():
				best = d
				c.target = e
	if c.target == null:
		return
	c.fire -= delta
	if c.fire <= 0.0:
		var gun: Node3D = n.get_meta("gun")
		var from := gun.global_position
		var e = c.target
		var aim: Vector3 = e.global_position + Vector3(0, 1.1, 0)
		gun.look_at(aim, Vector3.UP)
		c.burst += 1
		c.fire = 0.11 if c.burst % 8 != 0 else 0.7
		var hit := randf() < 0.55
		var end := aim if hit else aim + Vector3(randf_range(-1.5, 1.5), randf_range(-1.0, 0.2), randf_range(-1.5, 1.5))
		game.fx.tracer(from, end)
		flash.light_energy = 6.0
		game.sfx.play3d("lmg", from, 2.0)
		if hit:
			game.kill_ctx = {"weapon": -3, "melee": false, "last": false, "dist": 10.0, "hp": pl.health if pl else 100.0, "kind": "heli"}
			e.take_damage(45.0, false)
			game.kill_ctx = {}
			game.fx.blood(aim, (from - aim).normalized())
		else:
			game.fx.impact(Vector3(end.x, maxf(end.y, 0.02), end.z), Vector3.UP)
