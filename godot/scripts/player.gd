extends CharacterBody3D
## Player: movement (walk/sprint/crouch/jump/lean), aim-down-sights, spring recoil, hitscan weapons,
## and a hand/magazine reload choreography.

const WM := preload("res://scripts/weapon_models.gd")
const OPT := preload("res://scripts/optimize.gd")
const FPA := preload("res://scripts/fp_arms.gd")
const GRAV := 20.0
const LEAN_DIST := 0.55

var game
var head: Node3D
var camera: Camera3D
var holder: Node3D
var test_iz := 0.0           # automated checks: held "forward" input
var fp_arms = null          # fp_arms.gd: Mixamo arms with IK (null = modelled hands)
var shape: CollisionShape3D
var cap: CapsuleShape3D
var muzzle_light: OmniLight3D

var alive := true
var god := false
var health := 100.0
var last_hit := -99.0
var yaw := 0.0
var pitch := 0.0
var crouch := 0.0
var lean := 0.0
var strafe_roll := 0.0
var aim_k := 0.0
var sprint_k := 0.0
var bob_t := 0.0
var sway := Vector2.ZERO
var kick := 0.0
var view_kick := 0.0
var view_kick_v := 0.0
var recoil_p := 0.0
var recoil_y := 0.0
var land_off := 0.0
var land_v := 0.0
var was_on_floor := true
var shake := 0.0
var step_t := 0.0
var step_last := 0
var mouse_down := false
var aiming := false
var sprinting := false
var flash_t := 0.0
var smoke_n := 0
var fire_cd := 0.0
var cur := 0
var next_w := 0
var switch_t := 0.0
var swapped := true
var reloading := false
var reload_t := 0.0
var reload_dur := 1.0
var reload_empty := false
var reload_given := false
var reload_last_p := 0.0
var shells_to_load := 0
var shells_done := 0
var slide_kick := 0.0
var pump_t := 0.0

var weapons := [
	{"name": "AR-7 Fusil de asalto", "short": "Fusil", "auto": true, "rate": 0.095, "dmg": 30.0, "head": 2.0, "falloff": [35.0, 90.0, 0.75], "mag": 30, "reserve_max": 180, "reload": 2.0,
		"spread": 0.016, "aim_spread": 0.003, "pellets": 1, "recoil": 0.011, "range": 220.0, "fov": 52.0, "snd": "rifle", "ammo": 30, "reserve": 180},
	{"name": "M-12 Escopeta", "short": "Escopeta", "auto": false, "rate": 0.85, "dmg": 15.0, "head": 1.5, "mag": 6, "reserve_max": 36, "reload": 2.5,
		"spread": 0.07, "aim_spread": 0.05, "pellets": 9, "recoil": 0.05, "range": 45.0, "fov": 65.0, "snd": "shotgun", "ammo": 6, "reserve": 36, "falloff": [8.0, 30.0, 0.25]},
	{"name": "P9 Pistola", "short": "Pistola", "auto": false, "rate": 0.16, "dmg": 34.0, "head": 2.2, "falloff": [15.0, 50.0, 0.6], "mag": 12, "reserve_max": 72, "reload": 1.3,
		"spread": 0.014, "aim_spread": 0.004, "pellets": 1, "recoil": 0.022, "range": 120.0, "fov": 60.0, "snd": "pistol", "ammo": 12, "reserve": 72},
	{"name": "V-9 Subfusil", "short": "Subfusil", "auto": true, "rate": 0.07, "dmg": 24.0, "head": 1.8, "mag": 32, "reserve_max": 192, "reload": 1.7,
		"spread": 0.022, "aim_spread": 0.006, "pellets": 1, "recoil": 0.008, "range": 120.0, "fov": 58.0, "snd": "smg", "ammo": 32, "reserve": 192, "falloff": [15.0, 45.0, 0.55], "move": 1.05},
	{"name": "R-700 Francotirador", "short": "Francotirador", "auto": false, "rate": 1.2, "dmg": 120.0, "head": 2.5, "mag": 5, "reserve_max": 30, "reload": 2.6,
		"spread": 0.06, "aim_spread": 0.0, "pellets": 1, "recoil": 0.07, "range": 400.0, "fov": 16.0, "snd": "sniper", "ammo": 5, "reserve": 30, "scope": true, "move": 0.9, "pierce": true},
	{"name": "K-90 Ametralladora", "short": "Ametralladora", "auto": true, "rate": 0.1, "dmg": 32.0, "head": 1.8, "falloff": [40.0, 100.0, 0.8], "mag": 75, "reserve_max": 300, "reload": 3.6,
		"spread": 0.032, "aim_spread": 0.008, "pellets": 1, "recoil": 0.012, "range": 200.0, "fov": 55.0, "snd": "lmg", "ammo": 75, "reserve": 300, "move": 0.82},
]
var owned: Array = [0, 1, 2, 3, 4, 5]
var max_health := 100.0
var reload_mul := 1.0
var rate_mul := 1.0
var knife_node: Node3D
var melee_t := 0.0
var melee_done := false
var bolt_t := 0.0
var scoped := false
var grenades := 3
var throw_t := 0.0
var throw_done := false
var nade_node: Node3D
const MELEE_DUR := 0.5
const THROW_DUR := 0.7
# climbing (mantle onto ledges) and vaulting through windows
var climb_t := -1.0          # >= 0 while a climb/vault is playing
var climb_dur := 0.6
var climb_from := Vector3.ZERO
var climb_mid := Vector3.ZERO
var climb_to := Vector3.ZERO
var climb_vault := false
var climb_k := 0.0           # 0..1, lowers the weapon during the move
var space_was := false
# co-op zombies: watching a living teammate while dead
var spec_id := -1
var spec_pos := Vector3.ZERO
var spec_snap := true
var guns := []
var casings: Array = []
var inspect_on := false
var inspect_rot := Vector3.ZERO
var cam_attr: CameraAttributesPractical

# reload choreography: hand anchor keyframes over normalised time + magazine windows
const KEYS := {
	"magE": [[0.0, "home"], [0.06, "home"], [0.3, "pouch"], [0.44, "below"], [0.54, "well"], [0.6, "well"], [0.7, "handle"], [0.76, "back"], [0.79, "handle"], [0.93, "home"], [1.0, "home"]],
	"magT": [[0.0, "home"], [0.08, "home"], [0.2, "well"], [0.32, "below"], [0.42, "pouch"], [0.52, "below"], [0.62, "well"], [0.68, "well"], [0.86, "home"], [1.0, "home"]],
	"pisE": [[0.0, "home"], [0.05, "home"], [0.25, "pouch"], [0.42, "below"], [0.55, "well"], [0.62, "well"], [0.8, "home"], [1.0, "home"]],
	"pisT": [[0.0, "home"], [0.08, "home"], [0.2, "well"], [0.3, "below"], [0.4, "pouch"], [0.52, "below"], [0.6, "well"], [0.66, "well"], [0.84, "home"], [1.0, "home"]],
}
const PLANS := {
	"magE": {"k": "magE", "drop": [0.06, 0.3], "hold": [0.3, 0.54], "ins": [0.54, 0.6], "rack": [0.7, 0.79], "give": 0.6},
	"magT": {"k": "magT", "grab": [0.2, 0.42], "hold": [0.42, 0.62], "ins": [0.62, 0.68], "give": 0.68},
	"pisE": {"k": "pisE", "drop": [0.05, 0.25], "hold": [0.25, 0.55], "ins": [0.55, 0.62], "slide": 0.72, "give": 0.62},
	"pisT": {"k": "pisT", "grab": [0.2, 0.4], "hold": [0.4, 0.6], "ins": [0.6, 0.66], "give": 0.66},
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 4
	collision_mask = 1 | 2
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	shape = CollisionShape3D.new()
	cap = CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	head = Node3D.new()
	head.position.y = 1.65
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.03
	camera.far = 700.0
	head.add_child(camera)
	holder = Node3D.new()
	camera.add_child(holder)
	cam_attr = CameraAttributesPractical.new()
	# aiming focus: the target stays sharp, only the gun right in front of the eye softens
	cam_attr.dof_blur_far_enabled = false
	cam_attr.dof_blur_near_distance = 0.5
	cam_attr.dof_blur_near_transition = 0.4
	cam_attr.dof_blur_amount = 0.0
	camera.attributes = cam_attr
	var opd: Dictionary = preload("res://scripts/operators.gd").get_op(int(game.settings.get("op", 0)))
	WM.glove_col = opd.glove
	WM.sleeve_col = opd.sleeve
	# real arms (operator's Mixamo body + IK) replace the modelled hands when available
	WM.no_hands = FPA.available()
	guns = [WM.rifle(), WM.shotgun(), WM.pistol(), WM.smg(), WM.sniper(), WM.lmg()]
	WM.no_hands = false
	if FPA.available():
		fp_arms = FPA.new()
		fp_arms.build(camera, opd.body, opd.tint)
	for i in guns.size():
		holder.add_child(guns[i].model)
		guns[i].model.visible = i == 0
		_store_homes(guns[i])
	knife_node = WM.knife()
	knife_node.visible = false
	holder.get_parent().add_child(knife_node)
	nade_node = WM.grenade_hand()
	nade_node.visible = false
	holder.get_parent().add_child(nade_node)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.72, 0.4)
	muzzle_light.omni_range = 7.0
	muzzle_light.light_energy = 0.0
	muzzle_light.position = Vector3(0.2, -0.1, -1.0)
	camera.add_child(muzzle_light)


func _store_homes(g: Dictionary) -> void:
	g.left_home = g.left.position
	if g.has("mag"):
		g.mag_home = g.mag.position
		g.mag_rot = g.mag.rotation
	if g.has("handle"):
		g.handle_home = g.handle.position
	if g.has("slide"):
		g.slide_home = g.slide.position
	if g.has("pump"):
		g.pump_home = g.pump.position
	var well: Vector3 = (g.mag_home + Vector3(-0.025, -0.07, 0.03)) if g.has("mag") else g.left_home
	var hnd: Vector3 = (g.handle_home + Vector3(-0.04, -0.01, 0)) if g.has("handle") else g.left_home
	g.anch = {"home": g.left_home, "well": well, "below": well + Vector3(-0.03, -0.14, 0.05), "pouch": Vector3(-0.17, -0.52, 0.12),
		"handle": hnd, "back": hnd + Vector3(0, 0, 0.07), "port": Vector3(0, -0.085, -0.02), "port_in": Vector3(0, -0.07, -0.08), "pouch_s": Vector3(-0.06, -0.45, 0.16)}
	if g.has("mag"):
		g.grab = g.mag_home - well


# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if game.state != "playing" or game.ui.chat_open:
		return
	if not alive:
		# co-op zombies: left click switches which teammate the camera follows
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			spectate_next()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = 0.0022 * game.settings.sens * (maxf(0.25, camera.fov / 75.0) if aim_k > 0.5 else 1.0)
		yaw -= event.relative.x * s
		pitch = clampf(pitch - event.relative.y * s, -1.5, 1.5)
		sway.x = clampf(sway.x - event.relative.x * 0.0004, -0.04, 0.04)
		sway.y = clampf(sway.y + event.relative.y * 0.0004, -0.04, 0.04)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			mouse_down = event.pressed
			if event.pressed and not weapons[cur].auto:
				fire()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			aiming = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle_weapon(1)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_weapon(-1)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				start_reload()
			KEY_V:
				melee()
			KEY_G:
				throw_grenade()
			KEY_B:
				game.use_streak()
			KEY_F:
				game.interact()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var slot: int = event.physical_keycode - KEY_1
				if game.mode == "zombies":
					if slot < owned.size():
						switch_weapon(owned[slot])
				elif slot in owned:
					switch_weapon(slot)


# ---------------------------------------------------------------- movement + camera
func eye_height() -> float:
	return lerpf(1.65, 1.05, crouch)


func _physics_process(delta: float) -> void:
	if not alive:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAV * delta
		move_and_slide()
		_spectate(delta)
		return
	var in_ctrl: bool = game.state == "playing" and not game.ui.chat_open
	# Space: climb/vault when facing a ledge or window (also while jumping at one), else jump
	var space_now := Input.is_physical_key_pressed(KEY_SPACE) and in_ctrl
	var space_hit := space_now and not space_was
	space_was = space_now
	if climb_t < 0.0 and (space_hit or (space_now and not is_on_floor() and velocity.y < 3.0)):
		_try_climb()
	if climb_t >= 0.0:
		_climb_update(delta)
		return
	climb_k = maxf(0.0, climb_k - delta * 4.0)
	var crouching := Input.is_physical_key_pressed(KEY_C) and in_ctrl
	crouch = lerpf(crouch, 1.0 if crouching else 0.0, 1.0 - exp(-12.0 * delta))
	var ix := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var iz := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)) + test_iz
	if not in_ctrl:
		ix = 0.0
		iz = 0.0
		mouse_down = false
	sprinting = Input.is_physical_key_pressed(KEY_SHIFT) and iz > 0.0 and not aiming and not crouching and not mouse_down and is_on_floor()
	sprint_k = lerpf(sprint_k, 1.0 if sprinting else 0.0, 1.0 - exp(-10.0 * delta))
	var speed: float = (8.2 if sprinting else (3.4 if aiming else (2.8 if crouching else 5.4))) * weapons[cur].get("move", 1.0)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var wish := right * ix + fwd * iz
	if wish.length() > 0.0:
		wish = wish.normalized() * speed
	var k := 1.0 - exp(-(14.0 if is_on_floor() else 3.0) * delta)
	velocity.x = lerpf(velocity.x, wish.x, k)
	velocity.z = lerpf(velocity.z, wish.z, k)
	if is_on_floor():
		if space_now:
			velocity.y = 7.0
	else:
		velocity.y -= GRAV * delta
	var vy := velocity.y
	cap.height = lerpf(1.8, 1.25, crouch)
	shape.position.y = cap.height * 0.5
	move_and_slide()
	if is_on_floor() and not was_on_floor and vy < -4.0:
		land_v -= minf(0.9, -vy * 0.08)
		game.sfx.play("land", -4, 0.04)
	was_on_floor = is_on_floor()
	rotation.y = yaw
	var hs := Vector2(velocity.x, velocity.z).length()
	# footsteps
	if is_on_floor() and hs > 1.5:
		step_t -= delta * hs / 5.4
		if step_t <= 0.0:
			step_t = 0.42
			# never the same sample twice in a row; louder when sprinting, very soft crouched
			var si := randi() % 5
			if si >= step_last:
				si += 1
			step_last = si
			var vol := -16.0 if crouch > 0.5 else (-8.0 if hs > 6.0 else -11.0)
			game.sfx.play("step%d" % (si + 1), vol, 0.06)
	# lean (Q/E), blocked by walls at the side
	var lt := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	if sprinting or not in_ctrl:
		lt = 0.0
	if lt != 0.0:
		var from := global_position + Vector3(0, eye_height(), 0)
		var space := get_world_3d().direct_space_state
		var f := 1.0
		while f > 0.0:
			var to := from + right * (LEAN_DIST * f + 0.35) * lt
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])).is_empty():
				break
			f -= 0.25
		lt *= maxf(0.0, f)
	lean = lerpf(lean, lt, 1.0 - exp(-11.0 * delta))
	# recoil (smooth climb + spring kick), landing dip, strafe roll
	var rp := recoil_p * minf(1.0, delta * 22.0)
	var ry := recoil_y * minf(1.0, delta * 22.0)
	pitch = clampf(pitch + rp, -1.5, 1.5)
	yaw += ry
	recoil_p -= rp
	recoil_y -= ry
	view_kick_v += (-view_kick * 120.0 - view_kick_v * 16.0) * delta
	view_kick += view_kick_v * delta
	land_v += (-land_off * 90.0 - land_v * 12.0) * delta
	land_off += land_v * delta
	var lat := velocity.x * cos(yaw) - velocity.z * sin(yaw)
	strafe_roll = lerpf(strafe_roll, -lat * 0.0035 * (1.0 - aim_k), 1.0 - exp(-8.0 * delta))
	shake = maxf(0.0, shake - delta * 2.5)
	var sh := shake * shake * 0.12
	if is_on_floor() and hs > 0.5:
		bob_t += delta * hs * 1.6
	head.position = Vector3(lean * LEAN_DIST + randf_range(-sh, sh), eye_height() - absf(lean) * 0.08 + land_off + randf_range(-sh, sh), 0)
	camera.rotation = Vector3(pitch + view_kick + randf_range(-sh, sh) * 0.3, 0, -lean * 0.22 + strafe_roll + sin(bob_t * 0.5) * 0.004 * hs * (1.0 - aim_k))
	var w: Dictionary = weapons[cur]
	aim_k = lerpf(aim_k, 1.0 if aiming and not sprinting and switch_t <= 0.0 and not reloading else 0.0, 1.0 - exp(-14.0 * delta))
	var target_fov: float = lerpf(82.0 if sprint_k > 0.5 else 75.0, w.fov, aim_k)
	cam_attr.dof_blur_near_enabled = aim_k > 0.05 and game.settings.quality >= 1 and not scoped
	cam_attr.dof_blur_amount = 0.035 * aim_k
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-12.0 * delta))
	if scoped:
		camera.rotation.x += sin(game.clock * 1.3) * 0.0016
		camera.rotation.y = sin(game.clock * 0.9) * 0.002
	# regeneration
	if game.clock - last_hit > 4.0 and health < max_health:
		health = minf(max_health, health + 28.0 * delta)
	_update_weapon(delta, hs)


# ---------------------------------------------------------------- death / respawn
## Cancel everything that was in progress (trigger held, aiming, reload, knife, grenade, climb...).
## Called on death and on respawn: input released while dead never reaches the player, so without
## this you came back still firing / aiming / mid-reload.
func reset_actions() -> void:
	mouse_down = false
	aiming = false
	sprinting = false
	reloading = false
	reload_t = 0.0
	reload_given = false
	shells_to_load = 0
	shells_done = 0
	melee_t = 0.0
	melee_done = true
	throw_t = 0.0
	throw_done = true
	switch_t = 0.0
	next_w = cur
	swapped = true
	bolt_t = 0.0
	pump_t = 0.0
	fire_cd = 0.0
	flash_t = 0.0
	kick = 0.0
	recoil_p = 0.0
	recoil_y = 0.0
	view_kick = 0.0
	view_kick_v = 0.0
	land_off = 0.0
	land_v = 0.0
	aim_k = 0.0
	sprint_k = 0.0
	shake = 0.0
	lean = 0.0
	crouch = 0.0
	scoped = false
	inspect_on = false
	climb_t = -1.0
	climb_k = 0.0
	space_was = Input.is_physical_key_pressed(KEY_SPACE)
	velocity = Vector3.ZERO
	cap.height = 1.8
	shape.position.y = 0.9
	if knife_node:
		knife_node.visible = false
	if nade_node:
		nade_node.visible = false
	# put the moving parts of every gun back in place (a reload may have been cut in half)
	for i in guns.size():
		var g: Dictionary = guns[i]
		g.model.visible = i == cur
		g.left.position = g.left_home
		if g.has("mag"):
			g.mag.position = g.mag_home
			g.mag.rotation = g.mag_rot
			g.mag.visible = true
		if g.has("handle"):
			g.handle.position = g.handle_home
			g.handle.rotation.z = 0.0
		if g.has("slide"):
			g.slide.position = g.slide_home
		if g.has("pump"):
			g.pump.position = g.pump_home
	_end_spectate()


# ---------------------------------------------------------------- spectating (co-op zombies)
func _spectate_ids() -> Array:
	var ids := []
	if game.net.is_coop():
		for id in game.net.puppets:
			var pp = game.net.puppets[id]
			if is_instance_valid(pp) and not pp.dead:
				ids.append(id)
	ids.sort()
	return ids


func spectate_next() -> void:
	var ids := _spectate_ids()
	if ids.is_empty():
		return
	var k := ids.find(spec_id)
	spec_id = ids[(k + 1) % ids.size()]
	spec_snap = true
	game.sfx.play("click", -8)


## HUD line while watching a teammate ("" when not spectating).
func spectate_label() -> String:
	if alive or spec_id < 0 or not game.net.puppets.has(spec_id):
		return ""
	var n: String = game.net.players.get(spec_id, {}).get("name", "?")
	var many := _spectate_ids().size() > 1
	return "Observando a %s%s" % [n, "  ·  Clic izquierdo: cambiar de jugador" if many else ""]


## While dead in co-op: over-the-shoulder camera on a living teammate, following where they look.
func _spectate(delta: float) -> void:
	var ids := _spectate_ids()
	if ids.is_empty():
		_end_spectate()
		return
	if not spec_id in ids:
		spec_id = ids[0]
		spec_snap = true
	var pp = game.net.puppets[spec_id]
	var fy: float = pp.net_yaw
	var fp: float = clampf(pp.net_pitch, -1.1, 1.1)
	var look := Vector3(-sin(fy) * cos(fp), sin(fp), -cos(fy) * cos(fp))
	var side := Vector3(cos(fy), 0, -sin(fy))
	var headp: Vector3 = pp.global_position + Vector3(0, 1.6, 0)
	var want := headp - look * 2.3 + side * 0.55 + Vector3(0, 0.3, 0)
	# don't put the camera inside a wall
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(headp, want, 1))
	if not hit.is_empty():
		want = hit.position + (headp - want).normalized() * 0.25
	spec_pos = want if spec_snap else spec_pos.lerp(want, 1.0 - exp(-12.0 * delta))
	spec_snap = false
	camera.top_level = true
	holder.visible = false
	camera.fov = lerpf(camera.fov, 75.0, 1.0 - exp(-8.0 * delta))
	camera.global_position = spec_pos
	camera.look_at(headp + look * 12.0, Vector3.UP)


func _end_spectate() -> void:
	if camera == null or not camera.top_level:
		return
	camera.top_level = false
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	holder.visible = true
	spec_id = -1


# ---------------------------------------------------------------- climbing / vaulting
## Space facing an obstacle: climb onto it (top 0.45 - 2.25 m above the feet, with room to stand)
## or, if it is a window (sill with a clear opening above it), vault through to the other side.
func _try_climb() -> bool:
	if reloading and guns[cur].kind == "shell":
		reloading = false
	var space := get_world_3d().direct_space_state
	var rid := [get_rid()]
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var feet := global_position
	var hit := {}
	for hgt in [0.55, 1.0, 1.45]:
		var o := feet + Vector3(0, hgt, 0)
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + fwd * 0.95, 1, rid))
		if not r.is_empty() and absf(r.normal.y) < 0.5:
			hit = r
			break
	if hit.is_empty():
		return false
	var into := -Vector3(hit.normal.x, 0, hit.normal.z).normalized()
	if into.dot(fwd) < 0.45:
		return false
	var edge := Vector3(hit.position.x, feet.y, hit.position.z)
	var probe := edge + into * 0.3
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(probe + Vector3(0, 2.45, 0), probe + Vector3(0, 0.3, 0), 1, rid))
	if down.is_empty() or down.normal.y < 0.7:
		return false
	var top: float = down.position.y
	var rise := top - feet.y
	# zombies: never above 2.3 m, so the zone walls (3.6 m) can't be skipped from crates
	var max_y := 2.3 if game.mode == "zombies" else 99.0
	# 1) climb onto the top
	if rise > 0.45 and rise < 2.25 and top <= max_y:
		var land := Vector3(probe.x, top + 0.03, probe.z) + into * 0.25
		if _fits(land):
			_start_climb(Vector3(feet.x, top + 0.12, feet.z), land, 0.32 + rise * 0.2, false)
			return true
	# 2) window: clear opening above the sill -> vault through and land on the other side
	if rise > 0.3 and rise < 1.6:
		var o2 := Vector3(edge.x, top + 0.5, edge.z) - into * 0.3
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(o2, o2 + into * 1.9, 1, rid)).is_empty():
			var far := edge + into * 1.35
			var fl := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(far.x, top + 0.4, far.z), Vector3(far.x, feet.y - 2.5, far.z), 1, rid))
			if not fl.is_empty() and fl.normal.y > 0.7:
				var land2 := Vector3(far.x, fl.position.y + 0.03, far.z)
				if land2.y <= max_y and _fits(land2):
					_start_climb(Vector3(edge.x, top + 0.12, edge.z) - into * 0.15, land2, 0.62, true)
					return true
	return false


func _fits(pos: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var c := CapsuleShape3D.new()
	c.radius = 0.32
	c.height = 1.75
	q.shape = c
	q.transform = Transform3D(Basis(), pos + Vector3(0, 0.95, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _start_climb(mid: Vector3, to: Vector3, dur: float, vault: bool) -> void:
	climb_from = global_position
	climb_mid = mid
	climb_to = to
	climb_dur = dur
	climb_vault = vault
	climb_t = 0.0
	aiming = false
	sprinting = false
	velocity = Vector3.ZERO
	game.sfx.play("swish", -6)
	game.sfx.play("step%d" % (randi() % 6 + 1), -9, 0.05)


func _climb_update(delta: float) -> void:
	climb_t += delta
	var k := clampf(climb_t / climb_dur, 0.0, 1.0)
	climb_k = minf(1.0, climb_k + delta * 8.0)
	var pos: Vector3
	if climb_vault:
		# up to the sill, then through the opening and down on the far side
		var a := smoothstep(0.0, 0.35, k)
		var b := smoothstep(0.3, 1.0, k)
		pos = climb_from.lerp(climb_mid, a).lerp(climb_to, b)
		pos.y += sin(b * PI) * 0.15
	else:
		# pull up first, then roll forward onto the ledge
		var a := smoothstep(0.0, 0.6, k)
		var b := smoothstep(0.45, 1.0, k)
		pos = climb_from.lerp(climb_mid, a)
		pos = Vector3(lerpf(pos.x, climb_to.x, b), lerpf(pos.y, climb_to.y, b), lerpf(pos.z, climb_to.z, b))
	global_position = pos
	velocity = Vector3.ZERO
	# camera: through a window the eye ducks so it passes under the lintel; climbing tilts the view down a bit
	var duck := sin(k * PI) * (1.05 if climb_vault else 0.35)
	head.position = Vector3(0, eye_height() - duck, 0)
	camera.rotation = Vector3(pitch - sin(k * PI) * 0.12, 0, sin(k * PI) * 0.06 * (1.0 if climb_vault else -1.0))
	_update_weapon(delta, 0.0)
	if k >= 1.0:
		climb_t = -1.0
		global_position = climb_to
		velocity = (climb_to - climb_from) * Vector3(1, 0, 1)
		velocity = velocity.normalized() * 2.0 if velocity.length() > 0.01 else Vector3.ZERO
		land_v -= 0.35
		game.sfx.play("land", -8, 0.05)


# ---------------------------------------------------------------- weapons
func current_spread() -> float:
	var w: Dictionary = weapons[cur]
	var hs := Vector2(velocity.x, velocity.z).length()
	return lerpf(w.spread, w.aim_spread, aim_k) * (1.0 + hs / 5.0 * 1.2) * (1.0 if is_on_floor() else 2.5) * (0.75 if crouch > 0.5 else 1.0)


func fire() -> void:
	var w: Dictionary = weapons[cur]
	if reloading and guns[cur].kind == "shell" and w.ammo > 0:
		reloading = false
	if fire_cd > 0.0 or reloading or switch_t > 0.0 or sprint_k > 0.5 or not alive or melee_t > 0.0 or bolt_t > 0.0 or throw_t > 0.0 or climb_t >= 0.0:
		return
	if w.ammo <= 0:
		game.sfx.play("empty")
		fire_cd = 0.25
		if w.reserve > 0:
			start_reload()
		return
	w.ammo -= 1
	fire_cd = w.rate * rate_mul
	game.shots += 1
	if guns[cur].has("bolt") and w.ammo > 0:
		bolt_t = 0.001
	slide_kick = 1.0
	if guns[cur].has("pump") and w.ammo > 0:
		pump_t = 0.001
	game.sfx.play(w.snd, -1.0, 0.06)
	flash_t = 0.05
	kick = 1.0
	_eject_casing(guns[cur].kind == "shell")
	var spread := current_spread()
	var origin := camera.global_position
	var b := camera.global_transform.basis
	var fwd := -b.z
	var muzzle_w := camera.to_global(Vector3(lerpf(0.17, 0.0, aim_k), lerpf(-0.12, -0.06, aim_k), -0.9))
	# light muzzle haze: never while aiming, and only every third round on automatic fire
	smoke_n += 1
	if aim_k < 0.5 and (w.rate > 0.15 or smoke_n % 3 == 0):
		game.fx.puff(muzzle_w + b.x * 0.05 + b.y * 0.04, Color(0.75, 0.75, 0.75), 0.14, 0.35, 0.5, 2, 0.22)
	var space := get_world_3d().direct_space_state
	var dmg_map := {}
	for p in w.pellets:
		var a := randf() * TAU
		var r := sqrt(randf()) * spread
		var dir := (fwd + b.x * cos(a) * r + b.y * sin(a) * r).normalized()
		var excl := [get_rid()]
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * w.range, 1 | 2, excl)
		var hit := space.intersect_ray(q)
		# the sniper round passes through up to two bodies
		var extra := []
		if w.get("pierce", false):
			var h2 := hit
			for k in 2:
				if h2.is_empty() or not h2.collider.has_method("take_damage"):
					break
				excl.append(h2.collider.get_rid())
				q.exclude = excl
				h2 = space.intersect_ray(q)
				if not h2.is_empty() and h2.collider.has_method("take_damage"):
					extra.append(h2)
		var end: Vector3 = hit.position if not hit.is_empty() else origin + dir * w.range
		if p < 3:
			game.fx.tracer(muzzle_w, end)
		if p == 0 and game.net.active:
			game.net.shot(end)
		if hit.is_empty():
			continue
		var col = hit.collider
		if col.has_method("take_damage"):
			var rel: float = hit.position.y - col.global_position.y
			var is_head := rel > 1.5
			var dmg: float = w.dmg * (float(w.get("head", 2.0)) if is_head else (0.75 if rel < 0.85 else 1.0)) * (1.8 if w.get("up", false) else 1.0)
			if w.has("falloff"):
				var f: Array = w.falloff
				dmg *= clampf(1.0 - (hit.position.distance_to(origin) - f[0]) / (f[1] - f[0]) * (1.0 - f[2]), f[2], 1.0)
			if not dmg_map.has(col):
				dmg_map[col] = [0.0, false]
			dmg_map[col][0] += dmg
			if is_head:
				dmg_map[col][1] = true
			if col.has_meta("barrel"):
				game.fx.impact(hit.position, hit.normal, false, p < 2)
			else:
				game.fx.blood(hit.position, -dir)
			for h2 in extra:
				var c2 = h2.collider
				if not dmg_map.has(c2):
					dmg_map[c2] = [0.0, false]
				dmg_map[c2][0] += w.dmg * (1.8 if w.get("up", false) else 1.0)
				game.fx.blood(h2.position, -dir)
		else:
			game.fx.impact(hit.position, hit.normal, col.has_meta("wood"), p < 2)
	var any := false
	var killed := false
	var n_killed := 0
	for col in dmg_map:
		any = true
		game.kill_ctx = {"weapon": cur, "melee": false, "last": w.ammo == 0, "dist": origin.distance_to(col.global_position), "hp": health}
		if col.take_damage(dmg_map[col][0], dmg_map[col][1]):
			killed = true
			n_killed += 1
	game.kill_ctx = {}
	if n_killed >= 2:
		game.award_medal("collat")
	if any:
		game.hits += 1
		game.ui.hitmarker(killed)
		game.sfx.play("kill" if killed else "hit", -4.0, 0.0)
	var rk: float = w.recoil * (1.0 - aim_k * 0.4) * (0.7 if crouch > 0.5 else 1.0)
	recoil_p += rk * 0.55
	recoil_y += randf_range(-1, 1) * rk * 0.3
	view_kick_v += rk * 14.0
	if w.ammo == 0 and w.reserve > 0:
		var idx := cur
		get_tree().create_timer(0.25, false).timeout.connect(func():
			if cur == idx:
				start_reload()
		)


func _eject_casing(shell: bool) -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.mass = 0.02
	var cs := CollisionShape3D.new()
	var shp := CylinderShape3D.new()
	shp.radius = 0.012 if shell else 0.006
	shp.height = 0.06 if shell else 0.026
	cs.shape = shp
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = shp.radius
	cm.bottom_radius = shp.radius
	cm.height = shp.height
	cm.radial_segments = 8
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.66, 0.15, 0.11) if shell else Color(0.83, 0.66, 0.29)
	mat.metallic = 0.2 if shell else 1.0
	mat.roughness = 0.35
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	game.add_child(rb)
	var b := camera.global_transform.basis
	rb.global_position = camera.to_global(Vector3(lerpf(0.12, 0.03, aim_k), -0.1, -0.35))
	rb.rotation = Vector3(randf() * 3.0, randf() * 3.0, randf() * 3.0)
	rb.linear_velocity = b.x * randf_range(1.8, 2.8) + Vector3.UP * randf_range(1.8, 2.8) + velocity
	rb.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	casings.append(rb)
	if casings.size() > 30:
		var old = casings.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	get_tree().create_timer(6.0, false).timeout.connect(func():
		if is_instance_valid(rb):
			rb.queue_free()
	)


func start_reload() -> void:
	var w: Dictionary = weapons[cur]
	if reloading or switch_t > 0.0 or w.ammo >= w.mag or w.reserve <= 0 or not alive or melee_t > 0.0:
		return
	reloading = true
	reload_t = 0.0
	reload_empty = w.ammo == 0
	reload_given = false
	reload_last_p = 0.0
	shells_done = 0
	if guns[cur].kind == "shell":
		shells_to_load = mini(w.mag - w.ammo, w.reserve)
		reload_dur = 0.35 + shells_to_load * 0.5 + (0.45 if reload_empty else 0.0)
	else:
		reload_dur = w.reload * (1.12 if reload_empty else 0.92)
	reload_dur *= reload_mul
	game.sfx.play("click", -6)


func switch_weapon(i: int) -> void:
	if (i == cur and swapped) or switch_t > 0.0 or not alive:
		return
	reloading = false
	next_w = i
	switch_t = 0.45
	swapped = false
	game.sfx.play("swish", -8)


func refill() -> void:
	for i in owned:
		var w: Dictionary = weapons[i]
		w.reserve = maxi(w.reserve, w.mag * 2)


func max_ammo() -> void:
	for i in owned:
		weapons[i].reserve = weapons[i].reserve_max
		weapons[i].ammo = weapons[i].mag


func cycle_weapon(d: int) -> void:
	if owned.size() < 2:
		return
	var k := owned.find(cur)
	switch_weapon(owned[(k + d + owned.size()) % owned.size()])


## Zombies: buying a weapon. Owned -> ammo refill; otherwise it takes a free slot (max 2) or replaces the current one.
func give_weapon(i: int, upgraded := false) -> void:
	var w: Dictionary = weapons[i]
	if upgraded:
		upgrade(i)
	w.ammo = w.mag
	w.reserve = w.reserve_max
	if i in owned:
		if i != cur:
			switch_weapon(i)
		return
	if owned.size() < 2:
		owned.append(i)
	else:
		owned[owned.find(cur)] = i
	switch_weapon(i)


func throw_grenade() -> void:
	if grenades <= 0 or throw_t > 0.0 or melee_t > 0.0 or switch_t > 0.0 or not alive:
		return
	grenades -= 1
	reloading = false
	throw_t = THROW_DUR
	throw_done = false
	game.sfx.play("pin", -4)


func _spawn_grenade() -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.mass = 0.4
	rb.continuous_cd = true
	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.35
	pmat.friction = 0.8
	rb.physics_material_override = pmat
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.05
	cs.shape = sh
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.22, 0.27, 0.17)
	m.roughness = 0.6
	mi.material_override = m
	rb.add_child(mi)
	game.add_child(rb)
	var b := camera.global_transform.basis
	rb.global_position = camera.global_position + b.x * 0.15 - b.z * 0.5 + b.y * 0.05
	rb.linear_velocity = -b.z * 15.0 + Vector3.UP * 3.5 + velocity * 0.6
	rb.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	get_tree().create_timer(2.3, false).timeout.connect(func():
		if is_instance_valid(rb):
			game.explode(rb.global_position, 170.0, 7.5, "grenade")
			rb.queue_free()
	)


## Weapon upgrade: x1.8 damage, +50 % magazine and reserve, faster reload, gold finish.
func upgrade(i: int) -> bool:
	var w: Dictionary = weapons[i]
	if w.get("up", false):
		return false
	w.up = true
	w.mag = int(w.mag * 1.5)
	w.reserve_max = int(w.reserve_max * 1.5)
	w.reload = w.reload * 0.85
	w.name = w.name + " +"
	w.ammo = w.mag
	w.reserve = w.reserve_max
	WM.apply_camo(guns[i].model)
	return true


func melee() -> void:
	if melee_t > 0.0 or switch_t > 0.0 or not alive or throw_t > 0.0:
		return
	reloading = false
	melee_t = MELEE_DUR
	melee_done = false
	game.sfx.play("knife", -3, 0.1)


func _melee_hit() -> void:
	var origin := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	for off in [Vector3.ZERO, camera.global_transform.basis.x * 0.25, -camera.global_transform.basis.x * 0.25]:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + (fwd * 2.1 + off), 1 | 2, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var col = hit.collider
		if col.has_method("take_damage"):
			game.kill_ctx = {"weapon": -1, "melee": true, "last": false, "dist": 1.0, "hp": health}
			var killed: bool = col.take_damage(160.0, false)
			game.kill_ctx = {}
			game.fx.blood(hit.position, -fwd)
			game.sfx.play("stab", -2)
			game.ui.hitmarker(killed)
			shake = maxf(shake, 0.25)
		else:
			game.fx.impact(hit.position, hit.normal, col.has_meta("wood"))
		return


func _plan(g: Dictionary, empty: bool) -> Dictionary:
	if g.kind == "pistol":
		return PLANS.pisE if empty else PLANS.pisT
	return PLANS.magE if empty else PLANS.magT


static func _sm(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _in(p: float, w) -> bool:
	return w != null and p >= w[0] and p < w[1]


func _key_pos(keys: Array, anch: Dictionary, p: float) -> Vector3:
	for i in range(1, keys.size()):
		if p <= keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			return (anch[a[1]] as Vector3).lerp(anch[b[1]], _sm((p - a[0]) / maxf(0.000001, b[0] - a[0])))
	return anch[keys[keys.size() - 1][1]]


func _update_weapon(delta: float, hs: float) -> void:
	var w: Dictionary = weapons[cur]
	fire_cd -= delta
	if mouse_down and w.auto:
		fire()
	var g0: Dictionary = guns[cur]
	if reloading:
		reload_t += delta
		var p := minf(1.0, reload_t / reload_dur)
		var lp := reload_last_p
		reload_last_p = p
		if g0.kind == "shell":
			while shells_done < shells_to_load and reload_t / reload_mul >= 0.35 + (shells_done + 0.8) * 0.5 and w.reserve > 0 and w.ammo < w.mag:
				w.ammo += 1
				w.reserve -= 1
				shells_done += 1
				game.sfx.play("mag_in", -4, 0.1)
			if reload_empty and lp < 0.9 and p >= 0.9:
				game.sfx.play("rack")
				kick = maxf(kick, 0.5)
		else:
			var plan := _plan(g0, reload_empty)
			if plan.has("drop") and lp < plan.drop[0] and p >= plan.drop[0]:
				game.sfx.play("mag_out")
			if plan.has("grab") and lp < plan.grab[0] and p >= plan.grab[0]:
				game.sfx.play("mag_out")
			if not reload_given and p >= plan.give:
				reload_given = true
				var take: int = mini(w.mag - w.ammo, w.reserve)
				w.ammo += take
				w.reserve -= take
				game.sfx.play("mag_in")
				kick = maxf(kick, 0.6)
			if plan.has("rack") and lp < plan.rack[1] - 0.01 and p >= plan.rack[1] - 0.01:
				game.sfx.play("rack")
				kick = maxf(kick, 0.7)
			if plan.has("slide") and lp < plan.slide and p >= plan.slide:
				game.sfx.play("rack")
				kick = maxf(kick, 0.5)
		if p >= 1.0:
			reloading = false
	# switching
	var dip := 0.0
	if switch_t > 0.0:
		switch_t -= delta
		if not swapped and switch_t <= 0.22:
			guns[cur].model.visible = false
			cur = next_w
			guns[cur].model.visible = true
			swapped = true
		dip = (0.45 - switch_t) / 0.23 if switch_t > 0.22 else maxf(0.0, switch_t) / 0.22
		if switch_t <= 0.0:
			switch_t = 0.0
			swapped = true
	# knife: the gun drops out of view while the fist slashes across
	if melee_t > 0.0:
		melee_t -= delta
		var mp := 1.0 - maxf(0.0, melee_t) / MELEE_DUR
		dip = maxf(dip, sin(minf(1.0, mp * 1.4) * PI * 0.5) * (1.0 - _sm((mp - 0.75) / 0.25)))
		if not melee_done and mp >= 0.38:
			melee_done = true
			_melee_hit()
		var a0 := Vector3(0.24, -0.2, -0.32)
		var a1 := Vector3(0.12, -0.08, -0.5)
		var a2 := Vector3(-0.12, -0.16, -0.48)
		var r0 := Vector3(0.5, 0.9, -1.2)
		var r1 := Vector3(0.1, 0.35, -0.3)
		var r2 := Vector3(-0.25, -0.6, 0.9)
		var kp: Vector3
		var kr: Vector3
		if mp < 0.3:
			kp = a0.lerp(a1, _sm(mp / 0.3))
			kr = r0.lerp(r1, _sm(mp / 0.3))
		else:
			kp = a1.lerp(a2, _sm((mp - 0.3) / 0.3))
			kr = r1.lerp(r2, _sm((mp - 0.3) / 0.3))
		kp.y -= _sm((mp - 0.7) / 0.3) * 0.4
		knife_node.position = kp
		knife_node.rotation = kr
		knife_node.visible = melee_t > 0.0
	else:
		knife_node.visible = false
	# grenade throw: wind-up behind the shoulder, then a fast overhand release
	if throw_t > 0.0:
		throw_t -= delta
		var tp := 1.0 - maxf(0.0, throw_t) / THROW_DUR
		dip = maxf(dip, sin(minf(1.0, tp * 1.6) * PI * 0.5) * (1.0 - _sm((tp - 0.7) / 0.3)))
		var g0p := Vector3(0.26, -0.3, -0.3)
		var g1p := Vector3(0.3, 0.02, -0.12)
		var g2p := Vector3(0.08, 0.02, -0.65)
		var np: Vector3
		var nr: Vector3
		if tp < 0.4:
			np = g0p.lerp(g1p, _sm(tp / 0.4))
			nr = Vector3(0.2, 0.3, -0.3).lerp(Vector3(1.0, 0.4, -0.2), _sm(tp / 0.4))
		else:
			np = g1p.lerp(g2p, _sm((tp - 0.4) / 0.15))
			nr = Vector3(1.0, 0.4, -0.2).lerp(Vector3(-0.6, 0.0, 0.2), _sm((tp - 0.4) / 0.15))
		np.y -= _sm((tp - 0.6) / 0.4) * 0.5
		nade_node.position = np
		nade_node.rotation = nr
		nade_node.visible = true
		nade_node.get_child(0).visible = tp < 0.5
		nade_node.get_child(1).visible = tp < 0.5
		if not throw_done and tp >= 0.5:
			throw_done = true
			_spawn_grenade()
			game.sfx.play("swish", -4)
	else:
		nade_node.visible = false
	w = weapons[cur]
	var g: Dictionary = guns[cur]
	kick = maxf(0.0, kick - delta * (5.0 if w.pellets > 1 else 12.0))
	sway = sway.lerp(Vector2.ZERO, 1.0 - exp(-6.0 * delta))
	var bob_amp := (minf(hs / 5.4, 1.6) if is_on_floor() else 0.0) * (1.0 - aim_k * 0.85)
	var bx := sin(bob_t * 0.5) * 0.012 * bob_amp
	var by := -absf(cos(bob_t * 0.5)) * 0.012 * bob_amp
	var pos: Vector3 = (g.hip as Vector3).lerp(g.aim, aim_k)
	pos.x += bx + sway.x * (1.0 - aim_k * 0.7) - sprint_k * 0.05
	pos.y += by + sway.y * (1.0 - aim_k * 0.7) - dip * 0.35 - sprint_k * 0.04 + sin(game.clock * 1.7) * 0.0025 * (1.0 - aim_k * 0.6) + land_off * 0.4
	pos.z += kick * (0.09 if w.pellets > 1 else 0.035)
	# hip carry: muzzle tipped slightly up so the stock drops out of view toward the shoulder
	var rx := kick * (0.18 if w.pellets > 1 else 0.05) - sprint_k * 0.35 + 0.07 * (1.0 - aim_k)
	var ry := sprint_k * 0.6
	var rz := strafe_roll * 2.5 - lean * 0.12 * (1.0 - aim_k)
	# reset movable parts, then pose them
	var hand: Vector3 = g.left_home
	if g.has("mag"):
		g.mag.position = g.mag_home
		g.mag.rotation = g.mag_rot
		g.mag.visible = true
	if g.has("handle"):
		g.handle.position = g.handle_home
	if g.has("pump"):
		g.pump.position = g.pump_home
	if g.has("shell"):
		g.shell.visible = false
	slide_kick = maxf(0.0, slide_kick - delta * 14.0)
	if g.has("slide"):
		var locked: bool = w.ammo == 0 and not (reloading and reload_given and reload_t / reload_dur > 0.72)
		g.slide.position.z = g.slide_home.z + 0.035 * maxf(slide_kick, 1.0 if locked else 0.0)
	if reloading:
		var p := minf(1.0, reload_t / reload_dur)
		var env := _sm(p / 0.12) * (1.0 - _sm((p - 0.88) / 0.12))
		if g.kind == "shell":
			var a: Dictionary = g.anch
			var s0 := 0.35
			var cyc := 0.5
			var n := shells_to_load
			if reload_t < s0:
				hand = (a.home as Vector3).lerp(a.port, _sm(reload_t / s0))
			elif reload_t < s0 + n * cyc:
				var c := fmod(reload_t - s0, cyc) / cyc
				if c < 0.45:
					hand = (a.port as Vector3).lerp(a.pouch_s, _sm(c / 0.45))
				elif c < 0.8:
					hand = (a.pouch_s as Vector3).lerp(a.port, _sm((c - 0.45) / 0.35))
				else:
					hand = (a.port as Vector3).lerp(a.port_in, _sm((c - 0.8) / 0.2))
				g.shell.visible = c > 0.35 and c < 0.97
			else:
				var kk := clampf((reload_t - s0 - n * cyc) / maxf(0.01, reload_dur - s0 - n * cyc), 0.0, 1.0)
				if reload_empty:
					var pm := sin(clampf((kk - 0.3) / 0.7, 0.0, 1.0) * PI)
					hand = (a.port as Vector3).lerp(a.home, _sm(kk / 0.3))
					hand.z += pm * 0.08
					g.pump.position.z = g.pump_home.z + pm * 0.08
				else:
					hand = (a.port as Vector3).lerp(a.home, _sm(kk))
			rz -= 0.5 * env
			rx += 0.25 * env
			pos.y += 0.14 * env
			pos.x -= 0.05 * env
		else:
			var plan := _plan(g, reload_empty)
			hand = _key_pos(KEYS[plan.k], g.anch, p)
			if g.has("mag"):
				if _in(p, plan.get("drop")):
					var t: float = (p - plan.drop[0]) / (plan.drop[1] - plan.drop[0])
					g.mag.position = g.mag_home + Vector3(0.01 * t, -0.9 * t * t, 0.04 * t)
					g.mag.rotation.x = g.mag_rot.x + t * 1.3
					g.mag.visible = t < 0.9
				elif _in(p, plan.get("grab")) or _in(p, plan.get("hold")):
					g.mag.position = hand + g.grab
					g.mag.visible = not (_in(p, plan.get("grab")) and p > plan.grab[1] - 0.04)
				elif _in(p, plan.get("ins")):
					var t2 := _sm((p - plan.ins[0]) / (plan.ins[1] - plan.ins[0]))
					g.mag.position = (hand + g.grab).lerp(g.mag_home, t2)
			if plan.has("rack") and g.has("handle"):
				var pull := _sm((p - plan.rack[0] - 0.02) / 0.04) * (1.0 - _sm((p - plan.rack[1] + 0.03) / 0.03))
				g.handle.position.z = g.handle_home.z + 0.07 * pull
				rz += 0.12 * _sm((p - plan.rack[0] + 0.04) / 0.06) * (1.0 - _sm((p - plan.rack[1]) / 0.08))
			rz += 0.4 * env
			rx += 0.2 * env
			pos.y += 0.12 * env
			pos.x -= 0.05 * env
	elif g.has("bolt") and bolt_t > 0.0:
		bolt_t += delta
		var bq := clampf((bolt_t - 0.25) / 0.6, 0.0, 1.0)
		var bm := sin(bq * PI)
		g.handle.rotation.z = -minf(1.0, bm * 3.0) * 1.0
		g.handle.position.z = g.handle_home.z + maxf(0.0, bm * 1.3 - 0.3) * 0.08
		hand.z += bm * 0.03
		rz += bm * 0.15
		if bolt_t > 0.3 and bolt_t - delta <= 0.3:
			game.sfx.play("bolt", -3)
			_eject_casing(false)
		if bq >= 1.0:
			bolt_t = 0.0
			g.handle.rotation.z = 0.0
	elif g.has("pump") and pump_t > 0.0:
		pump_t += delta
		var q := clampf((pump_t - 0.18) / 0.35, 0.0, 1.0)
		var pm2 := sin(q * PI)
		g.pump.position.z = g.pump_home.z + pm2 * 0.08
		hand.z += pm2 * 0.08
		if pump_t > 0.18 and pump_t - delta <= 0.18:
			game.sfx.play("rack", -3)
		if q >= 1.0:
			pump_t = 0.0
	g.left.position = hand
	holder.position = pos
	holder.rotation = Vector3(rx, ry, rz)
	if climb_k > 0.001:
		# weapon swings down and aside while climbing / vaulting
		holder.position += Vector3(0.06, -0.3, 0.08) * climb_k
		holder.rotation += Vector3(-0.55, 0.35, 0.45) * climb_k
	scoped = w.get("scope", false) and aim_k > 0.86 and alive
	g.model.visible = not scoped and swapped
	if inspect_on:
		holder.position = Vector3(0, 0, -0.85)
		holder.rotation = inspect_rot
	flash_t -= delta
	g.flash.visible = flash_t > 0.0
	if flash_t > 0.0:
		g.flash.material_override.set_shader_parameter("spin", randf() * TAU)
		g.flash.scale = Vector3.ONE * randf_range(0.8, 1.2)
	muzzle_light.light_energy = 3.0 if flash_t > 0.0 else 0.0
	if fp_arms:
		fp_arms.update(g, g.model.visible and not inspect_on and alive)


# ---------------------------------------------------------------- damage
func take_damage(amount: float, from: Vector3) -> void:
	if not alive or god:
		return
	health -= amount
	last_hit = game.clock
	game.on_player_hit()
	shake = maxf(shake, 0.3)
	game.sfx.play("hurt", -3)
	var d := from - global_position
	game.ui.damage_from(atan2(-d.x, -d.z) - yaw)
	if health <= 0.0:
		health = 0.0
		alive = false
		reset_actions()
		if game.net.active:
			game.net.local_died()
		else:
			game.game_over()


# ---------------------------------------------------------------- helpers for automated checks
func test_fire(n: int) -> void:
	for i in n:
		fire_cd = 0.0
		fire()


func test_switch(i: int) -> void:
	switch_t = 0.0
	swapped = true
	reloading = false
	guns[cur].model.visible = false
	cur = i
	guns[cur].model.visible = true


func test_reload(empty: bool) -> void:
	if empty:
		weapons[cur].ammo = 0
	start_reload()
