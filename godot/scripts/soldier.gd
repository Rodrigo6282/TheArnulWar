extends CharacterBody3D
const SHP := preload("res://scripts/shapes.gd")
const GLASS := preload("res://scripts/glass.gd")
const OPT := preload("res://scripts/optimize.gd")
const OPS := preload("res://scripts/operators.gd")
const RIG := preload("res://scripts/rig.gd")
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
var label_col := Color(1.0, 0.45, 0.35)
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var aim_pitch_out := 0.0
var step_d := 0.0          # distance walked since the last footstep sound   # host bots: aim pitch streamed to the clients' puppets
var net_aim := false
var net_t := 0.0
var op := -1              # operator look (multiplayer puppets / menu preview); -1 = enemy soldier
var MM := {}              # per-instance material overrides
var R := {}               # Mixamo body (rig.gd): node, skel, ap, aim; empty = procedural body
var _prev := Vector3.ZERO
# ---- smarter AI (Operación soldiers and multiplayer bots)
var bot_id := 0           # >0: multiplayer bot simulated by the host (net.gd), fights players and other bots
var bot_wpn := 0          # bot's weapon (index of player.weapons) for damage / fire rate
var max_hp := 100.0
var target = null         # player / puppet / bot being fought
var target_t := 0.0
var last_known := Vector3.ZERO
var intel_t := -99.0      # game.clock when the target was last seen (by us or a squadmate)
var share_t := 0.0
var role := 0             # 0 assault, 1 flanker (goes around), 2 support (holds and suppresses)
var flank_side := 1.0
var cover_pos := Vector3.ZERO
var cover_state := 0      # 0 none, 1 moving to cover, 2 in cover
var cover_t := 0.0
var cover_cd := 0.0
var nades := 1
var nade_cd := 6.0
var hit_by := 0           # set by whoever damages a bot right before take_damage (net id)
var killer_id := 0
var stuck_t := 0.0
var detour := Vector3.ZERO
var suppress := 0.0       # bullets passing close by (player.fire): seek cover, aim slower
var flee_t := 0.0         # running from a live grenade
var flee_check_t := 0.0
var flee_pos := Vector3.ZERO
var nade_at := Vector3.ZERO
var detour_t := 0.0

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
	reaction = randf_range(0.35, 0.8) / _acc()
	fire_t = randf_range(0.3, 1.0)
	role = [0, 0, 1, 2][randi() % 4]
	flank_side = -1.0 if randf() < 0.5 else 1.0
	nades = 1 if randf() < 0.6 else 0
	nade_cd = randf_range(5.0, 12.0)
	if bot_id > 0:
		health = 100.0
		speed = 4.2
		nades = 2
		role = randi() % 3
	max_hp = health
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	if puppet:
		health = 1.0e9
	if puppet or bot_id > 0:
		var lab := Label3D.new()
		lab.text = display_name
		lab.font_size = 42
		lab.outline_size = 10
		lab.pixel_size = 0.004
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.modulate = label_col
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


## Horizontal direction of the next nav path point towards the player (ZERO when the path is done).
func _path_dir(pl: Node3D) -> Vector3:
	return _path_to(pl.global_position)


var _path_goal := Vector3.INF


func _path_to(goal: Vector3) -> Vector3:
	repath_t -= get_physics_process_delta_time()
	if repath_t <= 0.0 or _path_goal.distance_to(goal) > 2.0:
		repath_t = 0.4
		_path_goal = goal
		agent.target_position = goal
	if agent.is_navigation_finished():
		return Vector3.ZERO
	var mv := agent.get_next_path_position() - global_position
	mv.y = 0.0
	return mv.normalized() if mv.length() > 0.01 else Vector3.ZERO


## CharacterBody3D can't climb vertical edges, but the nav mesh links anything up to its
## agent_max_climb (0.5 m): curbs, low crates, the lip at the foot of a ramp.
## When blocked while walking, lift by up to STEP if there is room up there and ahead.
const STEP := 0.5


func _step_up(before: Vector3, want: Vector3) -> void:
	if want.length() < 0.001 or not is_on_wall():
		return
	var got := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if got > want.length() * 0.6:
		return
	var xf := global_transform
	xf.origin = before
	if test_move(xf, Vector3.UP * STEP):
		return   # no headroom
	xf.origin += Vector3.UP * STEP
	var ahead := want.normalized() * maxf(want.length(), 0.12)
	if test_move(xf, ahead):
		return   # still a wall: too tall to step on
	global_position = before + Vector3.UP * STEP + ahead
	velocity.y = 0.0
	apply_floor_snap()


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


func _build_skin() -> void:
	var id: String = RIG.SOLDIERS[randi() % RIG.SOLDIERS.size()]
	var tint := Color.WHITE
	if op >= 0:
		id = OPS.get_op(op).body
		tint = OPS.get_op(op).tint
	R = RIG.make(self, id, tint)
	B.root = R.node
	gun = _g(RIG.gun_mount(R, id), Vector3.ZERO)
	_m(gun, "gbody", "gun", Vector3(0, 0, -0.05))
	_m(gun, "gbarrel", "gun", Vector3(0, 0.015, -0.45), Vector3(PI / 2, 0, 0))
	_m(gun, "gstock", "gun", Vector3(0, -0.02, 0.27))
	mag = _m(gun, "gmag", "gun", Vector3(0, -0.11, -0.09), Vector3(0.22, 0, 0))
	tip = _g(gun, Vector3(0, 0.015, -0.63))
	flash = _m(gun, "flash", "flash", Vector3(0, 0.015, -0.63), Vector3.ZERO, false)
	flash.visible = false
	(R.ap as AnimationPlayer).play("idle")
	(R.ap as AnimationPlayer).seek(randf() * 2.0, true)
	_prev = global_position


## Mixamo body: pick the clip from speed / direction / state; the spine follows the aim.
func _animate_skin(delta: float, moved: float, aiming: bool, aim_pitch: float, rel_yaw: float) -> void:
	var ap: AnimationPlayer = R.ap
	var sp := moved / maxf(delta, 0.0001)
	gait = lerpf(gait, sp, 1.0 - exp(-8.0 * delta))
	var d := global_position - _prev
	_prev = global_position
	var local := Basis(Vector3.UP, facing).inverse() * d
	var firing: bool = game.clock - last_shot < 0.9 or burst > 0 or (aiming and fire_t < 0.35 and not puppet)
	crouch_k = lerpf(crouch_k, 1.0 if crouch_pref and aiming and not firing else 0.0, 1.0 - exp(-(10.0 if firing else 6.0) * delta))
	aim_k = lerpf(aim_k, 1.0 if aiming and reload_t <= 0.0 else 0.0, 1.0 - exp(-8.0 * delta))
	hit_k = maxf(0.0, hit_k - delta * 5.0)
	kick = maxf(0.0, kick - delta * 10.0)
	var clip := "idle"
	var rate := 1.0
	if reload_t > 0.0:
		clip = "reload"
		rate = 3.3 / reload_dur
		var p := 1.0 - reload_t / reload_dur
		mag.visible = not (p > 0.3 and p < 0.62)
	else:
		mag.visible = true
		if crouch_k > 0.5:
			clip = "crouch"
			rate = clampf(gait / 1.1, 0.0, 1.5)
		elif gait < 0.45:
			clip = ("fire" if game.clock - last_shot < 0.35 else "aim") if aiming else "idle"
		elif gait > 3.6 and not aiming:
			clip = "run"
			rate = clampf(gait / 4.6, 0.7, 1.4)
		else:
			var fz := -local.z
			var fx := local.x
			if absf(fx) > absf(fz) * 1.2:
				clip = "right" if fx > 0.0 else "left"
			elif fz < 0.0:
				clip = "back"
			else:
				clip = "walk"
			rate = clampf(gait / 1.5, 0.6, 1.8)
	if ap.current_animation != clip:
		ap.play(clip, 0.25 if clip != "fire" else 0.1)
	ap.speed_scale = rate
	var aim: RIG.Aim = R.aim
	aim.pitch = aim_pitch * aim_k + kick * 0.05 - hit_k * 0.25
	aim.yaw = rel_yaw * 0.6 * aim_k + hit_dir * hit_k * 0.2


func _skin_die(head: bool) -> void:
	var aim: RIG.Aim = R.aim
	aim.pitch = 0.0
	aim.yaw = 0.0
	var ap: AnimationPlayer = R.ap
	ap.speed_scale = 1.0
	ap.play("die_head" if head else ["die_front", "die_back"][randi() % 2], 0.12)


func _build_body() -> void:
	if RIG.available():
		_build_skin()
		return
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
		# teammates (team deathmatch / co-op) can't be hurt
		if game.net.is_ally(peer_id):
			return false
		# the owner of this player decides; damage is sent over the network
		hit_k = 1.0
		hit_dir = -1.0 if randf() < 0.5 else 1.0
		game.net.send_hit(peer_id, d, head)
		return false
	if bot_id > 0:
		# friendly fire between bots / host player on the same team is ignored
		var att: int = hit_by if hit_by != 0 else int(game.net.my_id())
		if att != bot_id and game.net.same_team(att, bot_id):
			return false
		killer_id = att
	health -= d
	hit_k = 1.0
	hit_dir = -1.0 if randf() < 0.5 else 1.0
	seen_t = maxf(seen_t, reaction * 0.5)
	# turn towards whoever shot us, even without line of sight
	var src = _attacker_node()
	if src != null:
		last_known = src.global_position
		intel_t = game.clock
		if bot_id > 0 and (target == null or not los):
			target = src
	# hurt: break off and look for cover soon
	if health < max_hp * 0.5 and cover_state == 0:
		cover_cd = minf(cover_cd, 0.2)
	if health <= 0.0:
		_die(head)
		return true
	return false


## The node that hit us last (operation soldiers: always the player).
func _attacker_node():
	if bot_id == 0:
		return game.player if game.player and is_instance_valid(game.player) else null
	return game.net.node_of(killer_id)


func _die(head: bool) -> void:
	dead = true
	dead_t = 0.0
	death_type = 0 if head else randi() % 3
	collision_layer = 0
	flash.visible = false
	if not R.is_empty():
		_skin_die(head)
	velocity = Vector3.ZERO
	gun.reparent(game.world)
	gun_vel = Vector3(randf_range(-1, 1), randf_range(1, 2), randf_range(-1, 1))
	gun_spin = Vector3(randf_range(-5, 5), randf_range(-3, 3), randf_range(-5, 5))
	if bot_id > 0:
		# multiplayer bot: the host announces the death (kill credit goes through net.died)
		game.net.bot_died(bot_id, killer_id, head, bool(game.kill_ctx.get("melee", false)) if game.kill_ctx else false)
		return
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
	if not R.is_empty():
		_skin_die(head)
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
	_footsteps(moved)
	flash_t -= delta
	flash.visible = flash_t > 0.0


func _exit_tree() -> void:
	if is_instance_valid(gun) and gun.get_parent() != B.get("rig"):
		gun.queue_free()


## 3D footsteps for soldiers, bots and remote players (you hear them coming round the corner).
func _footsteps(moved: float) -> void:
	if collision_layer == 0 or moved > 2.0:
		return   # our own third-person body (the player plays its own steps) / teleports
	step_d += moved
	var stride := 1.5 if crouch_k < 0.5 else 1.0
	if step_d < stride:
		return
	step_d = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(global_position) > 32.0:
		return
	var run: bool = moved > 0.07
	game.sfx.step(game.sfx.surface_at(global_position, game.map_idx), (-9.0 if run else -13.0) - (6.0 if crouch_k > 0.5 else 0.0), global_position + Vector3(0, 0.1, 0))


## Accuracy multiplier: difficulty for Operación, bot skill in multiplayer.
func _acc() -> float:
	if bot_id > 0:
		return [0.65, 1.0, 1.4][clampi(int(game.settings.get("bot_skill", 1)), 0, 2)]
	return game.DIFF_ACC[game.settings.diff]


# ---- target helpers: the local player (alive/eye_height), a remote puppet or another bot (dead)
func _t_alive(t) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	if t.get("alive") != null:
		return bool(t.alive)
	return not bool(t.dead)


func _t_eye(t) -> Vector3:
	if t.has_method("eye_height"):
		return t.global_position + Vector3(0, t.eye_height(), 0)
	var cr: float = float(t.get("crouch_k")) if t.get("crouch_k") != null else 0.0
	return t.global_position + Vector3(0, 1.6 - cr * 0.4, 0)


func _has_los(pl) -> bool:
	var from := global_position + Vector3(0, 1.7 - crouch_k * 0.4, 0)
	var to: Vector3 = _t_eye(pl) - Vector3(0, 0.1, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Bots: pick the nearest enemy, preferring the ones in sight (re-evaluated twice a second).
func _pick_target(delta: float) -> void:
	if bot_id == 0:
		target = game.player
		return
	target_t -= delta
	if target_t > 0.0 and _t_alive(target):
		return
	target_t = 0.5
	var best = null
	var bs := 1.0e9
	for c in game.net.bot_enemies(bot_id):
		if not _t_alive(c):
			continue
		var d: float = global_position.distance_to(c.global_position)
		var score := d
		if d < 70.0 and _has_los(c):
			score *= 0.4
		if c == target:
			score *= 0.8
		if score < bs:
			bs = score
			best = c
	target = best


## Damage a target with the right attribution (player, remote player, bot).
func _deal(t, dmg: float, head: bool, from: Vector3) -> void:
	if not _t_alive(t):
		return
	if t == game.player:
		if bot_id > 0:
			game.net.last_attacker = bot_id
			game.net.last_head = head
			game.net.last_melee = false
			t.take_damage(dmg, from)
		else:
			game.damage_player(dmg, from)
	elif t.get("puppet") == true:
		game.net.bot_hit_peer(t.peer_id, bot_id, dmg, head, from)
	elif t.has_method("take_damage"):
		t.hit_by = bot_id
		t.take_damage(dmg, head)
		t.hit_by = 0


const BOT_DMG := [[22.0, 0.095], [55.0, 0.85], [24.0, 0.2], [17.0, 0.075], [80.0, 1.3], [22.0, 0.1]]


func _shoot(dist: float, pl) -> void:
	var acc: float = _acc()
	var chance := (0.4 - dist * 0.0045) * acc * (1.0 + wave * 0.03)
	var pv = pl.get("velocity")
	var ps := Vector2(pv.x, pv.z).length() if pv != null else 0.0
	if ps > 6.0:
		chance *= 0.55
	elif ps > 3.0:
		chance *= 0.8
	if float(pl.get("crouch") if pl.get("crouch") != null else 0.0) > 0.5:
		chance *= 0.75
	if absf(float(pl.get("lean") if pl.get("lean") != null else 0.0)) > 0.5:
		chance *= 0.8
	# moving while shooting / just out of cover spoils the aim a little
	if Vector2(velocity.x, velocity.z).length() > 2.0:
		chance *= 0.85
	if suppress > 2.5:
		chance *= 0.7
	if bot_id > 0 and bot_wpn == 1:
		chance = clampf(1.1 - dist / 14.0, 0.0, 0.9) * acc   # shotgun: deadly up close only
	chance = clampf(chance, 0.04, 0.8)
	flash_t = 0.05
	kick = 1.0
	ammo -= 1
	last_shot = game.clock
	if "--aidbg" in OS.get_cmdline_user_args() and R != null:
		print("AISHOT d=%.1f clip=%s aim_k=%.2f gait=%.2f crouch=%.2f" % [dist, (R.ap as AnimationPlayer).current_animation, aim_k, gait, crouch_k])
	var from := tip.global_position
	var aim_at: Vector3 = _t_eye(pl) - Vector3(0, 0.25, 0)
	var hit := randf() < chance
	if not hit:
		# a near miss: the tracer passes close to the target (aimed fire, not random spray)
		var side := Vector3(randf_range(-1, 1), randf_range(-0.6, 0.8), randf_range(-1, 1)).normalized()
		aim_at += side * randf_range(0.35, 0.9) * (1.0 + dist / 60.0)
	game.fx.tracer(from, aim_at)
	# their rounds break window glass on the way too
	if GLASS.current != null and is_instance_valid(GLASS.current):
		var gq := PhysicsRayQueryParameters3D.create(from, aim_at, GLASS.GLASS_LAYER)
		var gh := get_world_3d().direct_space_state.intersect_ray(gq)
		if not gh.is_empty():
			GLASS.current.shatter(GLASS.pane_of(gh.collider), aim_at - from)
	game.fx.flash_light(from, 2.0, 5.0)
	game.sfx.play3d("enemy", from, -2.0)
	if bot_id > 0:
		game.net.bot_fx(bot_id, aim_at)
	if hit:
		if bot_id > 0:
			var head := randf() < 0.12 * acc
			var bd: float = BOT_DMG[bot_wpn][0] * (2.0 if head else 1.0)
			_deal(pl, bd, head, global_position)
		else:
			_deal(pl, randf_range(6, 10), false, global_position)
	elif pl == game.player and dist < 30.0 and randf() < 0.5:
		game.sfx.play("whiz", -10)


## Distances for the weapon: [too close, ideal, max engagement range].
func _ranges() -> Array:
	if bot_id == 0:
		return [7.0, 28.0 if role == 2 else 20.0, 60.0]
	return [[7.0, 20.0, 48.0], [2.0, 6.0, 18.0], [5.0, 12.0, 30.0], [4.0, 11.0, 34.0], [15.0, 38.0, 85.0], [8.0, 22.0, 52.0]][clampi(bot_wpn, 0, 5)]


## Closest live grenade thrown by an enemy within blast reach (null if none).
func _nearest_nade():
	var best = null
	var bd := 7.5
	for g in get_tree().get_nodes_in_group("live_nade"):
		if not is_instance_valid(g):
			continue
		var owner_id: int = int(g.get_meta("owner", -1))
		# Operación soldiers ignore their own team's grenades; bots ignore their own and their team's
		if bot_id == 0 and owner_id == 0:
			continue
		if bot_id > 0 and owner_id > 0 and game.net.same_team(owner_id, bot_id):
			continue
		var d: float = (g as Node3D).global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = (g as Node3D).global_position
	if best != null:
		nade_at = best
	return best


## Gunshot heard (player.fire, unsilenced): we know roughly where the shooter is.
func hear(pos: Vector3) -> void:
	if dead or puppet:
		return
	if global_position.distance_to(pos) < 45.0 and game.clock - intel_t > 1.0:
		last_known = pos + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		intel_t = game.clock


## Squad intel: soldiers near us (same side) learn where the target is.
func _share_intel(pos: Vector3) -> void:
	if game.clock - share_t < 0.6:
		return
	share_t = game.clock
	for e in game.enemies:
		if e == self or not is_instance_valid(e) or e.dead or e.get("puppet") == true or not e.has_method("_share_intel"):
			continue
		if e.bot_id != 0 and not game.net.same_team(e.bot_id, bot_id):
			continue
		if (bot_id == 0) != (e.bot_id == 0):
			continue
		if e.global_position.distance_to(global_position) < 32.0 and game.clock - e.intel_t > 0.5:
			e.last_known = pos
			e.intel_t = game.clock


## A spot within reach that the target can't see (behind a wall/crate), reachable on the nav mesh.
func _find_cover(from_pos: Vector3) -> Variant:
	var space := get_world_3d().direct_space_state
	var best = null
	var bd := 1.0e9
	var map_rid := get_world_3d().navigation_map
	for i in 14:
		var a := TAU * i / 14.0 + randf() * 0.3
		var r := randf_range(3.0, 9.0)
		var p := global_position + Vector3(cos(a) * r, 0, sin(a) * r)
		p = NavigationServer3D.map_get_closest_point(map_rid, p)
		if p.distance_to(global_position) < 1.5 or absf(p.y - global_position.y) > 1.0:
			continue
		# hidden at crouch height from the target's eye
		var q := PhysicsRayQueryParameters3D.create(from_pos, p + Vector3(0, 1.1, 0), 1, [get_rid()])
		if space.intersect_ray(q).is_empty():
			continue
		# don't run towards the enemy to reach it
		var cost := p.distance_to(global_position) + maxf(0.0, 12.0 - p.distance_to(from_pos)) * 1.5
		if cost < bd:
			bd = cost
			best = p
	return best


## Lob a grenade to where the target was last seen (it is hiding behind cover).
func _throw_nade(at: Vector3) -> void:
	nades -= 1
	var g := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	g.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.25, 0.16)
	g.material_override = m
	game.add_child(g)
	g.add_to_group("live_nade")
	g.set_meta("owner", bot_id)
	var from := global_position + Vector3(0, 1.8, 0)
	at += Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)) / _acc()
	g.global_position = from
	game.sfx.play3d("pin", from, -2.0)
	var dur := clampf(from.distance_to(at) / 14.0, 0.6, 1.6)
	var tw: Tween = game.create_tween()
	tw.tween_method(func(k: float):
		if is_instance_valid(g):
			g.global_position = from.lerp(at, k) + Vector3(0, sin(k * PI) * (2.0 + dur * 2.0), 0)
	, 0.0, 1.0, dur)
	var me_id := bot_id
	var me := self
	var gm = game
	gm.get_tree().create_timer(dur + 1.1, false).timeout.connect(func():
		if is_instance_valid(g):
			g.queue_free()
		gm.enemy_nade_blast(at + Vector3(0, 0.1, 0), me_id, me)
	)




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
	if not R.is_empty():
		_animate_skin(delta, moved, aiming, aim_pitch, rel_yaw)
		return
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
	if not R.is_empty():
		return
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
	_pick_target(delta)
	var pl = target
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if pl == null or not is_instance_valid(pl):
		# nobody to fight (multiplayer bot with every enemy dead): stand by
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_animate(delta, 0.0, false, 0.0, 0.0)
		rotation.y = facing
		return
	var tpos: Vector3 = pl.global_position
	var to: Vector3 = tpos - global_position
	to.y = 0.0
	var dist := to.length()
	var n := to / maxf(dist, 0.001)
	var wr0: Array = _ranges()
	los_t -= delta
	if los_t <= 0.0:
		los_t = randf_range(0.15, 0.25)
		los = _t_alive(pl) and dist < (75.0 if bot_id == 0 else float(wr0[2]) + 15.0) and _has_los(pl)
		if los:
			last_known = tpos
			intel_t = game.clock
			_share_intel(tpos)
	if los:
		seen_t += delta
	else:
		seen_t = maxf(0.0, seen_t - delta * 2.0)
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			ammo = 30
	nade_cd -= delta
	cover_cd -= delta
	suppress = maxf(0.0, suppress - delta * 0.8)
	var mv := Vector3.ZERO
	var spd := speed
	var hurt := health < max_hp * 0.5
	var wr: Array = _ranges()     # [too close, ideal, max engagement distance]
	# ---- a live grenade lands nearby: drop everything and sprint away from it
	flee_check_t -= delta
	if flee_check_t <= 0.0 and flee_t <= 0.0:
		flee_check_t = 0.2
		var nd = _nearest_nade()
		if nd != null:
			var away: Vector3 = global_position - nd
			away.y = 0.0
			if away.length() < 0.2:
				away = -n
			flee_pos = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, global_position + away.normalized() * 9.0)
			flee_t = randf_range(1.6, 2.2)
			cover_state = 0
			crouch_pref = false
			burst = 0
	if flee_t > 0.0:
		flee_t -= delta
		mv = _path_to(flee_pos)
		if mv == Vector3.ZERO:
			mv = Vector3(global_position.x - nade_at.x, 0, global_position.z - nade_at.z).normalized()
		spd = speed * 1.45
	else:
		# ---- cover: hurt, pinned down by fire or reloading -> a spot the target can't see; support
		# and long-range shooters also like to fight from cover even when healthy
		var want_cover: bool = hurt or suppress > 2.5 or (reload_t > 0.0 and dist < 25.0) or (role == 2 and randf() < 0.004)
		if cover_state == 0 and cover_cd <= 0.0 and los and dist < 50.0 and want_cover:
			cover_cd = 2.5
			var cp = _find_cover(_t_eye(pl))
			if cp != null:
				cover_pos = cp
				cover_state = 1
				cover_t = 3.0
		if cover_state == 1:
			cover_t -= delta
			mv = _path_to(cover_pos)
			spd = speed * 1.15
			if global_position.distance_to(cover_pos) < 0.7 or mv == Vector3.ZERO or cover_t <= 0.0:
				cover_state = 2
				cover_t = randf_range(2.0, 3.5)
		elif cover_state == 2:
			cover_t -= delta
			crouch_pref = true
			strafe = 0
			# patch up a bit while hidden
			health = minf(max_hp * 0.75, health + 8.0 * delta)
			if cover_t <= 0.0 and reload_t <= 0.0 and suppress < 2.0:
				cover_state = 0
				cover_cd = randf_range(4.0, 7.0)
				crouch_pref = false
		if cover_state == 0 and los:
			facing = lerp_angle(facing, atan2(-n.x, -n.z), minf(1.0, delta * 8.0))
			# keep the distance that suits the weapon: close in when too far, back off when too close
			if dist > float(wr[2]):
				mv = _path_dir(pl)
				if mv == Vector3.ZERO:
					mv = n
			elif dist > float(wr[1]) + 6.0:
				mv = n
			elif dist < float(wr[0]):
				mv = -n
			strafe_t -= delta
			if strafe_t <= 0.0:
				strafe = [-1, 0, 0, 1][randi() % 4] if role != 1 else [-1, 1][randi() % 2]
				strafe_t = randf_range(0.8, 2.2)
				crouch_pref = dist > 14.0 and randf() < (0.6 if role == 2 else 0.4)
			if crouch_pref:
				strafe = 0
			mv += Vector3(-n.z, 0, n.x) * strafe
			spd *= 0.0 if crouch_pref and dist <= float(wr[2]) else 0.6
			# player on another floor (seen through a stairwell / window), or we are on the stairs:
			# keep pushing along the path while firing instead of holding position mid-flight
			var on_ramp := is_on_floor() and get_floor_normal().y < 0.97
			if absf(tpos.y - global_position.y) > 1.5 or on_ramp:
				var pm := _path_dir(pl)
				if pm != Vector3.ZERO:
					mv = pm
					spd = speed * 0.75
		elif cover_state == 0:
			crouch_pref = false
			# ---- no line of sight: hunt where the target was last seen or heard (ours or a squadmate's),
			# flankers swing wide around it; with no intel for a while, fall back to the real position
			var fresh: bool = game.clock - intel_t < 8.0
			var goal: Vector3 = last_known if fresh else tpos
			# while a squadmate keeps the target busy, flankers and assaulters go around it
			var pinned_by_mate: bool = fresh and game.clock - intel_t < 1.0 and not los
			if (role == 1 or (pinned_by_mate and role == 0)) and dist > 12.0 and fresh:
				var side := Vector3(-n.z, 0, n.x) * flank_side * minf(12.0, dist * 0.55)
				var fg := goal + side
				if global_position.distance_to(fg) > 3.0:
					goal = fg
			if fresh and global_position.distance_to(last_known) < 2.0:
				intel_t = -99.0
			mv = _path_to(goal)
			if mv == Vector3.ZERO:
				mv = n
			# moving carefully once close to where the target was (no sprinting into the open)
			if fresh and global_position.distance_to(last_known) < 12.0:
				spd = speed * 0.7
			# target hiding nearby behind cover: lob a grenade at its last position
			if nades > 0 and nade_cd <= 0.0 and game.clock - intel_t < 4.0 and last_known.distance_to(global_position) > 7.0 and last_known.distance_to(global_position) < 26.0:
				nade_cd = randf_range(10.0, 18.0)
				if randf() < 0.55:
					_throw_nade(last_known)
	# ---- firing: only once the gun is up and pointed at the target (no shots from the hip while
	# turning), aiming takes longer the farther away it is, and only inside the weapon's range
	var aim_err := absf(wrapf(atan2(-n.x, -n.z) - facing, -PI, PI))
	# the allowed error shrinks with distance (~0.5 m off at the target), so far shots are really aimed
	var aim_tol := clampf(atan2(0.5, maxf(dist, 1.0)), 0.025, 0.18)
	var far_shot := dist > 16.0
	# the burst clock runs while the target is in sight (it used to stop while turning, and planting
	# the feet below waits on it)
	if los and fire_t > -1.0:
		fire_t -= delta
	# at range they plant their feet for the burst (they still advance between bursts): no firing while
	# walking / strafing (the walk clips carry the rifle low, so it looked like spraying from the hip)
	# (not when the target is on another floor or we are on the stairs: then they keep walking the path)
	var other_floor: bool = absf(tpos.y - global_position.y) > 1.5 or (is_on_floor() and get_floor_normal().y < 0.97)
	var skinned := not R.is_empty()
	var hold := (far_shot or skinned) and los and flee_t <= 0.0 and cover_state == 0 and reload_t <= 0.0 and seen_t > reaction \
		and not other_floor and ((burst > 0 and fire_t < 0.5) or (burst == 0 and fire_t <= 0.0)) and dist <= float(wr[2])
	if hold:
		mv = Vector3.ZERO
		strafe = 0
		facing = lerp_angle(facing, atan2(-n.x, -n.z), minf(1.0, delta * 10.0))
	var steady: bool = (not far_shot and not skinned) or other_floor or Vector2(velocity.x, velocity.z).length() < 0.8
	var aimed: bool = aim_err < aim_tol and aim_k > (0.9 if far_shot else 0.75) and steady and (not skinned or crouch_k < 0.35 or other_floor)
	var settle: float = reaction + dist * 0.015 + (0.4 if suppress > 2.5 else 0.0)
	if los and flee_t <= 0.0 and cover_state != 1 and seen_t > settle and reload_t <= 0.0 and aimed and dist <= float(wr[2]):
		if ammo <= 0:
			reload_t = reload_dur
		else:
			if fire_t <= 0.0:
				if burst > 0:
					_shoot(dist, pl)
					burst -= 1
					fire_t = 0.13 if bot_id == 0 else maxf(BOT_DMG[bot_wpn][1], 0.09)
				else:
					burst = (3 + randi() % 3) if role != 2 else (5 + randi() % 4)
					# far away: short controlled bursts
					if dist > 35.0:
						burst = 2 + randi() % 2
					if bot_id > 0 and bot_wpn in [1, 2, 4]:
						burst = 1 + randi() % 2
					fire_t = (randf_range(0.7, 1.6) if role != 2 else randf_range(0.4, 1.0)) + dist * 0.01
	elif cover_state == 2 and ammo <= 0 and reload_t <= 0.0:
		reload_t = reload_dur
	# keep a little room from squadmates (two soldiers walking into each other block forever)
	for e in game.enemies:
		if e == self or not is_instance_valid(e) or e.dead or e.get("puppet") == true:
			continue
		var dd: Vector3 = global_position - e.global_position
		dd.y = 0.0
		var dl := dd.length()
		if dl < 1.1 and dl > 0.001:
			mv += dd / dl * (1.1 - dl) * 2.5
	if detour_t > 0.0:
		detour_t -= delta
		mv = detour
		spd = maxf(spd, speed * 0.8)
	if mv.length() > 0.01 and spd > 0.0:
		mv = mv.normalized()
		velocity.x = mv.x * spd
		velocity.z = mv.z * spd
		if not los or cover_state == 1:
			facing = lerp_angle(facing, atan2(-mv.x, -mv.z), minf(1.0, delta * 8.0))
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	var before := global_position
	var want := Vector3(velocity.x, 0.0, velocity.z) * delta
	move_and_slide()
	_step_up(before, want)
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_footsteps(moved)
	# stuck against something for a while: pick a sideways detour
	if want.length() > 0.02 and moved < want.length() * 0.2:
		stuck_t += delta
		if stuck_t > 0.6:
			stuck_t = 0.0
			repath_t = 0.0
			flank_side = -flank_side
			# step sideways (and a bit back) for a moment, then try the path again
			var w2 := want.normalized()
			detour = (Vector3(-w2.z, 0, w2.x) * flank_side - w2 * 0.4).normalized()
			detour_t = randf_range(0.5, 0.9)
	else:
		stuck_t = 0.0
	var aim_pitch := atan2(_t_eye(pl).y - 0.3 - (global_position.y + 1.5 - crouch_k * 0.36), dist)
	aim_pitch_out = aim_pitch if los else 0.0
	_animate(delta, moved, los, clampf(aim_pitch, -0.8, 0.8), clampf(wrapf(atan2(-n.x, -n.z) - facing, -PI, PI), -0.8, 0.8))
	rotation.y = facing
	flash_t -= delta
	flash.visible = flash_t > 0.0
