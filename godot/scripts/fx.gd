extends Node3D
## Visual effects: tracers, muzzle lights, impact particles, blood, bullet-hole decals, burning wrecks.

var decals: Array = []
var hole_tex: Texture2D
var smoke_tex: Texture2D
var part_mesh: BoxMesh
var m_spark: StandardMaterial3D
var m_dust: StandardMaterial3D
var m_blood: StandardMaterial3D
var m_wood: StandardMaterial3D
var m_tracer: StandardMaterial3D
var fires: Array = []
var weather: Array = []
var weather_kind := ""
var w_quality := 1
var tracer_mesh: BoxMesh
var puff_mesh: QuadMesh
var puff_ramp: Gradient
var puff_curve: Curve
var m_scorch: Texture2D
var m_fire: StandardMaterial3D
var m_debris: StandardMaterial3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	hole_tex = _radial_tex(64, [[0.0, Color(0, 0, 0, 1)], [0.22, Color(0.04, 0.035, 0.03, 0.95)], [0.48, Color(0.17, 0.15, 0.13, 0.45)], [1.0, Color(0, 0, 0, 0)]])
	smoke_tex = _radial_tex(64, [[0.0, Color(1, 1, 1, 0.8)], [0.5, Color(1, 1, 1, 0.3)], [1.0, Color(1, 1, 1, 0)]])
	part_mesh = BoxMesh.new()
	part_mesh.size = Vector3.ONE * 0.05
	m_spark = _unshaded(Color(1.0, 0.75, 0.35), 6.0)
	m_tracer = _unshaded(Color(1.0, 0.85, 0.55), 5.0)
	m_tracer.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_tracer.albedo_color.a = 0.85
	m_blood = StandardMaterial3D.new()
	m_blood.albedo_color = Color(0.35, 0.02, 0.02)
	m_blood.roughness = 0.4
	m_dust = StandardMaterial3D.new()
	m_dust.albedo_color = Color(0.55, 0.5, 0.44)
	m_wood = StandardMaterial3D.new()
	m_wood.albedo_color = Color(0.45, 0.33, 0.2)
	m_debris = StandardMaterial3D.new()
	m_debris.albedo_color = Color(0.25, 0.23, 0.21)
	# shared meshes/materials: effects reuse them instead of allocating new resources per shot
	tracer_mesh = BoxMesh.new()
	tracer_mesh.size = Vector3(0.018, 0.018, 1.0)
	puff_mesh = QuadMesh.new()
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.albedo_texture = smoke_tex
	pm.vertex_color_use_as_albedo = true
	puff_mesh.material = pm
	puff_ramp = Gradient.new()
	puff_ramp.set_color(0, Color(1, 1, 1, 0.8))
	puff_ramp.set_color(1, Color(1, 1, 1, 0))
	puff_curve = Curve.new()
	puff_curve.add_point(Vector2(0, 0.5))
	puff_curve.add_point(Vector2(1, 1.8))
	m_fire = StandardMaterial3D.new()
	m_fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_fire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_fire.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m_fire.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m_fire.albedo_texture = smoke_tex
	m_fire.vertex_color_use_as_albedo = true
	m_scorch = _radial_tex(64, [[0.0, Color(0.02, 0.02, 0.02, 0.95)], [0.5, Color(0.05, 0.04, 0.03, 0.7)], [1.0, Color(0, 0, 0, 0)]])


func _unshaded(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c * energy
	m.disable_receive_shadows = true
	return m


func _radial_tex(size: int, stops: Array) -> Texture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t


func clear() -> void:
	for d in decals:
		if is_instance_valid(d):
			d.queue_free()
	decals.clear()
	for c in get_children():
		if not (c in fires) and not (c in weather):
			c.queue_free()


func clear_fires() -> void:
	for f in fires:
		if is_instance_valid(f):
			f.queue_free()
	fires.clear()


func tracer(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.6:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = tracer_mesh
	mi.scale = Vector3(1, 1, length)
	mi.material_override = m_tracer
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (a + b) * 0.5
	var dir := (b - a).normalized()
	mi.look_at(b, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	mi.scale = Vector3(1, 1, length)
	get_tree().create_timer(0.05, false).timeout.connect(mi.queue_free)


func flash_light(pos: Vector3, energy := 2.5, rng := 6.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.4)
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos
	get_tree().create_timer(0.05, false).timeout.connect(l.queue_free)


func burst(pos: Vector3, normal: Vector3, mat: Material, amount: int, speed: float, life: float, size: float, grav: float, spread := 55.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.mesh = part_mesh
	p.material_override = mat
	p.direction = normal
	p.spread = spread
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -grav, 0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.4
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3, false).timeout.connect(p.queue_free)


func puff(pos: Vector3, color: Color, size: float, life: float, rise := 0.6, amount := 6, alpha := 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	color.a = alpha
	p.lifetime = life
	p.mesh = puff_mesh
	p.color = color
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, rise, 0)
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.6 * size
	p.scale_amount_curve = puff_curve
	p.color_ramp = puff_ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3, false).timeout.connect(p.queue_free)


func impact(pos: Vector3, normal: Vector3, wood := false, smoke := true) -> void:
	if wood:
		burst(pos, normal, m_wood, 6, 3.5, 0.7, 0.8, 12.0)
	else:
		burst(pos, normal, m_spark, 6, 5.0, 0.3, 0.5, 9.0, 40.0)
		burst(pos, normal, m_dust, 4, 2.5, 0.6, 0.7, 14.0)
	if smoke:
		# thin, short-lived dust so the target stays visible
		puff(pos + normal * 0.08, Color(0.62, 0.57, 0.5), 0.26, 0.55, 0.25, 3, 0.4)
	_decal(pos, normal)


func blood(pos: Vector3, dir: Vector3) -> void:
	burst(pos, dir, m_blood, 10, 3.0, 0.5, 0.6, 14.0, 60.0)
	puff(pos, Color(0.4, 0.03, 0.03), 0.3, 0.35, -0.5, 3, 0.6)


func _decal(pos: Vector3, normal: Vector3) -> void:
	var d := Decal.new()
	d.texture_albedo = hole_tex
	d.size = Vector3(0.16, 0.12, 0.16)
	d.cull_mask = 1
	add_child(d)
	var y := normal.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	d.global_transform = Transform3D(Basis(x, y, z), pos + y * 0.02)
	d.rotate_object_local(Vector3.UP, randf() * TAU)
	decals.append(d)
	if decals.size() > 90:
		var old = decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func add_fire(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	fires.append(root)
	var f := CPUParticles3D.new()
	f.amount = 40
	f.lifetime = 0.8
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.9
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = smoke_tex
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(3.0, 1.4, 0.4)
	q.material = m
	f.mesh = q
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	f.emission_sphere_radius = 0.5
	f.direction = Vector3.UP
	f.spread = 15.0
	f.initial_velocity_min = 0.8
	f.initial_velocity_max = 1.8
	f.gravity = Vector3(0, 1.5, 0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 0.4, 0.1, 0))
	f.color_ramp = g
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(f)
	var s := CPUParticles3D.new()
	s.amount = 30
	s.lifetime = 4.0
	var q2 := QuadMesh.new()
	q2.size = Vector2.ONE * 2.2
	var m2 := StandardMaterial3D.new()
	m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m2.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m2.albedo_texture = smoke_tex
	m2.vertex_color_use_as_albedo = true
	m2.albedo_color = Color(0.12, 0.11, 0.1)
	q2.material = m2
	s.mesh = q2
	s.position.y = 1.0
	s.direction = Vector3.UP
	s.spread = 12.0
	s.initial_velocity_min = 1.0
	s.initial_velocity_max = 2.0
	s.gravity = Vector3(0.4, 0.4, 0.15)
	var c := Curve.new()
	c.add_point(Vector2(0, 0.5))
	c.add_point(Vector2(1, 2.5))
	s.scale_amount_curve = c
	var g2 := Gradient.new()
	g2.set_color(0, Color(1, 1, 1, 0.8))
	g2.set_color(1, Color(1, 1, 1, 0))
	s.color_ramp = g2
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(s)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 2.0
	l.omni_range = 9.0
	l.position.y = 0.6
	root.add_child(l)


## Big explosion (grenades, airstrike): fireball, smoke column, debris, sparks, scorch mark, light.
func explosion(pos: Vector3, scale := 1.0) -> void:
	var f := CPUParticles3D.new()
	f.one_shot = true
	f.explosiveness = 0.95
	f.amount = 26
	f.lifetime = 0.7
	f.mesh = puff_mesh
	f.material_override = m_fire
	f.color = Color(3.2, 1.5, 0.45)
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	f.emission_sphere_radius = 0.6 * scale
	f.direction = Vector3.UP
	f.spread = 180.0
	f.initial_velocity_min = 2.0 * scale
	f.initial_velocity_max = 6.0 * scale
	f.damping_min = 6.0
	f.damping_max = 9.0
	f.scale_amount_min = 1.4 * scale
	f.scale_amount_max = 3.0 * scale
	f.scale_amount_curve = puff_curve
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 0.35, 0.1, 0))
	f.color_ramp = g
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(f)
	f.global_position = pos + Vector3(0, 0.5, 0)
	f.emitting = true
	get_tree().create_timer(1.2, false).timeout.connect(f.queue_free)
	var sm := CPUParticles3D.new()
	sm.one_shot = true
	sm.explosiveness = 0.7
	sm.amount = 18
	sm.lifetime = 3.5
	sm.mesh = puff_mesh
	sm.color = Color(0.16, 0.15, 0.14)
	sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 1.0 * scale
	sm.direction = Vector3.UP
	sm.spread = 40.0
	sm.initial_velocity_min = 1.0
	sm.initial_velocity_max = 3.5
	sm.gravity = Vector3(0.3, 0.8, 0.1)
	sm.damping_min = 1.0
	sm.damping_max = 2.0
	sm.scale_amount_min = 2.5 * scale
	sm.scale_amount_max = 4.5 * scale
	sm.scale_amount_curve = puff_curve
	sm.color_ramp = puff_ramp
	sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sm)
	sm.global_position = pos + Vector3(0, 0.8, 0)
	sm.emitting = true
	get_tree().create_timer(4.0, false).timeout.connect(sm.queue_free)
	burst(pos + Vector3(0, 0.3, 0), Vector3.UP, m_debris, 22, 11.0 * scale, 1.6, 2.2, 18.0, 70.0)
	burst(pos + Vector3(0, 0.3, 0), Vector3.UP, m_spark, 28, 14.0 * scale, 0.7, 0.7, 9.0, 85.0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 9.0
	l.omni_range = 16.0 * scale
	add_child(l)
	l.global_position = pos + Vector3(0, 1.2, 0)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.45)
	tw.tween_callback(l.queue_free)
	var d := Decal.new()
	d.texture_albedo = m_scorch
	d.size = Vector3(3.6, 1.5, 3.6) * scale
	d.cull_mask = 1
	add_child(d)
	d.global_position = pos
	d.rotate_y(randf() * TAU)
	decals.append(d)


# ---------------------------------------------------------------- weather (follows the camera)
func weather_quality(q: int) -> void:
	w_quality = q
	if weather_kind != "":
		set_weather(weather_kind)


func set_weather(kind: String) -> void:
	for w in weather:
		if is_instance_valid(w):
			w.queue_free()
	weather.clear()
	weather_kind = kind
	if kind == "":
		return
	var mul: float = [0.5, 0.8, 1.0][w_quality]
	match kind:
		"snow":
			_weather_layer(int(2200 * mul), 7.0, Vector3(0.25, -1.3, 0.1), Color(0.95, 0.96, 1.0, 0.9), 0.07, 0.6, false)
		"dust":
			_weather_layer(int(700 * mul), 9.0, Vector3(0.5, 0.03, 0.15), Color(1.0, 0.85, 0.6, 0.35), 0.05, 0.2, false)
			_weather_layer(int(40 * mul), 9.0, Vector3(1.2, 0.05, 0.3), Color(0.9, 0.75, 0.55, 0.06), 3.5, 0.3, false)
		"ash":
			_weather_layer(int(900 * mul), 9.0, Vector3(0.15, -0.35, 0.05), Color(0.32, 0.3, 0.3, 0.8), 0.05, 0.3, false)
			_weather_layer(int(90 * mul), 5.0, Vector3(0.1, 0.35, 0.05), Color(3.0, 1.1, 0.3, 1.0), 0.035, 0.6, true)


func _weather_layer(amount: int, life: float, grav: Vector3, col: Color, size: float, turb: float, additive: bool) -> void:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 8)
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24, 9, 24)
	pm.gravity = grav
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = turb
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.1, 0.85, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = smoke_tex
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	weather.append(p)


func follow(cam_pos: Vector3) -> void:
	for w in weather:
		if is_instance_valid(w):
			w.global_position = cam_pos + Vector3(0, 4.0, 0)
