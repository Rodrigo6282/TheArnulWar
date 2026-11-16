extends Node3D
## Breakable window glass for the real window openings (world.wall_gaps). All panes of a map are one
## MultiMesh (one draw call, cheap on the Intel iGPU) plus one thin StaticBody3D per pane on its own
## collision layer (GLASS_LAYER), which only the player's bullets / knife look at: navigation, line of
## sight, climbing and movement all use layer 1, so the glass never changes how the map plays.
## A pane breaks when it is shot, knifed, caught in an explosion or when the player goes through it
## (vaulting / jumping through the window). Online the break is mirrored with net.zzzz_glass.

const GLASS_LAYER := 16

static var current: Node3D = null

var panes: Array = []        # [{xf: Transform3D (basis = size), body: StaticBody3D, broken: bool}]
var mm_pane: MultiMesh
var mm_rest: MultiMesh       # jagged remains left in the frame once broken
var _shard_mesh: BoxMesh
var _shard_mat: StandardMaterial3D
var _check_t := 0.0


## Builds the set from [Transform3D] items (unit quad facing +Z scaled to the pane size).
func setup(list: Array) -> void:
	current = self
	add_to_group("glass_set")
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.albedo_color = Color(0.42, 0.55, 0.6, 0.4)
	gm.roughness = 0.04
	gm.metallic = 0.35
	gm.metallic_specular = 0.9
	gm.vertex_color_use_as_albedo = false
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm_pane = _mm(q, gm, list.size())
	mm_rest = _mm(_remains_mesh(), gm, list.size())
	for k in list.size():
		var xf: Transform3D = list[k]
		mm_pane.set_instance_transform(k, xf)
		mm_rest.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin))
		var sb := StaticBody3D.new()
		sb.collision_layer = GLASS_LAYER
		sb.collision_mask = 0
		sb.set_meta("glass", k)
		sb.set_meta("nomerge", true)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(xf.basis.x.length(), xf.basis.y.length(), 0.06)
		cs.shape = bs
		sb.add_child(cs)
		add_child(sb)
		sb.transform = Transform3D(Basis(xf.basis.x.normalized(), xf.basis.y.normalized(), xf.basis.z.normalized()), xf.origin)
		panes.append({"xf": xf, "body": sb, "broken": false})
	_shard_mesh = BoxMesh.new()
	_shard_mesh.size = Vector3(0.07, 0.05, 0.004)
	_shard_mat = StandardMaterial3D.new()
	_shard_mat.albedo_color = Color(0.7, 0.8, 0.85)
	_shard_mat.roughness = 0.05
	_shard_mat.metallic = 0.6
	_shard_mat.metallic_specular = 1.0


func _exit_tree() -> void:
	if current == self:
		current = null


func _mm(mesh: Mesh, mat: Material, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.set_meta("nomerge", true)
	add_child(mi)
	return mm


## Jagged triangles hanging from the frame of a unit pane (x, y in -0.5..0.5, facing +Z).
func _remains_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := [
		[Vector2(-0.5, 0.5), Vector2(-0.12, 0.5), Vector2(-0.5, 0.18)],
		[Vector2(-0.12, 0.5), Vector2(0.08, 0.5), Vector2(-0.04, 0.3)],
		[Vector2(0.22, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.05)],
		[Vector2(0.5, -0.5), Vector2(0.5, -0.2), Vector2(0.3, -0.5)],
		[Vector2(-0.5, -0.5), Vector2(-0.2, -0.5), Vector2(-0.5, -0.05)],
		[Vector2(0.05, -0.5), Vector2(0.18, -0.5), Vector2(0.1, -0.36)],
		[Vector2(-0.5, -0.02), Vector2(-0.5, 0.1), Vector2(-0.38, 0.06)],
	]
	for t in tris:
		for v in t:
			st.set_normal(Vector3.BACK)
			st.add_vertex(Vector3(v.x, v.y, 0.0))
	return st.commit()


## Breaks pane k. dir pushes the shards (bullet direction / from the blast); quiet = no sync (from net).
func shatter(k: int, dir := Vector3.ZERO, quiet := false) -> void:
	if k < 0 or k >= panes.size() or panes[k].broken:
		return
	var p: Dictionary = panes[k]
	p.broken = true
	var xf: Transform3D = p.xf
	mm_pane.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin))
	mm_rest.set_instance_transform(k, xf)
	var body: StaticBody3D = p.body
	if is_instance_valid(body):
		body.queue_free()
	var nrm := xf.basis.z.normalized()
	if dir == Vector3.ZERO:
		dir = nrm
	var push := nrm if dir.dot(nrm) >= 0.0 else -nrm
	_shards(xf, push)
	var game = get_tree().root.get_node_or_null("Main")
	if game != null:
		game.sfx.play3d("glass", xf.origin, 2.0)
		if not quiet and game.net.active:
			game.net.glass_send(k)


func _shards(xf: Transform3D, push: Vector3) -> void:
	var w := xf.basis.x.length()
	var h := xf.basis.y.length()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = clampi(int(w * h * 26.0), 14, 48)
	p.lifetime = 1.4
	p.mesh = _shard_mesh
	p.material_override = _shard_mat
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(w * 0.45, h * 0.45, 0.02)
	p.direction = Vector3(0, 0.2, 1)
	p.spread = 40.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.6
	p.gravity = Vector3(0, -14.0, 0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.particle_flag_rotate_y = true
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.8
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	# emitter space: local Z = the side the shards fly to
	var z := push.normalized()
	var x := xf.basis.x.normalized()
	p.global_transform = Transform3D(Basis(x, z.cross(x).normalized(), z), xf.origin)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3, false).timeout.connect(p.queue_free)
	# a little glittering dust
	var game = get_tree().root.get_node_or_null("Main")
	if game != null:
		game.fx.puff(xf.origin, Color(0.85, 0.9, 0.95), 0.25, 0.5, 0.1, 3, 0.25)


## Breaks every pane whose centre is within r of pos (explosions).
func blast(pos: Vector3, r: float, quiet := false) -> void:
	for k in panes.size():
		if not panes[k].broken and (panes[k].xf as Transform3D).origin.distance_to(pos) < r:
			shatter(k, (panes[k].xf as Transform3D).origin - pos, quiet)


## Breaks the panes a body goes through: point p (chest height) inside the pane rectangle, close to
## its plane. Called by the player a few times per second.
func touch(p: Vector3, vel: Vector3) -> void:
	for k in panes.size():
		if panes[k].broken:
			continue
		var xf: Transform3D = panes[k].xf
		if xf.origin.distance_squared_to(p) > 4.0:
			continue
		var l := xf.affine_inverse() * p   # unit-pane space: x, y in -0.5..0.5 on the glass
		var w := xf.basis.x.length()
		var h := xf.basis.y.length()
		var dz := absf(l.z) * xf.basis.z.length()
		if absf(l.x) * w < w * 0.5 + 0.25 and absf(l.y) * h < h * 0.5 + 0.55 and dz < 0.5:
			shatter(k, vel)


## Pane index from a ray hit collider (or -1).
static func pane_of(col) -> int:
	if col is Object and is_instance_valid(col) and (col as Object).has_meta("glass"):
		return int((col as Object).get_meta("glass"))
	return -1
