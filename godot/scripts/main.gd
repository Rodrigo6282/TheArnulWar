extends Node
## The Arnul War (Godot) - game hub: settings, environment, maps, game modes (Operación waves /
## Zombis rounds), medals and profile, menus.

const WorldBuilder := preload("res://scripts/world.gd")
const PlayerScript := preload("res://scripts/player.gd")
const SoldierScript := preload("res://scripts/soldier.gd")
const ZombieScript := preload("res://scripts/zombie.gd")
const ZModeScript := preload("res://scripts/zmode.gd")
const Medals := preload("res://scripts/medals.gd")
const UIScript := preload("res://scripts/ui.gd")
const FxScript := preload("res://scripts/fx.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const OPT := preload("res://scripts/optimize.gd")

const DIFF_ACC := [0.6, 1.0, 1.35]
const DIFF_DMG := [0.6, 1.0, 1.45]
const BUY_NAMES := {0: "AR-7 FUSIL", 1: "M-12 ESCOPETA", 2: "P9 MUNICIÓN", 3: "V-9 SUBFUSIL", 4: "R-700 FRANCOTIRADOR", 5: "K-90 AMETRALLADORA"}

var settings := {"sens": 1.0, "quality": 1, "fullscreen": true, "diff": 1, "map": 0, "name": "Jugador", "last_ip": "127.0.0.1", "op": 0, "mp_mode": "ffa"}
var state := "menu"
var mode := "ops"
var map_idx := 0
var map_dirty := false
var env_node: WorldEnvironment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var world: Node3D
var nav: NavigationRegion3D
var spawns: Array = []
var player: CharacterBody3D
var ui
var fx
var sfx
var zm = null
var menu_cam: Camera3D
var enemies: Array = []
var wave := 0
var to_spawn := 0
var spawn_t := 0.0
var intermission := 0.0
var score := 0
var kills := 0
var heads := 0
var shots := 0
var hits := 0
var streak := 0
var clock := 0.0
var best := 0
var best_round := 0
var medal_totals := {}
var medals_game := {}
var kill_ctx := {}
var multi_n := 0
var multi_t := -9.0
var wave_hit := false
var nav_baking := false
var ks := 0
var ks_given := {}
var streak_ready: Array = []
var radar_t := 0.0
var pickups: Array = []
const STREAKS := {3: ["uav", "UAV"], 5: ["bomber", "BOMBARDERO"], 7: ["heli", "HELICÓPTERO FURTIVO"]}
const StreaksScript := preload("res://scripts/streaks.gd")
const NetScript := preload("res://scripts/net.gd")
var net
var air
var user_args: PackedStringArray


func _ready() -> void:
	user_args = OS.get_cmdline_user_args()
	randomize()
	load_settings()
	fx = FxScript.new()
	add_child(fx)
	sfx = SfxScript.new()
	add_child(sfx)
	_build_environment()
	nav = NavigationRegion3D.new()
	nav.name = "Nav"
	add_child(nav)
	nav.bake_finished.connect(func(): nav_baking = false)
	air = StreaksScript.new()
	air.game = self
	add_child(air)
	net = NetScript.new()
	net.name = "Net"
	net.game = self
	add_child(net)
	world = Node3D.new()
	world.name = "World"
	nav.add_child(world)
	menu_cam = Camera3D.new()
	menu_cam.far = 700.0
	add_child(menu_cam)
	menu_cam.current = true
	ui = UIScript.new()
	add_child(ui)
	ui.setup(self)
	# final sharpen + vignette pass (under the HUD layer)
	var post := CanvasLayer.new()
	post.layer = 5
	add_child(post)
	var pr := ColorRect.new()
	pr.set_anchors_preset(Control.PRESET_FULL_RECT)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = preload("res://shaders/post.gdshader")
	pr.material = pm
	post.add_child(pr)
	var m := arg_value("--map")
	load_map(int(m) if m != "" else clampi(settings.map, 0, WorldBuilder.MAPS.size() - 1))
	apply_quality()
	if has_arg("--noocc"):
		get_viewport().use_occlusion_culling = false
	if not has_arg("--autotest") and arg_value("--shot") == "":
		apply_fullscreen()
	ui.show_menu()
	if has_arg("--perf"):
		_perf()
	elif has_arg("--autotest"):
		_autotest()
	elif arg_value("--shot") != "":
		_shot(arg_value("--shot"), arg_value("--out"))
	elif arg_value("--mptest") != "":
		_mptest(arg_value("--mptest"))


func has_arg(a: String) -> bool:
	return a in user_args


func arg_value(key: String) -> String:
	for a in user_args:
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return ""


# ---------------------------------------------------------------- environment / quality
func _build_environment() -> void:
	env_node = WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("cloud_offset", Vector2(randf() * 50.0, randf() * 50.0))
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 4.5
	e.glow_enabled = true
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.1
	e.fog_enabled = true
	e.fog_aerial_perspective = 0.5
	e.fog_sky_affect = 0.25
	e.ssao_radius = 1.4
	e.ssao_intensity = 1.8
	e.ssil_intensity = 0.8
	e.volumetric_fog_density = 0.006
	e.adjustment_enabled = true
	env_node.environment = e
	add_child(env_node)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	# bounce/fill light from the opposite side (cheap stand-in for light reflected by the ground)
	fill = DirectionalLight3D.new()
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	add_child(fill)
	e.fog_sun_scatter = 0.18


## Per-map lighting, sky, fog, colour grade and weather.
func apply_env(d: Dictionary) -> void:
	var e: Environment = env_node.environment
	sun.rotation_degrees = d.sun
	sun.light_color = d.sun_col
	sun.light_energy = d.sun_e
	fill.rotation_degrees = Vector3(28.0, d.sun.y + 180.0, 0.0)
	fill.light_color = d.gnd.lerp(d.hor, 0.4)
	fill.light_energy = d.sun_e * (0.34 if settings.quality < 2 else 0.14)
	sky_mat.set_shader_parameter("zenith", d.zen)
	sky_mat.set_shader_parameter("horizon", d.hor)
	sky_mat.set_shader_parameter("ground", d.gnd)
	sky_mat.set_shader_parameter("cloud_cover", d.clouds)
	sky_mat.set_shader_parameter("cloud_light", d.cloud_light)
	sky_mat.set_shader_parameter("stars", d.stars)
	sky_mat.set_shader_parameter("sun_sharp", d.sun_sharp)
	e.ambient_light_energy = d.amb
	# night maps: add a moonlit base ambient so the scene is readable without washing out the lights
	e.ambient_light_color = d.get("amb_col", Color.BLACK)
	e.ambient_light_sky_contribution = 0.35 if d.has("amb_col") else 1.0
	e.tonemap_exposure = d.exp
	e.glow_intensity = d.glow
	e.fog_light_color = d.fog_col
	e.fog_density = d.fog_d
	e.volumetric_fog_albedo = d.fog_col.lightened(0.3)
	e.volumetric_fog_density = d.fog_d * (2.5 if d.night else 1.3)
	e.adjustment_saturation = d.sat
	e.adjustment_contrast = d.con
	fx.set_weather(d.weather)


func apply_quality() -> void:
	# 0 Baja: no AO, FXAA, FSR at 77 %, light shadows
	# 1 Media: half-res low-quality SSAO, FXAA, 2048 shadows (tuned for integrated GPUs)
	# 2 Alta: SDFGI global illumination, SSIL, SSR, volumetric fog, MSAA 2x, 4096 shadows
	var q: int = settings.quality
	var e: Environment = env_node.environment
	var vp := get_viewport()
	e.ssao_enabled = q >= 1
	e.ssil_enabled = q >= 2
	e.sdfgi_enabled = q >= 2
	e.ssr_enabled = q >= 2
	e.volumetric_fog_enabled = q >= 2
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_VERY_LOW if q < 2 else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
	# Alta optimised without losing detail: GI (low-frequency light) traced at half resolution, and
	# fewer rays per frame spread over more frames (same converged result)
	RenderingServer.gi_set_use_half_resolution(true)
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_8)
	RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES)
	RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_8_FRAMES)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.use_taa = q == 2 and not has_arg("--notaa")
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q < 2 or has_arg("--notaa") else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q == 0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 0.77 if q == 0 else 1.0
	RenderingServer.directional_shadow_atlas_set_size(4096 if q == 2 else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if q == 2 else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	sun.directional_shadow_max_distance = [60.0, 90.0, 120.0][q]
	if fill and WorldBuilder.MAPS.size() > map_idx:
		fill.light_energy = WorldBuilder.ENVS[WorldBuilder.MAPS[map_idx].env].sun_e * (0.34 if q < 2 else 0.14)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q == 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# bloom: the full-res glow levels are the expensive ones on integrated GPUs; the lower-res
	# levels give almost the same soft halo for a fraction of the cost
	for lv in 7:
		e.set_glow_level(lv, 0.0)
	var lv_on: Array = [[3, 4, 5], [2, 3, 4, 5], [1, 2, 3, 4, 5]][q]
	for lv in lv_on:
		e.set_glow_level(lv, 1.0)
	e.glow_normalized = true
	fx.weather_quality(q)


func apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://ajustes.cfg") == OK:
		for k in settings.keys():
			settings[k] = cf.get_value("ajustes", k, settings[k])
		best = cf.get_value("perfil", "best", 0)
		best_round = cf.get_value("perfil", "best_round", 0)
		medal_totals = cf.get_value("perfil", "medallas", {})
	else:
		# first run: integrated Intel graphics start on "Baja" so the game runs smoothly
		var gpu := RenderingServer.get_video_adapter_name().to_lower()
		if gpu.contains("intel") and not gpu.contains("arc"):
			settings.quality = 0


func save_settings() -> void:
	if has_arg("--autotest") or arg_value("--shot") != "":
		return
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("ajustes", k, settings[k])
	cf.set_value("perfil", "best", best)
	cf.set_value("perfil", "best_round", best_round)
	cf.set_value("perfil", "medallas", medal_totals)
	cf.save("user://ajustes.cfg")


func medal_count() -> int:
	var n := 0
	for k in medal_totals:
		n += int(medal_totals[k])
	return n


# ---------------------------------------------------------------- maps + navigation
func load_map(i: int) -> void:
	map_idx = i
	settings.map = i
	mode = WorldBuilder.MAPS[i].mode
	for c in world.get_children():
		world.remove_child(c)
		c.queue_free()
	world.remove_meta("fires")
	fx.clear_fires()
	spawns = WorldBuilder.build(i, world, BUY_NAMES)
	for f in world.get_meta("fires", []):
		fx.add_fire(f)
	if not has_arg("--nomerge"):
		ui.build_minimap(WorldBuilder.rects)
	OPT.merge_world(world)
	apply_env(WorldBuilder.ENVS[WorldBuilder.MAPS[i].env])
	_bake_nav()
	map_dirty = false


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.5
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.filter_baking_aabb = AABB(Vector3(-60, -1, -60), Vector3(120, 8, 120))
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)


## After a zombie door opens: re-bake in the background (no hitch).
func rebake_nav() -> void:
	if nav_baking:
		await nav.bake_finished
	nav_baking = true
	nav.bake_navigation_mesh(true)


# ---------------------------------------------------------------- game flow
func start_game() -> void:
	_reset()
	state = "playing"
	get_tree().paused = false
	ui.show_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if arg_value("--shot") == "":
		apply_fullscreen()


func _clear_enemies() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()


func _reset() -> void:
	_clear_enemies()
	fx.clear()
	if zm:
		zm.clear()
		zm.queue_free()
		zm = null
	if map_dirty:
		load_map(map_idx)
	if player and is_instance_valid(player):
		player.queue_free()
	player = PlayerScript.new()
	player.game = self
	add_child(player)
	var md: Dictionary = WorldBuilder.MAPS[map_idx]
	player.global_position = md.start
	player.yaw = md.yaw
	player.camera.current = true
	wave = 0
	to_spawn = 0
	spawn_t = 0.0
	intermission = 3.0
	score = 0
	kills = 0
	heads = 0
	shots = 0
	hits = 0
	streak = 0
	multi_n = 0
	multi_t = -9.0
	wave_hit = false
	medals_game = {}
	kill_ctx = {}
	air.clear()
	_clear_pickups()
	ks = 0
	ks_given = {}
	streak_ready = []
	radar_t = 0.0
	ui.reset_feed()
	if mode == "mp":
		player.owned = [0, 1, 2, 3, 4, 5]
	elif mode == "zombies":
		zm = ZModeScript.new()
		add_child(zm)
		zm.setup(self)
		player.owned = [2]
		player.weapons[2].reserve = 48
		player.grenades = 2
		player.test_switch(2)
		ui.notice(md.name.to_upper(), "Sobrevive todas las rondas que puedas · F para interactuar", 4.0)
	elif mode != "mp":
		ui.notice("PREPÁRATE", "%s · la primera oleada llega en 3 segundos" % md.name, 3.0)


## Start (or rejoin) a multiplayer match on map i (mode in net.gmode).
func start_mp(i: int) -> void:
	if map_dirty or i != map_idx:
		load_map(i)
	else:
		mode = WorldBuilder.MAPS[i].mode
	if net.gmode == "zombies":
		mode = "zombies"
		start_game()
		ui.notice(net.mode_title(), "%s · F para interactuar · Tab: marcador" % WorldBuilder.MAPS[i].name, 4.0)
		return
	mode = "mp"
	start_game()
	mp_respawn()
	ui.notice(net.mode_title(), net.MODES[net.gmode][1] + " · Tab: marcador", 4.0)


## Gun game: give the local player only the weapon of their current ladder level.
func gun_game_loadout(announce := false) -> void:
	if player == null or not is_instance_valid(player) or net.gmode != "gun":
		return
	var w: int = net.gun_weapon(net.my_id())
	player.owned = [w]
	player.weapons[w].ammo = player.weapons[w].mag
	player.weapons[w].reserve = player.weapons[w].reserve_max
	player.test_switch(w)
	if announce:
		sfx.play("buy")
		ui.notice("NUEVA ARMA", player.weapons[w].name, 1.5)


## Respawn the local player at the spawn point farthest from the other players
## (in co-op zombies: next to a living teammate, or at the map start).
func mp_respawn(_revive := false) -> void:
	if player == null or not is_instance_valid(player):
		return
	if net.gmode == "zombies":
		var at: Vector3 = WorldBuilder.MAPS[map_idx].start
		for id in net.puppets:
			var mate = net.puppets[id]
			if is_instance_valid(mate) and not mate.dead:
				at = mate.global_position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
				break
		player.global_position = at + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		player.alive = true
		player.health = player.max_health
		player.refill()
		return
	var pts: Array = spawns if not spawns.is_empty() else [WorldBuilder.MAPS[map_idx].start]
	if net.gmode == "tdm":
		# each team spawns on its own half of the map
		var side: float = -1.0 if net.team_of(net.my_id()) == 0 else 1.0
		var half: Array = pts.filter(func(p): return p.x * side > 0.0)
		if half.size() >= 2:
			pts = half
	var best: Vector3 = pts[randi() % pts.size()]
	var best_d := -1.0
	for i in 12:
		var c: Vector3 = pts[randi() % pts.size()]
		var dmin := 999.0
		for id in net.puppets:
			var pp = net.puppets[id]
			if is_instance_valid(pp) and not pp.dead and not net.is_ally(id):
				dmin = minf(dmin, c.distance_to(pp.global_position))
		if dmin > best_d:
			best_d = dmin
			best = c
	player.global_position = best + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	player.alive = true
	player.health = player.max_health
	player.yaw = atan2(best.x, best.z)
	player.max_ammo()
	player.grenades = 3
	if net.gmode == "gun":
		gun_game_loadout()
	ks = 0
	ks_given = {}
	streak = 0


func pause() -> void:
	if state != "playing":
		return
	state = "paused"
	# multiplayer keeps running underneath the menu
	get_tree().paused = not net.active
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_pause()


func resume() -> void:
	if state != "paused":
		return
	state = "playing"
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.show_hud()
	apply_fullscreen()


func to_menu() -> void:
	if net.active:
		net.leave()
	_clear_enemies()
	air.clear()
	_clear_pickups()
	if zm:
		zm.clear()
		zm.queue_free()
		zm = null
	if player and is_instance_valid(player):
		player.queue_free()
	player = null
	state = "menu"
	get_tree().paused = false
	if map_dirty:
		load_map(map_idx)
	menu_cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_menu()


func game_over() -> void:
	state = "dead"
	if mode == "ops" and score > best:
		best = score
	var rnd: int = zm.round_n if zm else 0
	if mode == "zombies" and rnd > best_round:
		best_round = rnd
	save_settings()
	await get_tree().create_timer(1.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var acc := 0 if shots == 0 else int(round(100.0 * hits / shots))
	ui.show_gameover({"mode": mode, "score": score, "wave": wave, "round": rnd, "kills": kills, "heads": heads, "acc": acc,
		"best": best, "best_round": best_round, "medals": medals_game})


func interact() -> void:
	if zm and state == "playing":
		zm.interact()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k == KEY_ESCAPE:
			if state == "playing":
				pause()
			elif state == "paused":
				resume()
		elif (k == KEY_ENTER and event.alt_pressed) or k == KEY_F11:
			settings.fullscreen = not settings.fullscreen
			apply_fullscreen()
			save_settings()
			ui.sync_settings()


func _process(delta: float) -> void:
	clock += delta
	var cam: Camera3D = menu_cam
	radar_t = maxf(0.0, radar_t - delta) if state == "playing" else radar_t
	if state == "menu":
		var a := clock * 0.05
		var r: float = WorldBuilder.MAPS[map_idx].cam
		menu_cam.global_position = Vector3(sin(a) * r, r * 0.37, cos(a) * r)
		menu_cam.look_at(Vector3(0, 2, 0))
	elif player and is_instance_valid(player):
		cam = player.camera
		# online the world keeps running while the pause menu is open
		if state == "playing" or (state == "paused" and net.active):
			if mode == "zombies":
				zm.update(delta)
			elif mode == "mp":
				pass
			else:
				_update_waves(delta)
			_update_pickups(delta)
		if net.active:
			net.update(delta)
	fx.follow(cam.global_position)
	ui.tick(delta)


func alive_count() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and not e.dead and e.get("puppet") != true:
			n += 1
	return n


func _update_waves(delta: float) -> void:
	if intermission > 0.0:
		intermission -= delta
		if intermission <= 0.0:
			wave += 1
			to_spawn = 4 + wave * 2
			spawn_t = 0.5
			wave_hit = false
			player.grenades = maxi(player.grenades, 3)
			ui.notice("OLEADA %d" % wave, "%d hostiles se acercan" % to_spawn, 2.5)
			sfx.play("wave")
		return
	if to_spawn > 0:
		spawn_t -= delta
		if spawn_t <= 0.0 and alive_count() < min(4 + wave, 12):
			_spawn_soldier()
			to_spawn -= 1
			spawn_t = randf_range(0.8, 1.8)
	elif alive_count() == 0:
		var bonus := wave * 250
		score += bonus
		ui.notice("OLEADA %d SUPERADA" % wave, "+%d puntos" % bonus, 3.0)
		if not wave_hit:
			award_medal("wave")
		if wave % 3 == 0 and player.upgrade(player.cur):
			ui.notice("ARMA MEJORADA", "%s · recompensa por superar %d oleadas" % [player.weapons[player.cur].name, wave], 3.0)
		intermission = 7.0
		player.refill()


func _spawn_soldier() -> void:
	var pp := player.global_position
	var far := spawns.filter(func(p): return Vector2(p.x - pp.x, p.z - pp.z).length() > 30.0)
	if far.is_empty():
		far = spawns
	var p: Vector3 = far[randi() % far.size()]
	var s = SoldierScript.new()
	s.game = self
	s.wave = wave
	add_child(s)
	s.global_position = p + Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1))
	enemies.append(s)


# ---------------------------------------------------------------- kills + medals
func register_kill(head: bool, _victim = null) -> void:
	kills += 1
	streak += 1
	ks += 1
	if STREAKS.has(ks) and not ks_given.has(ks):
		ks_given[ks] = true
		var st: Array = STREAKS[ks]
		sfx.play("radar", -2)
		if st[0] == "uav":
			radar_t = 30.0
			air.uav(30.0)
			ui.notice("RACHA: UAV", "Dron de reconocimiento: enemigos marcados 30 segundos", 2.5)
		else:
			streak_ready.append(st[0])
			ui.notice("RACHA: %s" % st[1], "Pulsa B para usarla", 2.5)
	if head:
		heads += 1
	if mode == "ops" or mode == "mp":
		var pts := 150 if head else 100
		score += pts
		ui.feed_line("+%d %s" % [pts, "Disparo a la cabeza" if head else "Baja"], head)
	var ctx := kill_ctx
	if kills == 1:
		award_medal("first")
	if head and mode == "ops":
		award_medal("head")
	if clock - multi_t < 2.0:
		multi_n += 1
	else:
		multi_n = 1
	multi_t = clock
	if multi_n == 2:
		award_medal("double")
	elif multi_n == 3:
		award_medal("triple")
	elif multi_n == 4 or (multi_n > 4 and mode == "ops"):
		award_medal("multi")
	if streak == 5:
		award_medal("streak5")
	elif streak == 10:
		award_medal("streak10")
	elif streak == 20:
		award_medal("streak20")
	if not ctx.is_empty():
		if ctx.melee:
			award_medal("knife")
		elif ctx.dist > 40.0:
			award_medal("long")
		elif ctx.dist < 3.0 and mode == "ops":
			award_medal("close")
		if ctx.get("last", false):
			award_medal("last")
		if ctx.hp < 25.0:
			award_medal("edge")


func award_medal(id: String) -> void:
	if not Medals.LIST.has(id):
		return
	var m: Array = Medals.LIST[id]
	medals_game[id] = int(medals_game.get(id, 0)) + 1
	medal_totals[id] = int(medal_totals.get(id, 0)) + 1
	if mode == "zombies" and zm:
		zm.add_points(m[1])
	else:
		score += m[1]
	ui.medal(id)


# ---------------------------------------------------------------- loot dropped by soldiers
func _clear_pickups() -> void:
	for p in pickups:
		if is_instance_valid(p.node):
			p.node.queue_free()
	pickups.clear()


static var _loot_mats := {}


func drop_loot(pos: Vector3) -> void:
	_spawn_pickup(pos + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), "ammo")
	if randf() < 0.35:
		_spawn_pickup(pos + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)), "nade")


func _spawn_pickup(pos: Vector3, kind: String) -> void:
	if _loot_mats.is_empty():
		var olive := StandardMaterial3D.new()
		olive.albedo_color = Color(0.28, 0.32, 0.2)
		olive.roughness = 0.7
		olive.emission_enabled = true
		olive.emission = Color(0.9, 0.75, 0.3)
		olive.emission_energy_multiplier = 0.25
		var stripe := StandardMaterial3D.new()
		stripe.albedo_color = Color(0.95, 0.75, 0.15)
		stripe.emission_enabled = true
		stripe.emission = Color(0.95, 0.75, 0.15)
		stripe.emission_energy_multiplier = 1.2
		var nade := StandardMaterial3D.new()
		nade.albedo_color = Color(0.22, 0.27, 0.17)
		nade.roughness = 0.6
		nade.emission_enabled = true
		nade.emission = Color(0.6, 0.9, 0.4)
		nade.emission_energy_multiplier = 0.3
		_loot_mats = {"olive": olive, "stripe": stripe, "nade": nade}
	var n := Node3D.new()
	world.add_child(n)
	n.global_position = Vector3(pos.x, 0.0, pos.z)
	var body := Node3D.new()
	n.add_child(body)
	if kind == "ammo":
		var b := BoxMesh.new()
		b.size = Vector3(0.34, 0.2, 0.18)
		var mi := MeshInstance3D.new()
		mi.mesh = b
		mi.material_override = _loot_mats.olive
		body.add_child(mi)
		var s := BoxMesh.new()
		s.size = Vector3(0.345, 0.04, 0.185)
		var ms := MeshInstance3D.new()
		ms.mesh = s
		ms.material_override = _loot_mats.stripe
		ms.position.y = 0.04
		body.add_child(ms)
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.15
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = _loot_mats.nade
		body.add_child(mi)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = 0.05
		var mc := MeshInstance3D.new()
		mc.mesh = cm
		mc.material_override = _loot_mats.stripe
		mc.position.y = 0.08
		body.add_child(mc)
	pickups.append({"node": n, "body": body, "kind": kind, "t": 30.0})


func _update_pickups(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.alive:
		return
	var pp := player.global_position
	for p in pickups.duplicate():
		var n: Node3D = p.node
		if not is_instance_valid(n):
			pickups.erase(p)
			continue
		p.t -= delta
		p.body.position.y = 0.25 + sin(clock * 3.0 + n.global_position.x) * 0.05
		p.body.rotation.y += delta * 1.8
		if Vector2(n.global_position.x - pp.x, n.global_position.z - pp.z).length() < 1.4:
			if p.kind == "ammo":
				for i in player.owned:
					var w: Dictionary = player.weapons[i]
					w.reserve = mini(w.reserve_max, w.reserve + maxi(w.mag, 8))
				ui.feed_line("+ Munición", false)
			else:
				if player.grenades >= 4:
					continue
				player.grenades += 1
				ui.feed_line("+1 Granada", true)
			sfx.play("mag_in", -4)
			n.queue_free()
			pickups.erase(p)
		elif p.t <= 0.0:
			n.queue_free()
			pickups.erase(p)


func on_player_hit() -> void:
	streak = 0
	wave_hit = true
	# the killstreak survives light hits; it is lost when badly wounded
	if player and player.health < player.max_health * 0.5:
		ks = 0
		ks_given = {}


func hud_info() -> String:
	var t := "Granadas: %d   ·   Racha: %d" % [player.grenades, ks]
	if radar_t > 0.0:
		t += "\nUAV activo %ds" % ceili(radar_t)
	if not streak_ready.is_empty():
		t += "\n[B] " + {"bomber": "Bombardero", "heli": "Helicóptero furtivo"}[streak_ready[0]]
	return t


func use_streak() -> void:
	if streak_ready.is_empty() or state != "playing" or player == null:
		return
	var kind: String = streak_ready.pop_front()
	var cam: Camera3D = player.camera
	if kind == "bomber":
		# carpet bombing along where the player is looking
		var fwd: Vector3 = -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_transform.basis.z * 90.0, 1)
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		var center: Vector3 = hit.position if not hit.is_empty() else player.global_position + fwd * 30.0
		center.y = 0.0
		var pflat := Vector3(player.global_position.x, 0, player.global_position.z)
		if center.distance_to(pflat) < 14.0:
			center = pflat + fwd * 22.0
		ui.notice("BOMBARDERO EN CAMINO", "¡Cuerpo a tierra!", 2.0)
		air.bomber(center, fwd)
	else:
		ui.notice("HELICÓPTERO FURTIVO", "Apoyo aéreo durante 35 segundos", 2.0)
		air.heli(35.0)


## Explosion damage with falloff and wall occlusion; credits kills for medals.
func explode(pos: Vector3, dmg: float, radius: float, kind: String) -> void:
	if state != "playing" and state != "paused":
		return
	fx.explosion(pos, radius / 7.5)
	sfx.play3d("boom", pos, 4.0)
	if net.active:
		net.boom(pos, radius)
	var space := world.get_world_3d().direct_space_state
	var n_kill := 0
	for e in enemies.duplicate():
		if not is_instance_valid(e) or e.dead:
			continue
		var c: Vector3 = e.global_position + Vector3(0, 1.0, 0)
		var d := c.distance_to(pos + Vector3(0, 0.4, 0))
		if d > radius:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.4, 0), c, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		kill_ctx = {"weapon": -2, "melee": false, "last": false, "dist": 10.0, "hp": player.health if player else 100.0, "kind": kind}
		if e.take_damage(dmg * pow(1.0 - d / radius, 0.6), false):
			n_kill += 1
		kill_ctx = {}
	if n_kill >= 2:
		award_medal("boom")
	if player and player.alive:
		var pd := player.global_position.distance_to(pos)
		player.shake = maxf(player.shake, clampf(1.2 - pd / 30.0, 0.0, 1.0))
		if pd < radius * 0.9 and kind == "grenade":
			var q2 := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.4, 0), player.global_position + Vector3(0, 1.0, 0), 1)
			if space.intersect_ray(q2).is_empty():
				player.take_damage(dmg * 0.55 * (1.0 - pd / radius), pos)


func damage_player(amount: float, from: Vector3) -> void:
	if player and player.alive:
		player.take_damage(amount * DIFF_DMG[settings.diff], from)


# ---------------------------------------------------------------- automated checks (used while developing)
func _autotest() -> void:
	await get_tree().process_frame
	var log := []
	# every map builds and bakes
	for i in WorldBuilder.MAPS.size():
		load_map(i)
		await get_tree().process_frame
		log.append("%s: polys=%d spawns=%s" % [WorldBuilder.MAPS[i].name, nav.navigation_mesh.get_polygon_count(), str(spawns.size()) if mode == "ops" else str(WorldBuilder.zlayout.spawns.values().map(func(a): return a.size()))])
	# operation mode on the city map
	load_map(0)
	start_game()
	player.god = true
	await get_tree().create_timer(7.0).timeout
	log.append("wave=%d alive=%d" % [wave, alive_count()])
	player.test_fire(40)
	await get_tree().create_timer(2.0).timeout
	for w in player.weapons.size():
		player.test_switch(w)
		await get_tree().create_timer(0.6).timeout
		player.test_reload(true)
		await get_tree().create_timer(4.0).timeout
		log.append("%s:%d/%d" % [player.weapons[w].short, player.weapons[w].ammo, player.weapons[w].reserve])
	player.melee()
	await get_tree().create_timer(0.8).timeout
	streak_ready = ["bomber", "heli"]
	use_streak()
	use_streak()
	air.uav(5.0)
	await get_tree().create_timer(8.0).timeout
	log.append("streaks craft=%d bombs=%d kills=%d" % [air.craft.size(), air.bombs.size(), kills])
	for e in enemies:
		if is_instance_valid(e) and not e.dead:
			e.take_damage(999.0, true)
	await get_tree().create_timer(9.0).timeout
	var loot_n := pickups.size()
	var res0: int = player.weapons[player.cur].reserve
	if loot_n > 0:
		player.global_position = pickups[0].node.global_position + Vector3(0, 0.2, 0)
		await get_tree().create_timer(0.4).timeout
	log.append("loot=%d picked=%s" % [loot_n, str(pickups.size() < loot_n)])
	log.append("kills=%d score=%d wave=%d medals=%s" % [kills, score, wave, str(medals_game)])
	# zombies mode
	load_map(3)
	start_game()
	player.god = true
	zm.points = 50000
	await get_tree().create_timer(9.0).timeout
	log.append("Z round=%d alive=%d (sin abrir puertas)" % [zm.round_n, alive_count()])
	player.global_position = Vector3(0, 0.2, -10.5)
	await get_tree().create_timer(0.3).timeout
	zm._update_interact()
	var tt: String = zm.target.get("type", "none")
	zm.interact()
	await get_tree().create_timer(1.5).timeout
	log.append("door target=%s active=%s" % [tt, str(zm.active.keys())])
	player.global_position = Vector3(-6, 0.2, -10.6)
	await get_tree().create_timer(0.3).timeout
	zm._update_interact()
	zm.interact()
	await get_tree().create_timer(0.8).timeout
	log.append("owned=%s cur=%d" % [str(player.owned), player.cur])
	player.global_position = Vector3(-8, 0.2, -28.3)
	await get_tree().create_timer(0.3).timeout
	zm._update_interact()
	var bt: String = zm.target.get("type", "none")
	zm.interact()
	await get_tree().create_timer(3.4).timeout
	zm._update_interact()
	zm.interact()
	log.append("box target=%s owned=%s" % [bt, str(player.owned)])
	player.global_position = Vector3(8, 0.2, -28.3)
	await get_tree().create_timer(0.3).timeout
	zm._update_interact()
	var ft: String = zm.target.get("type", "none")
	zm.interact()
	log.append("forge target=%s upgraded=%s name=%s" % [ft, str(player.weapons[player.cur].get("up", false)), player.weapons[player.cur].name])
	for k in 3:
		for e in enemies:
			if is_instance_valid(e) and not e.dead and e.rise_t <= 0.0:
				e.take_damage(99999.0, randf() < 0.5)
		await get_tree().create_timer(4.0).timeout
	log.append("Z after: round=%d kills=%d points=%d alive=%d medals=%s" % [zm.round_n, kills, zm.points, alive_count(), str(medals_game)])
	print("AUTOTEST ", " | ".join(log))
	get_tree().quit()


## Two-instance network check: one host, one client, each damages the other through the network.
func _mptest(role: String) -> void:
	await get_tree().process_frame
	var log := []
	var mm := arg_value("--mpmode") if arg_value("--mpmode") != "" else "ffa"
	if role == "host":
		net.host("Anfitrión", 3 if mm == "zombies" else 0, net.PORT, mm)
		player.god = true
		if zm:
			zm.inter = 2.0
		var t := 0.0
		while net.players.size() < 2 and t < 20.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		log.append("mode=%s players=%d" % [net.gmode, net.players.size()])
		await get_tree().create_timer(4.0).timeout
		var cid := 0
		for id in net.players:
			if id != 1:
				cid = id
		log.append("puppet_client=%s ally=%s" % [str(net.puppets.has(cid)), str(net.is_ally(cid))])
		if mm == "tdm":
			log.append("teams host=%d client=%d" % [net.team_of(1), net.team_of(cid)])
			# put the client on the other team so the hit counts
			net.players[cid].team = 1 - net.team_of(1)
			net.rpc("sync_players", net.players)
			await get_tree().create_timer(0.5).timeout
		if mm == "zombies":
			log.append("host_zombies=%d round=%d" % [alive_count(), zm.round_n])
		else:
			net.send_hit(cid, 250.0, true)
		await get_tree().create_timer(9.0).timeout
		if mm == "gun":
			log.append("host_gun_lvl=%d owned=%s" % [int(net.players[1].lvl), str(player.owned)])
		if mm == "tdm":
			log.append("team_kills=%s" % str(net.team_kills))
		if mm == "zombies":
			log.append("host_zombies_end=%d" % alive_count())
	else:
		await get_tree().create_timer(1.5).timeout
		if role == "lanjoin":   # find the host through the LAN beacon instead of a typed IP
			ui.show_mp()
			var tl := 0.0
			while net.lan_games.is_empty() and tl < 30.0:
				await get_tree().create_timer(0.25).timeout
				tl += 0.25
			var found: Array = net.lan_games.values()
			log.append("listen_ok=%s lan_found=%d %s" % [str(net.listen_ok), found.size(), str(found[0]) if not found.is_empty() else ""])
			if found.is_empty():
				print("MPTEST ", role, " ", " | ".join(log))
				get_tree().quit()
				return
			net.join("Cliente", found[0].ip, found[0].port)
		else:
			net.join("Cliente", "127.0.0.1")
		var t2 := 0.0
		while state != "playing" and t2 < 20.0:
			await get_tree().create_timer(0.25).timeout
			t2 += 0.25
		await get_tree().create_timer(2.0).timeout
		log.append("in_game=%s mode=%s gmode=%s map=%d puppet_host=%s" % [str(state == "playing"), mode, net.gmode, map_idx, str(net.puppets.has(1))])
		net.shot(Vector3(0, 1, 0))
		if net.gmode == "zombies":
			player.god = true
			await get_tree().create_timer(3.0).timeout
			var remote_n := 0
			var first = null
			for e in enemies:
				if is_instance_valid(e) and e.get("remote") == true and not e.dead:
					remote_n += 1
					if first == null:
						first = e
			var p0: int = zm.points
			log.append("client_remote_zombies=%d round=%d" % [remote_n, zm.round_n])
			if first != null:
				first.take_damage(1.0e6, true)
			await get_tree().create_timer(1.5).timeout
			log.append("points %d -> %d kills=%d" % [p0, zm.points, kills])
		else:
			net.send_hit(1, 60.0, false)
			net.send_hit(1, 60.0, false)
		await get_tree().create_timer(6.0).timeout
		if net.gmode == "gun":
			log.append("client_owned=%s" % str(player.owned))
		log.append("alive_after_respawn=%s" % str(player != null and player.alive))
		await get_tree().create_timer(4.0).timeout
	var sc := []
	for id in net.players:
		sc.append("%s:%d/%d" % [net.players[id].name, net.players[id].kills, net.players[id].deaths])
	log.append("scores=" + " ".join(sc))
	print("MPTEST ", role, " ", " | ".join(log))
	net.leave()
	get_tree().quit()


func _perf() -> void:
	await get_tree().process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	start_game()
	player.god = true
	intermission = 999.0
	var out := []
	if has_arg("--stress"):
		settings.quality = int(arg_value("--q")) if arg_value("--q") != "" else 0
		apply_quality()
		if zm:
			zm.inter = 999.0
		for i in 20:
			var z = ZombieScript.new()
			z.game = self
			z.round_n = 5
			add_child(z)
			var a := TAU * i / 20.0
			z.global_position = player.global_position + Vector3(cos(a) * 9.0, 0.2, sin(a) * 9.0 - 6.0)
			z.rise_t = 0.0
			enemies.append(z)
		await get_tree().create_timer(2.0).timeout
		var a4 := 0.0
		for i in 4:
			await get_tree().create_timer(0.7).timeout
			a4 += Engine.get_frames_per_second()
		print("PERF stress20 q%d=%d draw_calls=%d" % [settings.quality, int(a4 / 4.0), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		get_tree().quit()
		return
	if has_arg("--diag4"):
		settings.quality = 2
		apply_quality()
		var e4: Environment = env_node.environment
		var vp4 := get_viewport()
		for t in ["alta", "nosdfgi", "nossil", "nossr", "novolfog", "nomsaa", "shadow2k", "softlow"]:
			match t:
				"nosdfgi":
					e4.sdfgi_enabled = false
				"nossil":
					e4.ssil_enabled = false
				"nossr":
					e4.ssr_enabled = false
				"novolfog":
					e4.volumetric_fog_enabled = false
				"nomsaa":
					vp4.msaa_3d = Viewport.MSAA_DISABLED
				"shadow2k":
					RenderingServer.directional_shadow_atlas_set_size(2048, true)
				"softlow":
					RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			await get_tree().create_timer(2.5).timeout
			var a6 := 0.0
			for i in 3:
				await get_tree().create_timer(0.7).timeout
				a6 += Engine.get_frames_per_second()
			out.append("%s=%d" % [t, int(a6 / 3.0)])
		print("PERF ", " ".join(out))
		get_tree().quit()
		return
	if has_arg("--diag3"):
		settings.quality = 0
		apply_quality()
		var mats := {}
		for mi in world.find_children("*", "MeshInstance3D", true, false):
			if mi.material_override is StandardMaterial3D:
				mats[mi.material_override] = mi
		var steps := ["base", "noaniso", "planar_ground", "notriplanar"]
		for t in steps:
			for m in mats:
				if t == "noaniso" and m.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:
					m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				if t == "planar_ground" and mats[m].mesh is PlaneMesh and m.uv1_triplanar:
					m.uv1_triplanar = false
					m.uv1_scale = Vector3(100, 100, 1)
				if t == "notriplanar":
					m.uv1_triplanar = false
			await get_tree().create_timer(2.0).timeout
			var a5 := 0.0
			for i in 3:
				await get_tree().create_timer(0.7).timeout
				a5 += Engine.get_frames_per_second()
			out.append("%s=%d" % [t, int(a5 / 3.0)])
		print("PERF ", " ".join(out))
		get_tree().quit()
		return
	if has_arg("--diag2"):
		var vp := get_viewport()
		var cfgs := [[0, "fsr1", 0.77], [0, "fsr2", 0.67], [0, "fsr2", 0.77], [1, "bil", 1.0], [1, "fsr2", 0.77], [1, "fsr2", 0.67], [2, "fsr2", 0.67]]
		for c in cfgs:
			settings.quality = c[0]
			apply_quality()
			vp.scaling_3d_mode = {"fsr1": Viewport.SCALING_3D_MODE_FSR, "fsr2": Viewport.SCALING_3D_MODE_FSR2, "bil": Viewport.SCALING_3D_MODE_BILINEAR}[c[1]]
			vp.scaling_3d_scale = c[2]
			if c[1] == "fsr2":
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
				vp.msaa_3d = Viewport.MSAA_DISABLED
			await get_tree().create_timer(2.5).timeout
			var a3 := 0.0
			for i in 3:
				await get_tree().create_timer(0.7).timeout
				a3 += Engine.get_frames_per_second()
			out.append("q%d_%s_%.2f=%d" % [c[0], c[1], c[2], int(a3 / 3.0)])
		print("PERF ", " ".join(out))
		get_tree().quit()
		return
	if has_arg("--diag5"):
		settings.quality = 0
		apply_quality()
		for t in ["all", "nogi_fill", "nooccl"]:
			match t:
				"nogi_fill":
					fill.visible = false
				"nooccl":
					get_viewport().use_occlusion_culling = false
			await get_tree().create_timer(2.0).timeout
			var a7 := 0.0
			for k in 3:
				await get_tree().create_timer(0.7).timeout
				a7 += Engine.get_frames_per_second()
			out.append("%s=%d" % [t, int(a7 / 3.0)])
		print("PERF ", " ".join(out))
		get_tree().quit()
		return
	if has_arg("--diag"):
		settings.quality = 0
		apply_quality()
		var e: Environment = env_node.environment
		var tests := ["base", "noweather", "noshadow", "noglow", "nofog", "noviewmodel", "nosky", "noadjust", "nolights"]
		for t in tests:
			match t:
				"noweather":
					fx.set_weather("")
				"noshadow":
					sun.shadow_enabled = false
				"noglow":
					e.glow_enabled = false
				"nofog":
					e.fog_enabled = false
				"noviewmodel":
					player.holder.visible = false
				"nosky":
					e.background_mode = Environment.BG_COLOR
				"noadjust":
					e.adjustment_enabled = false
				"nolights":
					for l in world.find_children("*", "OmniLight3D", true, false):
						l.visible = false
			await get_tree().create_timer(2.0).timeout
			var a2 := 0.0
			for i in 3:
				await get_tree().create_timer(0.7).timeout
				a2 += Engine.get_frames_per_second()
			out.append("%s=%d" % [t, int(a2 / 3.0)])
		print("PERF ", " ".join(out))
		get_tree().quit()
		return
	for q in [0, 1, 2]:
		settings.quality = q
		apply_quality()
		await get_tree().create_timer(4.0).timeout
		var acc := 0.0
		for i in 3:
			await get_tree().create_timer(1.0).timeout
			acc += Engine.get_frames_per_second()
		out.append("q%d=%d" % [q, int(acc / 3.0)])
	print("PERF ", " ".join(out), " res=", get_viewport().get_visible_rect().size)
	settings.quality = 1
	get_tree().quit()


func _shot(kind: String, out: String) -> void:
	await get_tree().process_frame
	var q := arg_value("--q")
	if q != "":
		settings.quality = int(q)
		apply_quality()
	if kind.begins_with("inspect"):
		start_game()
		intermission = 999.0
		player.god = true
		player.global_position = Vector3(-3, 0.2, 7)
		player.yaw = 2.6
		player.pitch = 0.0
		var parts := kind.split("_")
		player.test_switch(int(parts[1]))
		player.inspect_on = true
		player.inspect_rot = Vector3(float(parts[2]), float(parts[3]), 0.0)
		player.camera.fov = 40.0
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		get_tree().quit()
		return
	if arg_value("--op") != "":
		settings["op"] = int(arg_value("--op"))
	if kind == "menu":
		await get_tree().create_timer(3.0).timeout
	elif kind == "zwall" or kind == "zbox":
		start_game()
		player.god = true
		zm.inter = 999.0
		zm.points = 99999
		for k in ["armor", "hands", "pulse"]:
			zm.perks_owned.append(k)
		if kind == "zwall":
			player.global_position = Vector3(-6, 0.2, -9.6)
			player.yaw = 0.0
			player.pitch = 0.05
		else:
			player.global_position = Vector3(-8, 0.2, -26.5)
			player.yaw = 0.0
			player.pitch = -0.1
			zm._update_interact()
			zm.target = {"type": "box", "ref": zm.L.box}
			zm.interact()
		await get_tree().create_timer(1.4).timeout
	elif kind == "opmenu":
		settings["name"] = "Arnul"
		ui.show_ops()
		await get_tree().create_timer(2.0).timeout
	elif kind == "map":
		# overview from the player start, no enemies
		start_game()
		intermission = 999.0
		player.god = true
		var pv := arg_value("--pos")
		if pv != "":
			var c := pv.split(",")
			player.global_position = Vector3(float(c[0]), float(c[1]), float(c[2]))
		var yw := arg_value("--yaw")
		if yw != "":
			player.yaw = float(yw)
		await get_tree().create_timer(2.5).timeout
	elif kind == "zombies":
		start_game()
		player.god = true
		zm.inter = 999.0
		zm.round_n = 6
		for i in 6:
			var z = ZombieScript.new()
			z.game = self
			z.round_n = 6
			add_child(z)
			z.global_position = player.global_position + Vector3(randf_range(-4, 4), 0.2, -5.0 - i * 1.3)
			z.rise_t = 0.0
			enemies.append(z)
		await get_tree().create_timer(1.6).timeout
	else:
		start_game()
		intermission = 999.0
		player.global_position = Vector3(-3, 0.2, 7)
		player.yaw = 0.35
		player.pitch = 0.0
		for p in [Vector3(-6, 0.3, -6), Vector3(-1.5, 0.3, -9), Vector3(2.5, 0.3, -4)]:
			var s = SoldierScript.new()
			s.game = self
			add_child(s)
			s.global_position = p
			enemies.append(s)
		await get_tree().create_timer(3.0).timeout
		var names := ["rifle", "shotgun", "pistol", "smg", "sniper", "lmg"]
		if kind in names:
			player.test_switch(names.find(kind))
			await get_tree().create_timer(0.5).timeout
		if kind == "scope":
			player.test_switch(4)
			player.aiming = true
			await get_tree().create_timer(0.8).timeout
		if kind == "knife":
			player.melee()
			await get_tree().create_timer(0.17).timeout
		if kind == "grenade":
			player.god = true
			player.pitch = 0.12
			player.throw_grenade()
			await get_tree().create_timer(0.6).timeout
			var fw: Vector3 = -player.camera.global_transform.basis.z
			fw.y = 0.0
			explode(player.global_position + fw.normalized() * 9.0, 10.0, 7.5, "air")
			await get_tree().create_timer(0.12).timeout
		if kind == "heli" or kind == "bomber":
			player.god = true
			player.pitch = 0.45
			if kind == "heli":
				air.heli(30.0)
				await get_tree().create_timer(5.0).timeout
				var hp: Vector3 = air.craft[0].node.global_position
				var dv: Vector3 = hp - player.camera.global_position
				player.yaw = atan2(-dv.x, -dv.z)
				player.pitch = atan2(dv.y, Vector2(dv.x, dv.z).length())
				await get_tree().create_timer(0.1).timeout
			else:
				var fw2: Vector3 = -player.camera.global_transform.basis.z
				fw2.y = 0.0
				air.bomber(player.global_position + fw2.normalized() * 30.0, Vector3(1, 0, 0))
				await get_tree().create_timer(2.6).timeout
		if kind == "ads":
			player.god = true
			player.aiming = true
			player.yaw = 0.42
			await get_tree().create_timer(0.8).timeout
		if kind == "fire":
			player.god = true
			for i in 12:
				player.fire_cd = 0.0
				player.fire()
				await get_tree().create_timer(0.09).timeout
		if kind == "medal":
			award_medal("double")
			await get_tree().create_timer(0.3).timeout
		if kind == "reload":
			player.test_reload(true)
			await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SHOT saved ", out)
	get_tree().quit()
