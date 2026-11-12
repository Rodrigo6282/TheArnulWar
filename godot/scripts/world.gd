extends RefCounted
## Map builder: primitive meshes + photoscanned PBR materials (world-space triplanar, so no UV work),
## static colliders that the engine also uses to bake the navigation mesh.

static var H := 60.0
const SHP := preload("res://scripts/shapes.gd")
static var rects: Array = []      # [minx, minz, maxx, maxz, top] of every solid, for placement checks
static var _mats := {}
static var rng := RandomNumberGenerator.new()


static func tex(id: String, kind: String) -> Texture2D:
	return load("res://assets/tex/%s_%s.jpg" % [id, kind])


const WORLD_SHADER := preload("res://shaders/world_pbr.gdshader")


## World surface: photoscanned triplanar PBR with weather (wet / puddles / snow, shaders/world_pbr).
static func pbr(id: String, tint := Color.WHITE, scale := 0.5, metal := 0.0, world_tri := true) -> Material:
	if "--oldmat" in OS.get_cmdline_user_args():
		return pbr_std(id, tint, scale, metal, world_tri)
	var key := "w|%s|%s|%s|%s|%s" % [id, tint.to_html(), scale, metal, world_tri]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = WORLD_SHADER
	m.set_shader_parameter("tex_albedo", tex(id, "diff"))
	m.set_shader_parameter("tex_normal", tex(id, "nor"))
	m.set_shader_parameter("tex_rough", tex(id, "rough"))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("uv_scale", scale)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("world_tri", world_tri)
	m.set_shader_parameter("porosity", 0.15 if id.begins_with("snow") else (1.0 - metal * 0.9))
	_mats[key] = m
	return m


## Same look as pbr() but as a StandardMaterial3D (for code that tweaks its properties, e.g. leaves).
static func pbr_std(id: String, tint := Color.WHITE, scale := 0.5, metal := 0.0, world_tri := true) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [id, tint.to_html(), scale, metal, world_tri]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(id, "diff")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = tex(id, "nor")
	m.roughness_texture = tex(id, "rough")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = 1.0
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world_tri
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


## Foliage: the scanned leaf normal/roughness give the bumpy leafy surface, the colour stays green.
static func leaves(c: Color, scale := 1.4) -> StandardMaterial3D:
	var key := "leaf|%s|%s" % [c.to_html(), scale]
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D = pbr_std("forest_leaves_02", Color.WHITE, scale, 0.0, false).duplicate()
	m.albedo_texture = null
	m.albedo_color = c
	m.normal_scale = 1.6
	_mats[key] = m
	return m


static func colm(c: Color, rough := 0.85, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var key := "c|%s|%s|%s|%s" % [c.to_html(), rough, metal, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	_mats[key] = m
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


static func mesh_node(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Solid box given its base height y0 (adds collider + placement rect).
static func blk(parent: Node3D, x: float, y0: float, z: float, w: float, h: float, d: float, mat: Material, collide := true, rnd := 0.0) -> MeshInstance3D:
	var bm: Mesh
	if rnd > 0.0:
		bm = SHP.rbox(Vector3(w, h, d), rnd, 3)
	else:
		var bx := BoxMesh.new()
		bx.size = Vector3(w, h, d)
		bm = bx
	var c := Vector3(x, y0 + h * 0.5, z)
	if not collide:
		return mesh_node(parent, bm, mat, c)
	var sb := StaticBody3D.new()
	sb.position = c
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(w, h, d)
	cs.shape = sh
	sb.add_child(cs)
	parent.add_child(sb)
	var mi := mesh_node(sb, bm, mat, Vector3.ZERO)
	rects.append([x - w * 0.5, z - d * 0.5, x + w * 0.5, z + d * 0.5, y0 + h])
	return mi


static func collider_only(parent: Node3D, c: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = c
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	parent.add_child(sb)
	rects.append([c.x - size.x * 0.5, c.z - size.z * 0.5, c.x + size.x * 0.5, c.z + size.z * 0.5, c.y + size.y * 0.5])


static func flat(parent: Node3D, c: Vector3, size: Vector2, mat: Material) -> void:
	var pm := PlaneMesh.new()
	pm.size = size
	# flat planes don't need triplanar mapping: same texel density with plain UVs = 1/3 of the samples
	if mat is StandardMaterial3D and mat.uv1_triplanar and mat.uv1_world_triplanar:
		var key := "planar|%d|%s" % [mat.get_instance_id(), size]
		if not _mats.has(key):
			var m2: StandardMaterial3D = mat.duplicate()
			m2.uv1_triplanar = false
			m2.uv1_world_triplanar = false
			m2.uv1_scale = Vector3(size.x * mat.uv1_scale.x, size.y * mat.uv1_scale.z, 1.0)
			m2.uv1_offset = Vector3(c.x * mat.uv1_scale.x, c.z * mat.uv1_scale.z, 0.0)
			_mats[key] = m2
		mat = _mats[key]
	var mi := mesh_node(parent, pm, mat, c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func disc(parent: Node3D, c: Vector3, r: float, h: float, mat: Material) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 48
	var mi := mesh_node(parent, cm, mat, c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func is_free(x: float, z: float, r: float) -> bool:
	if absf(x) > H - 2 or absf(z) > H - 2:
		return false
	for q in rects:
		if x + r > q[0] and x - r < q[2] and z + r > q[1] and z - r < q[3]:
			return false
	return true


## Wall along an axis with door ('d') and window ('w') openings: gaps = [[center, type], ...]
static func wall_gaps(p: Node3D, a0: float, a1: float, fixed: float, axis: String, h: float, t: float, gaps: Array, mat: Material) -> void:
	gaps.sort_custom(func(a, b): return a[0] < b[0])
	var cur := a0
	var seg := func(s: float, e: float, y: float, hh: float) -> void:
		if e - s < 0.05 or hh <= 0.01:
			return
		if axis == "x":
			blk(p, (s + e) * 0.5, y, fixed, e - s, hh, t, mat)
		else:
			blk(p, fixed, y, (s + e) * 0.5, t, hh, e - s, mat)
	for g in gaps:
		var gw: float = 2.4 if g[1] == "d" else 1.6
		seg.call(cur, g[0] - gw * 0.5, 0.0, h)
		if g[1] == "w":
			seg.call(g[0] - gw * 0.5, g[0] + gw * 0.5, 0.0, 1.1)
			seg.call(g[0] - gw * 0.5, g[0] + gw * 0.5, 2.2, h - 2.2)
		else:
			seg.call(g[0] - gw * 0.5, g[0] + gw * 0.5, 2.7, h - 2.7)
		cur = g[0] + gw * 0.5
	seg.call(cur, a1, 0.0, h)


static func building(p: Node3D, cx: float, cz: float, w: float, d: float, h: float, doors: Dictionary, mat: Material, trim: Material) -> void:
	var t := 0.4
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	var z0 := cz - d * 0.5
	var z1 := cz + d * 0.5
	var conv := func(arr, c):
		var out := []
		for o in arr:
			out.append([c + o[0], o[1]])
		return out
	wall_gaps(p, x0, x1, z0, "x", h, t, conv.call(doors.get("n", []), cx), mat)
	wall_gaps(p, x0, x1, z1, "x", h, t, conv.call(doors.get("s", []), cx), mat)
	wall_gaps(p, z0 + t * 0.5, z1 - t * 0.5, x0, "z", h, t, conv.call(doors.get("w", []), cz), mat)
	wall_gaps(p, z0 + t * 0.5, z1 - t * 0.5, x1, "z", h, t, conv.call(doors.get("e", []), cz), mat)
	for side in [[cx, z0, w + 0.16, t + 0.16], [cx, z1, w + 0.16, t + 0.16], [x0, cz, t + 0.16, d], [x1, cz, t + 0.16, d]]:
		blk(p, side[0], h, side[1], side[2], 0.16, side[3], trim, false)
	if night and rng.randf() < 0.6:
		lamp_light(p, Vector3(cx, h * 0.7, cz), Color(1.0, 0.68, 0.38), 1.8, maxf(w, d) * 0.9)


static func car(p: Node3D, x: float, z: float, rot: float, paint: Color, burning: bool, fx_list: Array) -> void:
	var hx := 0.95 if rot != 0.0 else 2.1
	var hz := 2.1 if rot != 0.0 else 0.95
	if not is_free(x, z, 0.0):
		return
	var root := StaticBody3D.new()
	root.position = Vector3(x, 0, z)
	root.rotation.y = rot
	p.add_child(root)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(4.2, 1.6, 1.9)
	cs.shape = sh
	cs.position.y = 0.8
	root.add_child(cs)
	# burnt wrecks get scanned rusty paint; intact cars a glossy clear-coated paint
	var pm: Material
	if burning:
		pm = pbr("rusty_painted_metal", paint.lightened(0.5), 0.9, 0.5, false)
	else:
		var paint_m := colm(paint, 0.35, 0.45)
		paint_m.clearcoat_enabled = true
		paint_m.clearcoat = 0.8
		paint_m.clearcoat_roughness = 0.15
		pm = paint_m
	var glass := colm(Color(0.04, 0.05, 0.06), 0.05, 0.9)
	var tire := colm(Color(0.07, 0.07, 0.07), 0.9)
	mesh_node(root, SHP.rbox(Vector3(4.2, 0.7, 1.85), 0.22, 4), pm, Vector3(0, 0.66, 0))
	mesh_node(root, SHP.rbox(Vector3(2.3, 0.62, 1.66), 0.26, 4), pm, Vector3(-0.25, 1.28, 0))
	mesh_node(root, SHP.rbox(Vector3(2.36, 0.38, 1.7), 0.16, 4), glass, Vector3(-0.25, 1.32, 0))
	var hub := CylinderMesh.new()
	hub.top_radius = 0.2
	hub.bottom_radius = 0.2
	hub.height = 0.27
	var rim := colm(Color(0.35, 0.35, 0.36), 0.4, 0.8)
	var wm := CylinderMesh.new()
	wm.top_radius = 0.36
	wm.bottom_radius = 0.36
	wm.height = 0.26
	for wp in [Vector3(1.3, 0.36, 0.86), Vector3(-1.3, 0.36, 0.86), Vector3(1.3, 0.36, -0.86), Vector3(-1.3, 0.36, -0.86)]:
		mesh_node(root, wm, tire, wp, Vector3(PI / 2, 0, 0))
		mesh_node(root, hub, rim, wp, Vector3(PI / 2, 0, 0), false)
	rects.append([x - hx, z - hz, x + hx, z + hz, 1.6])
	if burning:
		fx_list.append(Vector3(x, 1.5, z))


static func tree(p: Node3D, x: float, z: float, s: float) -> void:
	if not is_free(x, z, 1.1):
		return
	var trunk := pbr("bark_brown_02", Color(0.8, 0.72, 0.66), 1.2, 0.0, false)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16 * s
	cm.bottom_radius = 0.24 * s
	cm.height = 2.6 * s
	var sb := StaticBody3D.new()
	sb.position = Vector3(x, 1.3 * s, z)
	p.add_child(sb)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.24 * s
	cy.height = 2.6 * s
	cs.shape = cy
	sb.add_child(cs)
	mesh_node(sb, cm, trunk, Vector3.ZERO)
	var leaf_cols := [Color(0.3, 0.42, 0.18), Color(0.37, 0.48, 0.2), Color(0.24, 0.35, 0.16)]
	for i in 3:
		var sm := SphereMesh.new()
		sm.radius = (1.5 - i * 0.3) * s
		sm.height = sm.radius * 1.7
		sm.radial_segments = 14
		sm.rings = 8
		var lm := leaves(leaf_cols[i])
		mesh_node(p, sm, lm, Vector3(x + rng.randf_range(-0.5, 0.5) * s, (2.6 + i * 0.75) * s, z + rng.randf_range(-0.5, 0.5) * s), Vector3(rng.randf() * 3, rng.randf() * 3, 0))
	rects.append([x - 0.25 * s, z - 0.25 * s, x + 0.25 * s, z + 0.25 * s, 2.6 * s])


static func lamp(p: Node3D, x: float, z: float, ax: float, az: float) -> void:
	if not is_free(x, z, 0.4):
		return
	var pole := colm(Color(0.22, 0.23, 0.25), 0.5, 0.7)
	var bulb := colm(Color(1.0, 0.86, 0.6), 0.5, 0.0, 6.0)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.1
	cm.height = 5.2
	blk(p, x, 0, z, 0.24, 5.2, 0.24, pole, true).visible = false
	mesh_node(p, cm, pole, Vector3(x, 2.6, z))
	var arm := BoxMesh.new()
	arm.size = Vector3(1.3, 0.09, 0.09)
	var ry := atan2(-az, ax)
	mesh_node(p, arm, pole, Vector3(x + ax * 0.6, 5.15, z + az * 0.6), Vector3(0, ry, 0))
	var hd := BoxMesh.new()
	hd.size = Vector3(0.55, 0.14, 0.3)
	mesh_node(p, hd, pole, Vector3(x + ax * 1.25, 5.08, z + az * 1.25), Vector3(0, ry, 0))
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.03, 0.18)
	mesh_node(p, bm, bulb, Vector3(x + ax * 1.25, 4.995, z + az * 1.25), Vector3(0, ry, 0), false)
	if night:
		street_light(p, Vector3(x + ax * 1.25, 4.95, z + az * 1.25))


static var _halo_mat: StandardMaterial3D


static func street_light(p: Node3D, pos: Vector3, col := Color(1.0, 0.78, 0.5)) -> void:
	var sl := SpotLight3D.new()
	sl.light_color = col
	sl.light_energy = 5.0
	sl.spot_range = 15.0
	sl.spot_angle = 58.0
	sl.spot_angle_attenuation = 0.7
	sl.spot_attenuation = 1.1
	sl.shadow_enabled = false
	sl.distance_fade_enabled = true
	sl.distance_fade_begin = 45.0
	sl.distance_fade_length = 10.0
	sl.position = pos
	sl.rotation = Vector3(-PI / 2, 0, 0)
	p.add_child(sl)
	# faint omni so walls and faces right next to the lamp also catch some light
	lamp_light(p, pos - Vector3(0, 0.4, 0), col, 0.6, 7.0)
	if _halo_mat == null:
		_halo_mat = StandardMaterial3D.new()
		_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_halo_mat.disable_receive_shadows = true
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_halo_mat.albedo_texture = t
		_halo_mat.albedo_color = Color(1.0, 0.8, 0.55)
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	var hm := MeshInstance3D.new()
	hm.mesh = q
	hm.material_override = _halo_mat
	hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hm.position = pos - Vector3(0, 0.1, 0)
	hm.set_meta("nomerge", true)
	p.add_child(hm)


## Burning oil drum: rusty barrel with a fire on top (fire + flickering light come from fx).
static func fire_barrel(root: Node3D, x: float, z: float, fires: Array) -> void:
	if not is_free(x, z, 0.6):
		return
	barrel(root, x, z, Color(0.35, 0.22, 0.15))
	fires.append(Vector3(x, 0.95, z))


static func sandbags(p: Node3D, walls: Array) -> void:
	var transforms := []
	for q in walls:
		var x: float = q[0]
		var z: float = q[1]
		var w: float = q[2]
		var d: float = q[3]
		collider_only(p, Vector3(x, 0.5, z), Vector3(w, 1.0, d))
		var along_x := w >= d
		var length := w if along_x else d
		var thick := d if along_x else w
		var n := maxi(1, int(round(length / 0.6)))
		var step := length / n
		var sides := [-thick / 4.0, thick / 4.0] if thick > 0.6 else [0.0]
		var half := thick / 4.0 if thick > 0.6 else thick / 2.0
		for row in 4:
			var off := step * 0.5 if row % 2 == 1 else 0.0
			var cnt := n - 1 if row % 2 == 1 else n
			for i in cnt:
				var t := -length * 0.5 + step * 0.5 + off + i * step
				for sd in sides:
					var pos := Vector3(x + t if along_x else x + sd, 0.13 + row * 0.245, z + sd if along_x else z + t)
					var b := Basis.from_euler(Vector3(rng.randf_range(-0.05, 0.05), (0.0 if along_x else PI / 2) + rng.randf_range(-0.08, 0.08), rng.randf_range(-0.05, 0.05)))
					b = b.scaled(Vector3(step * 0.56, 0.14, half * 1.05))
					transforms.append(Transform3D(b, pos))
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sm
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, Color.from_hsv(0.11, rng.randf_range(0.25, 0.35), rng.randf_range(0.5, 0.62)))
	var mat := pbr("clay_plaster", Color.WHITE, 2.0, 0.0, false)
	mat = mat.duplicate()
	mat.set_shader_parameter("vcol", true)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	p.add_child(mmi)


## ---------------------------------------------------------------- Ciudad Rota
static func build_city(root: Node3D) -> Array:
	rects.clear()
	rng.seed = 1337
	var wall := pbr("concrete_block_wall", Color(0.92, 0.9, 0.86))
	var dark := pbr("chipped_concrete", Color(0.68, 0.7, 0.72), 0.33)
	var brick := pbr("brick_wall_001")
	var c_red := pbr("corrugated_iron_02", Color(0.75, 0.3, 0.24), 0.38, 0.45)
	var c_blue := pbr("corrugated_iron_02", Color(0.3, 0.45, 0.62), 0.38, 0.45)
	var c_green := pbr("corrugated_iron_02", Color(0.38, 0.5, 0.32), 0.38, 0.45)
	var crate := pbr("brown_planks_04", Color(0.95, 0.85, 0.7), 0.8, 0.0, false)
	var ground := pbr("gravel_ground_01", Color(0.86, 0.8, 0.72), 0.25)
	var asphalt := pbr("asphalt_02", Color(0.85, 0.85, 0.88), 0.22)
	var walk := pbr("concrete_floor_01", Color(0.6, 0.58, 0.55), 0.35)
	var grass := pbr("sparse_grass", Color(0.9, 0.95, 0.85), 0.35)
	var paint_y := colm(Color(0.92, 0.82, 0.4), 0.7)
	var paint_w := colm(Color(0.9, 0.9, 0.88), 0.7)
	# ground
	var g := StaticBody3D.new()
	root.add_child(g)
	var gcs := CollisionShape3D.new()
	var gsh := BoxShape3D.new()
	gsh.size = Vector3(400, 1, 400)
	gcs.shape = gsh
	gcs.position.y = -0.5
	g.add_child(gcs)
	flat(g, Vector3.ZERO, Vector2(400, 400), ground)
	# roads, roundabout, sidewalks (raised curbs), markings
	flat(root, Vector3(0, 0.01, 1.5), Vector2(7.2, 85), asphalt)
	flat(root, Vector3(0, 0.012, -17), Vector2(120, 7.2), asphalt)
	disc(root, Vector3(0, 0.0, 0), 9.6, 0.03, asphalt)
	disc(root, Vector3(0, 0.0, 0), 4.4, 0.08, grass)
	for sx in [-1.0, 1.0]:
		blk(root, sx * 4.55, 0, -30.5, 1.9, 0.12, 21.0, walk, false)
		blk(root, sx * 4.55, 0, 27.3, 1.9, 0.12, 33.4, walk, false)
	for sz in [-21.55, -12.45]:
		blk(root, -32.0, 0, sz, 56.0, 0.12, 1.9, walk, false)
		blk(root, 32.0, 0, sz, 56.0, 0.12, 1.9, walk, false)
	var dash := Vector2(0.18, 2.5)
	for z in range(-40, 44, 5):
		if absf(z) < 11:
			continue
		flat(root, Vector3(0, 0.02, z), dash, paint_y)
	for x in range(-58, 60, 5):
		if absf(x) < 5:
			continue
		flat(root, Vector3(x, 0.02, -17), Vector2(2.5, 0.18), paint_y)
	for i in 7:
		flat(root, Vector3(-3.2 + i * 0.95 + 0.25, 0.02, -22.9), Vector2(0.5, 2.2), paint_w)
		flat(root, Vector3(-3.2 + i * 0.95 + 0.25, 0.02, 12.6), Vector2(0.5, 2.2), paint_w)
	# perimeter
	H = 60.0
	blk(root, 0, 0, -H - 1, 2 * H + 4, 6, 2, wall)
	blk(root, 0, 0, H + 1, 2 * H + 4, 6, 2, wall)
	blk(root, -H - 1, 0, 0, 2, 6, 2 * H + 4, wall)
	blk(root, H + 1, 0, 0, 2, 6, 2 * H + 4, wall)
	# skyline outside the walls
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(80, 150)
		var w := rng.randf_range(10, 25)
		var h := rng.randf_range(12, 45)
		var d := rng.randf_range(10, 25)
		blk(root, cos(a) * r, 0, sin(a) * r, w, h, d, dark, false)
	# buildings
	building(root, -30, -30, 16, 12, 4, {"n": [[0, "d"]], "e": [[0, "d"]], "s": [[-4, "w"], [4, "w"]], "w": [[0, "w"]]}, brick, dark)
	building(root, 30, -28, 14, 14, 4.5, {"w": [[2, "d"]], "s": [[-3, "d"]], "n": [[-3, "w"], [3, "w"]], "e": [[0, "w"]]}, wall, dark)
	wall_gaps(root, -34.6, -21.4, 30, "z", 4.5, 0.3, [[-28, "d"]], wall)
	building(root, -28, 30, 18, 10, 4, {"e": [[0, "d"]], "n": [[-5, "d"]], "s": [[5, "d"]], "w": [[0, "w"]]}, wall, dark)
	building(root, 32, 32, 12, 16, 4, {"w": [[-3, "d"]], "n": [[0, "d"]], "s": [[0, "w"]], "e": [[2, "w"]]}, brick, dark)
	blk(root, 0, 0, -45, 20, 10, 8, dark, true, 0.3)
	blk(root, -50, 0, 0, 8, 8, 20, dark, true, 0.3)
	blk(root, 50, 0, 0, 8, 9, 18, dark, true, 0.3)
	blk(root, 0, 0, 47, 14, 7, 6, dark, true, 0.3)
	blk(root, 0, 0, 0, 4, 1, 4, wall, true, 0.12)
	blk(root, 0, 1, 0, 1.4, 3.5, 1.4, wall, true, 0.15)
	# containers
	blk(root, 14, 0, 10, 12, 2.6, 2.6, c_red, true, 0.1)
	blk(root, 14, 2.6, 10, 12, 2.6, 2.6, c_blue, true, 0.1)
	blk(root, -15, 0, -8, 2.6, 2.6, 12, c_blue, true, 0.1)
	blk(root, 16, 0, -14, 2.6, 2.6, 12, c_green, true, 0.1)
	blk(root, -12, 0, 14, 12, 2.6, 2.6, c_green, true, 0.1)
	blk(root, -40, 0, -12, 12, 2.6, 2.6, c_red, true, 0.1)
	blk(root, 42, 0, 16, 2.6, 2.6, 10, c_blue, true, 0.1)
	sandbags(root, [[0, -7, 6, 0.8], [0, 7, 6, 0.8], [-7, 0, 0.8, 6], [7, 0, 0.8, 6], [-30, -18, 6, 0.8], [30, -14, 0.8, 6], [-28, 20, 8, 0.8], [32, 20, 6, 0.8],
		[-45, 25, 0.8, 6], [45, -25, 0.8, 6], [20, 45, 6, 0.8], [-20, -40, 6, 0.8]])
	blk(root, -45, 0, 40, 6, 2.2, 0.5, wall)
	blk(root, 45, 0, -42, 0.5, 2.5, 7, wall)
	blk(root, -20, 0, -50, 0.5, 3, 6, wall)
	blk(root, 22, 0, 50, 7, 2, 0.5, wall)
	var fires := []
	car(root, -8, -17, 0.0, Color(0.36, 0.18, 0.13), true, fires)
	car(root, 27, -16.2, 0.0, Color(0.18, 0.23, 0.27), false, fires)
	car(root, -1.9, 31, PI / 2, Color(0.23, 0.22, 0.2), false, fires)
	car(root, 1.9, -30, PI / 2, Color(0.16, 0.15, 0.14), true, fires)
	car(root, 46, -18, 0.0, Color(0.42, 0.38, 0.31), false, fires)
	car(root, -40, 36, PI / 2, Color(0.16, 0.15, 0.14), true, fires)
	for l in [[4.6, -36, -1, 0], [-4.6, -26, 1, 0], [4.6, 14, -1, 0], [-4.6, 26, 1, 0], [4.6, 36, -1, 0], [-50, -21.6, 0, 1], [-30, -12.4, 0, -1],
			[-10, -21.6, 0, 1], [10, -12.4, 0, -1], [34, -12.4, 0, -1], [50, -21.6, 0, 1], [22, -21.6, 0, 1]]:
		lamp(root, l[0], l[1], l[2], l[3])
	for t in [[6.5, -38], [-6.5, -33], [6.5, 12], [-6.5, 18], [6.5, 40], [-6.5, 36], [-12, -23.5], [12, -23.5], [-44, -23.5], [52, -11], [-52, -11], [24, -10.5],
			[-50, 50], [50, 52], [52, -52], [-52, -50], [-38, 8], [38, -6], [20, 30], [-20, 44], [44, 10], [-30, 8], [30, 10], [8, -52]]:
		tree(root, t[0], t[1], rng.randf_range(0.85, 1.25))
	# crates
	var placed := 0
	for i in 400:
		if placed >= 34:
			break
		var x := rng.randf_range(-H + 4, H - 4)
		var z := rng.randf_range(-H + 4, H - 4)
		var s := 1.6 if rng.randf() < 0.3 else 1.2
		if Vector2(x - 0, z - 22).length() < 5 or not is_free(x, z, s / 2 + 1.4):
			continue
		blk(root, x, 0, z, s, s, s, crate, true, 0.06)
		placed += 1
		if rng.randf() < 0.3:
			blk(root, x + rng.randf_range(-0.15, 0.15), s, z + rng.randf_range(-0.15, 0.15), 1.0, 1.0, 1.0, crate, true, 0.06)
	# rubble near walls (decorative multimesh)
	var rub := []
	for i in 2500:
		if rub.size() >= 300:
			break
		var x := rng.randf_range(-H + 1, H - 1)
		var z := rng.randf_range(-H + 1, H - 1)
		if not is_free(x, z, 0.25):
			continue
		var sc := rng.randf_range(0.06, 0.28)
		var b := Basis.from_euler(Vector3(rng.randf() * 6, rng.randf() * 6, rng.randf() * 6)).scaled(Vector3(sc * rng.randf_range(0.8, 1.4), sc * rng.randf_range(0.5, 1), sc * rng.randf_range(0.8, 1.4)))
		rub.append(Transform3D(b, Vector3(x, sc * 0.35, z)))
	var rm := SphereMesh.new()
	rm.radial_segments = 6
	rm.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rm
	mm.instance_count = rub.size()
	for i in rub.size():
		mm.set_instance_transform(i, rub[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = pbr("concrete_debris", Color(0.85, 0.83, 0.8), 1.5, 0.0, false)
	root.add_child(mmi)
	root.set_meta("fires", fires)
	# spawn points around the edge
	var sp := []
	for a in range(-52, 53, 8):
		for q in [[a, -55], [a, 55], [-55, a], [55, a]]:
			if is_free(q[0], q[1], 1.0):
				sp.append(Vector3(q[0], 0, q[1]))
	return sp


## ================================================================ map registry
## env keys: sun (rotation deg), sun_col, sun_e, zen, hor, gnd (sky), clouds, cloud_light, fog_col, fog_d, amb, exp,
## sat, con, glow, stars, sun_sharp, weather ("" | dust | snow | ash), night (lamps get real lights)
const ENVS := {
	"day": {"sun": Vector3(-48, -32, 0), "sun_col": Color(1.0, 0.95, 0.86), "sun_e": 1.35, "zen": Color(0.2, 0.38, 0.66), "hor": Color(0.68, 0.75, 0.82),
		"gnd": Color(0.36, 0.34, 0.31), "clouds": 0.5, "cloud_light": 1.0, "fog_col": Color(0.66, 0.72, 0.79), "fog_d": 0.0045, "amb": 1.1, "exp": 1.15,
		"sat": 1.1, "con": 1.06, "glow": 0.55, "stars": 0.0, "sun_sharp": 1400.0, "weather": "", "night": false},
	"desert": {"sun": Vector3(-17, -62, 0), "sun_col": Color(1.0, 0.74, 0.48), "sun_e": 1.6, "zen": Color(0.22, 0.36, 0.62), "hor": Color(0.98, 0.72, 0.5),
		"gnd": Color(0.55, 0.42, 0.3), "clouds": 0.22, "cloud_light": 1.0, "fog_col": Color(0.92, 0.72, 0.52), "fog_d": 0.0065, "amb": 1.0, "exp": 1.08,
		"sat": 1.12, "con": 1.1, "glow": 0.75, "stars": 0.0, "sun_sharp": 900.0, "weather": "dust", "night": false},
	"snow": {"sun": Vector3(-26, 38, 0), "sun_col": Color(0.86, 0.91, 1.0), "sun_e": 0.95, "zen": Color(0.42, 0.5, 0.62), "hor": Color(0.8, 0.84, 0.9),
		"gnd": Color(0.7, 0.72, 0.76), "clouds": 0.85, "cloud_light": 0.85, "fog_col": Color(0.8, 0.84, 0.9), "fog_d": 0.011, "amb": 1.1, "exp": 1.08,
		"sat": 0.85, "con": 1.05, "glow": 0.5, "stars": 0.0, "sun_sharp": 600.0, "weather": "snow", "night": false},
	"dusk": {"amb_col": Color(0.34, 0.25, 0.22), "sun": Vector3(-7, 125, 0), "sun_col": Color(1.0, 0.45, 0.27), "sun_e": 1.0, "zen": Color(0.07, 0.07, 0.16), "hor": Color(0.62, 0.3, 0.22),
		"gnd": Color(0.12, 0.09, 0.08), "clouds": 0.65, "cloud_light": 0.45, "fog_col": Color(0.36, 0.22, 0.2), "fog_d": 0.018, "amb": 0.9, "exp": 1.5,
		"sat": 0.95, "con": 1.12, "glow": 0.9, "stars": 0.4, "sun_sharp": 700.0, "weather": "ash", "night": true},
	"arctic": {"amb_col": Color(0.28, 0.32, 0.4), "sun": Vector3(-40, -50, 0), "sun_col": Color(0.65, 0.75, 1.0), "sun_e": 0.95, "zen": Color(0.02, 0.04, 0.09), "hor": Color(0.2, 0.26, 0.35),
		"gnd": Color(0.12, 0.13, 0.16), "clouds": 0.7, "cloud_light": 0.18, "fog_col": Color(0.2, 0.25, 0.33), "fog_d": 0.022, "amb": 0.9, "exp": 1.55,
		"sat": 0.85, "con": 1.08, "glow": 0.9, "stars": 0.5, "sun_sharp": 400.0, "weather": "snow", "night": true},
	"graveyard": {"amb_col": Color(0.32, 0.34, 0.34), "sun": Vector3(-30, 160, 0), "sun_col": Color(0.72, 0.75, 0.95), "sun_e": 0.8, "zen": Color(0.03, 0.035, 0.05), "hor": Color(0.18, 0.2, 0.2),
		"gnd": Color(0.06, 0.06, 0.05), "clouds": 0.55, "cloud_light": 0.15, "fog_col": Color(0.16, 0.19, 0.17), "fog_d": 0.02, "amb": 0.9, "exp": 1.75,
		"sat": 0.8, "con": 1.12, "glow": 0.95, "stars": 0.8, "sun_sharp": 300.0, "weather": "ash", "night": true},
	"night": {"amb_col": Color(0.26, 0.28, 0.36), "sun": Vector3(-55, 25, 0), "sun_col": Color(0.62, 0.72, 1.0), "sun_e": 0.9, "zen": Color(0.008, 0.012, 0.035), "hor": Color(0.06, 0.08, 0.12),
		"gnd": Color(0.03, 0.03, 0.035), "clouds": 0.4, "cloud_light": 0.08, "fog_col": Color(0.07, 0.08, 0.11), "fog_d": 0.022, "amb": 0.85, "exp": 1.8,
		"sat": 0.9, "con": 1.1, "glow": 1.0, "stars": 1.0, "sun_sharp": 350.0, "weather": "ash", "night": true},
}

const MAPS := [
	{"name": "Ciudad Rota", "mode": "ops", "env": "day", "desc": "Ciudad en ruinas con rotonda central y contenedores.", "start": Vector3(0, 0.2, 22), "yaw": 0.0, "cam": 46.0},
	{"name": "Aldea del Desierto", "mode": "ops", "env": "desert", "desc": "Casas de adobe, mercado y pozo bajo un sol de atardecer.", "start": Vector3(0, 0.2, 30), "yaw": 0.0, "cam": 48.0},
	{"name": "Puerto Helado", "mode": "ops", "env": "snow", "desc": "Muelle nevado con almacenes, grúas y tanques de combustible.", "start": Vector3(0, 0.2, 44), "yaw": 0.0, "cam": 48.0},
	{"name": "Pueblo Olvidado", "mode": "zombies", "env": "dusk", "desc": "Zombis · un pueblo abandonado al anochecer. Abre zonas y sobrevive.", "start": Vector3(0, 0.2, 5), "yaw": 0.0, "cam": 36.0},
	{"name": "Fábrica Abandonada", "mode": "zombies", "env": "night", "desc": "Zombis · naves industriales de noche, tanques y almacenes.", "start": Vector3(0, 0.2, 5), "yaw": 0.0, "cam": 36.0},
	{"name": "Base Ártica", "mode": "zombies", "env": "arctic", "desc": "Zombis · base militar en plena ventisca nocturna: barracones, radar y antena.", "start": Vector3(0, 0.2, 5), "yaw": 0.0, "cam": 36.0},
	{"name": "Cementerio", "mode": "zombies", "env": "graveyard", "desc": "Zombis · tumbas, mausoleos y una capilla entre la niebla.", "start": Vector3(0, 0.2, 5), "yaw": 0.0, "cam": 36.0},
]

static var night := false
static var zlayout := {}


static func build(i: int, root: Node3D, names := {}) -> Array:
	rects.clear()
	zlayout = {}
	H = 60.0
	night = ENVS[MAPS[i].env].night
	var sp: Array
	match i:
		0:
			sp = build_city(root)
		1:
			sp = build_desert(root)
		2:
			sp = build_port(root)
		3:
			sp = build_pueblo(root, names)
		4:
			sp = build_factory(root, names)
		5:
			sp = build_arctic(root, names)
		_:
			sp = build_cemetery(root, names)
	for p in sp:
		reserve(p.x, p.z, 1.0)
	if zlayout.has("spawns"):
		for zid in zlayout.spawns:
			for p in zlayout.spawns[zid]:
				reserve(p.x, p.z, 1.0)
	rng.seed = 31337 + i
	if not ("--nodress" in OS.get_cmdline_user_args()):
		dress(root, i)
	# wet streets on the temperate maps, and contact shadows under everything
	match i:
		0:
			puddles_on(root, 14, Rect2(-50, -50, 100, 100))
		3:
			puddles_on(root, 10, Rect2(-36, -36, 72, 72))
		4:
			puddles_on(root, 12, Rect2(-36, -36, 72, 72))
		6:
			puddles_on(root, 10, Rect2(-36, -36, 72, 72))
	if MAPS[i].mode == "zombies":
		var fl: Array = root.get_meta("fires", []).duplicate()
		for q in [[-7.5, -7.5], [7.5, 7.5], [-30, -20], [30, -22], [24, 24], [-24, 22], [-30, 4], [30, -4], [0, -24], [0, 24]]:
			fire_barrel(root, q[0], q[1], fl)
		root.set_meta("fires", fl)
	contact_shadows(root)
	return sp


# ---------------------------------------------------------------- shared helpers
static func ground_plane(root: Node3D, mat: Material, cz := 0.0, sz := 400.0) -> void:
	var g := StaticBody3D.new()
	root.add_child(g)
	var gcs := CollisionShape3D.new()
	var gsh := BoxShape3D.new()
	gsh.size = Vector3(400, 1, sz)
	gcs.shape = gsh
	gcs.position = Vector3(0, -0.5, cz)
	g.add_child(gcs)
	flat(g, Vector3(0, 0, cz), Vector2(400, sz), mat)


static func perimeter(root: Node3D, half: float, h: float, mat: Material, skip_north := false) -> void:
	if skip_north:
		collider_only(root, Vector3(0, 3, -half - 1), Vector3(2 * half + 4, 6, 2))
	else:
		blk(root, 0, 0, -half - 1, 2 * half + 4, h, 2, mat)
	blk(root, 0, 0, half + 1, 2 * half + 4, h, 2, mat)
	blk(root, -half - 1, 0, 0, 2, h, 2 * half + 4, mat)
	blk(root, half + 1, 0, 0, 2, h, 2 * half + 4, mat)


static func reserve(x: float, z: float, r: float) -> void:
	rects.append([x - r, z - r, x + r, z + r, 0.0])


static func edge_spawns(half: float) -> Array:
	var sp := []
	var e := half - 5.0
	for a in range(-int(e), int(e) + 1, 8):
		for q in [[a, -e], [a, e], [-e, a], [e, a]]:
			if is_free(q[0], q[1], 1.0):
				sp.append(Vector3(q[0], 0, q[1]))
	return sp


static func scatter_crates(root: Node3D, n: int, mat: Material, avoid: Vector3, half: float) -> void:
	var placed := 0
	for i in 500:
		if placed >= n:
			break
		var x := rng.randf_range(-half + 4, half - 4)
		var z := rng.randf_range(-half + 4, half - 4)
		var s := 1.6 if rng.randf() < 0.3 else 1.2
		if Vector2(x - avoid.x, z - avoid.z).length() < 5 or not is_free(x, z, s / 2 + 1.4):
			continue
		blk(root, x, 0, z, s, s, s, mat, true, 0.06)
		placed += 1
		if rng.randf() < 0.3:
			blk(root, x + rng.randf_range(-0.15, 0.15), s, z + rng.randf_range(-0.15, 0.15), 1.0, 1.0, 1.0, mat, true, 0.06)


static func barrel(root: Node3D, x: float, z: float, col: Color) -> void:
	if not is_free(x, z, 0.5):
		return
	var sb := StaticBody3D.new()
	sb.position = Vector3(x, 0.45, z)
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.32
	cy.height = 0.9
	cs.shape = cy
	sb.add_child(cs)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.3
	cm.height = 0.9
	cm.radial_segments = 18
	var m := pbr("rusty_metal_02", col.lightened(0.45), 1.1, 0.55, false)
	mesh_node(sb, cm, m, Vector3.ZERO)
	for y in [-0.25, 0.25]:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.3
		tm.outer_radius = 0.325
		mesh_node(sb, tm, m, Vector3(0, y, 0), Vector3.ZERO, false)
	rects.append([x - 0.32, z - 0.32, x + 0.32, z + 0.32, 0.9])


static func rock(root: Node3D, x: float, z: float, s: float, mat: Material) -> void:
	if not is_free(x, z, s * 0.6):
		return
	var sm := SphereMesh.new()
	sm.radius = s
	sm.height = s * 1.3
	sm.radial_segments = 9
	sm.rings = 5
	var sb := StaticBody3D.new()
	sb.position = Vector3(x, s * 0.3, z)
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = s * 0.75
	cs.shape = sh
	sb.add_child(cs)
	var mi := mesh_node(sb, sm, mat, Vector3.ZERO, Vector3(rng.randf() * 0.5, rng.randf() * 6.0, rng.randf() * 0.5))
	mi.scale = Vector3(rng.randf_range(0.9, 1.4), rng.randf_range(0.7, 1.0), rng.randf_range(0.9, 1.4))
	rects.append([x - s * 0.7, z - s * 0.7, x + s * 0.7, z + s * 0.7, s])


static func palm(root: Node3D, x: float, z: float, s: float) -> void:
	if not is_free(x, z, 0.8):
		return
	var bark := pbr("bark_brown_02", Color(0.85, 0.7, 0.55), 1.4, 0.0, false)
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
	var p := Vector3(x, 0, z)
	for i in 7:
		var cm := CylinderMesh.new()
		cm.top_radius = (0.2 - i * 0.012) * s
		cm.bottom_radius = (0.23 - i * 0.012) * s
		cm.height = 0.9 * s
		cm.radial_segments = 10
		mesh_node(root, cm, bark, p + Vector3(0, 0.45 * s, 0), Vector3(lean.z * i * 0.3, 0, -lean.x * i * 0.3))
		p += Vector3(lean.x * i * 0.3, 0.88 * s, lean.z * i * 0.3)
	collider_only(root, Vector3(x, 2.5 * s, z), Vector3(0.4 * s, 5.0 * s, 0.4 * s))
	var leaf := leaves(Color(0.27, 0.4, 0.16), 2.0)
	for k in 9:
		var a := k * TAU / 9.0 + rng.randf() * 0.3
		var fr := Node3D.new()
		fr.position = p
		fr.rotation = Vector3(0, a, 0)
		root.add_child(fr)
		for j in 4:
			var bm := SHP.rbox(Vector3(0.55 - j * 0.08, 0.04, 0.6) * s, 0.015, 1)
			mesh_node(fr, bm, leaf, Vector3(0, -j * j * 0.09 * s, -(0.35 + j * 0.55) * s), Vector3(-0.25 - j * 0.25, 0, 0))


static func pine(root: Node3D, x: float, z: float, s: float, snowy: bool) -> void:
	if absf(x) < H + 3.0 and absf(z) < H + 3.0 and not is_free(x, z, 1.0):
		return
	var bark := pbr("bark_brown_02", Color(0.7, 0.6, 0.55), 1.2, 0.0, false)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1 * s
	cm.bottom_radius = 0.22 * s
	cm.height = 2.2 * s
	mesh_node(root, cm, bark, Vector3(x, 1.1 * s, z))
	collider_only(root, Vector3(x, 1.5 * s, z), Vector3(0.45 * s, 3.0 * s, 0.45 * s))
	var green := leaves(Color(0.13, 0.24, 0.15), 1.5)
	var white := pbr("snow_02", Color.WHITE, 0.8, 0.0, false)
	for i in 4:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = (1.6 - i * 0.32) * s
		c.height = 1.5 * s
		c.radial_segments = 12
		var y := (1.4 + i * 0.95) * s
		mesh_node(root, c, green, Vector3(x, y, z), Vector3(0, rng.randf() * 3, 0))
		if snowy:
			var c2 := CylinderMesh.new()
			c2.top_radius = 0.0
			c2.bottom_radius = (1.0 - i * 0.2) * s
			c2.height = 0.7 * s
			c2.radial_segments = 12
			mesh_node(root, c2, white, Vector3(x, y + 0.42 * s, z), Vector3.ZERO, false)


## Market stall: four poles and a slanted cloth roof.
static func stall(root: Node3D, x: float, z: float, rot: float, cloth: Color) -> void:
	if not is_free(x, z, 1.8):
		return
	var n := Node3D.new()
	n.position = Vector3(x, 0, z)
	n.rotation.y = rot
	root.add_child(n)
	var wood := pbr("brown_planks_04", Color(0.8, 0.7, 0.55), 1.0, 0.0, false)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.05
	pole.bottom_radius = 0.05
	pole.height = 2.4
	for p in [Vector3(-1.4, 1.2, -0.9), Vector3(1.4, 1.2, -0.9), Vector3(-1.4, 1.0, 0.9), Vector3(1.4, 1.0, 0.9)]:
		mesh_node(n, pole, wood, p)
	var cm: StandardMaterial3D = colm(cloth, 0.95).duplicate()
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_node(n, SHP.rbox(Vector3(3.2, 0.04, 2.2), 0.015, 1), cm, Vector3(0, 2.25, 0), Vector3(-0.18, 0, 0))
	mesh_node(n, SHP.rbox(Vector3(2.8, 0.8, 0.9), 0.05, 2), wood, Vector3(0, 0.4, 0.3))
	collider_only(root, Vector3(x, 0.4, z), Vector3(2.8, 0.8, 1.6) if absf(sin(rot)) < 0.5 else Vector3(1.6, 0.8, 2.8))
	for i in 5:
		var fm := SphereMesh.new()
		fm.radius = 0.12
		fm.height = 0.2
		mesh_node(n, fm, colm(Color.from_hsv(rng.randf_range(0.0, 0.15), 0.8, 0.8), 0.6), Vector3(-1.0 + i * 0.5, 0.88, 0.3), Vector3.ZERO, false)


static func lamp_light(root: Node3D, pos: Vector3, col := Color(1.0, 0.75, 0.45), energy := 2.2, rng_ := 13.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 38.0
	l.distance_fade_length = 10.0
	l.position = pos
	root.add_child(l)


static func roof(root: Node3D, cx: float, cz: float, w: float, d: float, h: float, mat: Material) -> void:
	blk(root, cx, h + 0.16, cz, w + 0.6, 0.22, d + 0.6, mat, false)


static func label3d(parent: Node3D, text: String, pos: Vector3, size: int, col: Color, rot_y: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 8
	l.modulate = col
	l.pixel_size = 0.004
	l.position = pos
	l.shaded = false
	l.double_sided = false
	l.rotation.y = rot_y
	parent.add_child(l)
	return l


# ================================================================ Aldea del Desierto
static func build_desert(root: Node3D) -> Array:
	rng.seed = 2024
	var sand := pbr("coast_sand_02", Color(1.0, 0.9, 0.75), 0.18)
	var adobe := pbr("patterned_clay_plaster", Color(1.0, 0.88, 0.72), 0.4)
	var adobe2 := pbr("white_stucco", Color(0.95, 0.82, 0.66), 0.4)
	var trim := pbr("clay_plaster", Color(0.62, 0.48, 0.36), 0.5)
	var stone := pbr("dark_rock", Color(1.1, 0.95, 0.8), 0.45)
	var crate := pbr("brown_planks_04", Color(0.95, 0.85, 0.7), 0.8, 0.0, false)
	var dirt := pbr("concrete_floor_01", Color(0.75, 0.6, 0.45), 0.25)
	ground_plane(root, sand)
	flat(root, Vector3(0, 0.01, 0), Vector2(8, 110), dirt)
	flat(root, Vector3(0, 0.012, -4), Vector2(110, 7), dirt)
	disc(root, Vector3(0, 0.0, -4), 11.0, 0.03, dirt)
	perimeter(root, H, 5.0, adobe2)
	# dunes and far mesas outside the wall
	var dune := pbr("coast_sand_02", Color(0.95, 0.82, 0.66), 0.06)
	for i in 34:
		var a := rng.randf() * TAU
		var r := rng.randf_range(75, 150)
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(14, 30)
		sm.height = sm.radius * 0.5
		mesh_node(root, sm, dune, Vector3(cos(a) * r, -2.0, sin(a) * r), Vector3(0, rng.randf() * 3, 0), false).scale = Vector3(1.6, 1, 1)
	for i in 8:
		var a := rng.randf() * TAU
		blk(root, cos(a) * 160, 0, sin(a) * 160, rng.randf_range(30, 50), rng.randf_range(18, 30), rng.randf_range(20, 40), trim, false)
	# central well + square
	var sb := StaticBody3D.new()
	sb.position = Vector3(0, 0.5, -4)
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 1.5
	cy.height = 1.0
	cs.shape = cy
	sb.add_child(cs)
	var wm := CylinderMesh.new()
	wm.top_radius = 1.5
	wm.bottom_radius = 1.6
	wm.height = 1.0
	wm.radial_segments = 28
	mesh_node(sb, wm, stone, Vector3.ZERO)
	var wat := CylinderMesh.new()
	wat.top_radius = 1.25
	wat.bottom_radius = 1.25
	wat.height = 0.05
	mesh_node(sb, wat, colm(Color(0.05, 0.08, 0.1), 0.05, 0.3), Vector3(0, 0.42, 0), Vector3.ZERO, false)
	for sx in [-1.0, 1.0]:
		blk(root, sx * 1.2, 1.0, -4, 0.15, 1.8, 0.15, crate, false)
	blk(root, 0, 2.75, -4, 2.6, 0.14, 0.14, crate, false)
	rects.append([-1.6, -5.6, 1.6, -2.4, 1.0])
	# houses (walls + flat roofs), doors on several sides to keep them open
	var houses := [[-30, -32, 14, 10, 4.0, {"n": [[0, "d"]], "s": [[-3, "d"], [3, "w"]], "e": [[0, "w"]]}],
		[30, -32, 12, 12, 4.5, {"s": [[0, "d"]], "w": [[2, "d"]], "n": [[0, "w"]]}],
		[-30, 30, 16, 10, 4.0, {"n": [[-4, "d"], [4, "w"]], "e": [[0, "d"]]}],
		[30, 30, 12, 14, 4.0, {"n": [[0, "d"]], "w": [[-3, "d"], [3, "w"]]}],
		[0, -44, 18, 9, 5.0, {"s": [[-5, "d"], [0, "w"], [5, "d"]]}],
		[-46, 2, 10, 16, 4.0, {"e": [[-4, "d"], [4, "d"]]}],
		[46, 2, 10, 14, 4.5, {"w": [[0, "d"]], "n": [[0, "w"]]}],
		[-15, -18, 8, 7, 3.4, {"e": [[0, "d"]], "s": [[0, "w"]]}],
		[16, 14, 8, 8, 3.4, {"w": [[0, "d"]], "n": [[0, "w"]]}],
		[-17, 16, 7, 7, 3.2, {"n": [[0, "d"]], "e": [[0, "w"]]}],
		[18, -17, 7, 8, 3.2, {"s": [[0, "d"]], "w": [[0, "w"]]}]]
	for hh in houses:
		var m: Material = adobe if rng.randf() < 0.6 else adobe2
		building(root, hh[0], hh[1], hh[2], hh[3], hh[4], hh[5], m, trim)
		roof(root, hh[0], hh[1], hh[2], hh[3], hh[4], trim)
	# low adobe cover walls
	for q in [[-8, 8, 5, 0.5], [9, 6, 0.5, 4], [-36, -14, 6, 0.5], [36, -12, 0.5, 6], [-40, 40, 6, 0.5], [40, 42, 0.5, 6], [0, 22, 6, 0.5], [-24, 0, 0.5, 5], [24, -2, 0.5, 5]]:
		blk(root, q[0], 0, q[1], q[2], 1.25, q[3], adobe2, true, 0.12)
	# market stalls around the square
	var cloths := [Color(0.7, 0.2, 0.15), Color(0.85, 0.65, 0.25), Color(0.2, 0.42, 0.55), Color(0.55, 0.3, 0.5), Color(0.8, 0.8, 0.72)]
	var k := 0
	for q in [[-7, -12, 0.0], [6, -12, 0.0], [-11, 2, PI / 2], [11, 0, -PI / 2], [-6, 6, PI], [6, 4, PI]]:
		stall(root, q[0], q[1], q[2], cloths[k % cloths.size()])
		k += 1
	var fires := []
	car(root, -6, 30, PI / 2, Color(0.3, 0.27, 0.22), true, fires)
	car(root, 38, -4, 0.0, Color(0.55, 0.5, 0.4), false, fires)
	car(root, -38, -24, 0.0, Color(0.2, 0.18, 0.16), true, fires)
	sandbags(root, [[0, 16, 6, 0.8], [-20, -6, 0.8, 6], [20, 4, 0.8, 6], [-34, 18, 6, 0.8], [34, -20, 6, 0.8], [0, -26, 8, 0.8]])
	for p in [[-5, -22], [5, -24], [-24, 10], [24, 20], [-44, -44], [44, 44], [-44, 46], [46, -46], [12, 38], [-12, 40], [-36, -2], [36, 12], [-4, 46], [10, -32]]:
		palm(root, p[0], p[1], rng.randf_range(0.85, 1.2))
	for i in 20:
		rock(root, rng.randf_range(-55, 55), rng.randf_range(-55, 55), rng.randf_range(0.4, 0.9), stone)
	for i in 14:
		barrel(root, rng.randf_range(-50, 50), rng.randf_range(-50, 50), Color.from_hsv(rng.randf_range(0.0, 0.12), 0.5, rng.randf_range(0.4, 0.7)))
	scatter_crates(root, 24, crate, Vector3(0, 0, 30), H)
	root.set_meta("fires", fires)
	return edge_spawns(H)


# ================================================================ Puerto Helado
static func build_port(root: Node3D) -> Array:
	rng.seed = 777
	var snow := pbr("snow_02", Color(1.0, 1.0, 1.04), 0.22)
	var conc := pbr("concrete_floor_01", Color(0.62, 0.64, 0.68), 0.3)
	var wallm := pbr("concrete_block_wall", Color(0.82, 0.84, 0.88))
	var metal := pbr("metal_plate", Color(0.62, 0.66, 0.7), 0.35, 0.6)
	var steel_y := pbr("metal_plate", Color(0.85, 0.65, 0.2), 0.5, 0.6)
	var c_red := pbr("corrugated_iron_02", Color(0.72, 0.28, 0.22), 0.38, 0.45)
	var c_blue := pbr("corrugated_iron_02", Color(0.28, 0.42, 0.6), 0.38, 0.45)
	var c_grey := pbr("corrugated_iron_02", Color(0.55, 0.57, 0.58), 0.38, 0.45)
	var c_orange := pbr("corrugated_iron_02", Color(0.82, 0.45, 0.18), 0.38, 0.45)
	var crate := pbr("brown_planks_04", Color(0.9, 0.82, 0.72), 0.8, 0.0, false)
	var white := pbr("snow_02", Color.WHITE, 0.4)
	ground_plane(root, snow, (200.0 - H) * 0.5, 200.0 + H)
	# quay along the north edge: concrete apron, edge, water and a moored ship
	flat(root, Vector3(0, 0.012, -50), Vector2(120, 20), conc)
	blk(root, 0, -2.0, -H - 1.0, 2 * H + 4, 2.15, 2.0, conc, false)
	for x in range(-56, 57, 8):
		var bm := CylinderMesh.new()
		bm.top_radius = 0.22
		bm.bottom_radius = 0.26
		bm.height = 0.7
		mesh_node(root, bm, steel_y, Vector3(x, 0.35, -H + 0.6))
	var water := colm(Color(0.03, 0.06, 0.08), 0.06, 0.2)
	flat(root, Vector3(0, -1.2, -H - 70), Vector2(400, 140), water)
	blk(root, 10, -1.2, -H - 22, 70, 12, 14, colm(Color(0.12, 0.13, 0.15), 0.5, 0.4), false, 2.0)
	blk(root, 30, 10.8, -H - 22, 14, 7, 12, colm(Color(0.85, 0.85, 0.82), 0.6), false, 0.5)
	perimeter(root, H, 5.0, wallm, true)
	# skyline: snowy hills
	for i in 26:
		var a := rng.randf_range(0.2, PI - 0.2)
		var r := rng.randf_range(90, 160)
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(20, 40)
		sm.height = sm.radius * 0.8
		mesh_node(root, sm, white, Vector3(cos(a) * r, -4.0, sin(a) * r), Vector3.ZERO, false)
	# warehouses
	for w in [[-34, -22, 18, 12, 6.0, {"s": [[0, "d"]], "e": [[0, "d"]], "n": [[-4, "w"], [4, "w"]]}],
			[34, -20, 16, 14, 6.0, {"s": [[-3, "d"]], "w": [[0, "d"]]}],
			[-36, 32, 14, 12, 5.0, {"n": [[0, "d"]], "e": [[2, "d"]]}],
			[36, 34, 12, 12, 5.0, {"w": [[0, "d"]], "n": [[0, "w"]]}]]:
		building(root, w[0], w[1], w[2], w[3], w[4], w[5], metal, conc)
		roof(root, w[0], w[1], w[2], w[3], w[4], c_grey)
		blk(root, w[0], w[4] + 0.38, w[1], w[2] + 0.4, 0.14, w[3] + 0.4, white, false)
	# container stacks with snow caps
	var conts := [[-12, -36, 0], [-12, -36, 1], [2, -38, 0], [16, -34, 0], [16, -34, 1], [-20, 4, 0], [-20, 4, 1], [20, 6, 0], [6, 16, 0], [-6, -10, 0], [12, -12, 0], [-44, 8, 0], [46, 6, 0], [46, 6, 1]]
	var cmats := [c_red, c_blue, c_orange, c_grey]
	for i in conts.size():
		var c: Array = conts[i]
		var along := i % 3 != 0
		var w := 12.0 if along else 2.6
		var d := 2.6 if along else 12.0
		blk(root, c[0], c[2] * 2.6, c[1], w, 2.6, d, cmats[i % 4], true, 0.1)
		if c[2] == 1 or not (conts.has([c[0], c[1], 1])):
			blk(root, c[0], c[2] * 2.6 + 2.6, c[1], w - 0.2, 0.08, d - 0.2, white, false)
	# fuel tanks
	for t in [[-30, 6, 3.5], [-38, 14, 3.0], [30, 20, 3.5]]:
		var sb := StaticBody3D.new()
		sb.position = Vector3(t[0], 3.0, t[1])
		root.add_child(sb)
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = t[2]
		cy.height = 6.0
		cs.shape = cy
		sb.add_child(cs)
		var tm := CylinderMesh.new()
		tm.top_radius = t[2]
		tm.bottom_radius = t[2]
		tm.height = 6.0
		tm.radial_segments = 40
		mesh_node(sb, tm, metal, Vector3.ZERO)
		var cap := SphereMesh.new()
		cap.radius = t[2]
		cap.height = t[2] * 0.6
		cap.is_hemisphere = true
		mesh_node(sb, cap, white, Vector3(0, 3.0, 0))
		rects.append([t[0] - t[2], t[1] - t[2], t[0] + t[2], t[1] + t[2], 6.0])
	# gantry crane over the quay
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			blk(root, 8 + sx * 6, 0, -48 + sz * 4, 0.8, 14, 0.8, steel_y, true)
	blk(root, 8, 14, -48, 14, 1.2, 9.6, steel_y, false)
	blk(root, 8, 15.2, -46, 3, 2.4, 3, steel_y, false)
	sandbags(root, [[0, 26, 6, 0.8], [-24, -6, 0.8, 6], [24, -4, 0.8, 6], [0, -24, 8, 0.8], [-44, 44, 6, 0.8], [44, -36, 0.8, 6]])
	for l in [[-50, 22, 1, 0], [50, 22, -1, 0], [-8, 34, 1, 0], [8, -28, -1, 0], [-24, -44, 0, 1], [24, -44, 0, 1]]:
		lamp(root, l[0], l[1], l[2], l[3])
	for p in [[-52, 50], [-44, 52], [52, 50], [44, 52], [-52, -6], [52, -8], [-14, 50], [14, 52], [-26, 46], [26, 46]]:
		pine(root, p[0], p[1], rng.randf_range(0.9, 1.3), true)
	# snow drifts
	for i in 40:
		var x := rng.randf_range(-56, 56)
		var z := rng.randf_range(-36, 56)
		if not is_free(x, z, 1.0):
			continue
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.6, 1.6)
		sm.height = sm.radius * 0.7
		mesh_node(root, sm, white, Vector3(x, -0.05, z), Vector3(0, rng.randf() * 3, 0), false).scale = Vector3(1.8, 0.6, 1.2)
	for i in 10:
		barrel(root, rng.randf_range(-50, 50), rng.randf_range(-40, 50), Color(0.25, 0.35, 0.5) if rng.randf() < 0.5 else Color(0.7, 0.2, 0.15))
	scatter_crates(root, 22, crate, Vector3(0, 0, 44), H)
	var fires := []
	car(root, -9, 38, PI / 2, Color(0.2, 0.22, 0.25), false, fires)
	car(root, 22, -30, 0.0, Color(0.3, 0.18, 0.12), true, fires)
	root.set_meta("fires", fires)
	return edge_spawns(H).filter(func(p): return p.z > -H + 8)


# ================================================================ zombie maps
## Shared layout (half size 40): a walled start courtyard (zone 0) and four outer zones
## (1 north, 2 east, 3 south, 4 west) separated by walls; every gate is blocked by debris
## that the player buys open. Returns the layout through `zlayout`.
const ZH := 40.0


static func zone_of(p: Vector3) -> int:
	if absf(p.x) < 12.0 and absf(p.z) < 12.0:
		return 0
	if p.z <= -12.0:
		return 1
	if p.z >= 12.0:
		return 3
	return 2 if p.x > 0.0 else 4


static func wall_line(root: Node3D, a0: float, a1: float, fixed: float, axis: String, gaps: Array, h: float, mat: Material) -> void:
	var cur := a0
	var segs := []
	for g in gaps:
		segs.append([cur, g - 1.6])
		cur = g + 1.6
	segs.append([cur, a1])
	for s in segs:
		if s[1] - s[0] < 0.05:
			continue
		if axis == "x":
			blk(root, (s[0] + s[1]) * 0.5, 0, fixed, s[1] - s[0], h, 0.6, mat, true, 0.06)
		else:
			blk(root, fixed, 0, (s[0] + s[1]) * 0.5, 0.6, h, s[1] - s[0], mat, true, 0.06)
	for g in gaps:
		# gate posts + lintel
		for sd in [-1.0, 1.0]:
			if axis == "x":
				blk(root, g + sd * 1.75, 0, fixed, 0.4, h + 0.3, 0.8, mat, false, 0.05)
			else:
				blk(root, fixed, 0, g + sd * 1.75, 0.8, h + 0.3, 0.4, mat, false, 0.05)


static func debris(root: Node3D, pos: Vector3, axis: String) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.set_meta("nomerge", true)
	if axis == "z":
		sb.rotation.y = PI / 2
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(3.3, 3.6, 0.9)
	cs.shape = sh
	cs.position.y = 1.8
	sb.add_child(cs)
	var wood := pbr("distressed_painted_planks", Color(0.85, 0.8, 0.75), 1.0, 0.0, false)
	var stone := pbr("concrete_debris", Color(0.9, 0.88, 0.85), 0.6)
	for i in 7:
		var y := 0.3 + i * 0.48
		mesh_node(sb, SHP.rbox(Vector3(3.5, 0.22, 0.08), 0.03, 1), wood, Vector3(rng.randf_range(-0.1, 0.1), y, -0.25 + (i % 2) * 0.12),
			Vector3(0, rng.randf_range(-0.1, 0.1), rng.randf_range(-0.35, 0.35)))
	for i in 9:
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.25, 0.55)
		sm.height = sm.radius * 1.4
		sm.radial_segments = 7
		sm.rings = 4
		mesh_node(sb, sm, stone, Vector3(rng.randf_range(-1.4, 1.4), sm.radius * 0.4, rng.randf_range(-0.35, 0.35)), Vector3(rng.randf(), rng.randf() * 3, 0))
	mesh_node(sb, SHP.rbox(Vector3(0.9, 0.9, 0.9), 0.06, 2), wood, Vector3(0.9, 0.45, 0.2), Vector3(0, 0.4, 0))
	return sb


static func perk_machine(root: Node3D, pos: Vector3, face: Vector3, name: String, cost: int, col: Color, icon := "") -> void:
	var n := Node3D.new()
	n.position = pos
	root.add_child(n)
	n.look_at(pos + face, Vector3.UP)
	var body := colm(col.darkened(0.45), 0.35, 0.4)
	blk(n, 0, 0, 0, 1.1, 2.2, 0.8, body, false, 0.12)
	blk(n, 0, 2.2, 0, 1.2, 0.18, 0.9, colm(Color(0.12, 0.12, 0.13), 0.4, 0.6), false, 0.05)
	blk(n, 0, 0.9, -0.41, 0.8, 1.0, 0.04, colm(col, 0.3, 0.0, 2.6), false, 0.02)
	blk(n, 0, 0.25, -0.42, 0.5, 0.3, 0.06, colm(Color(0.05, 0.05, 0.05), 0.2, 0.8), false, 0.03)
	label3d(n, name.to_upper(), Vector3(0, 2.0, -0.43), 40, col.lightened(0.3), PI)
	label3d(n, "%d" % cost, Vector3(0, 1.72, -0.43), 30, Color(1, 1, 1), PI)
	if icon != "":
		var sp := Sprite3D.new()
		sp.texture = perk_icon(icon)
		sp.pixel_size = 0.0055
		sp.position = Vector3(0, 1.05, -0.445)
		sp.rotation.y = PI
		sp.shaded = false
		sp.set_meta("nomerge", true)
		n.add_child(sp)
	lamp_light(n, Vector3(0, 1.4, -1.0), col, 1.6, 6.0)
	collider_only(root, pos + Vector3(0, 1.1, 0), Vector3(1.1, 2.2, 1.1))


static func mystery_box(root: Node3D, pos: Vector3, rot: float) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot
	n.set_meta("nomerge", true)
	root.add_child(n)
	var wood := pbr("brown_planks_04", Color(0.55, 0.42, 0.3), 1.0, 0.0, false)
	blk(n, 0, 0, 0, 1.7, 0.75, 0.8, wood, false, 0.06)
	blk(n, 0, 0.75, 0, 1.75, 0.12, 0.85, colm(Color(0.2, 0.16, 0.12), 0.6), false, 0.04)
	for sd in [-1.0, 1.0]:
		var q := label3d(n, "?", Vector3(0, 0.4, sd * 0.43), 140, Color(1.6, 1.2, 0.4), 0.0 if sd > 0.0 else PI)
		q.outline_size = 0
	var beam := CylinderMesh.new()
	beam.top_radius = 0.35
	beam.bottom_radius = 0.5
	beam.height = 14.0
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(0.35, 0.55, 1.0, 0.18)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_node(n, beam, bm, Vector3(0, 7.5, 0), Vector3.ZERO, false)
	lamp_light(n, Vector3(0, 1.5, 0), Color(0.45, 0.6, 1.0), 2.0, 7.0)
	collider_only(root, pos + Vector3(0, 0.4, 0), Vector3(1.7, 0.8, 1.7))
	return n


static func chalk_buy(root: Node3D, pos: Vector3, face: Vector3, text: String, weapon := -1) -> void:
	var chalk := StandardMaterial3D.new()
	chalk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chalk.albedo_color = Color(0.92, 0.92, 0.85)
	var n := Node3D.new()
	n.position = pos + face * 0.02
	root.add_child(n)
	n.look_at(n.position - face, Vector3.UP)
	for e in [[Vector3(0, 0.32, 0), Vector3(1.3, 0.025, 0.01)], [Vector3(0, -0.32, 0), Vector3(1.3, 0.025, 0.01)],
			[Vector3(-0.65, 0, 0), Vector3(0.025, 0.66, 0.01)], [Vector3(0.65, 0, 0), Vector3(0.025, 0.66, 0.01)]]:
		var bm := BoxMesh.new()
		bm.size = e[1]
		mesh_node(n, bm, chalk, e[0], Vector3(0, 0, rng.randf_range(-0.02, 0.02)), false)
	if weapon >= 0:
		# chalk outline of the actual gun, flattened against the wall
		var sil: Node3D = load("res://scripts/weapon_models.gd").chalk_copy(weapon)
		sil.set_meta("nomerge", true)
		n.add_child(sil)
		sil.rotation = Vector3(0, PI / 2, 0)
		var sc: float = [1.0, 1.0, 2.2, 1.35, 0.95, 0.9][weapon]
		var zc: float = [-0.18, -0.15, -0.06, -0.04, -0.23, -0.25][weapon]
		sil.scale = Vector3(0.05, sc, sc)
		sil.position = Vector3(-zc * sc, 0.13, 0.0)
	var l := Label3D.new()
	l.text = text
	l.font_size = 34
	l.outline_size = 0
	l.modulate = Color(0.95, 0.95, 0.88)
	l.pixel_size = 0.004
	l.position = Vector3(0, -0.24, -0.01)
	l.font_size = 24
	l.shaded = false
	n.add_child(l)


## Builds the walls, gates, debris and interactables of the zombie layout.
static func zring(root: Node3D, wallm: Material, inner: Material, buy_names: Dictionary) -> void:
	H = ZH
	perimeter(root, ZH, 4.5, wallm)
	wall_line(root, -12, 12, -12, "x", [0.0], 3.6, inner)
	wall_line(root, -12, 12, 12, "x", [0.0], 3.6, inner)
	wall_line(root, -11.7, 11.7, -12, "z", [0.0], 3.6, inner)
	wall_line(root, -11.7, 11.7, 12, "z", [0.0], 3.6, inner)
	wall_line(root, -ZH, -12.3, -12, "x", [-26.0], 3.6, inner)
	wall_line(root, 12.3, ZH, -12, "x", [26.0], 3.6, inner)
	wall_line(root, -ZH, -12.3, 12, "x", [-26.0], 3.6, inner)
	wall_line(root, 12.3, ZH, 12, "x", [26.0], 3.6, inner)
	var gates := [[Vector3(0, 0, -12), "x", [0, 1], 750], [Vector3(12, 0, 0), "z", [0, 2], 750], [Vector3(0, 0, 12), "x", [0, 3], 1000],
		[Vector3(-12, 0, 0), "z", [0, 4], 1000], [Vector3(-26, 0, -12), "x", [1, 4], 1250], [Vector3(26, 0, -12), "x", [1, 2], 1250],
		[Vector3(-26, 0, 12), "x", [3, 4], 1250], [Vector3(26, 0, 12), "x", [3, 2], 1250]]
	var doors := []
	for gt in gates:
		var node := debris(root, gt[0], gt[1])
		doors.append({"pos": gt[0], "node": node, "zones": gt[2], "cost": gt[3], "open": false})
		reserve(gt[0].x, gt[0].z, 4.0)
	# interactables (positions reserved so props never block them)
	var buys := [[Vector3(-6, 1.5, -11.68), Vector3(0, 0, 1), 1, 500], [Vector3(11.68, 1.5, -6), Vector3(-1, 0, 0), 3, 1000],
		[Vector3(6, 1.5, -12.32), Vector3(0, 0, -1), 0, 1200], [Vector3(-ZH + 0.02, 1.5, -5), Vector3(1, 0, 0), 4, 1500],
		[Vector3(-6, 1.5, 12.32), Vector3(0, 0, 1), 2, 250], [Vector3(ZH - 0.02, 1.5, 5), Vector3(-1, 0, 0), 5, 2500]]
	var wb := []
	for b in buys:
		chalk_buy(root, b[0], b[1], "%s\n%d" % [buy_names[b[2]], b[3]], b[2])
		wb.append({"pos": b[0] + b[1] * 0.6 - Vector3(0, 1.5, 0), "weapon": b[2], "cost": b[3]})
		reserve(b[0].x + b[1].x * 1.5, b[0].z + b[1].z * 1.5, 2.0)
	var perks := [[Vector3(34, 0, -8), Vector3(-1, 0, 0), "armor", "Blindaje", 2500, Color(0.25, 0.55, 1.0)],
		[Vector3(-34, 0, 8), Vector3(1, 0, 0), "hands", "Manos rápidas", 3000, Color(0.3, 1.0, 0.45)],
		[Vector3(20, 0, 32), Vector3(0, 0, -1), "pulse", "Pulso", 2000, Color(1.0, 0.35, 0.25)]]
	var pk := []
	for p in perks:
		perk_machine(root, p[0], p[1], p[3], p[4], p[5], p[2])
		pk.append({"pos": p[0] + p[1] * 1.0, "kind": p[2], "name": p[3], "cost": p[4]})
		reserve(p[0].x + p[1].x * 1.5, p[0].z + p[1].z * 1.5, 2.2)
	# weapon upgrade machine ("Forja")
	var up_pos := Vector3(8, 0, -30)
	perk_machine(root, up_pos, Vector3(0, 0, 1), "Forja", 5000, Color(1.0, 0.7, 0.2), "forge")
	reserve(up_pos.x, up_pos.z + 1.5, 2.2)
	var box_pos := Vector3(-8, 0, -30)
	var box := mystery_box(root, box_pos, 0.0)
	reserve(box_pos.x, box_pos.z + 1.6, 2.2)
	reserve(0, 5, 3.0)
	zlayout = {"doors": doors, "buys": wb, "perks": pk, "box": {"pos": box_pos + Vector3(0, 0, 1.0), "node": box, "cost": 950}, "spawns": {},
		"forge": {"pos": up_pos + Vector3(0, 0, 1.0), "cost": 5000}}


static func zone_spawns() -> void:
	var sp := {0: [], 1: [], 2: [], 3: [], 4: []}
	var cand := []
	# start courtyard: a ring of points along its walls (several per side so props never block them all)
	for a in [-9.5, -6.5, -3.5, 3.5, 6.5, 9.5]:
		cand.append([0, a, -10.6])
		cand.append([0, a, 10.6])
		cand.append([0, -10.6, a])
		cand.append([0, 10.6, a])
	for x in range(-34, 35, 9):
		cand.append([1, x, -36])
		cand.append([1, x, -17])
		cand.append([3, x, 36])
		cand.append([3, x, 17])
	for z in [-7, 0, 7]:
		cand.append([2, 36, z])
		cand.append([2, 18, z])
		cand.append([4, -36, z])
		cand.append([4, -18, z])
	for c in cand:
		if is_free(c[1], c[2], 0.7):
			sp[c[0]].append(Vector3(c[1], 0, c[2]))
	# never leave a zone without spawns: fall back to its candidates even if a prop is close
	for c in cand:
		if sp[c[0]].size() < 3:
			sp[c[0]].append(Vector3(c[1], 0, c[2]))
	zlayout.spawns = sp


# ---------------------------------------------------------------- Pueblo Olvidado
static func build_pueblo(root: Node3D, buy_names := {}) -> Array:
	rng.seed = 4242
	var dirt := pbr("brown_mud_leaves_01", Color(0.85, 0.8, 0.75), 0.22)
	var grassm := pbr("sparse_grass", Color(0.7, 0.72, 0.6), 0.3)
	var road := pbr("asphalt_02", Color(0.7, 0.68, 0.66), 0.22)
	var brick := pbr("brick_wall_001", Color(0.85, 0.8, 0.75))
	var plaster := pbr("white_stucco", Color(0.85, 0.8, 0.72), 0.4)
	var plaster2 := pbr("patterned_clay_plaster", Color(0.8, 0.85, 0.78), 0.4)
	var wallm := pbr("concrete_block_wall", Color(0.7, 0.68, 0.64))
	var roofm := pbr("clay_roof_tiles_02", Color(0.85, 0.75, 0.7), 0.5)
	var crate := pbr("brown_planks_04", Color(0.85, 0.75, 0.6), 0.8, 0.0, false)
	var stone := pbr("chipped_concrete", Color(0.6, 0.6, 0.58), 0.4)
	ground_plane(root, dirt)
	flat(root, Vector3(0, 0.01, 0), Vector2(6, 80), road)
	flat(root, Vector3(0, 0.012, 0), Vector2(80, 6), road)
	for q in [[-26, -26], [26, -26], [-26, 26], [26, 26]]:
		flat(root, Vector3(q[0], 0.008, q[1]), Vector2(22, 20), grassm)
	zring(root, wallm, stone, buy_names)
	# outside: dark forest silhouettes + church spire
	for i in 60:
		var a := rng.randf() * TAU
		var r := rng.randf_range(50, 110)
		pine(root, cos(a) * r, sin(a) * r, rng.randf_range(1.4, 2.4), false)
	# courtyard: dry fountain, benches, lamps
	var sb := StaticBody3D.new()
	sb.position = Vector3(0, 0.35, -2)
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 2.2
	cy.height = 0.7
	cs.shape = cy
	sb.add_child(cs)
	var fm := CylinderMesh.new()
	fm.top_radius = 2.2
	fm.bottom_radius = 2.3
	fm.height = 0.7
	fm.radial_segments = 32
	mesh_node(sb, fm, stone, Vector3.ZERO)
	blk(root, 0, 0.7, -2, 0.6, 1.6, 0.6, stone, false, 0.1)
	rects.append([-2.3, -4.3, 2.3, 0.3, 0.7])
	for q in [[-7, 6, 0.0], [7, 6, 0.0], [-8, -7, PI / 2], [8, -7, PI / 2]]:
		var bn := Node3D.new()
		bn.position = Vector3(q[0], 0, q[1])
		bn.rotation.y = q[2]
		root.add_child(bn)
		blk(bn, 0, 0.42, 0, 1.8, 0.08, 0.5, crate, false, 0.02)
		blk(bn, 0, 0.5, 0.22, 1.8, 0.45, 0.06, crate, false, 0.02)
		for sx in [-0.8, 0.8]:
			blk(bn, sx, 0, 0, 0.08, 0.42, 0.45, colm(Color(0.1, 0.1, 0.1), 0.5, 0.7), false)
	for q in [[-10, -10], [10, -10], [-10, 10], [10, 10]]:
		lamp(root, q[0], q[1], 1 if q[0] < 0 else -1, 0)
	# houses in the outer zones (with roofs)
	var houses := [[-30, -27, 10, 8, 3.6, {"s": [[0, "d"]], "e": [[0, "w"]]}, brick], [30, -27, 10, 8, 3.6, {"s": [[0, "d"]], "w": [[0, "w"]]}, plaster],
		[0, -34, 10, 7, 4.0, {"s": [[-2, "d"], [3, "w"]]}, plaster2], [-30, 28, 10, 8, 3.6, {"n": [[0, "d"]], "e": [[0, "w"]]}, plaster],
		[32, 27, 8, 8, 3.6, {"n": [[0, "d"]]}, brick], [26, 2, 8, 8, 3.5, {"w": [[0, "d"]], "s": [[0, "w"]]}, plaster2],
		[-27, -3, 8, 6, 3.5, {"e": [[0, "d"]], "n": [[0, "w"]]}, brick]]
	for hh in houses:
		building(root, hh[0], hh[1], hh[2], hh[3], hh[4], hh[5], hh[6], stone)
		roof(root, hh[0], hh[1], hh[2], hh[3], hh[4], roofm)
	# small chapel in the south zone with a bell tower
	building(root, 0, 31, 12, 9, 5.5, {"n": [[0, "d"]], "e": [[0, "w"]], "w": [[0, "w"]]}, plaster, stone)
	roof(root, 0, 31, 12, 9, 5.5, roofm)
	blk(root, -8, 0, 37, 3, 11, 3, plaster, true, 0.1)
	blk(root, -8, 11, 37, 3.4, 0.4, 3.4, stone, false, 0.05)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.2
	cone.height = 3.5
	cone.radial_segments = 4
	mesh_node(root, cone, roofm, Vector3(-8, 13.1, 37), Vector3(0, PI / 4, 0))
	lamp_light(root, Vector3(-8, 9.5, 35.3), Color(1.0, 0.6, 0.3), 2.0, 10.0)
	# fences, cars, trees, crates, lamps
	var fence := pbr("distressed_painted_planks", Color(0.8, 0.75, 0.7), 1.0, 0.0, false)
	for q in [[-20, -20, 8, 0.15], [20, -20, 8, 0.15], [-20, 20, 8, 0.15], [36, 20, 0.15, 6], [-36, -20, 0.15, 6]]:
		blk(root, q[0], 0, q[1], q[2], 1.1, q[3], fence, true, 0.03)
	var fires := []
	car(root, -16, -32, 0.0, Color(0.3, 0.12, 0.1), true, fires)
	car(root, 18, 20, PI / 2, Color(0.2, 0.25, 0.3), false, fires)
	car(root, -20, 4, PI / 2, Color(0.35, 0.33, 0.3), false, fires)
	car(root, 30, -4, 0.0, Color(0.15, 0.15, 0.15), true, fires)
	for t in [[-36, -36], [36, -36], [-36, 36], [16, -24], [-16, 24], [36, -16], [-36, 16], [24, 36]]:
		tree(root, t[0], t[1], rng.randf_range(0.8, 1.15))
	for q in [[-22, -16], [22, -16], [-22, 16], [22, 16], [-34, 0], [34, 0], [0, -22], [0, 22]]:
		lamp(root, q[0], q[1], 0, 1)
	scatter_crates(root, 10, crate, Vector3(0, 0, 5), ZH)
	for i in 8:
		barrel(root, rng.randf_range(-36, 36), rng.randf_range(-36, 36), Color(0.35, 0.3, 0.22))
	root.set_meta("fires", fires)
	zone_spawns()
	return []


# ---------------------------------------------------------------- Fábrica Abandonada
static func build_factory(root: Node3D, buy_names := {}) -> Array:
	rng.seed = 9090
	var conc := pbr("dirty_concrete", Color(0.75, 0.75, 0.78), 0.2)
	var wallm := pbr("concrete_block_wall", Color(0.6, 0.6, 0.62))
	var inner := pbr("painted_concrete", Color(0.7, 0.72, 0.74), 0.35)
	var metal := pbr("rusty_corrugated_iron", Color(0.85, 0.85, 0.85), 0.35, 0.4)
	var rusty := pbr("rusty_corrugated_iron", Color(1.0, 0.8, 0.7), 0.35, 0.4)
	var plate := pbr("green_metal_rust", Color(0.85, 0.9, 0.85), 0.5, 0.5)
	var yellow := pbr("metal_plate", Color(0.85, 0.65, 0.15), 0.5, 0.6)
	var c_red := pbr("corrugated_iron_02", Color(0.6, 0.22, 0.18), 0.38, 0.45)
	var c_blue := pbr("corrugated_iron_02", Color(0.22, 0.35, 0.5), 0.38, 0.45)
	var crate := pbr("brown_planks_04", Color(0.85, 0.75, 0.6), 0.8, 0.0, false)
	ground_plane(root, conc)
	var paint := colm(Color(0.8, 0.65, 0.15), 0.7)
	for z in range(-36, 37, 4):
		flat(root, Vector3(-2.2, 0.015, z), Vector2(0.15, 2.0), paint)
		flat(root, Vector3(2.2, 0.015, z), Vector2(0.15, 2.0), paint)
	zring(root, wallm, inner, buy_names)
	# chimneys + silhouettes outside
	for q in [[-50, -55, 2.5, 30], [-42, -60, 2.0, 24], [55, -48, 3.0, 34], [60, 30, 2.2, 26]]:
		var cm := CylinderMesh.new()
		cm.top_radius = q[2] * 0.8
		cm.bottom_radius = q[2]
		cm.height = q[3]
		mesh_node(root, cm, wallm, Vector3(q[0], q[3] * 0.5, q[1]))
		var red := colm(Color(1.0, 0.1, 0.05), 0.5, 0.0, 6.0)
		var sm := SphereMesh.new()
		sm.radius = 0.25
		sm.height = 0.5
		mesh_node(root, sm, red, Vector3(q[0], q[3] + 0.3, q[1]), Vector3.ZERO, false)
	for i in 30:
		var a := rng.randf() * TAU
		var r := rng.randf_range(60, 130)
		blk(root, cos(a) * r, 0, sin(a) * r, rng.randf_range(12, 30), rng.randf_range(8, 22), rng.randf_range(12, 30), inner, false)
	# north: big factory hall (mystery box inside)
	building(root, 0, -28, 30, 14, 7.0, {"s": [[-10, "d"], [0, "d"], [10, "d"]], "n": [[-8, "w"], [8, "w"]], "e": [[0, "d"]], "w": [[0, "d"]]}, metal, plate)
	roof(root, 0, -28, 30, 14, 7.0, rusty)
	for x in [-10.0, 0.0, 10.0]:
		lamp_light(root, Vector3(x, 6.2, -28), Color(0.85, 0.95, 1.0), 2.4, 14.0)
		blk(root, x, 6.4, -28, 1.4, 0.12, 0.4, colm(Color(0.9, 0.95, 1.0), 0.5, 0.0, 5.0), false)
	for x in [-11.0, 11.0]:
		blk(root, x, 0, -31, 4, 1.2, 2, yellow, true, 0.08)
		blk(root, x, 1.2, -31, 1.2, 1.6, 1.2, plate, true, 0.05)
	blk(root, 3, 0, -32, 8, 1.0, 1.2, plate, true, 0.05)
	# east: storage tanks with pipes
	for t in [[30, 4, 2.6], [22, 6, 2.0]]:
		var sb := StaticBody3D.new()
		sb.position = Vector3(t[0], 2.5, t[1])
		root.add_child(sb)
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = t[2]
		cy.height = 5.0
		cs.shape = cy
		sb.add_child(cs)
		var tm := CylinderMesh.new()
		tm.top_radius = t[2]
		tm.bottom_radius = t[2]
		tm.height = 5.0
		tm.radial_segments = 36
		mesh_node(sb, tm, plate, Vector3.ZERO)
		rects.append([t[0] - t[2], t[1] - t[2], t[0] + t[2], t[1] + t[2], 5.0])
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.25
	pipe.bottom_radius = 0.25
	pipe.height = 26.0
	mesh_node(root, pipe, yellow, Vector3(26, 5.2, -1), Vector3(0, 0, PI / 2))
	for x in [16.0, 24.0, 32.0]:
		blk(root, x, 0, -1, 0.3, 5.0, 0.3, plate, true)
	# west: conveyor line and pallets
	blk(root, -26, 0, 6, 14, 1.0, 1.6, plate, true, 0.05)
	for i in 7:
		blk(root, -32 + i * 2.0, 1.0, 6, 0.9, 0.5, 0.9, crate, false, 0.03)
	# south: warehouse
	building(root, 0, 30, 20, 10, 5.5, {"n": [[-5, "d"], [5, "d"]], "e": [[0, "w"]]}, rusty, plate)
	roof(root, 0, 30, 20, 10, 5.5, metal)
	lamp_light(root, Vector3(0, 4.8, 30), Color(1.0, 0.8, 0.55), 2.0, 12.0)
	# containers + forklift crates in the yard
	blk(root, -8.5, 0, 8.5, 2.6, 2.6, 5.5, c_red, true, 0.1)
	blk(root, 8.5, 0, 8.6, 5.5, 2.6, 2.6, c_blue, true, 0.1)
	blk(root, 30, 0, -26, 2.6, 2.6, 10, c_red, true, 0.1)
	blk(root, -30, 0, 26, 10, 2.6, 2.6, c_blue, true, 0.1)
	blk(root, -30, 2.6, 26, 10, 2.6, 2.6, c_red, true, 0.1)
	blk(root, 30, 0, 26, 2.6, 2.6, 8, c_blue, true, 0.1)
	for q in [[-10, -10], [10, -10], [-10, 10], [10, 10], [-24, -18], [24, -18], [-24, 18], [24, 18], [-34, -4], [34, 6]]:
		lamp(root, q[0], q[1], 1 if q[0] < 0 else -1, 0)
	var fires := []
	car(root, 18, 22, PI / 2, Color(0.2, 0.2, 0.22), true, fires)
	car(root, -20, -20, 0.0, Color(0.5, 0.45, 0.2), false, fires)
	scatter_crates(root, 14, crate, Vector3(0, 0, 5), ZH)
	for i in 14:
		barrel(root, rng.randf_range(-36, 36), rng.randf_range(-36, 36), Color(0.2, 0.3, 0.45) if rng.randf() < 0.5 else Color(0.6, 0.18, 0.12))
	root.set_meta("fires", fires)
	zone_spawns()
	return []


# ================================================================ extra environment props
static func _solid(root: Node3D, x: float, z: float, size: Vector3, rot := 0.0) -> void:
	var sb := StaticBody3D.new()
	sb.position = Vector3(x, size.y * 0.5, z)
	sb.rotation.y = rot
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	root.add_child(sb)
	var r := maxf(size.x, size.z) * 0.5
	rects.append([x - r, z - r, x + r, z + r, size.y])


static func cone(root: Node3D, x: float, z: float) -> void:
	if not is_free(x, z, 0.3):
		return
	var orange := colm(Color(0.95, 0.35, 0.08), 0.6)
	var white := colm(Color(0.92, 0.92, 0.9), 0.5)
	var c := CylinderMesh.new()
	c.top_radius = 0.03
	c.bottom_radius = 0.17
	c.height = 0.7
	c.radial_segments = 14
	mesh_node(root, c, orange, Vector3(x, 0.39, z))
	var band := CylinderMesh.new()
	band.top_radius = 0.085
	band.bottom_radius = 0.11
	band.height = 0.12
	band.radial_segments = 14
	mesh_node(root, band, white, Vector3(x, 0.47, z), Vector3.ZERO, false)
	mesh_node(root, SHP.rbox(Vector3(0.42, 0.04, 0.42), 0.02, 1), orange, Vector3(x, 0.02, z))


static func jersey(root: Node3D, x: float, z: float, rot: float) -> void:
	if not is_free(x, z, 1.1):
		return
	var conc := pbr("concrete_floor_01", Color(0.82, 0.8, 0.76), 0.6)
	var n := Node3D.new()
	n.position = Vector3(x, 0, z)
	n.rotation.y = rot
	root.add_child(n)
	mesh_node(n, SHP.rbox(Vector3(2.0, 0.3, 0.62), 0.05, 2), conc, Vector3(0, 0.15, 0))
	mesh_node(n, SHP.rbox(Vector3(2.0, 0.55, 0.3), 0.08, 2), conc, Vector3(0, 0.55, 0))
	mesh_node(n, SHP.rbox(Vector3(2.0, 0.08, 0.32), 0.03, 1), colm(Color(0.85, 0.75, 0.2), 0.6), Vector3(0, 0.5, 0.0))
	_solid(root, x, z, Vector3(2.0, 0.85, 0.62) if absf(sin(rot)) < 0.5 else Vector3(0.62, 0.85, 2.0))


static func tires(root: Node3D, x: float, z: float) -> void:
	if not is_free(x, z, 0.6):
		return
	var rub := colm(Color(0.05, 0.05, 0.05), 0.85)
	var n := 1 + rng.randi() % 4
	for i in n:
		var t := TorusMesh.new()
		t.inner_radius = 0.2
		t.outer_radius = 0.38
		t.rings = 20
		t.ring_segments = 10
		mesh_node(root, t, rub, Vector3(x + rng.randf_range(-0.05, 0.05), 0.09 + i * 0.18, z + rng.randf_range(-0.05, 0.05)), Vector3(0, rng.randf() * 3, 0)).scale = Vector3(1, 1.0, 1)
	_solid(root, x, z, Vector3(0.75, n * 0.18, 0.75))


static func trash_bags(root: Node3D, x: float, z: float) -> void:
	if not is_free(x, z, 0.7):
		return
	var bag := colm(Color(0.05, 0.06, 0.05), 0.3)
	for i in 3 + rng.randi() % 3:
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.22, 0.32)
		sm.height = sm.radius * 1.6
		sm.radial_segments = 10
		sm.rings = 6
		mesh_node(root, sm, bag, Vector3(x + rng.randf_range(-0.4, 0.4), sm.radius * 0.6, z + rng.randf_range(-0.4, 0.4)), Vector3(rng.randf(), rng.randf() * 3, rng.randf() * 0.4)).scale = Vector3(1, 0.8, 1.1)
	rects.append([x - 0.5, z - 0.5, x + 0.5, z + 0.5, 0.5])


static func dumpster(root: Node3D, x: float, z: float, rot: float) -> void:
	if not is_free(x, z, 1.3):
		return
	var m := pbr("green_metal_rust", Color(0.75, 0.85, 0.75), 0.8, 0.5, false)
	var n := Node3D.new()
	n.position = Vector3(x, 0, z)
	n.rotation.y = rot
	root.add_child(n)
	mesh_node(n, SHP.rbox(Vector3(1.9, 1.15, 1.1), 0.05, 2), m, Vector3(0, 0.68, 0))
	mesh_node(n, SHP.rbox(Vector3(1.95, 0.06, 1.15), 0.02, 1), colm(Color(0.08, 0.08, 0.08), 0.6), Vector3(0, 1.28, -0.05), Vector3(-0.12, 0, 0))
	for sx in [-0.8, 0.8]:
		for sz in [-0.45, 0.45]:
			var w := CylinderMesh.new()
			w.top_radius = 0.06
			w.bottom_radius = 0.06
			w.height = 0.05
			mesh_node(n, w, colm(Color(0.05, 0.05, 0.05), 0.8), Vector3(sx, 0.06, sz), Vector3(PI / 2, 0, 0), false)
	_solid(root, x, z, Vector3(1.9, 1.3, 1.1) if absf(sin(rot)) < 0.5 else Vector3(1.1, 1.3, 1.9))


static func pallet(root: Node3D, x: float, z: float, stack: int) -> void:
	if not is_free(x, z, 0.8):
		return
	var wood := pbr("brown_planks_04", Color(0.9, 0.82, 0.68), 1.4, 0.0, false)
	var r := rng.randf() * 0.5
	for k in stack:
		var n := Node3D.new()
		n.position = Vector3(x, k * 0.15, z)
		n.rotation.y = r + rng.randf_range(-0.08, 0.08)
		root.add_child(n)
		for i in 5:
			mesh_node(n, SHP.rbox(Vector3(1.2, 0.025, 0.16), 0.006, 1), wood, Vector3(0, 0.135, -0.46 + i * 0.23), Vector3.ZERO, k == stack - 1)
		for i in 3:
			mesh_node(n, SHP.rbox(Vector3(0.1, 0.1, 1.0), 0.01, 1), wood, Vector3(-0.52 + i * 0.52, 0.06, 0), Vector3.ZERO, false)
	_solid(root, x, z, Vector3(1.2, stack * 0.15, 1.2))


static func utility_pole(root: Node3D, x: float, z: float, along_x: bool) -> Vector3:
	var wood := pbr("bark_brown_02", Color(0.55, 0.45, 0.38), 1.6, 0.0, false)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.11
	cm.bottom_radius = 0.15
	cm.height = 8.0
	cm.radial_segments = 10
	mesh_node(root, cm, wood, Vector3(x, 4.0, z))
	var arm := SHP.rbox(Vector3(0.14, 0.12, 1.8) if along_x else Vector3(1.8, 0.12, 0.14), 0.02, 1)
	mesh_node(root, arm, wood, Vector3(x, 7.4, z))
	var ins := colm(Color(0.85, 0.85, 0.82), 0.3)
	for o in [-0.75, 0.0, 0.75]:
		var c := CylinderMesh.new()
		c.top_radius = 0.035
		c.bottom_radius = 0.05
		c.height = 0.14
		mesh_node(root, c, ins, Vector3(x, 7.53, z) + (Vector3(0, 0, o) if along_x else Vector3(o, 0, 0)), Vector3.ZERO, false)
	collider_only(root, Vector3(x, 4.0, z), Vector3(0.3, 8.0, 0.3))
	return Vector3(x, 7.6, z)


## Sagging power lines between consecutive poles.
static func wires(root: Node3D, tops: Array, along_x: bool) -> void:
	var m := colm(Color(0.04, 0.04, 0.04), 0.6)
	for i in tops.size() - 1:
		for o in [-0.75, 0.0, 0.75]:
			var off := Vector3(0, 0, o) if along_x else Vector3(o, 0, 0)
			var a: Vector3 = tops[i] + off
			var b: Vector3 = tops[i + 1] + off
			var prev := a
			for k in range(1, 9):
				var t := k / 8.0
				var p := a.lerp(b, t) - Vector3(0, sin(t * PI) * 0.9, 0)
				var d := p - prev
				var cm := CylinderMesh.new()
				cm.top_radius = 0.012
				cm.bottom_radius = 0.012
				cm.height = d.length()
				cm.radial_segments = 4
				var mi := mesh_node(root, cm, m, (p + prev) * 0.5, Vector3.ZERO, false)
				mi.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
				prev = p


static func sign_post(root: Node3D, x: float, z: float, rot: float, col: Color) -> void:
	if not is_free(x, z, 0.3):
		return
	var pole := colm(Color(0.5, 0.52, 0.55), 0.4, 0.8)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.035
	cm.height = 2.6
	mesh_node(root, cm, pole, Vector3(x, 1.3, z))
	var n := Node3D.new()
	n.position = Vector3(x, 2.35, z)
	n.rotation.y = rot
	root.add_child(n)
	mesh_node(n, SHP.rbox(Vector3(0.62, 0.62, 0.03), 0.02, 1), colm(Color(0.9, 0.9, 0.88), 0.4), Vector3(0, 0, 0.0))
	mesh_node(n, SHP.rbox(Vector3(0.52, 0.52, 0.035), 0.02, 1), colm(col, 0.4), Vector3(0, 0, 0.0), Vector3.ZERO, false)
	collider_only(root, Vector3(x, 1.3, z), Vector3(0.1, 2.6, 0.1))


static func rubble_pile(root: Node3D, x: float, z: float, s: float) -> void:
	if not is_free(x, z, s):
		return
	var m := pbr("concrete_debris", Color(0.85, 0.83, 0.8), 0.7)
	var brick := pbr("brick_wall_001", Color(0.8, 0.75, 0.7), 1.0, 0.0, false)
	for i in 10:
		var bx := Vector3(rng.randf_range(0.2, 0.6), rng.randf_range(0.12, 0.35), rng.randf_range(0.2, 0.6)) * s
		mesh_node(root, SHP.rbox(bx, 0.03, 1), m if rng.randf() < 0.7 else brick, Vector3(x + rng.randf_range(-0.8, 0.8) * s, bx.y * 0.4 + rng.randf() * 0.15 * s, z + rng.randf_range(-0.8, 0.8) * s),
			Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * 3, rng.randf_range(-0.4, 0.4)))
	var sm := SphereMesh.new()
	sm.radius = 0.9 * s
	sm.height = 0.6 * s
	sm.is_hemisphere = true
	mesh_node(root, sm, m, Vector3(x, 0, z), Vector3(0, rng.randf() * 3, 0)).scale = Vector3(1.2, 1, 1)
	_solid(root, x, z, Vector3(1.4 * s, 0.4 * s, 1.4 * s))


static func clay_pots(root: Node3D, x: float, z: float) -> void:
	if not is_free(x, z, 0.6):
		return
	var clay := pbr("clay_plaster", Color(0.75, 0.45, 0.3), 1.5, 0.0, false)
	for i in 2 + rng.randi() % 3:
		var sm := SphereMesh.new()
		var r := rng.randf_range(0.18, 0.3)
		sm.radius = r
		sm.height = r * 2.2
		sm.radial_segments = 14
		var px := x + rng.randf_range(-0.4, 0.4)
		var pz := z + rng.randf_range(-0.4, 0.4)
		mesh_node(root, sm, clay, Vector3(px, r * 1.1, pz))
		var nk := CylinderMesh.new()
		nk.top_radius = r * 0.45
		nk.bottom_radius = r * 0.35
		nk.height = r * 0.5
		mesh_node(root, nk, clay, Vector3(px, r * 2.3, pz), Vector3.ZERO, false)
	rects.append([x - 0.5, z - 0.5, x + 0.5, z + 0.5, 0.6])


static func hay_bale(root: Node3D, x: float, z: float) -> void:
	if not is_free(x, z, 0.8):
		return
	var hay := pbr("sparse_grass", Color(1.3, 1.1, 0.6), 2.0, 0.0, false)
	var c := CylinderMesh.new()
	c.top_radius = 0.6
	c.bottom_radius = 0.6
	c.height = 1.1
	c.radial_segments = 20
	mesh_node(root, c, hay, Vector3(x, 0.6, z), Vector3(PI / 2, rng.randf() * 3, 0))
	_solid(root, x, z, Vector3(1.2, 1.2, 1.2))


static func gas_bottles(root: Node3D, x: float, z: float) -> void:
	if not is_free(x, z, 0.5):
		return
	var cols := [Color(0.7, 0.15, 0.1), Color(0.2, 0.35, 0.6), Color(0.85, 0.8, 0.75)]
	for i in 3:
		var c := CylinderMesh.new()
		c.top_radius = 0.12
		c.bottom_radius = 0.12
		c.height = 1.3
		mesh_node(root, c, colm(cols[i % 3], 0.4, 0.5), Vector3(x + (i - 1) * 0.26, 0.65, z))
		var cap := SphereMesh.new()
		cap.radius = 0.12
		cap.height = 0.24
		mesh_node(root, cap, colm(cols[i % 3], 0.4, 0.5), Vector3(x + (i - 1) * 0.26, 1.3, z), Vector3.ZERO, false)
	_solid(root, x, z, Vector3(0.8, 1.4, 0.3))


## Grass tufts: crossed alpha-tested cards in one MultiMesh (one draw call).
static var _grass_mat: StandardMaterial3D
static func grass_tufts(root: Node3D, center: Vector3, half: Vector2, n: int, tint: Color) -> void:
	if _grass_mat == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var r := RandomNumberGenerator.new()
		r.seed = 5
		for b in 22:
			var x0 := r.randi_range(4, 60)
			var hgt := r.randi_range(28, 62)
			var lean := r.randf_range(-0.35, 0.35)
			for y in hgt:
				var w := maxi(1, int(3.0 * (1.0 - float(y) / hgt)))
				var cx := x0 + int(lean * y)
				for dx in w:
					var px := clampi(cx + dx, 0, 63)
					var k := float(y) / hgt
					img.set_pixel(px, 63 - y, Color(0.2 + 0.22 * k, 0.3 + 0.22 * k, 0.1 + 0.06 * k, 1.0))
		img.generate_mipmaps()
		_grass_mat = StandardMaterial3D.new()
		_grass_mat.albedo_texture = ImageTexture.create_from_image(img)
		_grass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_grass_mat.alpha_scissor_threshold = 0.4
		_grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_grass_mat.vertex_color_use_as_albedo = true
		_grass_mat.roughness = 0.9
		_grass_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := k * PI / 2.0
		var dx := Vector3(cos(a), 0, sin(a)) * 0.35
		var v := [-dx, dx, dx + Vector3(0, 0.55, 0), -dx + Vector3(0, 0.55, 0)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
	var mesh := st.commit()
	var xs := []
	for i in n * 3:
		if xs.size() >= n:
			break
		var x := center.x + rng.randf_range(-half.x, half.x)
		var z := center.z + rng.randf_range(-half.y, half.y)
		if not is_free(x, z, 0.2):
			continue
		var s := rng.randf_range(0.6, 1.3)
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(x, 0, z)))
	# one MultiMesh per 16 m cell: off-screen and far chunks are culled individually
	var cells := {}
	for t in xs:
		var key := Vector2i(int(floor(t.origin.x / 16.0)), int(floor(t.origin.z / 16.0)))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(t)
	for key in cells:
		var list: Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_color(i, tint * rng.randf_range(0.8, 1.15))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _grass_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 48.0
		mmi.visibility_range_end_margin = 8.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mmi)


## Per-map dressing, placed after the main layout so it only fills free space.
static func dress(root: Node3D, i: int) -> void:
	match i:
		0:
			for q in [[6.2, -26], [-6.2, -6], [6.2, 20], [-6.2, 32], [20, -15], [-24, -18], [36, -14.5], [-40, -19.5]]:
				cone(root, q[0], q[1])
				cone(root, q[0] + 0.7, q[1] + 0.4)
			for q in [[3, -11, 0.0], [-3, 11, 0.0], [10, -20, PI / 2], [-26, 2, 0.0], [40, 28, PI / 2], [-38, -36, 0.0]]:
				jersey(root, q[0], q[1], q[2])
			for q in [[-24, -24, 0.0], [24, -32, PI / 2], [-36, 24, 0.0], [38, 26, 0.0], [10, 40, PI / 2]]:
				dumpster(root, q[0], q[1], q[2])
				trash_bags(root, q[0] + 1.8, q[1] + 0.6)
			for q in [[-20, 36], [30, -40], [-48, -30], [48, 40], [16, -40], [-10, 46]]:
				tires(root, q[0], q[1])
			for q in [[-34, 4], [34, -4], [-14, -36], [22, 36], [-46, 14], [46, -28]]:
				rubble_pile(root, q[0], q[1], rng.randf_range(0.8, 1.3))
			for q in [[5.4, -42, PI], [-5.4, 18, 0.0], [-14, -12.6, PI / 2], [26, -21.4, -PI / 2]]:
				sign_post(root, q[0], q[1], q[2], [Color(0.75, 0.1, 0.1), Color(0.15, 0.3, 0.7)][rng.randi() % 2])
			var tops := []
			for z in range(-50, 51, 14):
				tops.append(utility_pole(root, -6.9, z, true))
			wires(root, tops, true)
			grass_tufts(root, Vector3(0, 0, 0), Vector2(4.2, 4.2), 120, Color(0.75, 0.85, 0.55))
			grass_tufts(root, Vector3(0, 0, 0), Vector2(56, 56), 700, Color(0.8, 0.8, 0.55))
		1:
			for q in [[-12, -22], [14, 20], [-20, 22], [22, -22], [-40, -8], [40, 10], [8, -36], [-8, 36]]:
				clay_pots(root, q[0], q[1])
			for q in [[-26, -12], [26, 12], [-36, 34], [36, -36], [10, 28]]:
				hay_bale(root, q[0], q[1])
			for q in [[-6, -30, 2], [6, -30, 3], [-50, 20, 2], [50, -14, 1], [30, 44, 2]]:
				pallet(root, q[0], q[1], q[2])
			for q in [[-28, 8], [28, -8], [-10, -50], [44, 36]]:
				tires(root, q[0], q[1])
			var tops := []
			for x in range(-36, 37, 12):
				tops.append(utility_pole(root, x, 3.8, false))
			wires(root, tops, false)
			grass_tufts(root, Vector3.ZERO, Vector2(56, 56), 500, Color(0.95, 0.85, 0.5))
		2:
			for q in [[-6, 30], [6, 30], [-24, -40], [30, 0], [-40, -30], [40, -40]]:
				pallet(root, q[0], q[1], 1 + rng.randi() % 4)
			for q in [[4, -24, 0.0], [-10, -26, 0.0], [26, -2, PI / 2], [-28, 22, 0.0], [12, 26, PI / 2]]:
				jersey(root, q[0], q[1], q[2])
			for q in [[2, -30], [-16, -44], [32, -46], [-44, 0], [44, 30]]:
				cone(root, q[0], q[1])
			for q in [[-20, 20], [22, 30], [-50, -44]]:
				gas_bottles(root, q[0], q[1])
			for q in [[-30, -8], [30, 40]]:
				dumpster(root, q[0], q[1], 0.0)
		3:
			for q in [[-24, -18], [24, -18], [-24, 18], [16, 30], [-34, -34], [34, 34]]:
				trash_bags(root, q[0], q[1])
			for q in [[-16, -16], [-30, 38], [30, -36]]:
				hay_bale(root, q[0], q[1])
			for q in [[-6, -24], [20, -30], [-20, 30], [34, -2]]:
				rubble_pile(root, q[0], q[1], rng.randf_range(0.8, 1.1))
			for q in [[-35, -24], [35, 22], [-14, 36]]:
				tires(root, q[0], q[1])
			var tops := []
			for z in [-34, -22, -6, 6, 22, 34]:
				tops.append(utility_pole(root, 4.6, z, true))
			wires(root, tops, true)
			grass_tufts(root, Vector3(-26, 0, -26), Vector2(11, 10), 160, Color(0.6, 0.65, 0.4))
			grass_tufts(root, Vector3(26, 0, -26), Vector2(11, 10), 160, Color(0.6, 0.65, 0.4))
			grass_tufts(root, Vector3(-26, 0, 26), Vector2(11, 10), 160, Color(0.6, 0.65, 0.4))
			grass_tufts(root, Vector3(26, 0, 26), Vector2(11, 10), 160, Color(0.6, 0.65, 0.4))
		4:
			for q in [[-34, -20, 3], [34, -20, 2], [-18, 30, 4], [18, 34, 2], [-34, 20, 1], [26, -6, 2]]:
				pallet(root, q[0], q[1], q[2])
			for q in [[-24, -16], [24, 16], [-12, -36], [12, 18]]:
				gas_bottles(root, q[0], q[1])
			for q in [[-34, 34, 0.0], [34, -34, PI / 2], [-20, -6, 0.0]]:
				dumpster(root, q[0], q[1], q[2])
			for q in [[-6, 34], [30, 30], [-30, -34]]:
				tires(root, q[0], q[1])
			for q in [[16, -20], [-16, 20]]:
				rubble_pile(root, q[0], q[1], 1.0)


# ================================================================ ground detail decals
static var _ao_tex: Texture2D
static var _puddle_alb: Texture2D
static var _puddle_orm: Texture2D


## Soft dark blob under an object: fake contact shadow / ambient occlusion (works on every quality).
static func ao_decal(parent: Node3D, x: float, z: float, w: float, d: float, rot := 0.0) -> void:
	if _ao_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_ao_tex = t
	var dc := Decal.new()
	dc.texture_albedo = _ao_tex
	dc.size = Vector3(w * 1.45 + 0.4, 0.6, d * 1.45 + 0.4)
	dc.cull_mask = 1
	dc.distance_fade_enabled = true
	dc.distance_fade_begin = 45.0
	dc.distance_fade_length = 10.0
	dc.position = Vector3(x, 0.05, z)
	dc.rotation.y = rot
	parent.add_child(dc)


## Rain puddle: darker albedo and almost zero roughness, so it mirrors the sky / lights.
static func puddle(parent: Node3D, x: float, z: float, s: float) -> void:
	if _puddle_alb == null:
		var n := FastNoiseLite.new()
		n.seed = 77
		n.frequency = 0.035
		var alb := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		var orm := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			for xx in 128:
				var dx := (xx - 64.0) / 64.0
				var dy := (y - 64.0) / 64.0
				var edge := 1.0 - sqrt(dx * dx + dy * dy)
				var v := clampf((n.get_noise_2d(xx, y) * 0.6 + edge - 0.25) * 3.0, 0.0, 1.0)
				alb.set_pixel(xx, y, Color(0.02, 0.025, 0.03, v * 0.55))
				orm.set_pixel(xx, y, Color(1.0, lerpf(0.9, 0.04, v), 0.0, 1.0))
		alb.generate_mipmaps()
		orm.generate_mipmaps()
		_puddle_alb = ImageTexture.create_from_image(alb)
		_puddle_orm = ImageTexture.create_from_image(orm)
	var dc := Decal.new()
	dc.texture_albedo = _puddle_alb
	dc.texture_orm = _puddle_orm
	dc.size = Vector3(3.0 * s, 0.4, 2.2 * s)
	dc.cull_mask = 1
	dc.distance_fade_enabled = true
	dc.distance_fade_begin = 50.0
	dc.distance_fade_length = 10.0
	dc.position = Vector3(x, 0.02, z)
	dc.rotation.y = rng.randf() * TAU
	parent.add_child(dc)


static func puddles_on(root: Node3D, n: int, area: Rect2) -> void:
	for i in n:
		var x := rng.randf_range(area.position.x, area.end.x)
		var z := rng.randf_range(area.position.y, area.end.y)
		if is_free(x, z, 1.2):
			puddle(root, x, z, rng.randf_range(0.6, 1.4))


## Contact shadows under every small solid already placed (crates, cars, barrels, props...).
static func contact_shadows(root: Node3D) -> void:
	for q in rects:
		var w: float = q[2] - q[0]
		var d: float = q[3] - q[1]
		if q[4] <= 0.05 or w > 13.5 or d > 13.5 or (w < 0.25 and d < 0.25):
			continue
		ao_decal(root, (q[0] + q[2]) * 0.5, (q[1] + q[3]) * 0.5, w, d)


# ================================================================ Base Ártica (zombies)
static func quonset(root: Node3D, cx: float, cz: float, length: float, r: float, along_x: bool, mat: Material, door_mat: Material) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 28
	var mi := mesh_node(root, cm, mat, Vector3(cx, 0.0, cz), Vector3(0, 0 if along_x else PI / 2, PI / 2))
	mi.scale = Vector3(1, 1, 1)
	var snowcap := SphereMesh.new()
	snowcap.radius = r * 1.02
	snowcap.height = r * 0.5
	snowcap.is_hemisphere = true
	var cap := mesh_node(root, snowcap, pbr("snow_02", Color.WHITE, 0.6, 0.0, false), Vector3(cx, r * 0.78, cz), Vector3.ZERO, false)
	cap.scale = Vector3(length / (r * 2.0) if along_x else 0.55, 0.6, 0.55 if along_x else length / (r * 2.0))
	for sd in [-1.0, 1.0]:
		var p := Vector3(cx + (sd * length * 0.5 if along_x else 0.0), 0, cz + (0.0 if along_x else sd * length * 0.5))
		var wall := CylinderMesh.new()
		wall.top_radius = r * 0.98
		wall.bottom_radius = r * 0.98
		wall.height = 0.12
		wall.radial_segments = 28
		mesh_node(root, wall, door_mat, p, Vector3(0, 0 if along_x else PI / 2, PI / 2))
	var sx := length if along_x else r * 2.0
	var sz := r * 2.0 if along_x else length
	collider_only(root, Vector3(cx, r * 0.5, cz), Vector3(sx, r, sz))


static func build_arctic(root: Node3D, buy_names := {}) -> Array:
	rng.seed = 5151
	var snow := pbr("snow_02", Color(0.95, 0.97, 1.02), 0.22)
	var wallm := pbr("concrete_block_wall", Color(0.72, 0.74, 0.78))
	var inner := pbr("painted_concrete", Color(0.75, 0.78, 0.82), 0.35)
	var hut := pbr("corrugated_iron_02", Color(0.5, 0.56, 0.5), 0.4, 0.4)
	var plate := pbr("metal_plate", Color(0.6, 0.62, 0.65), 0.4, 0.6)
	var c_red := pbr("corrugated_iron_02", Color(0.7, 0.25, 0.2), 0.38, 0.45)
	var c_grey := pbr("corrugated_iron_02", Color(0.55, 0.57, 0.58), 0.38, 0.45)
	var crate := pbr("brown_planks_04", Color(0.85, 0.78, 0.68), 0.8, 0.0, false)
	var white := pbr("snow_02", Color.WHITE, 0.5)
	ground_plane(root, snow)
	zring(root, wallm, inner, buy_names)
	# skyline: snowy mountains + forest
	for i in 22:
		var a := rng.randf() * TAU
		var r := rng.randf_range(90, 150)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = rng.randf_range(25, 45)
		cm.height = rng.randf_range(25, 55)
		cm.radial_segments = 7
		mesh_node(root, cm, white, Vector3(cos(a) * r, cm.height * 0.45, sin(a) * r), Vector3(0, rng.randf() * 3, 0), false)
	for i in 50:
		var a := rng.randf() * TAU
		pine(root, cos(a) * rng.randf_range(48, 85), sin(a) * rng.randf_range(48, 85), rng.randf_range(1.3, 2.2), true)
	# courtyard: heli pad + supply crates
	disc(root, Vector3(0, 0.0, -3), 4.5, 0.04, pbr("concrete_floor_01", Color(0.6, 0.62, 0.66), 0.3))
	var hm := colm(Color(0.9, 0.85, 0.2), 0.6)
	blk(root, -1.0, 0.02, -3, 0.35, 0.02, 3.0, hm, false)
	blk(root, 1.0, 0.02, -3, 0.35, 0.02, 3.0, hm, false)
	blk(root, 0, 0.02, -3, 2.0, 0.02, 0.35, hm, false)
	blk(root, -8, 0, 8, 1.4, 1.4, 1.4, crate, true, 0.06)
	blk(root, 8.5, 0, 7.5, 1.2, 1.2, 1.2, crate, true, 0.06)
	# huts in the outer zones
	quonset(root, -28, -28, 12.0, 3.0, true, hut, plate)
	quonset(root, 28, -28, 12.0, 3.0, true, hut, plate)
	quonset(root, -30, 30, 12.0, 3.0, true, hut, plate)
	quonset(root, 28, 4, 9.0, 2.6, false, hut, plate)
	quonset(root, -28, -2, 9.0, 2.6, false, hut, plate)
	# radar dome on a tower (north) + antenna mast (south)
	blk(root, 0, 0, -32, 4, 6, 4, plate, true, 0.1)
	var dome := SphereMesh.new()
	dome.radius = 3.4
	dome.height = 6.8
	mesh_node(root, dome, colm(Color(0.92, 0.93, 0.95), 0.4), Vector3(0, 8.5, -32))
	for k in 4:
		blk(root, 0, 0, 30 + k * 0.01, 0.25, 16.0 - k * 0.01, 0.25, plate, false)
	blk(root, 0, 0, 30, 0.6, 16.0, 0.6, colm(Color(0.7, 0.2, 0.15), 0.6), true)
	var beacon := SphereMesh.new()
	beacon.radius = 0.25
	beacon.height = 0.5
	mesh_node(root, beacon, colm(Color(1.0, 0.1, 0.05), 0.5, 0.0, 6.0), Vector3(0, 16.3, 30), Vector3.ZERO, false)
	lamp_light(root, Vector3(0, 16.0, 30), Color(1.0, 0.15, 0.1), 1.5, 12.0)
	# containers with snow caps, fuel tank, snowcat
	for q in [[30, -16, 0], [-30, 16, 0], [16, 34, 1], [-18, -34, 1]]:
		var along: bool = q[2] == 1
		blk(root, q[0], 0, q[1], 6.0 if along else 2.6, 2.6, 2.6 if along else 6.0, c_red if q[0] > 0 else c_grey, true, 0.1)
		blk(root, q[0], 2.6, q[1], 5.8 if along else 2.4, 0.1, 2.4 if along else 5.8, white, false)
	var sb := StaticBody3D.new()
	sb.position = Vector3(34, 2.0, -4)
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 2.0
	cy.height = 4.0
	cs.shape = cy
	sb.add_child(cs)
	var tm := CylinderMesh.new()
	tm.top_radius = 2.0
	tm.bottom_radius = 2.0
	tm.height = 4.0
	tm.radial_segments = 32
	mesh_node(sb, tm, plate, Vector3.ZERO)
	rects.append([32.0, -6.0, 36.0, -2.0, 4.0])
	blk(root, -16, 0, 22, 4.0, 1.2, 2.2, colm(Color(0.85, 0.45, 0.1), 0.5, 0.3), true, 0.15)
	blk(root, -16.6, 1.2, 22, 2.2, 1.2, 2.0, colm(Color(0.85, 0.45, 0.1), 0.5, 0.3), true, 0.2)
	for sd in [-1.0, 1.0]:
		blk(root, -16, 0, 22 + sd * 1.2, 4.2, 0.6, 0.5, colm(Color(0.08, 0.08, 0.08), 0.8), false, 0.15)
	for q in [[-10, -10], [10, -10], [-10, 10], [10, 10], [-22, -18], [22, -18], [-22, 18], [22, 18]]:
		lamp(root, q[0], q[1], 1 if q[0] < 0 else -1, 0)
	for i in 40:
		var x := rng.randf_range(-36, 36)
		var z := rng.randf_range(-36, 36)
		if not is_free(x, z, 1.2):
			continue
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.6, 1.4)
		sm.height = sm.radius * 0.7
		mesh_node(root, sm, white, Vector3(x, -0.05, z), Vector3(0, rng.randf() * 3, 0), false).scale = Vector3(1.8, 0.6, 1.2)
	scatter_crates(root, 10, crate, Vector3(0, 0, 5), ZH)
	root.set_meta("fires", [])
	zone_spawns()
	return []


# ================================================================ Cementerio (zombies)
static func headstones(root: Node3D, x0: float, z0: float, cols: int, rows: int, stone: Material) -> void:
	for r in rows:
		var zz := z0 + r * 2.6
		var row_has := false
		for c in cols:
			var xx := x0 + c * 1.8 + rng.randf_range(-0.2, 0.2)
			if not is_free(xx, zz, 0.5):
				continue
			row_has = true
			var kind := rng.randi() % 3
			var tilt := Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.15, 0.15), rng.randf_range(-0.1, 0.1))
			var n := Node3D.new()
			n.position = Vector3(xx, 0, zz)
			n.rotation = tilt
			root.add_child(n)
			if kind == 0:
				mesh_node(n, SHP.rbox(Vector3(0.7, 0.9, 0.18), 0.06, 2), stone, Vector3(0, 0.45, 0))
				var top := CylinderMesh.new()
				top.top_radius = 0.35
				top.bottom_radius = 0.35
				top.height = 0.18
				mesh_node(n, top, stone, Vector3(0, 0.9, 0), Vector3(PI / 2, 0, 0))
			elif kind == 1:
				mesh_node(n, SHP.rbox(Vector3(0.16, 1.3, 0.16), 0.03, 1), stone, Vector3(0, 0.65, 0))
				mesh_node(n, SHP.rbox(Vector3(0.7, 0.16, 0.16), 0.03, 1), stone, Vector3(0, 0.95, 0))
			else:
				mesh_node(n, SHP.rbox(Vector3(0.8, 0.6, 0.22), 0.05, 2), stone, Vector3(0, 0.3, 0))
			mesh_node(n, SHP.rbox(Vector3(0.9, 0.12, 1.9), 0.04, 1), stone, Vector3(0, 0.06, 0.9), Vector3.ZERO, false)
		if row_has:
			collider_only(root, Vector3(x0 + (cols - 1) * 0.9, 0.5, zz), Vector3(cols * 1.8, 1.0, 0.3))


static func dead_tree(root: Node3D, x: float, z: float, s: float) -> void:
	if absf(x) < H and absf(z) < H and not is_free(x, z, 0.6):
		return
	var bark := pbr("bark_brown_02", Color(0.45, 0.4, 0.36), 1.2, 0.0, false)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12 * s
	trunk.bottom_radius = 0.28 * s
	trunk.height = 4.0 * s
	mesh_node(root, trunk, bark, Vector3(x, 2.0 * s, z), Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08)))
	for k in 6:
		var a := rng.randf() * TAU
		var y := rng.randf_range(2.0, 3.8) * s
		var br := CylinderMesh.new()
		br.top_radius = 0.02 * s
		br.bottom_radius = 0.09 * s
		br.height = rng.randf_range(1.2, 2.2) * s
		var dir := Vector3(cos(a), rng.randf_range(0.4, 1.0), sin(a)).normalized()
		var mi := mesh_node(root, br, bark, Vector3(x, y, z) + dir * br.height * 0.5, Vector3.ZERO)
		mi.basis = Basis(Quaternion(Vector3.UP, dir))
	collider_only(root, Vector3(x, 2.0 * s, z), Vector3(0.5 * s, 4.0 * s, 0.5 * s))


static func iron_fence(root: Node3D, a: Vector3, b: Vector3) -> void:
	var m := colm(Color(0.06, 0.06, 0.06), 0.5, 0.7)
	var d := b - a
	var n := int(d.length() / 0.18)
	var bar := CylinderMesh.new()
	bar.top_radius = 0.015
	bar.bottom_radius = 0.015
	bar.height = 1.5
	bar.radial_segments = 5
	for i in n:
		mesh_node(root, bar, m, a + d * (float(i) / n) + Vector3(0, 0.75, 0), Vector3.ZERO, false)
	for y in [0.2, 1.35]:
		var rail := CylinderMesh.new()
		rail.top_radius = 0.02
		rail.bottom_radius = 0.02
		rail.height = d.length()
		var mi := mesh_node(root, rail, m, (a + b) * 0.5 + Vector3(0, y, 0), Vector3.ZERO, false)
		mi.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	collider_only(root, (a + b) * 0.5 + Vector3(0, 0.75, 0), Vector3(maxf(absf(d.x), 0.1), 1.5, maxf(absf(d.z), 0.1)))


static func build_cemetery(root: Node3D, buy_names := {}) -> Array:
	rng.seed = 6666
	var dirt := pbr("brown_mud_leaves_01", Color(0.75, 0.72, 0.68), 0.22)
	var grassm := pbr("sparse_grass", Color(0.55, 0.6, 0.5), 0.3)
	var wallm := pbr("brick_wall_001", Color(0.6, 0.58, 0.56))
	var inner := pbr("chipped_concrete", Color(0.55, 0.55, 0.53), 0.4)
	var stone := pbr("chipped_concrete", Color(0.62, 0.62, 0.6), 1.2, 0.0, false)
	var stone2 := pbr("concrete_block_wall", Color(0.55, 0.55, 0.52))
	var roofm := pbr("clay_roof_tiles_02", Color(0.55, 0.5, 0.5), 0.5)
	var path := pbr("concrete_debris", Color(0.6, 0.58, 0.55), 0.3)
	ground_plane(root, dirt)
	flat(root, Vector3(0, 0.01, 0), Vector2(4, 80), path)
	flat(root, Vector3(0, 0.012, 0), Vector2(80, 4), path)
	for q in [[-26, -26], [26, -26], [-26, 26], [26, 26]]:
		flat(root, Vector3(q[0], 0.008, q[1]), Vector2(24, 22), grassm)
	zring(root, wallm, inner, buy_names)
	for i in 45:
		var a := rng.randf() * TAU
		dead_tree(root, cos(a) * rng.randf_range(46, 80), sin(a) * rng.randf_range(46, 80), rng.randf_range(1.2, 2.0))
	# courtyard: angel statue + benches + lanterns
	blk(root, 0, 0, -2, 2.4, 0.8, 2.4, stone2, true, 0.08)
	blk(root, 0, 0.8, -2, 0.8, 2.2, 0.8, stone2, true, 0.1)
	var head := SphereMesh.new()
	head.radius = 0.35
	head.height = 0.7
	mesh_node(root, head, stone, Vector3(0, 3.35, -2))
	for sd in [-1.0, 1.0]:
		mesh_node(root, SHP.rbox(Vector3(1.4, 0.9, 0.08), 0.04, 2), stone, Vector3(sd * 0.8, 2.8, -1.9), Vector3(0, sd * 0.4, sd * 0.5))
	# graves in every outer zone
	headstones(root, -36, -36, 8, 4, stone)
	headstones(root, 22, -36, 8, 4, stone)
	headstones(root, -36, 18, 7, 4, stone)
	headstones(root, 20, 20, 5, 3, stone)
	headstones(root, -34, -8, 4, 2, stone)
	headstones(root, 18, -8, 4, 2, stone)
	# mausoleums with roofs and a chapel in the south
	for m in [[-28, -18, 6, 5], [28, -18, 6, 5], [-24, 30, 6, 6]]:
		building(root, m[0], m[1], m[2], m[3], 3.6, {"s": [[0, "d"]]} if m[1] < 0 else {"n": [[0, "d"]]}, stone2, stone)
		roof(root, m[0], m[1], m[2], m[3], 3.6, roofm)
		lamp_light(root, Vector3(m[0], 1.2, m[1]), Color(1.0, 0.55, 0.25), 1.4, 5.0)
	building(root, 2, 31, 12, 9, 6.0, {"n": [[0, "d"]], "e": [[0, "w"]], "w": [[0, "w"]]}, stone2, stone)
	roof(root, 2, 31, 12, 9, 6.0, roofm)
	blk(root, 10, 0, 36, 3, 12, 3, stone2, true, 0.1)
	var spire := CylinderMesh.new()
	spire.top_radius = 0.0
	spire.bottom_radius = 2.2
	spire.height = 4.0
	spire.radial_segments = 4
	mesh_node(root, spire, roofm, Vector3(10, 14.0, 36), Vector3(0, PI / 4, 0))
	lamp_light(root, Vector3(2, 4.0, 31), Color(1.0, 0.6, 0.3), 2.2, 11.0)
	# wrought-iron fences around grave plots
	iron_fence(root, Vector3(-38, 0, -16), Vector3(-20, 0, -16))
	iron_fence(root, Vector3(20, 0, -16), Vector3(38, 0, -16))
	iron_fence(root, Vector3(-38, 0, 16), Vector3(-22, 0, 16))
	# candle lanterns on posts
	for q in [[-10, -10], [10, -10], [-10, 10], [10, 10], [-20, -26], [20, -26], [-16, 24], [32, 30], [-34, 4], [34, -2]]:
		if not is_free(q[0], q[1], 0.3):
			continue
		blk(root, q[0], 0, q[1], 0.15, 1.6, 0.15, colm(Color(0.06, 0.06, 0.06), 0.5, 0.7), true)
		blk(root, q[0], 1.6, q[1], 0.32, 0.4, 0.32, colm(Color(1.0, 0.65, 0.3), 0.5, 0.0, 3.0), false, 0.05)
		lamp_light(root, Vector3(q[0], 1.9, q[1]), Color(1.0, 0.6, 0.3), 1.3, 7.0)
	for t in [[-14, -24], [14, -30], [-36, 0], [36, 4], [-14, 36], [30, 36], [-30, -38], [16, 22]]:
		dead_tree(root, t[0], t[1], rng.randf_range(0.8, 1.2))
	root.set_meta("fires", [])
	zone_spawns()
	return []



# ================================================================ perk icons (drawn into images, used on machines and the HUD)
const PERK_COL := {"armor": Color(0.25, 0.55, 1.0), "hands": Color(0.3, 1.0, 0.45), "pulse": Color(1.0, 0.35, 0.25), "forge": Color(1.0, 0.7, 0.2)}
static var _icons := {}


static func _in_poly(p: Vector2, poly: Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[j]
		if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside


static func perk_icon(kind: String) -> ImageTexture:
	if _icons.has(kind):
		return _icons[kind]
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var col: Color = PERK_COL.get(kind, Color.WHITE)
	var c := Vector2(n, n) * 0.5
	var shape := []
	match kind:
		"armor":
			shape = [Vector2(28, 26), Vector2(68, 26), Vector2(66, 52), Vector2(48, 74), Vector2(30, 52)]
		"hands":
			shape = [Vector2(26, 30), Vector2(52, 30), Vector2(52, 20), Vector2(72, 40), Vector2(52, 60), Vector2(52, 50), Vector2(26, 50)]
		"pulse":
			shape = [Vector2(54, 18), Vector2(30, 52), Vector2(46, 52), Vector2(40, 78), Vector2(66, 42), Vector2(50, 42), Vector2(58, 18)]
		"forge":
			shape = [Vector2(24, 40), Vector2(72, 40), Vector2(64, 52), Vector2(54, 52), Vector2(58, 72), Vector2(38, 72), Vector2(42, 52), Vector2(32, 52)]
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c)
			var px := Color(0, 0, 0, 0)
			if d < 46.0:
				px = Color(0.05, 0.05, 0.05, 0.9)
			if d < 42.0:
				px = col.darkened(0.35)
			if d < 42.0 and d > 38.0:
				px = Color(0.95, 0.8, 0.4)
			if not shape.is_empty() and _in_poly(p, shape):
				px = Color(1, 1, 1)
			img.set_pixel(x, y, px)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_icons[kind] = t
	return t
