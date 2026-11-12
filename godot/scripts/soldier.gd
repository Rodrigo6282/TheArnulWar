extends CharacterBody3D
const SHP := preload("res://scripts/shapes.gd")
const OPT := preload("res://scripts/optimize.gd")
const OPS := preload("res://scripts/operators.gd")
## Enemy soldier: articulated procedural body, engine navigation (NavigationAgent3D), burst fire,
## procedural walk / crouch / aim / reload / hit reaction and three death animations.

var game
var wave := 1
var health := 100.0
var dead := false
var dead_t := 0.0
var speed := 3.2
var facing := 0.0
var los := false
var los_t := 0.0
var seen_t := 0.0
var reaction := 0.6
var fire_t := 0.5
var burst := 0
var ammo := 30
var reload_t := 0.0
var reload_dur := 2.3
var strafe := 0
var strafe_t := 0.0
var crouch_pref := false
var crouch_k := 0.0
var aim_k := 0.0
var gait := 0.0
var phase := 0.0
var kick := 0.0
var hit_k := 0.0
var hit_dir := 1.0
var death_type := 0
var repath_t := 0.0
var seed := 0.0
var flash_t := 0.0
var agent: NavigationAgent3D
var B := {}
var gun: Node3D
var mag: MeshInstance3D
var tip: Node3D
var flash: MeshInstance3D
var gun_vel := Vector3.ZERO
var gun_spin := Vector3.ZERO
var gun_rest := false
var last_shot := -99.0
# multiplayer puppet (a remote human player)
var puppet := false
var peer_id := 0
var display_name := ""
var teammate := false     # co-op: shown with a green name tag
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var net_aim := false
var net_t := 0.0
var op := -1              # operator look (multiplayer puppets / menu preview); -1 = enemy soldier
var MM := {}              # per-instance material overrides

static var M := {}
static var ME := {}


static func _init_assets() -> void:
	if not M.is_empty():
		return
	var mk := func(c: Color, r := 0.85, m := 0.0) -> StandardMaterial3D:
		var s := StandardMaterial3D.new()
		s.albedo_color = c
		s.roughness = r
		s.metallic = m
		return s
	M = {"uniform": mk.call(Color(0.29, 0.31, 0.25)), "uniform2": mk.call(Color(0.24, 0.26, 0.21)), "vest": mk.call(Color(0.17, 0.18, 0.15)),
		"skin": mk.call(Color(0.72, 0.54, 0.41), 0.7), "helmet": mk.call(Color(0.23, 0.24, 0.2), 0.6), "boots": mk.call(Color(0.1, 0.1, 0.1)),
		"gun": mk.call(Color(0.11, 0.11, 0.12), 0.45, 0.6), "glove": mk.call(Color(0.1, 0.1, 0.09)), "pack": mk.call(Color(0.32, 0.33, 0.25)),
		"strap": mk.call(Color(0.12, 0.12, 0.1)), "goggles": mk.call(Color(0.05, 0.05, 0.05), 0.08, 0.9)}
	var flash_m := StandardMaterial3D.new()
	flash_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_m.albedo_color = Color(4.0, 2.6, 1.2)
	M["flash"] = flash_m
	ME = {"pelvis": _box(0.36, 0.2, 0.24), "belly": _box(0.34, 0.24, 0.22), "chest": _box(0.46, 0.36, 0.27), "vest": _box(0.5, 0.32, 0.32),
		"pouch": _box(0.1, 0.13, 0.06), "pack": _box(0.34, 0.4, 0.17), "radio": _box(0.12, 0.2, 0.07), "shoulder": _sphere(0.085),
		"neck": _cyl(0.065, 0.12), "head": _sphere(0.125), "helmet": _hemi(0.155), "goggles": _box(0.19, 0.055, 0.05), "nvg": _box(0.07, 0.05, 0.05),
		"thigh": _cap(0.09, 0.5), "knee": _box(0.12, 0.13, 0.06), "shin": _cap(0.075, 0.46), "boot": _box(0.15, 0.11, 0.28),
		"gbody": _box(0.07, 0.11, 0.48), "gbarrel": _cyl(0.017, 0.34), "gmag": _box(0.05, 0.16, 0.07), "gstock": _box(0.05, 0.08, 0.2),
		"hand": _sphere(0.05), "flash": _quad(0.5), "antenna": _cyl(0.006, 0.42)}


static func _box(x: float, y: float, z: float) -> Mesh:
	return SHP.rbox(Vector3(x, y, z), minf(x, minf(y, z)) * 0.35, 3)


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 20
	m.rings = 12
	return m


static func _hemi(r: float) -> SphereMesh:
	var m := _sphere(r)
	m.is_hemisphere = true
	m.height = r
	return m


static func _cyl(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 12
	return m


static func _cap(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 16
	m.rings = 6
	return m


static func _quad(s: float) -> QuadMesh:
	var m := QuadMesh.new()
	m.size = Vector2(s, s)
	return m


func _g(parent: Node3D, p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	parent.add_child(n)
	return n


func _m(parent: Node3D, mesh_key: String, mat_key: String, p: Vector3, r := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ME[mesh_key]
	mi.material_override = MM.get(mat_key, M[mat_key])
	mi.position = p
	mi.rotation = r
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _limb(parent: Node3D, a: Vector3, b: Vector3, r: float, mat_key: String) -> void:
	var d := b - a
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = d.length() + r * 2.0
	cm.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = MM.get(mat_key, M[mat_key])
	mi.position = (a + b) * 0.5
	mi.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	parent.add_child(mi)


func _ready() -> void:
	_init_assets()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 2
	collision_mask = 1 | 2
	seed = randf() * 10.0
	health = 100.0 + (wave - 1) * 4.0
	speed = minf(3.0 + wave * 0.12, 4.6)
	reaction = randf_range(0.35, 0.8) / game.DIFF_ACC[game.settings.diff]
	fire_t = randf_range(0.3, 1.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	if puppet:
		health = 1.0e9
		var lab := Label3D.new()
		lab.text = display_name
		lab.font_size = 42
		lab.outline_size = 10
		lab.pixel_size = 0.004
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.modulate = Color(0.45, 1.0, 0.5) if teammate else Color(1.0, 0.45, 0.35)
		lab.position.y = 2.25
		lab.no_depth_test = false
		add_child(lab)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.7
	agent.target_desired_distance = 1.2
	agent.radius = 0.5
	agent.height = 1.8
	add_child(agent)
	_build_body()


func _apply_operator() -> void:
	var o: Dictionary = OPS.get_op(op)
	for k in ["uniform", "uniform2", "vest", "pack", "helmet", "skin"]:
		var m: StandardMaterial3D = M[k].duplicate()
		m.albedo_color = o[k]
		MM[k] = m
	var g: StandardMaterial3D = M.glove.duplicate()
	g.albedo_color = o.glove
	MM["glove"] = g


func _headgear() -> void:
	var kind: String = OPS.get_op(op).head if op >= 0 else "helmet"
	match kind:
		"helmet":
			_m(B.head, "helmet", "helmet", Vector3(0, 0.1, 0.005))
			_m(B.head, "goggles", "goggles", Vector3(0, 0.085, -0.112), Vector3.ZERO, false)
			_m(B.head, "nvg", "strap", Vector3(0, 0.2, -0.13), Vector3.ZERO, false)
		"balaclava":
			var hm := _m(B.head, "head", "helmet", Vector3(0, 0.085, 0))
			hm.scale = Vector3(1.05, 1.05, 1.05)
			_m(B.head, "goggles", "goggles", Vector3(0, 0.09, -0.117), Vector3.ZERO, false)
		"boonie":
			var h := _m(B.head, "helmet", "helmet", Vector3(0, 0.12, 0.0))
			h.scale = Vector3(0.88, 0.8, 0.88)
			var brim := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.22
			c.bottom_radius = 0.23
			c.height = 0.015
			brim.mesh = c
			brim.material_override = MM.get("helmet", M.helmet)
			brim.position = Vector3(0, 0.13, 0)
			B.head.add_child(brim)
		"beanie":
			var h2 := _m(B.head, "helmet", "helmet", Vector3(0, 0.11, 0.0))
			h2.scale = Vector3(0.86, 1.25, 0.86)
		"cap":
			var h3 := _m(B.head, "helmet", "helmet", Vector3(0, 0.12, 0.0))
			h3.scale = Vector3(0.84, 0.7, 0.84)
			var bm := MeshInstance3D.new()
			bm.mesh = _box(0.17, 0.015, 0.11)
			bm.material_override = MM.get("helmet", M.helmet)
			bm.position = Vector3(0, 0.13, -0.15)
			bm.rotation.x = -0.12
			B.head.add_child(bm)
		"bandana":
			var h4 := _m(B.head, "helmet", "helmet", Vector3(0, 0.12, 0.0))
			h4.scale = Vector3(0.85, 0.55, 0.85)


func _build_body() -> void:
	if op >= 0:
		_apply_operator()
	var root := _g(self, Vector3.ZERO)
	B.root = root
	B.hips = _g(root, Vector3(0, 0.95, 0))
	B.spine = _g(B.hips, Vector3(0, 0.08, 0))
	B.chest = _g(B.spine, Vector3(0, 0.2, 0))
	B.neck = _g(B.chest, Vector3(0, 0.36, 0))
	B.head = _g(B.neck, Vector3(0, 0.06, 0))
	for sd in [-1, 1]:
		var k := "L" if sd < 0 else "R"
		B["th" + k] = _g(B.hips, Vector3(0.11 * sd, -0.04, 0))
		B["kn" + k] = _g(B["th" + k], Vector3(0, -0.44, 0))
		B["ft" + k] = _g(B["kn" + k], Vector3(0, -0.42, 0))
		_m(B["th" + k], "thigh", "uniform2", Vector3(0, -0.22, 0))
		_m(B["kn" + k], "knee", "pack", Vector3(0, 0, -0.07), Vector3.ZERO, false)
		_m(B["kn" + k], "shin", "uniform2", Vector3(0, -0.21, 0))
		_m(B["ft" + k], "boot", "boots", Vector3(0, 0, -0.05))
	_m(B.hips, "pelvis", "uniform2", Vector3.ZERO)
	_m(B.spine, "belly", "uniform", Vector3(0, 0.1, 0))
	_m(B.chest, "chest", "uniform", Vector3(0, 0.17, 0))
	_m(B.chest, "vest", "vest", Vector3(0, 0.15, 0))
	for px in [-0.13, 0.0, 0.13]:
		_m(B.chest, "pouch", "pack", Vector3(px, 0.07, -0.17), Vector3.ZERO, false)
	_m(B.chest, "pack", "pack", Vector3(0, 0.17, 0.22))
	_m(B.chest, "radio", "strap", Vector3(0.12, 0.26, 0.32), Vector3.ZERO, false)
	_m(B.chest, "antenna", "strap", Vector3(0.15, 0.55, 0.33), Vector3.ZERO, false)
	for sd in [-1, 1]:
		_m(B.chest, "shoulder", "uniform", Vector3(0.25 * sd, 0.29, 0), Vector3.ZERO, false)
	_m(B.neck, "neck", "skin", Vector3.ZERO)
	_m(B.head, "head", "skin", Vector3(0, 0.08, 0))
	_headgear()
	# weapon rig: rifle + arms pivoting at shoulder height
	B.rig = _g(B.chest, Vector3(0, 0.27, 0))
	gun = _g(B.rig, Vector3(0.1, 0, -0.28))
	_m(gun, "gbody", "gun", Vector3(0, 0, -0.05))
	_m(gun, "gbarrel", "gun", Vector3(0, 0.015, -0.45), Vector3(PI / 2, 0, 0))
	_m(gun, "gstock", "gun", Vector3(0, -0.02, 0.27))
	mag = _m(gun, "gmag", "gun", Vector3(0, -0.11, -0.09), Vector3(0.22, 0, 0))
	tip = _g(gun, Vector3(0, 0.015, -0.63))
	flash = _m(gun, "flash", "flash", Vector3(0, 0.015, -0.63), Vector3.ZERO, false)
	flash.visible = false
	_limb(B.rig, Vector3(0.25, 0, 0.02), Vector3(0.24, -0.22, -0.08), 0.066, "uniform")
	_limb(B.rig, Vector3(0.24, -0.22, -0.08), Vector3(0.12, -0.09, -0.2), 0.056, "uniform")
	_m(B.rig, "hand", "glove", Vector3(0.12, -0.08, -0.21), Vector3.ZERO, false)
	B.armL = _g(B.rig, Vector3(-0.25, 0, 0.02))
	_limb(B.armL, Vector3.ZERO, Vector3(0.05, -0.2, -0.28), 0.066, "uniform")
	_limb(B.armL, Vector3(0.05, -0.2, -0.28), Vector3(0.31, -0.05, -0.47), 0.056, "uniform")
	_m(B.armL, "hand", "glove", Vector3(0.32, -0.04, -0.48), Vector3.ZERO, false)


func take_damage(d: float, head: bool) -> bool:
	if dead:
		return false
	if puppet:
		# the owner of this player decides; damage is sent over the network
		hit_k = 1.0
		hit_dir = -1.0 if randf() < 0.5 else 1.0
		game.net.send_hit(peer_id, d, head)
		return false
	health -= d
	hit_k = 1.0
	hit_dir = -1.0 if randf() < 0.5 else 1.0
	seen_t = maxf(seen_t, reaction * 0.5)
	if health <= 0.0:
		_die(head)
		return true
	return false


func _die(head: bool) -> void:
	dead = true
	dead_t = 0.0
	death_type = 0 if head else randi() % 3
	collision_layer = 0
	flash.visible = false
	velocity = Vector3.ZERO
	gun.reparent(game.world)
	gun_vel = Vector3(randf_range(-1, 1), randf_range(1, 2), randf_range(-1, 1))
	gun_spin = Vector3(randf_range(-5, 5), randf_range(-3, 3), randf_range(-5, 5))
	game.register_kill(head)
	game.drop_loot(global_position)


## Remote player died (confirmed by its owner): play the death without awarding anything here.
func net_die(head: bool) -> void:
	if dead:
		return
	dead = true
	dead_t = 0.0
	death_type = 0 if head else randi() % 3
	collision_layer = 0
	flash.visible = false
	velocity = Vector3.ZERO
	gun.reparent(game.world)
	gun_vel = Vector3(randf_range(-1, 1), randf_range(1, 2), randf_range(-1, 1))
	gun_spin = Vector3(randf_range(-5, 5), randf_range(-3, 3), randf_range(-5, 5))


func _puppet_process(delta: float) -> void:
	var before := global_position
	var d := net_pos - global_position
	if d.length() > 6.0:
		global_position = net_pos
	else:
		global_position = global_position.lerp(net_pos, 1.0 - exp(-14.0 * delta))
	facing = lerp_angle(facing, net_yaw, 1.0 - exp(-14.0 * delta))
	rotation.y = facing
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_animate(delta, moved, net_aim or crouch_pref, clampf(net_pitch, -0.8, 0.8), 0.0)
	flash_t -= delta
	flash.visible = flash_t > 0.0


func _exit_tree() -> void:
	if is_instance_valid(gun) and gun.get_parent() != B.get("rig"):
		gun.queue_free()


func _has_los(pl) -> bool:
	var from := global_position + Vector3(0, 1.7, 0)
	var to: Vector3 = pl.global_position + Vector3(0, pl.eye_height() - 0.1, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _shoot(dist: float, pl) -> void:
	var acc: float = game.DIFF_ACC[game.settings.diff]
	var chance := (0.4 - dist * 0.0045) * acc * (1.0 + wave * 0.03)
	var ps := Vector2(pl.velocity.x, pl.velocity.z).length()
	if ps > 6.0:
		chance *= 0.55
	elif ps > 3.0:
		chance *= 0.8
	if pl.crouch > 0.5:
		chance *= 0.75
	if absf(pl.lean) > 0.5:
		chance *= 0.8
	chance = clampf(chance, 0.05, 0.75)
	flash_t = 0.05
	kick = 1.0
	ammo -= 1
	last_shot = game.clock
	var from := tip.global_position
	var target: Vector3 = pl.camera.global_position - Vector3(0, 0.25, 0)
	var hit := randf() < chance
	if not hit:
		target += Vector3(randf_range(-1.2, 1.2), randf_range(-0.6, 0.9), randf_range(-1.2, 1.2))
	game.fx.tracer(from, target)
	game.fx.flash_light(from, 2.0, 5.0)
	game.sfx.play3d("enemy", from, -2.0)
	if hit:
		game.damage_player(randf_range(6, 10), global_position)
	elif dist < 30.0 and randf() < 0.5:
		game.sfx.play("whiz", -10)


func _leg_pose(ph: float, g: float, c: float) -> void:
	var st := 0.5 * g
	var kb := 0.15 + 0.95 * g
	var tl := sin(ph) * st
	var tr := -sin(ph) * st
	var kl := -maxf(0.0, sin(ph + 1.3)) * kb
	var kr := -maxf(0.0, sin(ph + 1.3 + PI)) * kb
	tl = lerpf(tl, 1.05, c)
	tr = lerpf(tr, 0.5, c)
	kl = lerpf(kl, -1.9, c)
	kr = lerpf(kr, -1.45, c)
	B.thL.rotation.x = tl
	B.thR.rotation.x = tr
	B.knL.rotation.x = kl
	B.knR.rotation.x = kr
	B.ftL.rotation.x = -(tl + kl) * 0.7
	B.ftR.rotation.x = -(tr + kr) * 0.7


func _animate(delta: float, moved: float, aiming: bool, aim_pitch: float, rel_yaw: float) -> void:
	var sp := moved / maxf(delta, 0.0001)
	gait = lerpf(gait, clampf(sp / 4.2, 0.0, 1.25), 1.0 - exp(-10.0 * delta))
	phase += moved * 2.7
	crouch_k = lerpf(crouch_k, 1.0 if crouch_pref and aiming and gait < 0.15 else 0.0, 1.0 - exp(-6.0 * delta))
	aim_k = lerpf(aim_k, 1.0 if aiming and reload_t <= 0.0 else 0.0, 1.0 - exp(-8.0 * delta))
	var g := gait
	var sn := sin(phase)
	var tt: float = game.clock + seed
	_leg_pose(phase, g, crouch_k)
	B.hips.position.y = 0.95 - crouch_k * 0.36 + absf(cos(phase)) * 0.035 * g
	B.hips.rotation.y = sn * 0.07 * g * (1.0 - aim_k * 0.5)
	B.spine.rotation.x = -(0.06 + 0.18 * g * (1.0 - aim_k) + crouch_k * 0.15)
	hit_k = maxf(0.0, hit_k - delta * 5.0)
	B.chest.rotation = Vector3(-(sin(tt * 1.7) * 0.015 - hit_k * 0.35), -sn * 0.09 * g * (1.0 - aim_k) + rel_yaw * 0.4 * aim_k, hit_dir * hit_k * 0.25)
	B.neck.rotation.y = rel_yaw * 0.5 * aim_k
	B.head.rotation.x = aim_pitch * 0.4 * aim_k
	kick = maxf(0.0, kick - delta * 10.0)
	var rx := lerpf(-0.5 - 0.25 * g, aim_pitch, aim_k) + kick * 0.1 + sin(phase * 2.0) * 0.03 * g * (1.0 - aim_k)
	var rz := sin(phase) * 0.06 * g * (1.0 - aim_k)
	var arx := 0.0
	if reload_t > 0.0:
		var p := 1.0 - reload_t / reload_dur
		var e := sin(minf(1.0, p * 1.15) * PI)
		rz += e * 0.35
		rx = lerpf(rx, -0.25, e)
		arx = -sin(clampf((p - 0.1) / 0.8, 0.0, 1.0) * PI) * 0.9
		mag.visible = not (p > 0.3 and p < 0.62)
	else:
		mag.visible = true
	B.rig.rotation = Vector3(rx, 0, rz)
	B.rig.position.z = kick * 0.04
	B.armL.rotation = Vector3(arx, 0, -arx * 0.3)


func _death_anim() -> void:
	var r: Node3D = B.root
	var t := dead_t
	if death_type == 0:
		var k := clampf(t / 0.55, 0.0, 1.0)
		r.rotation.x = (k * k) * PI / 2 * 0.97
		B.knL.rotation.x = -0.6 * minf(1.0, t * 4.0) * (1.0 - k * 0.6)
		B.knR.rotation.x = B.knL.rotation.x
	elif death_type == 1:
		var k1 := clampf(t / 0.4, 0.0, 1.0)
		var k2 := clampf((t - 0.35) / 0.5, 0.0, 1.0)
		B.hips.position.y = lerpf(0.95, 0.5, k1)
		B.thL.rotation.x = 1.3 * k1
		B.thR.rotation.x = 1.3 * k1
		B.knL.rotation.x = -2.2 * k1
		B.knR.rotation.x = -2.2 * k1
		r.rotation.x = -(k2 * k2) * PI / 2 * 0.9
	else:
		var k3 := clampf(t / 0.7, 0.0, 1.0)
		r.rotation.z = hit_dir * (k3 * k3) * PI / 2 * 0.95
		B.chest.rotation.y = hit_dir * 0.6 * k3


func _physics_process(delta: float) -> void:
	var pl = game.player
	if dead:
		dead_t += delta
		_death_anim()
		if not gun_rest and is_instance_valid(gun):
			gun_vel.y -= 12.0 * delta
			gun.global_position += gun_vel * delta
			gun.rotation += gun_spin * delta
			if gun.global_position.y < 0.06:
				gun.global_position.y = 0.06
				gun_rest = true
				gun.rotation = Vector3(0, gun.rotation.y, PI / 2)
		if dead_t > 6.0:
			B.root.position.y -= delta * 0.5
		if dead_t > 8.0:
			queue_free()
		return
	if puppet:
		_puppet_process(delta)
		return
	if pl == null or not is_instance_valid(pl):
		return
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	var to: Vector3 = pl.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var n := to / maxf(dist, 0.001)
	los_t -= delta
	if los_t <= 0.0:
		los_t = randf_range(0.15, 0.25)
		los = pl.alive and dist < 75.0 and _has_los(pl)
	if los:
		seen_t += delta
	else:
		seen_t = maxf(0.0, seen_t - delta * 2.0)
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			ammo = 30
	var mv := Vector3.ZERO
	var spd := speed
	if los:
		facing = lerp_angle(facing, atan2(-n.x, -n.z), minf(1.0, delta * 10.0))
		if dist > 20.0:
			mv = n
		elif dist < 7.0:
			mv = -n
		strafe_t -= delta
		if strafe_t <= 0.0:
			strafe = [-1, 0, 0, 1][randi() % 4]
			strafe_t = randf_range(0.8, 2.2)
			crouch_pref = dist > 14.0 and randf() < 0.45
		if crouch_pref:
			strafe = 0
		mv += Vector3(-n.z, 0, n.x) * strafe
		spd *= 0.0 if crouch_pref else 0.6
		if seen_t > reaction and reload_t <= 0.0:
			if ammo <= 0:
				reload_t = reload_dur
			else:
				fire_t -= delta
				if fire_t <= 0.0:
					if burst > 0:
						_shoot(dist, pl)
						burst -= 1
						fire_t = 0.13
					else:
						burst = 3 + randi() % 3
						fire_t = randf_range(0.7, 1.6)
	else:
		repath_t -= delta
		if repath_t <= 0.0:
			repath_t = 0.4
			agent.target_position = pl.global_position
		if not agent.is_navigation_finished():
			var nxt := agent.get_next_path_position()
			mv = nxt - global_position
			mv.y = 0.0
			mv = mv.normalized()
		else:
			mv = n
	if mv.length() > 0.01 and spd > 0.0:
		mv = mv.normalized()
		velocity.x = mv.x * spd
		velocity.z = mv.z * spd
		if not los:
			facing = lerp_angle(facing, atan2(-mv.x, -mv.z), minf(1.0, delta * 8.0))
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	var before := global_position
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	var aim_pitch := atan2(pl.global_position.y + pl.eye_height() - 0.3 - (global_position.y + 1.5 - crouch_k * 0.36), dist)
	_animate(delta, moved, los, clampf(aim_pitch, -0.8, 0.8), clampf(wrapf(atan2(-n.x, -n.z) - facing, -PI, PI), -0.8, 0.8))
	rotation.y = facing
	flash_t -= delta
	flash.visible = flash_t > 0.0
