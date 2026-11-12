extends Node
## Zombies mode: rounds, spendable points, debris doors that open zones, chalk wall-buys,
## perk machines, the mystery box and power-up drops. Layout comes from world.gd (zlayout).

const WB := preload("res://scripts/world.gd")
const ZombieScript := preload("res://scripts/zombie.gd")
const DROPS := {"ammo": ["MUNICIÓN MÁXIMA", Color(0.4, 1.0, 0.4)], "insta": ["MUERTE INSTANTÁNEA", Color(1.0, 0.3, 0.25)],
	"double": ["DOBLE PUNTOS", Color(1.0, 0.85, 0.2)], "nuke": ["BOMBA", Color(1.0, 0.55, 0.15)]}

var game
var L := {}
var round_n := 0
var to_spawn := 0
var spawn_t := 0.0
var inter := 4.0
var points := 500
var active := {0: true}
var insta_t := 0.0
var double_t := 0.0
var drops: Array = []
var drops_round := 0
var perks_owned: Array = []
var prompt := ""
var target := {}
var box_t := 0.0
var box_result := -1
var box_up := false
var box_hold := 0.0
var box_label: Label3D
var round_kills := 0
var box_guns := {}


func setup(g) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_PAUSABLE
	L = WB.zlayout


func max_alive() -> int:
	return 14 if game.settings.quality == 0 else 20


func round_total(r: int) -> int:
	return 6 if r == 1 else mini(6 + r * 4, 64)


func add_points(n: int) -> void:
	var v := n * (2 if double_t > 0.0 else 1)
	points += v
	game.score += v


## Co-op: is this machine the one running the zombies? (always true offline)
func is_host_side() -> bool:
	return not game.net.is_coop() or game.net.is_host


func on_hit(z, killed: bool, head: bool) -> void:
	var ctx: Dictionary = game.kill_ctx
	var pts := 10
	if killed:
		pts = 60
		if ctx.get("melee", false):
			pts = 130
		elif head:
			pts = 100
		round_kills += 1
		# power-up drop
		if drops_round < 4 and randf() < 0.035:
			drops_round += 1
			var kind: String = DROPS.keys()[randi() % DROPS.size()]
			drop_seq += 1
			spawn_drop(z.global_position, kind, drop_seq)
			game.net.zdrop(drop_seq, z.global_position, kind)
	var who: int = z.attacker
	if who != 0 and who != game.net.my_id():
		# the client applies its own Doble puntos (power-ups are shared by everybody)
		game.net.zpoints(who, pts, killed, head)
	else:
		add_points(pts)


var drop_seq := 0
var drop_asked := {}
var zombies_by_id := {}


# ---------------------------------------------------------------- co-op (client side)
func find_zombie(id: int):
	var z = zombies_by_id.get(id)
	if z != null and is_instance_valid(z):
		return z
	zombies_by_id.erase(id)
	if is_host_side():
		for e in game.enemies:
			if is_instance_valid(e) and e.get("nid") == id:
				return e
	return null


func client_spawn(id: int, pos: Vector3, fac: float, rnd: int, gait: int, spd: float):
	var old = find_zombie(id)
	if old != null:
		return old
	var z = ZombieScript.new()
	z.game = game
	z.round_n = rnd
	z.remote = true
	z.nid = id
	game.add_child(z)
	z.gait_kind = gait
	z.speed = spd
	z.global_position = pos
	z.net_pos = pos
	z.facing = fac
	z.net_facing = fac
	z.net_seen = game.clock
	game.enemies.append(z)
	zombies_by_id[id] = z
	return z


func client_snapshot(arr: Array, rnd: int, left: int, it: float) -> void:
	to_spawn = left
	inter = it
	if rnd != round_n:
		client_round(rnd, left)
	for a in arr:
		var z = find_zombie(int(a[0]))
		if z == null:
			z = client_spawn(int(a[0]), a[1], a[2], round_n, int(a[3]) & 3, 2.0)
			z.rise_t = 0.0
		if not z.dead:
			z.net_apply(a[1], a[2], int(a[3]))
	# zombies the host no longer reports (missed death message): remove them
	for id in zombies_by_id.keys():
		var z = zombies_by_id[id]
		if is_instance_valid(z) and not z.dead and game.clock - z.net_seen > 2.0:
			game.enemies.erase(z)
			z.queue_free()
			zombies_by_id.erase(id)


func client_round(n: int, total: int) -> void:
	if n == round_n:
		return
	round_n = n
	round_kills = 0
	if n > 1 and game.player:
		game.player.grenades = mini(game.player.grenades + 2, 4)
	game.ui.notice("RONDA %d" % n, "Llegan %d zombis" % total, 3.0)
	game.sfx.play("round", -1)
	game.net.coop_round_start()


## For players joining a co-op game in progress.
func snapshot_state() -> Dictionary:
	var opened := []
	for i in L.doors.size():
		if L.doors[i].open:
			opened.append(i)
	return {"round": round_n, "doors": opened}


func apply_state(s: Dictionary) -> void:
	for i in s.get("doors", []):
		open_door(int(i), false)
	if int(s.get("round", 0)) > 0:
		client_round(int(s.round), 0)


func open_door(idx: int, broadcast: bool) -> void:
	if idx < 0 or idx >= L.doors.size():
		return
	var r: Dictionary = L.doors[idx]
	if r.open:
		return
	r.open = true
	var n: Node3D = r.node
	if is_instance_valid(n):
		game.fx.puff(n.global_position + Vector3(0, 1.0, 0), Color(0.5, 0.45, 0.4), 2.0, 1.6, 0.3)
		n.get_parent().remove_child(n)
		n.queue_free()
	for zid in r.zones:
		active[zid] = true
	game.map_dirty = true
	game.sfx.play("door")
	game.rebake_nav()
	if broadcast:
		game.net.zdoor(idx)


# ---------------------------------------------------------------- rounds
func update(delta: float) -> void:
	insta_t = maxf(0.0, insta_t - delta)
	double_t = maxf(0.0, double_t - delta)
	_update_drops(delta)
	_update_box(delta)
	_update_interact()
	if not is_host_side():
		if inter > 0.0:
			inter = maxf(0.0, inter - delta)
		return
	if inter > 0.0:
		inter -= delta
		if inter <= 0.0:
			round_n += 1
			round_kills = 0
			drops_round = 0
			to_spawn = round_total(round_n)
			spawn_t = 1.0
			if round_n > 1:
				game.player.grenades = mini(game.player.grenades + 2, 4)
			game.ui.notice("RONDA %d" % round_n, "Llegan %d zombis" % to_spawn, 3.0)
			game.sfx.play("round", -1)
			if game.net.is_coop():
				game.net.zround(round_n, to_spawn)
				game.net.coop_round_start()
			if round_n == 10:
				game.award_medal("survivor")
		return
	if to_spawn > 0:
		spawn_t -= delta
		if spawn_t <= 0.0 and game.alive_count() < max_alive():
			if _spawn_zombie():
				to_spawn -= 1
			spawn_t = maxf(0.35, 2.0 - round_n * 0.12)
	elif game.alive_count() == 0:
		inter = 9.0
		game.ui.notice("RONDA %d SUPERADA" % round_n, "La siguiente empieza en 9 segundos", 3.5)
		game.sfx.play("wave")
		if game.net.is_coop():
			game.net.rpc("zcleared", round_n)


func _spawn_zombie() -> bool:
	# spawn around a random living player (in co-op the zombies spread over the whole team)
	var pp: Vector3 = game.player.global_position
	if game.net.is_coop():
		var cands_p := []
		if game.player.alive:
			cands_p.append(pp)
		for id in game.net.puppets:
			var mate = game.net.puppets[id]
			if is_instance_valid(mate) and not mate.dead:
				cands_p.append(mate.global_position)
		if not cands_p.is_empty():
			pp = cands_p[randi() % cands_p.size()]
	var cands := []
	var near := []
	for zid in active.keys():
		for p in L.spawns.get(zid, []):
			var d := Vector2(p.x - pp.x, p.z - pp.z).length()
			if d > 7.0:
				cands.append(p)
				if d < 32.0:
					near.append(p)
	var pool := near if not near.is_empty() and randf() < 0.85 else cands
	if pool.is_empty():
		return false
	var p: Vector3 = pool[randi() % pool.size()]
	var z = ZombieScript.new()
	z.game = game
	z.round_n = round_n
	game.add_child(z)
	z.global_position = p + Vector3(randf_range(-0.8, 0.8), 0.15, randf_range(-0.8, 0.8))
	z.facing = atan2(-(pp.x - p.x), -(pp.z - p.z))
	game.enemies.append(z)
	game.net.zspawn(z)
	return true


# ---------------------------------------------------------------- interactables
func _update_interact() -> void:
	prompt = ""
	target = {}
	var pl = game.player
	if pl == null:
		return
	if not pl.alive:
		prompt = pl.spectate_label()
		return
	var pp: Vector3 = pl.global_position
	var best := 2.4
	for d in L.doors:
		if d.open:
			continue
		var dist := Vector2(d.pos.x - pp.x, d.pos.z - pp.z).length()
		if dist < best:
			best = dist
			target = {"type": "door", "ref": d}
	for b in L.buys:
		var dist := Vector2(b.pos.x - pp.x, b.pos.z - pp.z).length()
		if dist < best:
			best = dist
			target = {"type": "buy", "ref": b}
	for p in L.perks:
		var dist := Vector2(p.pos.x - pp.x, p.pos.z - pp.z).length()
		if dist < best:
			best = dist
			target = {"type": "perk", "ref": p}
	var bx: Dictionary = L.box
	if Vector2(bx.pos.x - pp.x, bx.pos.z - pp.z).length() < 2.4:
		target = {"type": "box", "ref": bx}
	if L.has("forge") and Vector2(L.forge.pos.x - pp.x, L.forge.pos.z - pp.z).length() < 2.4:
		target = {"type": "forge", "ref": L.forge}
	if target.is_empty():
		return
	var r: Dictionary = target.ref
	match target.type:
		"door":
			prompt = "[F] Retirar escombros · %d" % r.cost
		"buy":
			var w: Dictionary = pl.weapons[r.weapon]
			if r.weapon in pl.owned:
				prompt = "[F] Munición para %s · %d" % [w.short, r.cost / 2]
			else:
				prompt = "[F] Comprar %s · %d" % [w.short, r.cost]
		"perk":
			prompt = ("Ya tienes %s" % r.name) if r.kind in perks_owned else ("[F] Beber %s · %d" % [r.name, r.cost])
		"forge":
			var wf: Dictionary = pl.weapons[pl.cur]
			prompt = ("%s ya está mejorada" % wf.short) if wf.get("up", false) else ("[F] Mejorar %s · %d" % [wf.short, r.cost])
		"box":
			if box_t > 0.0:
				prompt = ""
			elif box_result >= 0:
				prompt = "[F] Coger %s%s" % [pl.weapons[box_result].short, " +" if box_up else ""]
			else:
				prompt = "[F] Caja misteriosa · %d" % r.cost


func interact() -> void:
	if target.is_empty() or game.player == null:
		return
	var pl = game.player
	var r: Dictionary = target.ref
	match target.type:
		"door":
			if not _pay(r.cost):
				return
			open_door(L.doors.find(r), true)
		"buy":
			var cost: int = r.cost / 2 if r.weapon in pl.owned else r.cost
			if not _pay(cost):
				return
			pl.give_weapon(r.weapon)
			game.sfx.play("buy")
		"perk":
			if r.kind in perks_owned or not _pay(r.cost):
				if r.kind in perks_owned:
					game.sfx.play("deny", -6)
				return
			perks_owned.append(r.kind)
			match r.kind:
				"armor":
					pl.max_health = 175.0
					pl.health = 175.0
				"hands":
					pl.reload_mul = 0.55
				"pulse":
					pl.rate_mul = 0.75
			game.sfx.play("perk")
			game.ui.notice(r.name.to_upper(), "Ventaja activada", 2.0)
		"forge":
			if pl.weapons[pl.cur].get("up", false):
				game.sfx.play("deny", -6)
				return
			if not _pay(r.cost):
				return
			pl.upgrade(pl.cur)
			game.sfx.play("perk")
			game.fx.flash_light(game.player.global_position + Vector3(0, 1.5, 0), 4.0, 6.0)
			game.ui.notice("ARMA MEJORADA", "%s · más daño y cargador" % pl.weapons[pl.cur].name, 2.5)
		"box":
			if box_t > 0.0:
				return
			if box_result >= 0:
				pl.give_weapon(box_result, box_up)
				game.sfx.play("buy")
				box_result = -1
				box_hold = 0.0
				if box_label:
					box_label.visible = false
				_show_box_gun(-1)
				return
			if not _pay(r.cost):
				return
			box_t = 3.0
			game.sfx.play("powerup", -4)
			if box_label == null:
				box_label = Label3D.new()
				box_label.font_size = 64
				box_label.outline_size = 10
				box_label.pixel_size = 0.005
				box_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				box_label.modulate = Color(1.0, 0.9, 0.5)
				box_label.no_depth_test = true
				game.world.add_child(box_label)
			box_label.visible = true


func _pay(cost: int) -> bool:
	if points < cost:
		game.sfx.play("deny", -4)
		game.ui.notice("", "Necesitas %d puntos" % cost, 1.2)
		return false
	points -= cost
	return true


## Real gun models floating above the box while it spins / waits to be taken.
func _show_box_gun(i: int) -> void:
	if box_guns.is_empty():
		var WMs = load("res://scripts/weapon_models.gd")
		for k in [0, 1, 2, 3, 4, 5]:
			var g: Node3D = WMs.world_copy(k)
			g.scale = Vector3.ONE * (2.3 if k != 2 else 3.4)
			g.visible = false
			game.world.add_child(g)
			box_guns[k] = g
	for k in box_guns:
		box_guns[k].visible = k == i


func _update_box(delta: float) -> void:
	if box_label == null or not is_instance_valid(box_label):
		return
	for k in box_guns:
		var g: Node3D = box_guns[k]
		if g.visible:
			g.global_position = L.box.node.global_position + Vector3(0, 1.15 + sin(game.clock * 2.0) * 0.04, 0)
			g.rotation.y += delta * 1.5
	var base: Vector3 = L.box.node.global_position + Vector3(0, 1.75, 0)
	var pl = game.player
	if box_t > 0.0:
		box_t -= delta
		var k := 1.0 - box_t / 3.0
		box_label.global_position = base + Vector3(0, k * 0.8, 0)
		var idx: int = int(game.clock * (14.0 - k * 10.0)) % pl.weapons.size()
		box_label.text = pl.weapons[idx].short.to_upper()
		_show_box_gun(idx)
		if box_t <= 0.0:
			var choices := [0, 1, 3, 4, 5]
			if pl:
				choices = choices.filter(func(i): return i != pl.cur)
			box_result = choices[randi() % choices.size()]
			box_up = randf() < 0.25
			box_hold = 7.0
			box_label.text = pl.weapons[box_result].short.to_upper() + (" +" if box_up else "")
			_show_box_gun(box_result)
			box_label.modulate = Color(0.6, 1.0, 0.6) if box_up else Color(1.0, 0.9, 0.5)
			game.sfx.play("medal", -6)
	elif box_result >= 0:
		box_hold -= delta
		box_label.global_position = base + Vector3(0, 0.8 + sin(game.clock * 3.0) * 0.05, 0)
		if box_hold <= 0.0:
			box_result = -1
			box_label.visible = false
			_show_box_gun(-1)


# ---------------------------------------------------------------- power-ups
func spawn_drop(pos: Vector3, kind: String, id := 0) -> void:
	var n := Node3D.new()
	game.world.add_child(n)
	n.global_position = Vector3(pos.x, 0.9, pos.z)
	var col: Color = DROPS[kind][1]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 3.5
	m.metallic = 0.6
	m.roughness = 0.25
	var mesh: Mesh
	match kind:
		"ammo":
			var b := BoxMesh.new()
			b.size = Vector3(0.45, 0.32, 0.3)
			mesh = b
		"insta":
			var s := SphereMesh.new()
			s.radius = 0.24
			s.height = 0.4
			mesh = s
		"double":
			var t := TorusMesh.new()
			t.inner_radius = 0.14
			t.outer_radius = 0.26
			mesh = t
		_:
			var c := CylinderMesh.new()
			c.top_radius = 0.16
			c.bottom_radius = 0.2
			c.height = 0.5
			mesh = c
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	n.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 2.0
	l.omni_range = 4.0
	n.add_child(l)
	var lab := Label3D.new()
	lab.text = DROPS[kind][0]
	lab.font_size = 36
	lab.outline_size = 8
	lab.pixel_size = 0.004
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = col.lightened(0.3)
	lab.position.y = 0.55
	n.add_child(lab)
	drops.append({"node": n, "kind": kind, "t": 25.0, "id": id})
	game.sfx.play3d("powerup", n.global_position, -2.0)


func _update_drops(delta: float) -> void:
	var pl = game.player
	for d in drops.duplicate():
		var n: Node3D = d.node
		d.t -= delta
		if not is_instance_valid(n):
			drops.erase(d)
			continue
		n.rotation.y += delta * 2.0
		n.get_child(0).position.y = sin(game.clock * 2.5) * 0.08
		n.visible = d.t > 5.0 or fmod(d.t, 0.4) > 0.2
		if pl and pl.alive and pl.global_position.distance_to(n.global_position - Vector3(0, 0.9, 0)) < 1.6:
			if game.net.is_coop():
				# the host confirms the pickup and everybody gets the effect
				if not drop_asked.has(d.id):
					drop_asked[d.id] = true
					game.net.zdrop_take(d.id)
				continue
			_apply_drop(d.kind, true)
			n.queue_free()
			drops.erase(d)
		elif d.t <= 0.0:
			n.queue_free()
			drops.erase(d)


func has_drop(id: int) -> bool:
	for d in drops:
		if d.id == id:
			return true
	return false


## Co-op: a power-up was picked up by someone (mine = by this player).
func take_drop(id: int, mine: bool) -> void:
	for d in drops.duplicate():
		if d.id == id:
			if is_instance_valid(d.node):
				d.node.queue_free()
			drops.erase(d)
			_apply_drop(d.kind, mine)
			return


func _apply_drop(kind: String, mine := true) -> void:
	game.sfx.play("powerup")
	game.ui.notice(DROPS[kind][0], "" if mine else "Para todo el equipo", 2.0)
	match kind:
		"ammo":
			if game.player and game.player.alive:
				game.player.max_ammo()
		"insta":
			insta_t = 20.0
		"double":
			double_t = 20.0
		"nuke":
			game.fx.flash_light(game.player.global_position + Vector3(0, 3, 0), 12.0, 60.0)
			if is_host_side():
				for e in game.enemies.duplicate():
					if is_instance_valid(e) and not e.dead and e.get("puppet") != true:
						e.take_damage(1.0e7, false)
			if mine:
				add_points(400)


func clear() -> void:
	for d in drops:
		if is_instance_valid(d.node):
			d.node.queue_free()
	drops.clear()
	if box_label and is_instance_valid(box_label):
		box_label.queue_free()
	for k in box_guns:
		if is_instance_valid(box_guns[k]):
			box_guns[k].queue_free()
	box_guns.clear()
