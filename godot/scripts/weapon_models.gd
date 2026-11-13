extends RefCounted
## First-person weapon models built from rounded primitives, using the depth-pulled weapon shader.
## Hands are articulated (palm, 4 fingers x 3 phalanges, thumb, wrist, forearm) and posed around
## the grip / handguard. Each builder returns the movable parts the reload choreography animates.

const SH := preload("res://shaders/weapon.gdshader")
const FL := preload("res://shaders/flash.gdshader")
const SHP := preload("res://scripts/shapes.gd")
static var _mats := {}


## detail sets: [texture, tiles per metre, normal strength, colour mode (0 wear / 1 full colour), colour mix]
const DETAIL := {"metal": ["metal_plate_02", 14.0, 0.5, 0.0, 0.55], "steel": ["metal_plate", 18.0, 0.45, 0.0, 0.4],
	"poly": ["concrete_floor_01", 30.0, 0.35, 0.0, 0.35], "wood": ["brown_planks_04", 4.0, 0.7, 1.0, 0.85],
	"fabric": ["denim_fabric", 22.0, 0.8, 0.0, 0.6], "leather": ["fabric_leather_02", 18.0, 0.8, 0.0, 0.7],
	"rubber": ["gravel_ground_01", 40.0, 0.3, 0.0, 0.2]}


static func wm(c: Color, rough := 0.6, metal := 0.0, emit := 0.0, det := "") -> ShaderMaterial:
	var key := "%s|%s|%s|%s|%s" % [c.to_html(), rough, metal, emit, det]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SH
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	if emit > 0.0:
		m.set_shader_parameter("emission", c)
		m.set_shader_parameter("emission_energy", emit)
	if det != "" and not ("--nodetail" in OS.get_cmdline_user_args()):
		var d: Array = DETAIL[det]
		m.set_shader_parameter("detail_nor", load("res://assets/tex/%s_nor.jpg" % d[0]))
		m.set_shader_parameter("detail_rough", load("res://assets/tex/%s_rough.jpg" % d[0]))
		m.set_shader_parameter("detail_scale", d[1])
		m.set_shader_parameter("detail_strength", d[2])
		m.set_shader_parameter("detail_alb", load("res://assets/tex/%s_diff.jpg" % d[0]))
		m.set_shader_parameter("detail_alb_mode", d[3])
		m.set_shader_parameter("detail_alb_mix", d[4])
	_mats[key] = m
	return m


# ---------------------------------------------------------------- palette
static func m_black() -> ShaderMaterial: return wm(Color(0.07, 0.075, 0.08), 0.5, 0.2, 0.0, "poly")
static func m_dark() -> ShaderMaterial: return wm(Color(0.13, 0.14, 0.15), 0.42, 0.65, 0.0, "metal")
static func m_mid() -> ShaderMaterial: return wm(Color(0.27, 0.29, 0.31), 0.48, 0.55, 0.0, "metal")
static func m_steel() -> ShaderMaterial: return wm(Color(0.36, 0.37, 0.39), 0.26, 0.92, 0.0, "steel")
static func m_tan() -> ShaderMaterial: return wm(Color(0.47, 0.41, 0.3), 0.75, 0.0, 0.0, "poly")
static func m_wood() -> ShaderMaterial: return wm(Color(0.43, 0.29, 0.17), 0.6, 0.0, 0.0, "wood")
static var glove_col := Color(0.34, 0.28, 0.2)
static var sleeve_col := Color(0.29, 0.32, 0.25)
static func m_glove() -> ShaderMaterial: return wm(glove_col, 0.75, 0.0, 0.0, "leather")
static func m_glove_pad() -> ShaderMaterial: return wm(Color(0.16, 0.145, 0.12), 0.75, 0.0, 0.0, "rubber")
static func m_sleeve() -> ShaderMaterial: return wm(sleeve_col, 0.95, 0.0, 0.0, "fabric")
static func m_cuff() -> ShaderMaterial: return wm(sleeve_col.darkened(0.3), 0.95, 0.0, 0.0, "fabric")
## Sight window: see-through tinted glass (an opaque pane right in front of the eye blacks out the view).
static var _glass: StandardMaterial3D
static func glass() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.albedo_color = Color(0.55, 0.8, 0.85, 0.1)
		_glass.roughness = 0.05
		_glass.metallic_specular = 0.9
		_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass


static func m_lens() -> ShaderMaterial: return wm(Color(0.9, 0.95, 1.0), 0.2, 0.0, 3.0)


## Small round screw / pin heads facing along `axis` (x = side, y = top).
static func pins(parent: Node3D, pts: Array, r: float, mat: Material, axis := "x") -> void:
	for p in pts:
		var c := CylinderMesh.new()
		c.top_radius = r
		c.bottom_radius = r
		c.height = r * 0.8
		c.radial_segments = 10
		_mi(parent, c, mat, p, Vector3(0, 0, PI / 2) if axis == "x" else Vector3.ZERO)


## Picatinny rail section with cross slots along -Z from z0.
static func rail(parent: Node3D, pos: Vector3, length: float, mat: Material, slot: Material, vertical := false) -> void:
	part(parent, Vector3(0.022, 0.009, length) if not vertical else Vector3(0.009, 0.022, length), mat, pos, Vector3.ZERO, 0.002)
	var n := int(length / 0.01)
	for i in n:
		if i % 2 == 0:
			var off := Vector3(0, 0.0, length * 0.5 - (i + 0.5) * 0.01)
			part(parent, Vector3(0.024, 0.004, 0.005) if not vertical else Vector3(0.004, 0.024, 0.005), slot, pos + off + (Vector3(0, 0.004, 0) if not vertical else Vector3(0.004, 0, 0)), Vector3.ZERO, 0.001)


## Weapon light: body, bezel, glowing lens, pressure switch.
static func flashlight(parent: Node3D, pos: Vector3) -> void:
	cyl(parent, 0.012, 0.09, m_black(), pos)
	cyl(parent, 0.0145, 0.02, m_dark(), pos + Vector3(0, 0, -0.05))
	cyl(parent, 0.011, 0.002, m_lens(), pos + Vector3(0, 0, -0.061))
	part(parent, Vector3(0.012, 0.016, 0.03), m_dark(), pos + Vector3(-0.012, 0.0, 0.0), Vector3.ZERO, 0.003)


static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func part(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO, r := -1.0) -> MeshInstance3D:
	return _mi(parent, SHP.rbox(size, r, 2), mat, pos, rot)


static func cyl(parent: Node3D, r: float, l: float, mat: Material, pos: Vector3, segs := 20) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = l
	cm.radial_segments = segs
	cm.rings = 1
	return _mi(parent, cm, mat, pos, Vector3(PI / 2, 0, 0))


static func cap(parent: Node3D, r: float, l: float, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = l + r * 2.0
	cm.radial_segments = 12
	cm.rings = 4
	return _mi(parent, cm, mat, pos, rot)


static func ring(parent: Node3D, r: float, t: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = r - t
	tm.outer_radius = r + t
	tm.rings = 24
	tm.ring_segments = 8
	return _mi(parent, tm, mat, pos, Vector3(PI / 2, 0, 0))


static func flash(g: Node3D, pos: Vector3, size: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var m := ShaderMaterial.new()
	m.shader = FL
	var mi := _mi(g, q, m, pos)
	mi.visible = false
	return mi


# ---------------------------------------------------------------- hands that wrap the gun
## Fingers are modelled as arcs hugging the grip/handguard (computed from the part's real axis
## and radius), so they always sit on the gun instead of floating. Palm, thumb, wrist cuff and
## forearm sleeve complete each hand.
static func limb(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.0005:
		return
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = L + r * 2.0
	cm.radial_segments = 10
	cm.rings = 3
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = (a + b) * 0.5
	mi.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	parent.add_child(mi)


static func arc_pt(c: Vector3, axis: Vector3, ref: Vector3, rad: float, th: float) -> Vector3:
	var side := axis.cross(ref).normalized()
	return c + (ref * cos(th) + side * sin(th)) * rad


static var no_hands := false


static func finger_arc(parent: Node3D, c: Vector3, axis: Vector3, ref: Vector3, rad: float, th0: float, lens: Array, r: float, dir := 1.0) -> void:
	if no_hands:
		return
	var th := th0
	var p := arc_pt(c, axis, ref, rad, th)
	var gl := m_glove()
	for i in lens.size():
		th += float(lens[i]) / rad * dir
		var q := arc_pt(c, axis, ref, rad * (1.0 - i * 0.04), th)
		limb(parent, p, q, r * (1.0 - i * 0.1), gl)
		if i == 0:
			limb(parent, p.lerp(q, 0.2), p.lerp(q, 0.75), r * 1.12, m_glove_pad())
		p = q


static func finger_path(parent: Node3D, pts: Array, r: float) -> void:
	if no_hands:
		return
	for i in pts.size() - 1:
		limb(parent, pts[i], pts[i + 1], r * (1.0 - i * 0.1), m_glove())


static func palm(parent: Node3D, c: Vector3, axis: Vector3, ref: Vector3, rad: float, th: float, size: Vector3) -> Vector3:
	var radial := (arc_pt(c, axis, ref, 1.0, th) - c).normalized()
	var ax := axis.normalized()
	var z := radial.cross(ax).normalized()
	var center := c + radial * (rad + size.x * 0.5)
	if no_hands:
		return center
	var mi := _mi(parent, SHP.rbox(size, size.x * 0.48, 3), m_glove(), center)
	mi.basis = Basis(radial, ax, z)
	# rounded back of the hand + knuckle line so it never reads as a box
	var bk := center + radial * (size.x * 0.25)
	limb(parent, bk - ax * size.y * 0.3, bk + ax * size.y * 0.3, size.x * 0.42, m_glove())
	var kn := center + z * (size.z * 0.42) + radial * (size.x * 0.1)
	limb(parent, kn - ax * size.y * 0.4, kn + ax * size.y * 0.4, size.x * 0.4, m_glove_pad())
	return center


static func taper(parent: Node3D, a: Vector3, b: Vector3, ra: float, rb: float, mat: Material) -> void:
	var d := b - a
	var cm := CylinderMesh.new()
	cm.bottom_radius = ra
	cm.top_radius = rb
	cm.height = d.length()
	cm.radial_segments = 14
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = (a + b) * 0.5
	mi.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	parent.add_child(mi)


## Wrist + forearm: slim at the wrist, widening toward the elbow like a real arm.
static func forearm(parent: Node3D, from: Vector3, wrist: Vector3, arm_dir: Vector3, watch := false) -> void:
	if no_hands:
		return
	var d := arm_dir.normalized()
	limb(parent, from, wrist, 0.026, m_glove())
	limb(parent, wrist - d * 0.005, wrist + d * 0.03, 0.031, m_cuff())
	taper(parent, wrist + d * 0.02, wrist + d * 0.075, 0.035, 0.038, m_sleeve())
	limb(parent, wrist + d * 0.075, wrist + d * 0.085, 0.04, m_sleeve())
	taper(parent, wrist + d * 0.08, wrist + d * 0.3, 0.037, 0.046, m_sleeve())
	limb(parent, wrist + d * 0.29, wrist + d * 0.31, 0.045, m_sleeve())
	taper(parent, wrist + d * 0.3, wrist + d * 0.55, 0.046, 0.05, m_sleeve())
	var q := Basis(Quaternion(Vector3.UP, d))
	# fabric folds bunching up along the sleeve
	var fold := wm(sleeve_col.darkened(0.18), 0.95, 0.0, 0.0, "fabric")
	for k in 4:
		var t := 0.1 + k * 0.055
		var tm := TorusMesh.new()
		tm.inner_radius = 0.036 + t * 0.03
		tm.outer_radius = tm.inner_radius + 0.007
		tm.rings = 18
		tm.ring_segments = 6
		var mi := _mi(parent, tm, fold, wrist + d * t)
		mi.basis = q * Basis(Vector3.RIGHT, 0.12 * (k % 2 * 2 - 1)) * Basis.from_scale(Vector3(1.0, 1.0, 0.92))
	# glove cuff strap with velcro tab
	var strap := TorusMesh.new()
	strap.inner_radius = 0.025
	strap.outer_radius = 0.032
	strap.rings = 18
	strap.ring_segments = 6
	var st := _mi(parent, strap, m_glove_pad(), wrist - d * 0.012)
	st.basis = q
	var up := q * Vector3(0, 0, 1)
	var side := d.cross(up).normalized()
	var tab := _mi(parent, SHP.rbox(Vector3(0.022, 0.006, 0.026), 0.002, 1), m_glove_pad(), wrist - d * 0.012 + side * 0.031)
	tab.basis = Basis(side.cross(d).normalized(), side, d).orthonormalized()
	# shoulder-style patch on the forearm sleeve
	var patch := _mi(parent, SHP.rbox(Vector3(0.03, 0.004, 0.04), 0.002, 1), wm(sleeve_col.lightened(0.15), 0.9, 0.0, 0.0, "fabric"), wrist + d * 0.2 + side * 0.043)
	patch.basis = Basis(side.cross(d).normalized(), side, d).orthonormalized()
	if watch:
		var wt := wrist + d * 0.045
		var band := TorusMesh.new()
		band.inner_radius = 0.034
		band.outer_radius = 0.041
		band.rings = 20
		band.ring_segments = 6
		var bm := _mi(parent, band, wm(Color(0.06, 0.06, 0.06), 0.6, 0.0, 0.0, "rubber"), wt)
		bm.basis = q
		var face_dir := -side
		var fc := CylinderMesh.new()
		fc.top_radius = 0.017
		fc.bottom_radius = 0.018
		fc.height = 0.009
		fc.radial_segments = 18
		var fb := Basis(face_dir.cross(d).normalized(), face_dir, d).orthonormalized()
		var case := _mi(parent, fc, m_dark(), wt + face_dir * 0.041)
		case.basis = fb
		var dial := CylinderMesh.new()
		dial.top_radius = 0.0135
		dial.bottom_radius = 0.0135
		dial.height = 0.002
		var dm := _mi(parent, dial, wm(Color(0.25, 0.9, 0.55), 0.3, 0.0, 1.4), wt + face_dir * 0.0458)
		dm.basis = fb
		var bez := TorusMesh.new()
		bez.inner_radius = 0.0145
		bez.outer_radius = 0.0185
		bez.rings = 20
		bez.ring_segments = 6
		var bz := _mi(parent, bez, m_steel(), wt + face_dir * 0.0455)
		bz.basis = fb


## Sling: flat webbing hanging between two swivels with a natural sag.
static func sling(parent: Node3D, a: Vector3, b: Vector3, sag: float) -> void:
	var web := wm(Color(0.12, 0.13, 0.11), 0.9, 0.0, 0.0, "fabric")
	var prev := a
	var n := 12
	for k in range(1, n + 1):
		var t := float(k) / n
		var p := a.lerp(b, t) - Vector3(0, sin(t * PI) * sag, 0)
		var dd := p - prev
		var mi := _mi(parent, SHP.rbox(Vector3(0.022, 0.003, dd.length() + 0.002), 0.001, 1), web, (p + prev) * 0.5)
		mi.basis = Basis.looking_at(dd.normalized(), Vector3.RIGHT.cross(dd.normalized()).normalized() if absf(dd.normalized().x) < 0.9 else Vector3.UP)
		prev = p
	for e in [a, b]:
		var buckle := _mi(parent, SHP.rbox(Vector3(0.026, 0.006, 0.012), 0.002, 1), m_steel(), e)


## Right hand on a pistol grip: c = grip centre, axis = grip up-axis, rg = grip half thickness,
## trig = 3 points for the index finger resting along the trigger.
static func right_grip(g: Node3D, c: Vector3, axis: Vector3, rg: float, trig: Array, arm_dir: Vector3) -> void:
	g.set_meta("rgrip", {"c": c, "axis": axis, "rad": rg})   # for the first-person arms (fp_arms.gd)
	if no_hands:
		return
	var a := axis.normalized()
	var ref := Vector3.RIGHT
	var fr := rg + 0.0095
	var lens := [[0.044, 0.028, 0.022], [0.041, 0.026, 0.021], [0.033, 0.021, 0.018]]
	var ts := [-0.004, -0.027, -0.049]
	for i in 3:
		finger_arc(g, c + a * ts[i], a, ref, fr, -0.35, lens[i], 0.0088 - i * 0.0005)
	var a0 := arc_pt(c + a * 0.021, a, ref, fr, -0.25)
	finger_path(g, [a0, trig[0], trig[1], trig[2]], 0.0086)
	var pc := palm(g, c + a * -0.016, a, ref, rg, -1.2, Vector3(0.028, 0.088, 0.07))
	finger_arc(g, c + a * 0.036, a, ref, rg + 0.011, -0.85, [0.036, 0.03], 0.011, -1.0)
	forearm(g, pc, pc + a * -0.05 + Vector3(0.012, 0.0, 0.03), arm_dir)


## Left hand under a horizontal part (handguard / pump) whose axis runs along Z through `c`.
static func left_guard(L: Node3D, c: Vector3, rad: float, arm_dir: Vector3, axis := Vector3(0, 0, -1)) -> void:
	L.set_meta("lgrip", {"c": c, "axis": axis, "rad": rad})
	if no_hands:
		return
	var ref := Vector3(0, -1, 0)
	var fr := rad + 0.0095
	# support grip: palm under the near side, fingers wrap underneath and up the far side,
	# thumb lies along the near side pointing forward (side = +th, far side = -th)
	var lens := [[0.042, 0.026, 0.021], [0.046, 0.028, 0.022], [0.043, 0.027, 0.021], [0.034, 0.021, 0.018]]
	var ts := [0.03, 0.01, -0.01, -0.029]
	for i in 4:
		finger_arc(L, c + axis * ts[i], axis, ref, fr, 0.15, lens[i], 0.0088 - absf(i - 1) * 0.0004, -1.0)
	var pc := palm(L, c, axis, ref, rad, 0.8, Vector3(0.028, 0.086, 0.07))
	finger_path(L, [arc_pt(c + axis * -0.012, axis, ref, rad + 0.012, 1.05), arc_pt(c + axis * 0.022, axis, ref, rad + 0.012, 1.3), arc_pt(c + axis * 0.052, axis, ref, rad + 0.011, 1.38)], 0.011)
	forearm(L, pc, pc + Vector3(0.032 * axis.z, -0.05, 0.05), arm_dir, axis.z < 0.0)


# ---------------------------------------------------------------- weapons
static func rifle() -> Dictionary:
	var g := Node3D.new()
	var black := m_black()
	var dark := m_dark()
	var mid := m_mid()
	var steel := m_steel()
	var tan := m_tan()
	# upper receiver, ejection port, forward assist, charging handle
	part(g, Vector3(0.064, 0.052, 0.3), dark, Vector3(0, 0.022, -0.04), Vector3.ZERO, 0.01)
	part(g, Vector3(0.004, 0.022, 0.07), black, Vector3(0.033, 0.024, -0.03), Vector3.ZERO, 0.002)
	part(g, Vector3(0.002, 0.014, 0.05), steel, Vector3(0.035, 0.024, -0.03), Vector3.ZERO, 0.001)
	cyl(g, 0.009, 0.03, dark, Vector3(0.036, 0.03, 0.06))
	var handle := part(g, Vector3(0.05, 0.01, 0.03), mid, Vector3(0, 0.05, 0.12), Vector3.ZERO, 0.004)
	# lower receiver, magwell, trigger guard, trigger, selector
	part(g, Vector3(0.06, 0.05, 0.26), dark, Vector3(0, -0.026, -0.02), Vector3.ZERO, 0.01)
	part(g, Vector3(0.066, 0.05, 0.085), dark, Vector3(0, -0.055, -0.11), Vector3(0.12, 0, 0), 0.012)
	part(g, Vector3(0.012, 0.006, 0.075), dark, Vector3(0, -0.085, -0.01), Vector3.ZERO, 0.003)
	part(g, Vector3(0.006, 0.03, 0.006), steel, Vector3(0, -0.068, -0.012), Vector3(0.25, 0, 0), 0.002)
	cyl(g, 0.007, 0.004, steel, Vector3(-0.032, -0.022, 0.03)).rotation = Vector3(0, 0, PI / 2)
	# top rail with ridges
	part(g, Vector3(0.03, 0.012, 0.42), mid, Vector3(0, 0.054, -0.12), Vector3.ZERO, 0.003)
	for i in 26:
		part(g, Vector3(0.032, 0.006, 0.006), black, Vector3(0, 0.062, 0.08 - i * 0.016), Vector3.ZERO, 0.001)
	# handguard with M-LOK slots and bottom rail
	part(g, Vector3(0.076, 0.072, 0.27), tan, Vector3(0, 0.012, -0.36), Vector3.ZERO, 0.022)
	for sx in [-1.0, 1.0]:
		for i in 4:
			part(g, Vector3(0.004, 0.012, 0.034), black, Vector3(0.038 * sx, 0.014, -0.27 - i * 0.055), Vector3.ZERO, 0.002)
	part(g, Vector3(0.026, 0.01, 0.12), mid, Vector3(0, -0.028, -0.42), Vector3.ZERO, 0.003)
	# gas block, front sight post, barrel, flash hider
	part(g, Vector3(0.032, 0.03, 0.03), dark, Vector3(0, 0.012, -0.5), Vector3.ZERO, 0.006)
	part(g, Vector3(0.006, 0.05, 0.006), black, Vector3(0, 0.052, -0.5), Vector3.ZERO, 0.002)
	part(g, Vector3(0.026, 0.008, 0.012), black, Vector3(0, 0.074, -0.5), Vector3.ZERO, 0.002)
	cyl(g, 0.0125, 0.22, steel, Vector3(0, 0.01, -0.58))
	cyl(g, 0.019, 0.07, black, Vector3(0, 0.01, -0.705))
	for k in 4:
		var a := k * PI / 2 + PI / 4
		part(g, Vector3(0.006, 0.004, 0.045), wm(Color(0.02, 0.02, 0.02), 0.9), Vector3(cos(a) * 0.017, 0.01 + sin(a) * 0.017, -0.715), Vector3(0, 0, a), 0.001)
	# curved magazine with ribs
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.09, -0.11)
	mag.rotation.x = 0.2
	g.add_child(mag)
	for s in 4:
		var seg := part(mag, Vector3(0.05, 0.05, 0.08), mid, Vector3(0, -s * 0.045, -s * 0.009), Vector3(s * 0.08, 0, 0), 0.008)
		seg.name = "seg%d" % s
		for sx in [-1.0, 1.0]:
			part(mag, Vector3(0.003, 0.03, 0.05), dark, Vector3(0.026 * sx, -s * 0.045, -s * 0.009), Vector3(s * 0.08, 0, 0), 0.001)
	part(mag, Vector3(0.056, 0.012, 0.088), black, Vector3(0, -0.175, -0.04), Vector3(0.3, 0, 0), 0.004)
	# pistol grip with texture ridges
	part(g, Vector3(0.042, 0.1, 0.05), black, Vector3(0, -0.095, 0.075), Vector3(-0.3, 0, 0), 0.012)
	for i in 5:
		part(g, Vector3(0.044, 0.004, 0.02), dark, Vector3(0, -0.07 - i * 0.017, 0.06 + i * 0.005), Vector3(-0.3, 0, 0), 0.001)
	# buffer tube + adjustable stock + cheek riser + butt pad + sling loop
	cyl(g, 0.016, 0.2, black, Vector3(0, 0.012, 0.2))
	part(g, Vector3(0.05, 0.085, 0.17), tan, Vector3(0, -0.012, 0.29), Vector3.ZERO, 0.02)
	part(g, Vector3(0.044, 0.02, 0.1), tan, Vector3(0, 0.04, 0.27), Vector3.ZERO, 0.008)
	part(g, Vector3(0.054, 0.1, 0.022), black, Vector3(0, -0.015, 0.384), Vector3.ZERO, 0.009)
	ring(g, 0.012, 0.0025, steel, Vector3(0, -0.06, 0.28)).rotation = Vector3(0, PI / 2, 0)
	# red-dot sight: mount, two rings, dot
	part(g, Vector3(0.03, 0.014, 0.07), dark, Vector3(0, 0.068, -0.07), Vector3.ZERO, 0.004)
	part(g, Vector3(0.014, 0.022, 0.03), dark, Vector3(0, 0.074, -0.07), Vector3.ZERO, 0.003)
	ring(g, 0.024, 0.005, dark, Vector3(0, 0.088, -0.045))
	ring(g, 0.024, 0.004, dark, Vector3(0, 0.088, -0.095))
	part(g, Vector3(0.0035, 0.0035, 0.002), wm(Color(1.0, 0.1, 0.08), 0.5, 0.0, 8.0), Vector3(0, 0.088, -0.07))
	# extra definition: rear flip-up sight, takedown pins, mag release, bolt catch, dust cover hinge,
	# handguard screws, weapon light, sling swivels, QD socket, stock lever, barrel nut
	part(g, Vector3(0.026, 0.014, 0.024), dark, Vector3(0, 0.068, 0.07), Vector3.ZERO, 0.003)
	for sx in [-1.0, 1.0]:
		part(g, Vector3(0.004, 0.026, 0.014), dark, Vector3(0.009 * sx, 0.084, 0.07), Vector3(-0.15, 0, 0), 0.0015)
	ring(g, 0.005, 0.0015, black, Vector3(0, 0.09, 0.07))
	pins(g, [Vector3(0.031, -0.03, -0.1), Vector3(-0.031, -0.03, -0.1), Vector3(0.031, -0.022, 0.07), Vector3(-0.031, -0.022, 0.07)], 0.0045, steel)
	cyl(g, 0.006, 0.006, steel, Vector3(0.034, -0.045, -0.06)).rotation = Vector3(0, 0, PI / 2)
	part(g, Vector3(0.004, 0.02, 0.012), dark, Vector3(-0.032, -0.012, -0.075), Vector3.ZERO, 0.0015)
	cyl(g, 0.0025, 0.07, steel, Vector3(0.034, 0.01, -0.03))
	pins(g, [Vector3(0.039, 0.035, -0.26), Vector3(0.039, 0.035, -0.46), Vector3(-0.039, 0.035, -0.26), Vector3(-0.039, 0.035, -0.46)], 0.003, steel)
	flashlight(g, Vector3(0.048, -0.01, -0.44))
	ring(g, 0.008, 0.0018, steel, Vector3(0, -0.04, -0.47)).rotation = Vector3(0, PI / 2, 0)
	cyl(g, 0.02, 0.025, dark, Vector3(0, 0.012, -0.235))
	for k in 6:
		var a := k * TAU / 6.0
		part(g, Vector3(0.006, 0.006, 0.02), black, Vector3(cos(a) * 0.02, 0.012 + sin(a) * 0.02, -0.235), Vector3(0, 0, a), 0.001)
	cyl(g, 0.006, 0.004, steel, Vector3(0.027, -0.03, 0.33)).rotation = Vector3(0, 0, PI / 2)
	part(g, Vector3(0.016, 0.008, 0.035), black, Vector3(0, -0.06, 0.24), Vector3.ZERO, 0.002)
	cyl(g, 0.0135, 0.003, black, Vector3(0, 0.01, -0.741))
	# hands
	if ak_on("rifle"):
		return _ak_scan("rifle", g, mag)
	right_grip(g, Vector3(0, -0.095, 0.075), Basis(Vector3.RIGHT, -0.3) * Vector3.UP, 0.025,
		[Vector3(0.017, -0.058, 0.02), Vector3(0.016, -0.062, -0.002), Vector3(0.012, -0.068, -0.014)], Vector3(0.18, -0.42, 1.0))
	var left := Node3D.new()
	left.position = Vector3(0, -0.03, -0.35)
	g.add_child(left)
	left_guard(left, Vector3(0, 0.042, -0.01), 0.04, Vector3(-0.32, -0.45, 1.0))
	sling(g, Vector3(0, -0.06, 0.28), Vector3(0, -0.04, -0.47), 0.13)
	return {"model": g, "hip": Vector3(0.14, -0.175, -0.5), "aim": Vector3(0, -0.088, -0.26), "flash": flash(g, Vector3(0, 0.01, -0.76), 0.32),
		"left": left, "mag": mag, "handle": handle, "kind": "mag"}


static func shotgun() -> Dictionary:
	var g := Node3D.new()
	var black := m_black()
	var dark := m_dark()
	var steel := m_steel()
	var wood := m_wood()
	part(g, Vector3(0.07, 0.085, 0.3), dark, Vector3(0, 0, -0.02), Vector3.ZERO, 0.014)
	part(g, Vector3(0.004, 0.03, 0.08), black, Vector3(0.036, 0.008, -0.03), Vector3.ZERO, 0.002)
	part(g, Vector3(0.012, 0.006, 0.075), dark, Vector3(0, -0.055, 0.02), Vector3.ZERO, 0.003)
	part(g, Vector3(0.006, 0.028, 0.006), steel, Vector3(0, -0.04, 0.02), Vector3(0.25, 0, 0), 0.002)
	cyl(g, 0.02, 0.56, steel, Vector3(0, 0.025, -0.43))
	cyl(g, 0.017, 0.46, dark, Vector3(0, -0.022, -0.39))
	cyl(g, 0.019, 0.02, dark, Vector3(0, -0.022, -0.62))
	part(g, Vector3(0.02, 0.012, 0.03), dark, Vector3(0, 0.0, -0.6), Vector3.ZERO, 0.004)
	var pump := Node3D.new()
	pump.position = Vector3(0, -0.03, -0.38)
	g.add_child(pump)
	part(pump, Vector3(0.076, 0.066, 0.19), wood, Vector3.ZERO, Vector3.ZERO, 0.026)
	for i in 6:
		part(pump, Vector3(0.078, 0.006, 0.008), wm(Color(0.27, 0.18, 0.1), 0.8), Vector3(0, -0.012, -0.07 + i * 0.028), Vector3.ZERO, 0.002)
	part(g, Vector3(0.044, 0.1, 0.05), wood, Vector3(0, -0.09, 0.1), Vector3(-0.35, 0, 0), 0.014)
	part(g, Vector3(0.054, 0.1, 0.26), wood, Vector3(0, -0.04, 0.27), Vector3(0.1, 0, 0), 0.024)
	part(g, Vector3(0.058, 0.11, 0.024), black, Vector3(0, -0.055, 0.405), Vector3(0.1, 0, 0), 0.01)
	var bead := SphereMesh.new()
	bead.radius = 0.006
	bead.height = 0.012
	_mi(g, bead, wm(Color(1.0, 0.95, 0.6), 0.5, 0.0, 3.0), Vector3(0, 0.05, -0.69))
	# side saddle with spare shells, loading port, heat shield with vents, safety, sling swivels, pad ridges
	part(g, Vector3(0.008, 0.05, 0.1), black, Vector3(-0.039, 0.0, -0.02), Vector3.ZERO, 0.003)
	for i in 4:
		cyl(g, 0.0105, 0.05, wm(Color(0.62, 0.14, 0.1), 0.5, 0.0, 0.0, "poly"), Vector3(-0.05, 0.0, -0.055 + i * 0.024)).rotation = Vector3.ZERO
		cyl(g, 0.0108, 0.012, wm(Color(0.75, 0.6, 0.3), 0.3, 1.0), Vector3(-0.05, -0.022, -0.055 + i * 0.024)).rotation = Vector3.ZERO
	part(g, Vector3(0.03, 0.006, 0.07), black, Vector3(0, -0.044, -0.02), Vector3.ZERO, 0.002)
	part(g, Vector3(0.03, 0.012, 0.28), black, Vector3(0, 0.048, -0.42), Vector3.ZERO, 0.005)
	for i in 7:
		part(g, Vector3(0.016, 0.004, 0.018), wm(Color(0.02, 0.02, 0.02), 0.9), Vector3(0, 0.054, -0.31 - i * 0.035), Vector3.ZERO, 0.002)
	cyl(g, 0.005, 0.03, steel, Vector3(0, -0.035, 0.035)).rotation = Vector3(0, 0, PI / 2)
	ring(g, 0.008, 0.0018, steel, Vector3(0, -0.04, -0.6)).rotation = Vector3(0, PI / 2, 0)
	ring(g, 0.008, 0.0018, steel, Vector3(0, -0.11, 0.3)).rotation = Vector3(0, PI / 2, 0)
	for i in 4:
		part(g, Vector3(0.06, 0.004, 0.026), wm(Color(0.04, 0.04, 0.04), 0.9), Vector3(0, -0.1 + i * 0.03, 0.418), Vector3(0.1, 0, 0), 0.001)
	pins(g, [Vector3(0.036, -0.02, 0.06), Vector3(-0.036, -0.02, 0.06), Vector3(0.036, 0.02, -0.12), Vector3(-0.036, 0.02, -0.12)], 0.004, steel)
	right_grip(g, Vector3(0, -0.09, 0.1), Basis(Vector3.RIGHT, -0.35) * Vector3.UP, 0.025,
		[Vector3(0.017, -0.03, 0.05), Vector3(0.016, -0.034, 0.032), Vector3(0.012, -0.04, 0.022)], Vector3(0.18, -0.42, 1.0))
	var left := Node3D.new()
	left.position = Vector3(0, -0.035, -0.38)
	g.add_child(left)
	left_guard(left, Vector3(0, 0.005, 0.0), 0.036, Vector3(-0.32, -0.45, 1.0))
	var shell := Node3D.new()
	shell.position = Vector3(0.03, 0.02, -0.02)
	shell.visible = false
	left.add_child(shell)
	var sb := CylinderMesh.new()
	sb.top_radius = 0.011
	sb.bottom_radius = 0.011
	sb.height = 0.055
	_mi(shell, sb, wm(Color(0.66, 0.15, 0.11), 0.5), Vector3.ZERO, Vector3(PI / 2, 0, 0))
	sling(g, Vector3(0, -0.11, 0.3), Vector3(0, -0.04, -0.6), 0.15)
	return {"model": g, "hip": Vector3(0.14, -0.17, -0.48), "aim": Vector3(0, -0.05, -0.3), "flash": flash(g, Vector3(0, 0.025, -0.73), 0.46),
		"left": left, "pump": pump, "shell": shell, "kind": "shell"}


static func pistol() -> Dictionary:
	var g := Node3D.new()
	var black := m_black()
	var dark := m_dark()
	var steel := m_steel()
	var slide := Node3D.new()
	g.add_child(slide)
	part(slide, Vector3(0.04, 0.042, 0.2), steel, Vector3(0, 0.002, -0.06), Vector3.ZERO, 0.007)
	for i in 6:
		part(slide, Vector3(0.042, 0.03, 0.003), dark, Vector3(0, 0.004, 0.0 + i * 0.007), Vector3.ZERO, 0.001)
	part(slide, Vector3(0.005, 0.016, 0.03), black, Vector3(0.02, 0.01, -0.04), Vector3.ZERO, 0.001)
	part(slide, Vector3(0.006, 0.012, 0.008), wm(Color(1.0, 0.95, 0.6), 0.5, 0.0, 3.0), Vector3(0, 0.028, -0.15))
	part(slide, Vector3(0.012, 0.01, 0.008), black, Vector3(-0.012, 0.027, 0.025))
	part(slide, Vector3(0.012, 0.01, 0.008), black, Vector3(0.012, 0.027, 0.025))
	cyl(g, 0.0075, 0.012, black, Vector3(0, 0.004, -0.163))
	part(g, Vector3(0.036, 0.028, 0.18), dark, Vector3(0, -0.033, -0.06), Vector3.ZERO, 0.006)
	part(g, Vector3(0.022, 0.008, 0.05), black, Vector3(0, -0.05, -0.11), Vector3.ZERO, 0.002)
	part(g, Vector3(0.01, 0.006, 0.05), dark, Vector3(0, -0.06, -0.02), Vector3.ZERO, 0.002)
	part(g, Vector3(0.005, 0.022, 0.005), steel, Vector3(0, -0.052, -0.02), Vector3(0.2, 0, 0), 0.0015)
	part(g, Vector3(0.036, 0.12, 0.055), black, Vector3(0, -0.09, 0.01), Vector3(-0.2, 0, 0), 0.01)
	for i in 6:
		part(g, Vector3(0.038, 0.003, 0.03), dark, Vector3(0, -0.06 - i * 0.014, 0.01 + i * 0.003), Vector3(-0.2, 0, 0), 0.001)
	cyl(g, 0.006, 0.01, steel, Vector3(0, 0.0, 0.045))
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.1, 0.018)
	mag.rotation.x = -0.2
	g.add_child(mag)
	part(mag, Vector3(0.028, 0.11, 0.042), m_mid(), Vector3.ZERO, Vector3.ZERO, 0.005)
	part(mag, Vector3(0.034, 0.016, 0.05), black, Vector3(0, -0.06, 0), Vector3.ZERO, 0.005)
	# front serrations, extractor, takedown lever, mag release, accessory rail, beavertail, grip panel stipple
	for i in 4:
		part(slide, Vector3(0.042, 0.026, 0.003), dark, Vector3(0, 0.006, -0.12 - i * 0.008), Vector3.ZERO, 0.001)
	part(slide, Vector3(0.003, 0.006, 0.025), steel, Vector3(0.0205, 0.012, -0.015), Vector3.ZERO, 0.001)
	part(g, Vector3(0.004, 0.008, 0.016), black, Vector3(0.019, -0.022, -0.035), Vector3.ZERO, 0.0015)
	part(g, Vector3(0.006, 0.01, 0.01), dark, Vector3(0.019, -0.045, 0.0), Vector3.ZERO, 0.002)
	rail(g, Vector3(0, -0.05, -0.12), 0.05, black, dark)
	part(g, Vector3(0.03, 0.012, 0.03), black, Vector3(0, -0.032, 0.048), Vector3(-0.4, 0, 0), 0.006)
	for sx in [-1.0, 1.0]:
		part(g, Vector3(0.003, 0.07, 0.036), wm(Color(0.09, 0.09, 0.09), 0.85, 0.0, 0.0, "rubber"), Vector3(0.019 * sx, -0.095, 0.012), Vector3(-0.2, 0, 0), 0.001)
	# scanned model (Poly Haven "service_pistol", CC0) replaces the primitives; the slide / mag
	# nodes, grip points and flash stay, so reloads, recoil and the IK hands work unchanged
	var scan := scan_pistol_on()
	if scan:
		for c in g.get_children():
			if c != slide and c != mag:
				c.free()
		for c in slide.get_children() + mag.get_children():
			c.free()
		_mount_scan(PISTOL_GLTF, Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, -0.08, 0.005)),
			{"service_pistol_pistol_a": g, "service_pistol_hammer_a": g, "service_pistol_trigger_a": g,
			"service_pistol_slide_a": slide, "service_pistol_magazine_loaded": mag},
			{"service_pistol_magazine_loaded": Vector3(0.1, 0, 0)})
	var ga := Basis(Vector3.RIGHT, -0.2) * Vector3.UP
	var gc := Vector3(0, -0.09, 0.01)
	right_grip(g, gc, ga, 0.022, [Vector3(0.015, -0.046, 0.0), Vector3(0.014, -0.049, -0.012), Vector3(0.011, -0.053, -0.022)], Vector3(0.15, -0.55, 1.0))
	var left := Node3D.new()
	left.position = Vector3(-0.03, -0.1, 0.02)
	g.add_child(left)
	var lc := gc - left.position
	left.set_meta("lgrip", {"c": lc + Vector3(-0.012, 0.0, 0.0), "axis": ga, "rad": 0.03, "pistol": true})
	var lens := [[0.042, 0.026, 0.021], [0.046, 0.028, 0.022], [0.043, 0.027, 0.021], [0.034, 0.021, 0.018]]
	for i in 4:
		finger_arc(left, lc + ga * (0.004 - i * 0.021), ga, Vector3.RIGHT, 0.044, 2.75, lens[i], 0.0086, -1.0)
	var lpc := palm(left, lc + ga * -0.02, ga, Vector3.RIGHT, 0.038, 3.55, Vector3(0.028, 0.085, 0.07))
	finger_path(left, [arc_pt(lc + ga * 0.03, ga, Vector3.RIGHT, 0.036, 3.35), Vector3(-0.026, -0.022, -0.035) - left.position, Vector3(-0.024, -0.024, -0.07) - left.position], 0.011)
	forearm(left, lpc, lpc + Vector3(-0.02, -0.04, 0.045), Vector3(-0.3, -0.5, 1.0), true)
	if scan:
		# the scanned pistol sits ~3 cm lower (its sights are at y≈0): lift the aim / hip poses
		return {"model": g, "hip": Vector3(0.11, -0.105, -0.4), "aim": Vector3(0, 0.0, -0.32), "flash": flash(g, Vector3(0, -0.018, -0.175), 0.22),
			"left": left, "mag": mag, "slide": slide, "kind": "pistol"}
	return {"model": g, "hip": Vector3(0.11, -0.13, -0.4), "aim": Vector3(0, -0.031, -0.32), "flash": flash(g, Vector3(0, 0.0, -0.18), 0.22),
		"left": left, "mag": mag, "slide": slide, "kind": "pistol"}


# ---------------------------------------------------------------- scanned gun models
const SHT := preload("res://shaders/weapon_tex.gdshader")
const PISTOL_GLTF := "res://assets/models/service_pistol/service_pistol_2k.gltf"
const RIFLE_GLTF := "res://assets/models/bolt_action_rifle_7_62/bolt_action_rifle_7_62_2k.gltf"
const STICK_GLTF := "res://assets/models/stick_grenade/stick_grenade_2k.gltf"
static var _scan_mats := {}
static var _surf_cache := {}


static func scan_on(gltf: String) -> bool:
	return ResourceLoader.exists(gltf) and not ("--oldguns" in OS.get_cmdline_user_args())


static func scan_pistol_on() -> bool:
	return scan_on(PISTOL_GLTF)


## Viewmodel material from a glTF material (albedo, normal and the ARM image that the importer
## assigns as roughness/metallic texture: R occlusion, G roughness, B metallic).
static func scan_mat(src: Material) -> ShaderMaterial:
	if _scan_mats.has(src):
		return _scan_mats[src]
	var m := ShaderMaterial.new()
	m.shader = SHT
	var sm := src as BaseMaterial3D
	if sm:
		m.set_shader_parameter("tex_alb", sm.albedo_texture)
		m.set_shader_parameter("tex_nor", sm.normal_texture)
		m.set_shader_parameter("tex_arm", sm.roughness_texture if sm.roughness_texture else sm.metallic_texture)
	_scan_mats[src] = m
	return m


## One single-surface mesh per material, so every piece can carry its own material_override
## (camo, world copies and chalk all work on material_override).
static func _surfaces(mesh: Mesh) -> Array:
	if _surf_cache.has(mesh):
		return _surf_cache[mesh]
	var out := []
	if mesh.get_surface_count() == 1:
		out.append([mesh, mesh.surface_get_material(0)])
	else:
		for s in mesh.get_surface_count():
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
			out.append([am, mesh.surface_get_material(s)])
	_surf_cache[mesh] = out
	return out


## Copy meshes of a scanned glTF onto gun nodes. base maps model space to gun space;
## parts = {mesh name: node it belongs to}; offs = model-space shift per part (pieces laid out
## beside the gun in the file, e.g. the magazine).
static func _mount_scan(gltf: String, base: Transform3D, parts: Dictionary, offs := {}) -> void:
	var sc: Node = (load(gltf) as PackedScene).instantiate()
	for nm in parts:
		var src := sc.find_child(nm, true, false) as MeshInstance3D
		if src == null:
			continue
		var xf := src.transform
		var p := src.get_parent()
		while p != null and p != sc and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		xf.origin += offs.get(nm, Vector3.ZERO)
		var dst: Node3D = parts[nm]
		for sf in _surfaces(src.mesh):
			var mi := MeshInstance3D.new()
			mi.mesh = sf[0]
			var sm: Material = src.get_surface_override_material(0) if src.mesh.get_surface_count() == 1 and src.get_surface_override_material(0) else sf[1]
			mi.material_override = scan_mat(sm)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.transform = dst.transform.affine_inverse() * base * xf if dst.get_parent() != null else base * xf
			mi.set_meta("scan", true)
			dst.add_child(mi)
	sc.free()


## Sniper on the scanned bolt-action rifle (Poly Haven "bolt_action_rifle_7_62", CC0, 1.23 m like
## the procedural one). Model: muzzle +X, bore at y≈0.045, trigger x≈-0.29; the bolt (bolt_a,
## closed) rides on `handle`, now on the bore axis so the bolt lift turns around it. Straight wrist
## (no pistol grip): the right hand sits behind the trigger guard, the left under the wooden forend.
static func _sniper_scan(g: Node3D, handle: Node3D, mag: Node3D) -> Dictionary:
	_clear_proc(g, [handle, mag])
	handle.position = Vector3(0, 0.015, 0.0)
	var base := Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, -0.03, -0.239))
	_mount_scan(RIFLE_GLTF, base, {"bolt_action_rifle_7_62": g, "bolt_action_rifle_7_62_scope": g,
		"bolt_action_rifle_7_62_wrap": g, "bolt_action_rifle_7_62_trigger": g, "bolt_action_rifle_7_62_bolt_a": handle})
	var gc := Vector3(0, -0.035, 0.105)
	var ga := Basis(Vector3.RIGHT, -0.75) * Vector3.UP
	right_grip(g, gc, ga, 0.021, [Vector3(0.014, -0.022, 0.075), Vector3(0.012, -0.032, 0.058), Vector3(0.008, -0.042, 0.05)], Vector3(0.18, -0.42, 1.0))
	var left := Node3D.new()
	left.position = Vector3(0, -0.01, -0.3)
	g.add_child(left)
	left_guard(left, Vector3(0, 0.025, 0), 0.024, Vector3(-0.32, -0.45, 1.0))
	return {"model": g, "hip": Vector3(0.14, -0.17, -0.5), "aim": Vector3(0, -0.041, -0.2), "flash": flash(g, Vector3(0, 0.015, -0.86), 0.4),
		"left": left, "mag": mag, "handle": handle, "bolt": true, "kind": "mag"}


# ---- "Ak trio pack" by mightydinosaurcol (OpenGameArt, CC-BY 3.0: credited in the main menu and
# LEEME): AK-47 → rifle, AKS-74U → smg, RPK → lmg. One mesh per gun (FBX, barrel along +Z), so the
# magazine is cut out of the mesh by triangle position (regions = [z min, z max, y max] in model
# space) and rides on the `mag` node for the reloads. Lined up on the procedural gun's pistol grip
# (where the right hand is); left hand, sights, flash and charging handle measured from side photos.
const AK_DIR := "res://assets/models/ak_trio/"
const AK_CFG := {
	"rifle": {"file": "ak47.fbx", "t": Vector3(0, -0.114, -0.014), "gc": Vector3(0, -0.095, 0.075), "gr": 0.025,
		"left": Vector3(0, -0.08, -0.21), "guard": Vector3(0, 0.016, 0), "guard_r": 0.024, "mag": Vector3(0, -0.048, -0.074),
		"handle": Vector3(0.02, -0.021, -0.122), "regions": [[0.022, 0.115, 0.066], [0.115, 0.17, 0.0]],
		"hip": Vector3(0.14, -0.14, -0.45), "aim": Vector3(0, -0.026, -0.33), "flash": Vector3(0, -0.011, -0.48), "fs": 0.32},
	"smg": {"file": "aks.fbx", "t": Vector3(0, -0.099, -0.004), "gc": Vector3(0, -0.085, 0.06), "gr": 0.024,
		"left": Vector3(0, -0.07, -0.19), "guard": Vector3(0, 0.02, 0), "guard_r": 0.024, "mag": Vector3(0, -0.033, -0.064),
		"handle": Vector3(0.02, -0.006, -0.112), "regions": [[0.022, 0.115, 0.066], [0.115, 0.17, 0.0]],
		"hip": Vector3(0.13, -0.14, -0.42), "aim": Vector3(0, -0.046, -0.25), "flash": Vector3(0, 0.006, -0.38), "fs": 0.28},
	"lmg": {"file": "RPK.fbx", "t": Vector3(0, -0.119, -0.004), "gc": Vector3(0, -0.1, 0.085), "gr": 0.026,
		"left": Vector3(0, -0.085, -0.2), "guard": Vector3(0, 0.016, 0), "guard_r": 0.024, "mag": Vector3(0, -0.053, -0.064),
		"handle": Vector3(0.02, -0.026, -0.112), "regions": [[0.012, 0.115, 0.066]],
		"hip": Vector3(0.14, -0.15, -0.48), "aim": Vector3(0, -0.021, -0.36), "flash": Vector3(0, -0.016, -0.59), "fs": 0.4},
}
static var _ak_mats := {}
static var _split_cache := {}


static func ak_on(which: String) -> bool:
	return AK_CFG.has(which) and scan_on(AK_DIR + AK_CFG[which].file)


static func _ak_mat(mat_name: String) -> ShaderMaterial:
	if _ak_mats.has(mat_name):
		return _ak_mats[mat_name]
	var m := ShaderMaterial.new()
	m.shader = SHT
	m.set_shader_parameter("use_arm", 0.0)
	if mat_name == "RPKMATS":
		m.set_shader_parameter("tex_alb", load(AK_DIR + "tex/RPKtex.tga"))
		m.set_shader_parameter("rough_mul", 0.7)
	else:
		m.set_shader_parameter("tex_alb", load(AK_DIR + "tex/akmatex.TGA"))
		m.set_shader_parameter("tex_rough", load(AK_DIR + "tex/akrough.TGA"))
		m.set_shader_parameter("tex_spec", load(AK_DIR + "tex/akspec.TGA"))
	_ak_mats[mat_name] = m
	return m


## Split one surface into [body, magazine] meshes: a triangle goes to the magazine when its
## centroid (model space, after xf) falls in one of the regions.
static func _split_surface(mesh: Mesh, s: int, xf: Transform3D, regions: Array) -> Array:
	var key := "%s|%d|%s" % [mesh.get_rid(), s, str(regions)]
	if _split_cache.has(key):
		return _split_cache[key]
	var arr: Array = mesh.surface_get_arrays(s)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
	var body := PackedInt32Array()
	var magi := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var c: Vector3 = xf * ((verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0)
		var in_mag := false
		for r in regions:
			if c.z >= r[0] and c.z <= r[1] and c.y <= r[2]:
				in_mag = true
				break
		var dst := magi if in_mag else body
		dst.append(idx[t])
		dst.append(idx[t + 1])
		dst.append(idx[t + 2])
	var out := []
	for ids in [body, magi]:
		if (ids as PackedInt32Array).is_empty():
			out.append(null)
			continue
		var a2 := arr.duplicate()
		a2[Mesh.ARRAY_INDEX] = ids
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
		out.append(am)
	_split_cache[key] = out
	return out


## Rifle / smg / lmg on an AK-pack model. g = gun root (procedural parts get freed), mag = the
## procedural magazine node (moved to the AK magazine). The charging handle becomes an empty
## node at the AK's handle (the hand reaches there during reloads).
static func _ak_scan(which: String, g: Node3D, mag: Node3D) -> Dictionary:
	var cf: Dictionary = AK_CFG[which]
	_clear_proc(g, [mag])
	mag.position = cf.mag
	mag.rotation = Vector3.ZERO
	var handle := Node3D.new()
	handle.position = cf.handle
	g.add_child(handle)
	var base := Transform3D(Basis(Vector3.UP, PI), cf.t)
	var sc: Node = (load(AK_DIR + cf.file) as PackedScene).instantiate()
	for src in sc.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = (src as MeshInstance3D).transform
		var p: Node = src.get_parent()
		while p != null and p != sc and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var mesh: Mesh = (src as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var sm: Material = mesh.surface_get_material(s)
			var mat := _ak_mat(sm.resource_name if sm else "AK")
			var parts := _split_surface(mesh, s, xf, cf.regions)
			for k in 2:
				if parts[k] == null:
					continue
				var dst: Node3D = g if k == 0 else mag
				var mi := MeshInstance3D.new()
				mi.mesh = parts[k]
				mi.material_override = mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.transform = (base * xf) if k == 0 else dst.transform.affine_inverse() * base * xf
				mi.set_meta("scan", true)
				dst.add_child(mi)
	sc.free()
	var gc: Vector3 = cf.gc
	right_grip(g, gc, Basis(Vector3.RIGHT, -0.3) * Vector3.UP, cf.gr, trig_pts(gc), Vector3(0.18, -0.42, 1.0))
	var left := Node3D.new()
	left.position = cf.left
	g.add_child(left)
	left_guard(left, cf.guard, cf.guard_r, Vector3(-0.32, -0.45, 1.0))
	return {"model": g, "hip": cf.hip, "aim": cf.aim, "flash": flash(g, cf.flash, cf.fs),
		"left": left, "mag": mag, "handle": handle, "kind": "mag"}


## Gun-root children that are procedural geometry (everything except the listed movable nodes).
static func _clear_proc(g: Node3D, keep: Array) -> void:
	for c in g.get_children():
		if not (c in keep):
			c.free()
	for k in keep:
		for c in (k as Node).get_children():
			c.free()


## Trigger-finger points for a grip centred at gc (same finger shape on every gun).
static func trig_pts(gc: Vector3) -> Array:
	return [gc + Vector3(0.017, 0.037, -0.055), gc + Vector3(0.016, 0.033, -0.077), gc + Vector3(0.012, 0.027, -0.089)]


static func smg() -> Dictionary:
	var g := Node3D.new()
	var black := m_black()
	var dark := m_dark()
	var mid := m_mid()
	var steel := m_steel()
	# receiver, top rail, ejection port, side cocking handle
	part(g, Vector3(0.058, 0.07, 0.26), dark, Vector3(0, 0.0, -0.06), Vector3.ZERO, 0.012)
	part(g, Vector3(0.03, 0.012, 0.24), mid, Vector3(0, 0.041, -0.07), Vector3.ZERO, 0.003)
	for i in 14:
		part(g, Vector3(0.032, 0.006, 0.006), black, Vector3(0, 0.049, 0.04 - i * 0.016), Vector3.ZERO, 0.001)
	part(g, Vector3(0.004, 0.022, 0.06), black, Vector3(0.03, 0.012, -0.04), Vector3.ZERO, 0.002)
	var handle := part(g, Vector3(0.022, 0.012, 0.02), mid, Vector3(-0.036, 0.02, -0.14), Vector3.ZERO, 0.004)
	# short ventilated handguard, barrel, compensator
	part(g, Vector3(0.066, 0.062, 0.15), black, Vector3(0, -0.002, -0.255), Vector3.ZERO, 0.018)
	for sx in [-1.0, 1.0]:
		for i in 3:
			part(g, Vector3(0.004, 0.014, 0.03), dark, Vector3(0.034 * sx, 0.004, -0.205 - i * 0.045), Vector3.ZERO, 0.002)
	cyl(g, 0.011, 0.08, steel, Vector3(0, 0.01, -0.36))
	cyl(g, 0.017, 0.06, black, Vector3(0, 0.01, -0.41))
	for k in 3:
		part(g, Vector3(0.024, 0.004, 0.008), wm(Color(0.02, 0.02, 0.02), 0.9), Vector3(0, 0.027, -0.395 - k * 0.014), Vector3.ZERO, 0.001)
	# magwell + straight magazine
	part(g, Vector3(0.042, 0.04, 0.064), dark, Vector3(0, -0.05, -0.1), Vector3.ZERO, 0.008)
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.085, -0.1)
	mag.rotation.x = 0.05
	g.add_child(mag)
	part(mag, Vector3(0.03, 0.17, 0.05), mid, Vector3(0, -0.05, 0), Vector3.ZERO, 0.005)
	part(mag, Vector3(0.032, 0.12, 0.004), dark, Vector3(0, -0.05, -0.026), Vector3.ZERO, 0.001)
	part(mag, Vector3(0.036, 0.014, 0.056), black, Vector3(0, -0.14, 0), Vector3.ZERO, 0.004)
	# trigger guard, trigger, grip
	part(g, Vector3(0.012, 0.006, 0.065), dark, Vector3(0, -0.072, -0.01), Vector3.ZERO, 0.003)
	part(g, Vector3(0.006, 0.028, 0.006), steel, Vector3(0, -0.055, -0.02), Vector3(0.25, 0, 0), 0.002)
	part(g, Vector3(0.04, 0.1, 0.05), black, Vector3(0, -0.085, 0.06), Vector3(-0.3, 0, 0), 0.012)
	for i in 5:
		part(g, Vector3(0.042, 0.004, 0.02), dark, Vector3(0, -0.06 - i * 0.017, 0.045 + i * 0.005), Vector3(-0.3, 0, 0), 0.001)
	# folding wire stock
	part(g, Vector3(0.05, 0.05, 0.05), dark, Vector3(0, -0.002, 0.095), Vector3.ZERO, 0.01)
	for sy in [0.018, -0.026]:
		cyl(g, 0.0065, 0.21, steel, Vector3(0, sy, 0.22))
	part(g, Vector3(0.05, 0.085, 0.016), black, Vector3(0, -0.005, 0.33), Vector3.ZERO, 0.006)
	# holographic sight: base, frame, window, reticle
	part(g, Vector3(0.036, 0.012, 0.07), dark, Vector3(0, 0.055, -0.06), Vector3.ZERO, 0.003)
	for sx in [-1.0, 1.0]:
		part(g, Vector3(0.005, 0.042, 0.055), dark, Vector3(0.019 * sx, 0.08, -0.06), Vector3.ZERO, 0.002)
	part(g, Vector3(0.043, 0.006, 0.055), dark, Vector3(0, 0.103, -0.06), Vector3.ZERO, 0.002)
	part(g, Vector3(0.033, 0.034, 0.002), glass(), Vector3(0, 0.08, -0.085), Vector3.ZERO, 0.0005)
	part(g, Vector3(0.003, 0.003, 0.002), wm(Color(1.0, 0.15, 0.1), 0.5, 0.0, 8.0), Vector3(0, 0.08, -0.06))
	# side rails with covers, ambidextrous selector, pins, sling plate, light under the handguard
	for sx in [-1.0, 1.0]:
		rail(g, Vector3(0.036 * sx, 0.0, -0.26), 0.09, black, dark, true)
		cyl(g, 0.006, 0.004, steel, Vector3(0.031 * sx, -0.022, 0.02)).rotation = Vector3(0, 0, PI / 2)
	pins(g, [Vector3(0.03, -0.02, -0.15), Vector3(-0.03, -0.02, -0.15), Vector3(0.03, -0.02, 0.04), Vector3(-0.03, -0.02, 0.04)], 0.004, steel)
	part(g, Vector3(0.004, 0.022, 0.03), steel, Vector3(-0.031, -0.01, 0.085), Vector3.ZERO, 0.002)
	flashlight(g, Vector3(0, -0.044, -0.27))
	if ak_on("smg"):
		return _ak_scan("smg", g, mag)
	right_grip(g, Vector3(0, -0.085, 0.06), Basis(Vector3.RIGHT, -0.3) * Vector3.UP, 0.024, trig_pts(Vector3(0, -0.085, 0.06)), Vector3(0.18, -0.42, 1.0))
	var left := Node3D.new()
	left.position = Vector3(0, -0.03, -0.255)
	g.add_child(left)
	left_guard(left, Vector3(0, 0.028, 0), 0.034, Vector3(-0.32, -0.45, 1.0))
	sling(g, Vector3(0, -0.03, 0.12), Vector3(0, -0.035, -0.32), 0.1)
	return {"model": g, "hip": Vector3(0.13, -0.165, -0.45), "aim": Vector3(0, -0.08, -0.25), "flash": flash(g, Vector3(0, 0.01, -0.45), 0.28),
		"left": left, "mag": mag, "handle": handle, "kind": "mag"}


static func sniper() -> Dictionary:
	var g := Node3D.new()
	var black := m_black()
	var dark := m_dark()
	var steel := m_steel()
	var olive := wm(Color(0.25, 0.28, 0.2), 0.75)
	# receiver + bolt (the "handle" the reload / bolt cycle pulls back)
	cyl(g, 0.026, 0.26, dark, Vector3(0, 0.015, -0.03))
	var handle := Node3D.new()
	handle.position = Vector3(0.03, 0.02, 0.06)
	g.add_child(handle)
	limb(handle, Vector3.ZERO, Vector3(0.04, -0.025, 0.0), 0.005, steel)
	var knob := SphereMesh.new()
	knob.radius = 0.011
	knob.height = 0.022
	_mi(handle, knob, black, Vector3(0.042, -0.027, 0.0))
	# long barrel + muzzle brake
	cyl(g, 0.014, 0.62, steel, Vector3(0, 0.015, -0.47))
	cyl(g, 0.021, 0.07, black, Vector3(0, 0.015, -0.8))
	for sx in [-1.0, 1.0]:
		part(g, Vector3(0.004, 0.012, 0.03), wm(Color(0.02, 0.02, 0.02), 0.9), Vector3(0.02 * sx, 0.015, -0.8), Vector3.ZERO, 0.001)
	# polymer stock: forend, wrist, butt, cheek rest, recoil pad
	part(g, Vector3(0.062, 0.058, 0.38), olive, Vector3(0, -0.025, -0.3), Vector3.ZERO, 0.02)
	part(g, Vector3(0.066, 0.065, 0.14), olive, Vector3(0, -0.03, -0.04), Vector3.ZERO, 0.02)
	part(g, Vector3(0.048, 0.105, 0.07), olive, Vector3(0, -0.075, 0.085), Vector3(-0.35, 0, 0), 0.016)
	part(g, Vector3(0.056, 0.125, 0.25), olive, Vector3(0, -0.045, 0.27), Vector3(0.06, 0, 0), 0.022)
	part(g, Vector3(0.046, 0.03, 0.15), olive, Vector3(0, 0.03, 0.26), Vector3.ZERO, 0.01)
	part(g, Vector3(0.06, 0.135, 0.022), black, Vector3(0, -0.05, 0.4), Vector3(0.06, 0, 0), 0.01)
	# trigger guard + trigger, detachable box magazine
	part(g, Vector3(0.012, 0.006, 0.06), dark, Vector3(0, -0.065, 0.02), Vector3.ZERO, 0.003)
	part(g, Vector3(0.006, 0.026, 0.006), steel, Vector3(0, -0.05, 0.012), Vector3(0.25, 0, 0), 0.002)
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.07, -0.07)
	g.add_child(mag)
	part(mag, Vector3(0.04, 0.05, 0.085), black, Vector3.ZERO, Vector3.ZERO, 0.006)
	# folded bipod
	for sx in [-1.0, 1.0]:
		cyl(g, 0.0055, 0.2, dark, Vector3(0.016 * sx, -0.062, -0.38))
	part(g, Vector3(0.05, 0.02, 0.03), dark, Vector3(0, -0.055, -0.47), Vector3.ZERO, 0.005)
	# scope: tube, objective bell, eyepiece, turrets, rings, lens
	cyl(g, 0.016, 0.3, black, Vector3(0, 0.078, -0.05))
	cyl(g, 0.027, 0.075, black, Vector3(0, 0.078, -0.225))
	cyl(g, 0.022, 0.065, black, Vector3(0, 0.078, 0.125))
	cyl(g, 0.012, 0.022, dark, Vector3(0, 0.1, -0.05)).rotation = Vector3.ZERO
	cyl(g, 0.011, 0.02, dark, Vector3(0.024, 0.078, -0.05)).rotation = Vector3(0, 0, PI / 2)
	for z in [-0.13, 0.03]:
		part(g, Vector3(0.038, 0.03, 0.018), dark, Vector3(0, 0.058, z), Vector3.ZERO, 0.006)
	cyl(g, 0.024, 0.003, wm(Color(0.15, 0.3, 0.45), 0.03, 0.9, 0.6), Vector3(0, 0.078, -0.264))
	# scope flip caps, knurled turret rings, parallax knob, bolt shroud, muzzle threads, sling swivels
	for z in [-0.264, 0.158]:
		part(g, Vector3(0.05, 0.05, 0.008), black, Vector3(0.03 if z < 0 else -0.03, 0.078, z), Vector3(0, PI / 2 * (1 if z < 0 else -1) * 0.5, 0), 0.003)
	for k in 4:
		ring(g, 0.0125, 0.0012, steel, Vector3(0, 0.104 + k * 0.004, -0.05)).rotation = Vector3.ZERO
		ring(g, 0.0115, 0.0012, steel, Vector3(0.027 + k * 0.004, 0.078, -0.05)).rotation = Vector3(0, 0, PI / 2)
	cyl(g, 0.009, 0.016, dark, Vector3(-0.025, 0.078, -0.05)).rotation = Vector3(0, 0, PI / 2)
	cyl(g, 0.02, 0.05, dark, Vector3(0, 0.015, 0.11))
	for k in 6:
		ring(g, 0.0142, 0.0008, steel, Vector3(0, 0.015, -0.765 + k * 0.004))
	ring(g, 0.009, 0.002, steel, Vector3(0, -0.06, -0.42)).rotation = Vector3(0, PI / 2, 0)
	ring(g, 0.009, 0.002, steel, Vector3(0, -0.11, 0.33)).rotation = Vector3(0, PI / 2, 0)
	rail(g, Vector3(0, 0.044, -0.05), 0.2, dark, black)
	if scan_on(RIFLE_GLTF):
		return _sniper_scan(g, handle, mag)
	var gc := Vector3(0, -0.075, 0.085)
	right_grip(g, gc, Basis(Vector3.RIGHT, -0.35) * Vector3.UP, 0.023, trig_pts(gc), Vector3(0.18, -0.42, 1.0))
	var left := Node3D.new()
	left.position = Vector3(0, -0.04, -0.3)
	g.add_child(left)
	left_guard(left, Vector3(0, 0.015, 0), 0.033, Vector3(-0.32, -0.45, 1.0))
	sling(g, Vector3(0, -0.11, 0.33), Vector3(0, -0.06, -0.42), 0.14)
	return {"model": g, "hip": Vector3(0.14, -0.18, -0.5), "aim": Vector3(0, -0.078, -0.2), "flash": flash(g, Vector3(0, 0.015, -0.86), 0.4),
		"left": left, "mag": mag, "handle": handle, "bolt": true, "kind": "mag"}


static func lmg() -> Dictionary:
	var g := Node3D.new()
	var black := m_black()
	var dark := m_dark()
	var mid := m_mid()
	var steel := m_steel()
	var olive := wm(Color(0.3, 0.32, 0.22), 0.8)
	# receiver + feed cover with rail
	part(g, Vector3(0.076, 0.082, 0.34), dark, Vector3(0, 0.008, -0.04), Vector3.ZERO, 0.014)
	part(g, Vector3(0.07, 0.022, 0.26), mid, Vector3(0, 0.058, -0.04), Vector3.ZERO, 0.006)
	for i in 14:
		part(g, Vector3(0.032, 0.006, 0.006), black, Vector3(0, 0.072, 0.07 - i * 0.016), Vector3.ZERO, 0.001)
	part(g, Vector3(0.004, 0.026, 0.07), black, Vector3(0.039, 0.0, -0.06), Vector3.ZERO, 0.002)
	var handle := part(g, Vector3(0.024, 0.014, 0.024), steel, Vector3(0.045, 0.02, -0.14), Vector3.ZERO, 0.004)
	# vented handguard, heavy barrel, carry handle, flash hider
	part(g, Vector3(0.084, 0.078, 0.27), black, Vector3(0, 0.0, -0.345), Vector3.ZERO, 0.02)
	for sx in [-1.0, 1.0]:
		for i in 5:
			cyl(g, 0.007, 0.006, dark, Vector3(0.042 * sx, 0.01, -0.25 - i * 0.045)).rotation = Vector3(0, 0, PI / 2)
	cyl(g, 0.017, 0.38, steel, Vector3(0, 0.012, -0.66))
	part(g, Vector3(0.018, 0.04, 0.14), dark, Vector3(0, 0.055, -0.55), Vector3.ZERO, 0.006)
	cyl(g, 0.023, 0.075, black, Vector3(0, 0.012, -0.87))
	# iron sights: rear aperture + tall front post
	ring(g, 0.008, 0.0025, black, Vector3(0, 0.082, 0.06))
	part(g, Vector3(0.014, 0.012, 0.01), black, Vector3(0, 0.072, 0.06), Vector3.ZERO, 0.002)
	part(g, Vector3(0.005, 0.055, 0.005), black, Vector3(0, 0.055, -0.8), Vector3.ZERO, 0.0015)
	# ammo box with belt
	var mag := Node3D.new()
	mag.position = Vector3(-0.01, -0.1, -0.12)
	g.add_child(mag)
	part(mag, Vector3(0.1, 0.11, 0.13), olive, Vector3.ZERO, Vector3.ZERO, 0.012)
	part(mag, Vector3(0.104, 0.012, 0.134), dark, Vector3(0, 0.05, 0), Vector3.ZERO, 0.004)
	part(mag, Vector3(0.006, 0.02, 0.05), mid, Vector3(-0.053, 0.0, 0), Vector3.ZERO, 0.002)
	for i in 4:
		cyl(g, 0.006, 0.03, wm(Color(0.8, 0.62, 0.28), 0.35, 1.0), Vector3(0.028, -0.035 + i * 0.012, -0.12 + (i % 2) * 0.004)).rotation = Vector3(0, 0, PI / 2)
	# folded bipod, trigger guard, grip, stock
	for sx in [-1.0, 1.0]:
		cyl(g, 0.006, 0.22, dark, Vector3(0.02 * sx, -0.05, -0.6))
	part(g, Vector3(0.012, 0.006, 0.07), dark, Vector3(0, -0.075, 0.02), Vector3.ZERO, 0.003)
	part(g, Vector3(0.006, 0.03, 0.006), steel, Vector3(0, -0.058, 0.01), Vector3(0.25, 0, 0), 0.002)
	var gc := Vector3(0, -0.1, 0.085)
	part(g, Vector3(0.044, 0.1, 0.052), black, gc, Vector3(-0.3, 0, 0), 0.012)
	part(g, Vector3(0.06, 0.1, 0.24), dark, Vector3(0, -0.015, 0.27), Vector3.ZERO, 0.02)
	part(g, Vector3(0.064, 0.112, 0.022), black, Vector3(0, -0.018, 0.395), Vector3.ZERO, 0.009)
	# belt links into the feed tray, feed cover latch, gas regulator, pins, folding handle hinge
	for i in 5:
		part(g, Vector3(0.012, 0.004, 0.016), steel, Vector3(0.03 - i * 0.004, -0.037 + i * 0.013, -0.12), Vector3(0, 0, 0.6), 0.001)
	part(g, Vector3(0.02, 0.01, 0.02), steel, Vector3(0, 0.07, 0.085), Vector3.ZERO, 0.003)
	cyl(g, 0.016, 0.03, dark, Vector3(0, -0.02, -0.5))
	for k in 6:
		var a := k * TAU / 6.0
		part(g, Vector3(0.005, 0.005, 0.03), black, Vector3(cos(a) * 0.016, -0.02 + sin(a) * 0.016, -0.5), Vector3(0, 0, a), 0.001)
	pins(g, [Vector3(0.039, -0.02, -0.17), Vector3(-0.039, -0.02, -0.17), Vector3(0.039, -0.02, 0.08), Vector3(-0.039, -0.02, 0.08), Vector3(0.042, 0.02, -0.26), Vector3(-0.042, 0.02, -0.26)], 0.0045, steel)
	cyl(g, 0.007, 0.03, steel, Vector3(0, 0.072, -0.53)).rotation = Vector3(0, 0, PI / 2)
	flashlight(g, Vector3(-0.05, -0.005, -0.42))
	if ak_on("lmg"):
		return _ak_scan("lmg", g, mag)
	right_grip(g, gc, Basis(Vector3.RIGHT, -0.3) * Vector3.UP, 0.026, trig_pts(gc), Vector3(0.18, -0.42, 1.0))
	var left := Node3D.new()
	left.position = Vector3(0, -0.035, -0.36)
	g.add_child(left)
	left_guard(left, Vector3(0, 0.035, 0), 0.042, Vector3(-0.32, -0.45, 1.0))
	sling(g, Vector3(0, -0.07, 0.3), Vector3(0, -0.04, -0.6), 0.16)
	return {"model": g, "hip": Vector3(0.14, -0.18, -0.5), "aim": Vector3(0, -0.082, -0.28), "flash": flash(g, Vector3(0, 0.012, -0.93), 0.4),
		"left": left, "mag": mag, "handle": handle, "kind": "mag"}


## Combat knife held in a right fist, blade forward (used by the melee attack).
static func knife() -> Node3D:
	var k := Node3D.new()
	var black := m_black()
	var steel := wm(Color(0.62, 0.63, 0.66), 0.18, 1.0)
	cyl(k, 0.014, 0.11, black, Vector3(0, 0, 0.0))
	for i in 5:
		ring(k, 0.0145, 0.0022, m_dark(), Vector3(0, 0, -0.045 + i * 0.022))
	part(k, Vector3(0.06, 0.016, 0.012), m_dark(), Vector3(0, 0, -0.06), Vector3.ZERO, 0.004)
	part(k, Vector3(0.006, 0.032, 0.15), steel, Vector3(0, -0.002, -0.14), Vector3.ZERO, 0.002)
	part(k, Vector3(0.0062, 0.018, 0.05), steel, Vector3(0, 0.004, -0.225), Vector3(0.55, 0, 0), 0.002)
	part(k, Vector3(0.0065, 0.004, 0.11), wm(Color(0.85, 0.86, 0.9), 0.1, 1.0), Vector3(0, -0.017, -0.14), Vector3.ZERO, 0.001)
	cyl(k, 0.012, 0.012, steel, Vector3(0, 0, 0.06))
	left_guard(k, Vector3.ZERO, 0.014, Vector3(0.25, -0.55, 1.0), Vector3(0, 0, 1))
	return k


## Frag grenade held in a right fist (shown during the throw).
static func grenade_hand() -> Node3D:
	var k := Node3D.new()
	if scan_on(STICK_GLTF):
		if no_hands:
			# held by the operator's own Mixamo arm (fp_arms IK on the `rgrip` meta): the handle
			# stands like a pistol grip, centred on the node, with the head above the fist
			_mount_scan(STICK_GLTF, Transform3D(Basis(), Vector3(0, 0.04, 0)), {"stick_grenade": k})
			right_grip(k, Vector3(0, 0, 0.0), Vector3.UP, 0.017, [], Vector3(0.18, -0.42, 1.0))
			return k
		# scanned stick grenade (Poly Haven "stick_grenade", CC0): fist around the wooden handle,
		# head pointing forward (model +Y → -Z)
		_mount_scan(STICK_GLTF, Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 0, -0.07)), {"stick_grenade": k})
		left_guard(k, Vector3(0, 0, -0.03), 0.02, Vector3(0.25, -0.55, 1.0), Vector3(0, 0, 1))
		return k
	var body := SphereMesh.new()
	body.radius = 0.032
	body.height = 0.07
	_mi(k, body, wm(Color(0.22, 0.27, 0.17), 0.7), Vector3(0, 0.0, -0.03)).set_meta("nade", true)
	cyl(k, 0.012, 0.02, m_dark(), Vector3(0, 0.03, -0.03)).set_meta("nade", true)
	k.get_child(1).rotation = Vector3.ZERO
	part(k, Vector3(0.012, 0.05, 0.006), m_steel(), Vector3(0.016, 0.01, -0.05), Vector3(0, 0, -0.2), 0.002)
	ring(k, 0.009, 0.0015, m_steel(), Vector3(-0.014, 0.045, -0.03))
	left_guard(k, Vector3(0, 0, -0.03), 0.026, Vector3(0.25, -0.55, 1.0), Vector3(0, 0, 1))
	return k



# ---------------------------------------------------------------- copies of the guns for the world
static func build_bare(i: int) -> Node3D:
	no_hands = true
	var d: Dictionary
	match i:
		0:
			d = rifle()
		1:
			d = shotgun()
		2:
			d = pistol()
		3:
			d = smg()
		4:
			d = sniper()
		_:
			d = lmg()
	no_hands = false
	(d.flash as Node3D).free()
	return d.model


static var _world_mats := {}


## Gun with ordinary world materials (the viewmodel shader pulls depth to the camera, unusable in the world).
static func world_copy(i: int) -> Node3D:
	var g := build_bare(i)
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var src = mi.material_override
		if src is ShaderMaterial and (src as ShaderMaterial).shader == SHT:
			if not _world_mats.has(src):
				var ms := StandardMaterial3D.new()
				ms.albedo_texture = src.get_shader_parameter("tex_alb")
				ms.normal_enabled = true
				ms.normal_texture = src.get_shader_parameter("tex_nor")
				var arm: Texture2D = src.get_shader_parameter("tex_arm")
				if arm != null:
					ms.roughness_texture = arm
					ms.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
					ms.metallic = 1.0
					ms.metallic_texture = arm
					ms.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
				else:
					# AK-pack layout: separate roughness map, moderate metal
					ms.roughness_texture = src.get_shader_parameter("tex_rough")
					ms.metallic = 0.35
				_world_mats[src] = ms
			mi.material_override = _world_mats[src]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		if src is ShaderMaterial and src.get_shader_parameter("albedo") != null:
			if not _world_mats.has(src):
				var m := StandardMaterial3D.new()
				m.albedo_color = src.get_shader_parameter("albedo")
				m.roughness = src.get_shader_parameter("roughness")
				m.metallic = src.get_shader_parameter("metallic")
				var ee = src.get_shader_parameter("emission_energy")
				if ee != null and ee > 0.0:
					m.emission_enabled = true
					m.emission = src.get_shader_parameter("emission")
					m.emission_energy_multiplier = ee
				var dn = src.get_shader_parameter("detail_nor")
				if dn != null:
					m.normal_enabled = true
					m.normal_texture = dn
					m.uv1_triplanar = true
					m.uv1_scale = Vector3.ONE * float(src.get_shader_parameter("detail_scale"))
				_world_mats[src] = m
			mi.material_override = _world_mats[src]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g


static var _chalk: StandardMaterial3D


## Flat chalk drawing of a gun for the wall-buys.
static func chalk_copy(i: int) -> Node3D:
	if _chalk == null:
		_chalk = StandardMaterial3D.new()
		_chalk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_chalk.albedo_color = Color(0.9, 0.9, 0.84)
	var g := build_bare(i)
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _chalk
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g


## Upgraded weapons get a gold/violet finish (per-gun material copies, the cached ones stay intact).
static func apply_camo(model: Node3D) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var src = mi.material_override
		if src is ShaderMaterial and (src as ShaderMaterial).shader == SHT:
			var mt: ShaderMaterial = src.duplicate()
			mt.set_shader_parameter("tint", Color(0.78, 0.58, 0.22))
			mt.set_shader_parameter("camo", 0.85)
			mt.set_shader_parameter("emission", Color(0.78, 0.58, 0.22))
			mt.set_shader_parameter("emission_energy", 0.1)
			mi.material_override = mt
			continue
		if not (src is ShaderMaterial) or src.get_shader_parameter("detail_alb_mode") == null:
			continue
		var dn = src.get_shader_parameter("detail_nor")
		if dn == null:
			continue
		var path: String = (dn as Texture2D).resource_path
		if path.contains("leather") or path.contains("denim") or path.contains("gravel"):
			continue
		var m: ShaderMaterial = src.duplicate()
		var c: Color = src.get_shader_parameter("albedo")
		var gold := Color(0.78, 0.58, 0.22) if c.get_luminance() < 0.2 else Color(0.45, 0.2, 0.6)
		m.set_shader_parameter("albedo", gold)
		m.set_shader_parameter("metallic", 0.9)
		m.set_shader_parameter("roughness", 0.3)
		m.set_shader_parameter("emission", gold)
		m.set_shader_parameter("emission_energy", 0.12)
		mi.material_override = m
