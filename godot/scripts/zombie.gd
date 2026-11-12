extends CharacterBody3D
## Zombie: rises out of the ground, shambles / jogs / sprints toward the player using the engine
## navigation mesh, swipes at close range. Headshot kills can blow the head off.
## Same interface as the soldier: take_damage(d, head) -> killed, `dead`.

const SHP := preload("res://scripts/shapes.gd")
const OPT := preload("res://scripts/optimize.gd")

var game
var round_n := 1
var health := 150.0
var dead := false
var dead_t := 0.0
var speed := 1.3
var gait_kind := 0          # 0 shamble, 1 jog, 2 sprint
var rise_t := 1.6
var facing := 0.0
var phase := 0.0
var gait := 0.0
var attack_t := 0.0
var attack_cd := 0.0
var hit_k := 0.0
var hit_dir := 1.0
var repath_t := 0.0
var groan_t := 0.0
var death_type := 0
var headless := false
var seed := 0.0
var agent: NavigationAgent3D
var B := {}
var mats: Array = []
# co-op multiplayer: the host simulates every zombie; clients show "remote" replicas that
# follow the host's state and forward damage to it
var net_id := 0
var remote := false
var net_pos := Vector3.ZERO
var net_seen := 0.0
var tgt = null            # player node being chased (local player or a teammate puppet)
var tgt_peer := 0         # 0 = local player, otherwise the teammate's peer id
var tgt_t := 0.0

static var M := {}
static var ME := {}


static func _init_assets() -> void:
	if not M.is_empty():
		return
	var mk := func(c: Color, r := 0.85) -> StandardMaterial3D:
		var s := StandardMaterial3D.new()
		s.albedo_color = c
		s.roughness = r
		return s
	M = {"skin": [mk.call(Color(0.45, 0.5, 0.4), 0.6), mk.call(Color(0.52, 0.48, 0.42), 0.6), mk.call(Color(0.38, 0.42, 0.38), 0.6)],
		"shirt": [mk.call(Color(0.35, 0.33, 0.28)), mk.call(Color(0.22, 0.27, 0.35)), mk.call(Color(0.42, 0.2, 0.17)), mk.call(Color(0.5, 0.48, 0.42))],
		"pants": [mk.call(Color(0.18, 0.2, 0.24)), mk.call(Color(0.28, 0.25, 0.2)), mk.call(Color(0.14, 0.14, 0.13))],
		"blood": mk.call(Color(0.25, 0.02, 0.02), 0.35), "shoe": mk.call(Color(0.1, 0.09, 0.08)), "hair": mk.call(Color(0.12, 0.1, 0.08), 0.9),
		"mouth": mk.call(Color(0.08, 0.02, 0.02), 0.5)}
	var eye := StandardMaterial3D.new()
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.albedo_color = Color(1.5, 0.75, 0.15)
	M["eye"] = eye
	ME = {"pelvis": _box(0.34, 0.2, 0.22), "belly": _box(0.32, 0.26, 0.2), "chest": _box(0.42, 0.34, 0.24), "rag": _box(0.44, 0.12, 0.26),
		"neck": _cyl(0.06, 0.12), "head": _sphere(0.12), "jaw": _box(0.13, 0.05, 0.1), "eye": _sphere(0.012), "hair": _hemi(0.125),
		"thigh": _cap(0.085, 0.48), "shin": _cap(0.07, 0.44), "shoe": _box(0.13, 0.1, 0.26), "upper": _cap(0.06, 0.32), "fore": _cap(0.05, 0.3),
		"hand": _box(0.08, 0.1, 0.04), "stump": _cyl(0.065, 0.04)}


static func _box(x: float, y: float, z: float) -> Mesh:
	return SHP.rbox(Vector3(x, y, z), minf(x, minf(y, z)) * 0.35, 2)


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 10
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
	m.radial_segments = 10
	return m


static func _cap(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	return m


func _g(parent: Node3D, p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	parent.add_child(n)
	return n


func _m(parent: Node3D, mesh_key: String, mat: Material, p: Vector3, r := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ME[mesh_key]
	mi.material_override = mat
	mi.position = p
	mi.rotation = r
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _ready() -> void:
	_init_assets()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 2
	collision_mask = 1 | 4
	seed = randf() * 10.0
	# toughness and speed scale with the round
	health = 150.0 + minf(round_n - 1, 8) * 100.0
	if round_n > 9:
		health *= pow(1.1, round_n - 9)
	var r := randf()
	var run_p := clampf((round_n - 3) * 0.12, 0.0, 0.85)
	var jog_p := clampf((round_n - 1) * 0.2, 0.0, 0.9)
	if r < run_p:
		gait_kind = 2
		speed = randf_range(4.3, 5.0)
	elif r < jog_p:
		gait_kind = 1
		speed = randf_range(2.4, 3.0)
	else:
		gait_kind = 0
		speed = randf_range(1.1, 1.6)
	groan_t = randf_range(1.0, 5.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.8
	agent.radius = 0.4
	agent.height = 1.8
	add_child(agent)
	_build_body()
	B.root.position.y = -1.75
	game.fx.puff(global_position + Vector3(0, 0.1, 0), Color(0.35, 0.3, 0.25), 1.0, 1.4, 0.2)


func _mat(arr_key: String) -> StandardMaterial3D:
	var arr: Array = M[arr_key]
	var m: StandardMaterial3D = arr[randi() % arr.size()].duplicate()
	mats.append(m)
	return m


func _build_body() -> void:
	var skin := _mat("skin")
	var shirt := _mat("shirt")
	var pants := _mat("pants")
	var root := _g(self, Vector3.ZERO)
	B.root = root
	B.hips = _g(root, Vector3(0, 0.93, 0))
	B.spine = _g(B.hips, Vector3(0, 0.08, 0))
	B.chest = _g(B.spine, Vector3(0, 0.2, 0))
	B.neck = _g(B.chest, Vector3(0, 0.34, 0))
	B.head = _g(B.neck, Vector3(0, 0.06, 0))
	for sd in [-1, 1]:
		var k := "L" if sd < 0 else "R"
		B["th" + k] = _g(B.hips, Vector3(0.1 * sd, -0.04, 0))
		B["kn" + k] = _g(B["th" + k], Vector3(0, -0.44, 0))
		B["ft" + k] = _g(B["kn" + k], Vector3(0, -0.42, 0))
		_m(B["th" + k], "thigh", pants, Vector3(0, -0.22, 0))
		_m(B["kn" + k], "shin", pants if randf() < 0.7 else skin, Vector3(0, -0.21, 0))
		_m(B["ft" + k], "shoe", M.shoe, Vector3(0, 0, -0.05))
		B["sh" + k] = _g(B.chest, Vector3(0.24 * sd, 0.28, 0))
		B["el" + k] = _g(B["sh" + k], Vector3(0, -0.3, 0))
		_m(B["sh" + k], "upper", shirt if randf() < 0.6 else skin, Vector3(0, -0.15, 0))
		_m(B["el" + k], "fore", skin, Vector3(0, -0.15, 0))
		_m(B["el" + k], "hand", skin, Vector3(0, -0.34, 0), Vector3.ZERO, false)
	_m(B.hips, "pelvis", pants, Vector3.ZERO)
	_m(B.spine, "belly", shirt if randf() < 0.75 else skin, Vector3(0, 0.1, 0))
	_m(B.chest, "chest", shirt, Vector3(0, 0.16, 0))
	_m(B.chest, "rag", shirt, Vector3(0.03, -0.02, 0.01), Vector3(0.1, 0.3, 0.25), false)
	for i in 3:
		_m(B.chest, "eye", M.blood, Vector3(randf_range(-0.15, 0.15), randf_range(0.05, 0.3), -0.125), Vector3.ZERO, false).scale = Vector3(2.2, 1.6, 0.4)
	_m(B.neck, "neck", skin, Vector3.ZERO)
	_m(B.head, "head", skin, Vector3(0, 0.08, 0))
	_m(B.head, "jaw", M.mouth, Vector3(0, 0.0, -0.06), Vector3(0.35, 0, 0), false)
	if randf() < 0.7:
		_m(B.head, "hair", M.hair, Vector3(0, 0.1, 0.01), Vector3(-0.2, 0, 0), false)
	for sx in [-1, 1]:
		_m(B.head, "eye", M.eye, Vector3(0.045 * sx, 0.1, -0.105), Vector3.ZERO, false)
	B.stump = _m(B.neck, "stump", M.blood, Vector3(0, 0.05, 0), Vector3.ZERO, false)
	B.stump.visible = false


func take_damage(d: float, head: bool) -> bool:
	if dead:
		return false
	if remote:
		# client replica: the host decides; the kill (and its points) comes back from it
		hit_k = 1.0
		hit_dir = -1.0 if randf() < 0.5 else 1.0
		if game.zm:
			game.zm.add_points(10)
		game.net.z_send_hit(net_id, d, head, bool(game.kill_ctx.get("melee", false)))
		return false
	if game.zm and game.zm.insta_t > 0.0:
		d = 99999.0
	health -= d
	hit_k = 1.0
	hit_dir = -1.0 if randf() < 0.5 else 1.0
	var killed := health <= 0.0
	if game.zm:
		game.zm.on_hit(self, killed, head)
	if killed:
		_die(head)
	return killed


func _die(head: bool) -> void:
	dead = true
	dead_t = 0.0
	collision_layer = 0
	collision_mask = 1
	velocity = Vector3.ZERO
	death_type = randi() % 2
	if head and randf() < 0.65:
		_lose_head()
	game.sfx.play3d("zdie", global_position + Vector3(0, 1.4, 0), -4.0)
	var by: int = game.net.z_attacker if game.net.active else 0
	if by == 0:
		game.register_kill(head, self)
	if game.net.active and game.net.is_host:
		game.net.z_died(self, head, by)


func _lose_head() -> void:
	headless = true
	B.head.visible = false
	B.stump.visible = true
	game.fx.blood(B.neck.global_position + Vector3(0, 0.1, 0), Vector3.UP)
	game.fx.blood(B.neck.global_position + Vector3(0, 0.1, 0), -transform.basis.z)


## Client replica: the host confirmed this zombie's death.
func net_die(lost_head: bool) -> void:
	if dead:
		return
	dead = true
	dead_t = 0.0
	collision_layer = 0
	collision_mask = 1
	velocity = Vector3.ZERO
	death_type = randi() % 2
	if lost_head:
		_lose_head()
	game.sfx.play3d("zdie", global_position + Vector3(0, 1.4, 0), -4.0)


## Nearest living player: the local one or (co-op) a teammate.
func _pick_target() -> void:
	tgt = null
	tgt_peer = 0
	var best := INF
	var pl = game.player
	if pl != null and is_instance_valid(pl) and pl.alive:
		tgt = pl
		best = global_position.distance_squared_to(pl.global_position)
	if game.net.active:
		for id in game.net.puppets:
			var pp = game.net.puppets[id]
			if pp == null or not is_instance_valid(pp) or pp.dead:
				continue
			var d := global_position.distance_squared_to(pp.global_position)
			if d < best:
				best = d
				tgt = pp
				tgt_peer = id


func _remote_process(delta: float) -> void:
	if rise_t > 0.0:
		rise_t -= delta
		var k := 1.0 - maxf(0.0, rise_t) / 1.6
		B.root.position.y = -1.75 * (1.0 - k * k * (3.0 - 2.0 * k))
		B.root.rotation.z = sin(k * 9.0) * 0.12 * (1.0 - k)
		_animate(delta, 0.0)
		B.shL.rotation.x = 2.7 - k * 1.2
		B.shR.rotation.x = 2.9 - k * 1.4
	else:
		B.root.position.y = 0.0
		B.root.rotation.z = 0.0
	var before := global_position
	if global_position.distance_to(net_pos) > 5.0:
		global_position = net_pos
	else:
		global_position = global_position.lerp(net_pos, 1.0 - exp(-12.0 * delta))
	rotation.y = lerp_angle(rotation.y, facing, 1.0 - exp(-12.0 * delta))
	if rise_t <= 0.0:
		attack_t = maxf(0.0, attack_t - delta)
		var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
		_animate(delta, moved)
	groan_t -= delta
	if groan_t <= 0.0:
		groan_t = randf_range(3.0, 8.0)
		game.sfx.play3d(["zgroan1", "zgroan2", "zgroan3"][randi() % 3], global_position + Vector3(0, 1.5, 0), -6.0)
	# the host stopped reporting it (missed death message): fade it out
	if game.clock - net_seen > 2.0:
		net_die(false)


func _exit_tree() -> void:
	mats.clear()


func _leg_pose(ph: float, g: float) -> void:
	var st := 0.45 * g
	var kb := 0.2 + 0.9 * g
	var tl := sin(ph) * st
	var tr := -sin(ph) * st
	var kl := -maxf(0.0, sin(ph + 1.3)) * kb
	var kr := -maxf(0.0, sin(ph + 1.3 + PI)) * kb
	if gait_kind == 0:
		# dragging limp: one leg stiff
		kr *= 0.3
		tr *= 0.6
	B.thL.rotation.x = tl
	B.thR.rotation.x = tr
	B.knL.rotation.x = kl
	B.knR.rotation.x = kr
	B.ftL.rotation.x = -(tl + kl) * 0.6
	B.ftR.rotation.x = -(tr + kr) * 0.6


func _animate(delta: float, moved: float) -> void:
	var sp := moved / maxf(delta, 0.0001)
	gait = lerpf(gait, clampf(sp / 3.5, 0.0, 1.3), 1.0 - exp(-8.0 * delta))
	phase += moved * (3.4 if gait_kind == 0 else 2.6)
	var t: float = game.clock + seed
	var g := gait
	var sn := sin(phase)
	_leg_pose(phase, g)
	hit_k = maxf(0.0, hit_k - delta * 4.0)
	B.hips.position.y = 0.93 + absf(cos(phase)) * 0.05 * g - (0.06 if gait_kind == 0 else 0.0)
	B.hips.rotation = Vector3(0, sn * 0.12 * g, (sin(phase * 0.5) * 0.08 if gait_kind == 0 else 0.0))
	var lean := 0.25 if gait_kind == 0 else (0.35 if gait_kind == 1 else 0.55)
	B.spine.rotation.x = -(lean * 0.5 + hit_k * -0.4)
	B.chest.rotation = Vector3(-lean * 0.5 + sin(t * 2.0) * 0.04, -sn * 0.15 * g, hit_dir * hit_k * 0.3 + sin(t * 1.3) * 0.06)
	B.neck.rotation = Vector3(0.25 + sin(t * 1.7) * 0.1, sin(t * 0.8) * 0.3, sin(t * 1.1) * 0.2)
	# arms reach forward for the player (+X rotation swings the hanging arm towards -Z, the
	# facing direction); the attack swipe raises them and claws down
	var reach := 1.45 if gait_kind < 2 else 0.75
	var at := 0.0
	if attack_t > 0.0:
		at = sin((1.0 - attack_t / 0.7) * PI)
	for sd in [-1, 1]:
		var k := "L" if sd < 0 else "R"
		var sw := sin(phase + (0.0 if sd < 0 else PI)) * (0.5 if gait_kind == 2 else 0.12) * g
		var shx := reach + sw + sin(t * 2.3 + sd) * 0.08 + at * (0.9 if sd > 0 else 0.55)
		# slightly inward so the hands reach towards the victim, not out to the sides
		B["sh" + k].rotation = Vector3(shx, sd * 0.12, -sd * (0.08 + at * 0.35))
		B["el" + k].rotation.x = 0.3 + sin(t * 1.9 + sd * 2.0) * 0.1 - at * 0.25


func _death_anim() -> void:
	var r: Node3D = B.root
	var t := dead_t
	if death_type == 0:
		var k := clampf(t / 0.6, 0.0, 1.0)
		r.rotation.x = -(k * k) * PI / 2 * 0.95
		B.knL.rotation.x = -0.8 * minf(1.0, t * 3.0)
	else:
		var k1 := clampf(t / 0.35, 0.0, 1.0)
		var k2 := clampf((t - 0.3) / 0.5, 0.0, 1.0)
		B.hips.position.y = lerpf(0.93, 0.45, k1)
		B.knL.rotation.x = -2.0 * k1
		B.knR.rotation.x = -2.0 * k1
		B.thL.rotation.x = 1.2 * k1
		B.thR.rotation.x = 1.2 * k1
		r.rotation.x = (k2 * k2) * PI / 2 * 0.95


func _physics_process(delta: float) -> void:
	if dead:
		dead_t += delta
		_death_anim()
		if dead_t > 4.0:
			B.root.position.y -= delta * 0.6
		if dead_t > 6.0:
			queue_free()
		return
	if remote:
		_remote_process(delta)
		return
	tgt_t -= delta
	if tgt_t <= 0.0 or tgt == null or not is_instance_valid(tgt) or (tgt_peer != 0 and tgt.dead) or (tgt_peer == 0 and not tgt.alive):
		tgt_t = 0.5
		_pick_target()
	var pl = tgt
	if pl == null or not is_instance_valid(pl):
		# nobody left alive to chase: stand and sway
		velocity = Vector3.ZERO
		if rise_t <= 0.0:
			_animate(delta, 0.0)
		return
	var pl_alive: bool = pl.alive if tgt_peer == 0 else not pl.dead
	# rising out of the ground
	if rise_t > 0.0:
		rise_t -= delta
		var k := 1.0 - maxf(0.0, rise_t) / 1.6
		B.root.position.y = -1.75 * (1.0 - k * k * (3.0 - 2.0 * k))
		B.root.rotation.z = sin(k * 9.0) * 0.12 * (1.0 - k)
		_animate(delta, 0.0)
		# clawing up out of the ground: arms above the head and in front, lowering to the reach
		B.shL.rotation.x = 2.7 - k * 1.2
		B.shR.rotation.x = 2.9 - k * 1.4
		return
	B.root.position.y = 0.0
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	var to: Vector3 = pl.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var n := to / maxf(dist, 0.001)
	groan_t -= delta
	if groan_t <= 0.0:
		groan_t = randf_range(3.0, 8.0)
		game.sfx.play3d(["zgroan1", "zgroan2", "zgroan3"][randi() % 3], global_position + Vector3(0, 1.5, 0), -6.0)
	attack_cd -= delta
	var mv := Vector3.ZERO
	if attack_t > 0.0:
		attack_t -= delta
		if attack_t <= 0.35 and attack_t + delta > 0.35 and dist < 1.7 and pl_alive:
			if tgt_peer == 0:
				game.damage_player(40.0, global_position)
			else:
				game.net.z_hurt(tgt_peer, 40.0, global_position)
		facing = lerp_angle(facing, atan2(-n.x, -n.z), minf(1.0, delta * 6.0))
	elif dist < 1.3 and pl_alive and attack_cd <= 0.0:
		attack_t = 0.7
		attack_cd = 1.1
		game.sfx.play3d("zattack", global_position + Vector3(0, 1.4, 0), -3.0)
	else:
		repath_t -= delta
		if dist < 5.0:
			mv = n
		else:
			if repath_t <= 0.0:
				repath_t = randf_range(0.25, 0.4)
				agent.target_position = pl.global_position
			if not agent.is_navigation_finished():
				var nxt := agent.get_next_path_position()
				mv = nxt - global_position
				mv.y = 0.0
				mv = mv.normalized()
			else:
				mv = n
		# keep a little space from the other zombies so they don't merge into one blob
		for e in game.enemies:
			if e == self or not is_instance_valid(e) or e.dead:
				continue
			var d: Vector3 = global_position - e.global_position
			d.y = 0.0
			var l := d.length()
			if l < 0.75 and l > 0.001:
				mv += d / l * (0.75 - l) * 2.0
	var spd := speed * (1.0 - hit_k * 0.5)
	if mv.length() > 0.01 and attack_t <= 0.0:
		mv = mv.normalized()
		velocity.x = mv.x * spd
		velocity.z = mv.z * spd
		facing = lerp_angle(facing, atan2(-mv.x, -mv.z), minf(1.0, delta * 6.0))
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	var before := global_position
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_animate(delta, moved)
	rotation.y = facing
