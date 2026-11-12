extends Node
## Multiplayer (ENet, host + clients). Two modes chosen by the host:
##  - "dm": free-for-all deathmatch on the Operación maps.
##  - "zombies": co-op Zombis. The host runs rounds and every zombie's AI and streams their
##    state; clients show replicas and forward their hits. Doors and power-ups are shared,
##    points / weapons / perks are per player. Fallen players come back at the next round;
##    if everyone is down the match restarts.
## Every peer simulates its own player; positions are streamed unreliably, hits/deaths/scores
## go reliably. Remote players are "puppet" soldiers that forward damage to their owner.

const SoldierScript := preload("res://scripts/soldier.gd")
const WB := preload("res://scripts/world.gd")
const PORT := 7777
const SEND_HZ := 20.0
const KILL_GOAL := 20
const RESPAWN_T := 3.0

var game
var active := false
var is_host := false
var my_name := "Jugador"
var map_idx := 0
var players := {}        # id -> {name, kills, deaths}
var puppets := {}        # id -> soldier puppet node
var send_t := 0.0
var respawn_t := 0.0
var ended := false
var status := ""
var gmode := "dm"        # "dm" deathmatch | "zombies" co-op
# co-op zombies
const ZSEND_HZ := 15.0
var zombies := {}        # net id -> zombie (host: the real ones, client: replicas)
var zdead := {}          # ids already dead (late state packets must not resurrect them)
var znext := 0
var zsend_t := 0.0
var z_attacker := 0      # host: peer whose hit is being applied (0 = local, -1 = nobody)
var z_melee := false


func coop() -> bool:
	return active and gmode == "zombies"


func mode_name(m: String) -> String:
	return "Zombis cooperativo" if m == "zombies" else "Duelo a muerte"

# ---- LAN discovery: the host broadcasts a small UDP beacon every second; the MULTIJUGADOR
# screen listens and lists every game found on the local network (no IP typing needed).
signal lan_changed
const LAN_PORT := 7778
const LAN_TAG := "TAW1"
const MAX_PLAYERS := 8
var lan_games := {}      # host uid -> {name, map, n, ip, port, t}
var beacon_t := 0.0
var beacon_udp: PacketPeerUDP
var listen_udp: PacketPeerUDP
var listen_ok := false
var host_uid := ""


func _process(delta: float) -> void:
	# host side: announce the game while it is running
	if active and is_host and not ended:
		beacon_t -= delta
		if beacon_t <= 0.0:
			beacon_t = 1.0
			_send_beacon()
	# browser side: only while the MULTIJUGADOR screen is open
	var browsing: bool = not active and game != null and game.ui != null and game.ui.mp_p != null and game.ui.mp_p.visible
	if browsing:
		_listen(delta)
	elif listen_udp:
		listen_udp.close()
		listen_udp = null
		if not lan_games.is_empty():
			lan_games.clear()
			lan_changed.emit()


func _send_beacon() -> void:
	if beacon_udp == null:
		beacon_udp = PacketPeerUDP.new()
		beacon_udp.set_broadcast_enabled(true)
	var pkt := JSON.stringify({"g": LAN_TAG, "id": host_uid, "name": my_name,
		"map": WB.MAPS[map_idx].name, "mode": gmode,
		"n": players.size(), "max": MAX_PLAYERS, "port": PORT}).to_utf8_buffer()
	var dests := ["255.255.255.255", "127.0.0.1"]
	for ip in local_ips():   # directed subnet broadcast too (some routers drop 255.255.255.255)
		var p: PackedStringArray = ip.split(".")
		dests.append("%s.%s.%s.255" % [p[0], p[1], p[2]])
	for d in dests:
		beacon_udp.set_dest_address(d, LAN_PORT)
		beacon_udp.put_packet(pkt)


func _listen(_delta: float) -> void:
	if listen_udp == null:
		listen_udp = PacketPeerUDP.new()
		listen_ok = listen_udp.bind(LAN_PORT, "*") == OK
		lan_changed.emit()
	var now := Time.get_ticks_msec() / 1000.0
	var changed := false
	while listen_ok and listen_udp.get_available_packet_count() > 0:
		var raw := listen_udp.get_packet()
		var ip := listen_udp.get_packet_ip()
		var d = JSON.parse_string(raw.get_string_from_utf8())
		if typeof(d) != TYPE_DICTIONARY or d.get("g", "") != LAN_TAG:
			continue
		var uid := str(d.get("id", ip))
		var prev: Dictionary = lan_games.get(uid, {})
		# same PC: the beacon also arrives via 127.0.0.1 — prefer the real LAN address
		if not prev.is_empty() and ip == "127.0.0.1" and prev.ip != "127.0.0.1":
			ip = prev.ip
		var g := {"name": str(d.get("name", "?")).substr(0, 16), "map": str(d.get("map", "")), "mode": str(d.get("mode", "dm")),
			"n": int(d.get("n", 1)), "max": int(d.get("max", MAX_PLAYERS)), "ip": ip,
			"port": int(d.get("port", PORT)), "t": now}
		if prev.is_empty() or prev.n != g.n or prev.ip != g.ip or prev.name != g.name:
			changed = true
		lan_games[uid] = g
	for uid in lan_games.keys():
		if now - lan_games[uid].t > 3.5:
			lan_games.erase(uid)
			changed = true
	if changed:
		lan_changed.emit()


func _ready() -> void:
	name = "Net"
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1


static func local_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a)
	return out


# ---------------------------------------------------------------- host / join / leave
func host(player_name: String, map_i: int, port := PORT, game_mode := "dm") -> String:
	leave()
	gmode = game_mode
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 8)
	if err != OK:
		return "No se pudo crear la partida en el puerto %d (¿ya está en uso?)" % port
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	my_name = player_name
	map_idx = map_i
	ended = false
	host_uid = "%d-%d" % [Time.get_ticks_usec(), randi()]
	beacon_t = 0.0
	players = {1: {"name": my_name, "kills": 0, "deaths": 0, "op": int(game.settings.get("op", 0)), "dead": false}}
	game.start_mp(map_idx)
	return ""


func join(player_name: String, ip: String, port := PORT) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return "Dirección no válida"
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	my_name = player_name
	status = "Conectando con %s..." % ip
	return ""


func leave() -> void:
	for id in puppets.keys():
		_remove_puppet(id)
	puppets.clear()
	players.clear()
	reset_zombies()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	active = false
	is_host = false
	ended = false


func _on_connected() -> void:
	status = "Conectado. Esperando datos de la partida..."
	rpc_id(1, "hello", my_name, int(game.settings.get("op", 0)))


func _on_failed() -> void:
	leave()
	game.ui.mp_status("No se pudo conectar. Comprueba la IP y que el host tenga la partida creada.")


func _on_server_lost() -> void:
	leave()
	game.to_menu()
	game.ui.mp_status("El host cerró la partida.")
	game.ui.show_mp()


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		game.ui.feed_line("%s salió de la partida" % players[id].name, false)
	players.erase(id)
	_remove_puppet(id)
	if is_host:
		rpc("sync_players", players)
		if coop():
			_coop_check()


# ---------------------------------------------------------------- lobby RPCs
@rpc("any_peer", "reliable")
func hello(player_name: String, op_i: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = {"name": player_name.substr(0, 16), "kills": 0, "deaths": 0, "op": op_i, "dead": false}
	var doors: Array = game.zm.open_doors() if coop() and game.zm else []
	var rnd: int = game.zm.round_n if coop() and game.zm else 0
	rpc_id(id, "welcome", map_idx, gmode, doors, rnd)
	rpc("sync_players", players)
	game.ui.feed_line("%s se unió a la partida" % player_name, true)


@rpc("authority", "reliable")
func welcome(map_i: int, game_mode: String, doors: Array, rnd: int) -> void:
	map_idx = map_i
	gmode = game_mode
	ended = false
	game.start_mp(map_idx)
	# co-op joined mid-game: catch up with the doors already opened and the current round
	if coop() and game.zm:
		for i in doors:
			game.zm.open_door(int(i), false)
		if rnd > 0:
			game.zm.round_n = rnd
			game.zm.inter = 0.0


@rpc("authority", "call_local", "reliable")
func sync_players(p: Dictionary) -> void:
	for id in p:
		if players.has(id) and not p[id].has("kills"):
			continue
	players = p
	for id in puppets.keys():
		if not players.has(id):
			_remove_puppet(id)


# ---------------------------------------------------------------- state streaming
func update(delta: float) -> void:
	if not active or game.player == null or not is_instance_valid(game.player):
		return
	var pl = game.player
	send_t -= delta
	if send_t <= 0.0:
		send_t = 1.0 / SEND_HZ
		var flags := (1 if pl.alive else 0) | (2 if pl.crouch > 0.5 else 0) | (4 if pl.aim_k > 0.5 else 0)
		rpc("st", pl.global_position, pl.yaw, pl.pitch, flags, pl.cur)
	if coop():
		if is_host:
			_send_zombies(delta)
		return
	if not pl.alive and not ended:
		respawn_t -= delta
		if respawn_t <= 0.0:
			game.mp_respawn()


@rpc("any_peer", "unreliable_ordered")
func st(pos: Vector3, yaw: float, pitch: float, flags: int, wpn: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id) or game.state == "menu":
		return
	var alive := (flags & 1) != 0
	if alive and players[id].get("dead", false):
		players[id].dead = false
	var pp = puppets.get(id)
	if pp != null and (not is_instance_valid(pp) or pp.dead):
		if not alive:
			return
		if is_instance_valid(pp):
			game.enemies.erase(pp)
			pp.queue_free()
		puppets.erase(id)
		pp = null
	if pp == null:
		if not alive:
			return
		pp = _spawn_puppet(id, pos, yaw)
	pp.net_pos = pos
	pp.net_yaw = yaw
	pp.net_pitch = pitch
	pp.crouch_pref = (flags & 2) != 0
	pp.net_aim = (flags & 4) != 0
	pp.net_t = game.clock


func _spawn_puppet(id: int, pos: Vector3, yaw: float):
	var s = SoldierScript.new()
	s.game = game
	s.puppet = true
	s.op = int(players[id].get("op", 0))
	s.peer_id = id
	s.display_name = players[id].name
	s.teammate = coop()
	game.add_child(s)
	s.global_position = pos
	s.facing = yaw
	s.net_pos = pos
	puppets[id] = s
	if coop():
		# teammates: not shootable, not counted as enemies, zombies can chase them
		s.collision_layer = 0
		s.collision_mask = 0
	else:
		game.enemies.append(s)
	return s


func _remove_puppet(id: int) -> void:
	var pp = puppets.get(id)
	if pp != null and is_instance_valid(pp):
		game.enemies.erase(pp)
		pp.queue_free()
	puppets.erase(id)


# ---------------------------------------------------------------- shots, hits, deaths
func shot(to: Vector3) -> void:
	if active:
		rpc("fx_shot", to)


@rpc("any_peer", "unreliable")
func fx_shot(to: Vector3) -> void:
	var pp = puppets.get(multiplayer.get_remote_sender_id())
	if pp == null or not is_instance_valid(pp) or pp.dead:
		return
	var from: Vector3 = pp.tip.global_position
	pp.flash_t = 0.05
	pp.kick = 1.0
	pp.last_shot = game.clock
	game.fx.tracer(from, to)
	game.fx.flash_light(from, 2.0, 5.0)
	game.sfx.play3d("enemy", from, -2.0)


func boom(pos: Vector3, radius: float) -> void:
	if active:
		rpc("fx_boom", pos, radius)


@rpc("any_peer", "unreliable")
func fx_boom(pos: Vector3, radius: float) -> void:
	game.fx.explosion(pos, radius / 7.5)
	game.sfx.play3d("boom", pos, 4.0)
	if game.player and game.player.alive:
		game.player.shake = maxf(game.player.shake, clampf(1.2 - game.player.global_position.distance_to(pos) / 30.0, 0.0, 1.0))


## Called when this peer damages a remote player's puppet.
func send_hit(victim: int, dmg: float, head: bool) -> void:
	if active and players.has(victim):
		rpc_id(victim, "hit", dmg, head, game.player.global_position if game.player else Vector3.ZERO)


@rpc("any_peer", "reliable")
func hit(dmg: float, head: bool, from: Vector3) -> void:
	var pl = game.player
	if pl == null or not pl.alive or ended:
		return
	last_attacker = multiplayer.get_remote_sender_id()
	last_head = head
	pl.take_damage(dmg, from)


var last_attacker := 0
var last_head := false


## The local player died (from player.take_damage).
func local_died() -> void:
	respawn_t = RESPAWN_T
	var killer := last_attacker
	rpc("died", my_id(), killer, last_head)
	last_attacker = 0
	game.ui.notice("HAS CAÍDO", "Reapareces en %d segundos" % int(RESPAWN_T), RESPAWN_T)


@rpc("any_peer", "call_local", "reliable")
func died(victim: int, killer: int, head: bool) -> void:
	if players.has(victim):
		players[victim].deaths += 1
	if killer != 0 and killer != victim and players.has(killer):
		players[killer].kills += 1
	var vn: String = players[victim].name if players.has(victim) else "?"
	var kn: String = players[killer].name if players.has(killer) else ""
	if killer == 0 or killer == victim:
		game.ui.feed_line("%s se eliminó a sí mismo" % vn, false)
	else:
		game.ui.feed_line("%s eliminó a %s%s" % [kn, vn, "  (cabeza)" if head else ""], killer == my_id())
	var pp = puppets.get(victim)
	if pp != null and is_instance_valid(pp) and not pp.dead:
		pp.net_die(head)
	if killer == my_id() and victim != killer:
		game.register_kill(head, null)
		game.ui.hitmarker(true)
	if is_host and not ended and killer != 0 and players.has(killer) and players[killer].kills >= KILL_GOAL:
		rpc("match_end", killer)


@rpc("authority", "call_local", "reliable")
func match_end(winner: int) -> void:
	ended = true
	var wn: String = players[winner].name if players.has(winner) else "?"
	game.ui.notice("%s GANA LA PARTIDA" % wn.to_upper(), "Nueva partida en 10 segundos", 9.5)
	game.sfx.play("round")
	if is_host:
		get_tree().create_timer(10.0, false).timeout.connect(func():
			if active and is_host:
				for id in players:
					players[id].kills = 0
					players[id].deaths = 0
				rpc("match_restart", players)
		)


@rpc("authority", "call_local", "reliable")
func match_restart(p: Dictionary) -> void:
	players = p
	ended = false
	game.mp_respawn()
	game.ui.notice("DUELO A MUERTE", "Primero en llegar a %d bajas gana" % KILL_GOAL, 3.0)


# ---------------------------------------------------------------- co-op zombies
func reset_zombies() -> void:
	zombies.clear()
	zdead.clear()
	znext = 0
	z_attacker = 0
	for id in players:
		players[id].dead = false


## Host: a zombie was just spawned.
func z_register(z) -> void:
	znext += 1
	z.net_id = znext
	zombies[znext] = z


func _send_zombies(delta: float) -> void:
	zsend_t -= delta
	if zsend_t > 0.0 or game.zm == null:
		return
	zsend_t = 1.0 / ZSEND_HZ
	var a := PackedFloat32Array()
	a.append(float(game.zm.left()))
	for id in zombies.keys():
		var z = zombies[id]
		if z == null or not is_instance_valid(z) or z.dead:
			zombies.erase(id)
			continue
		var p: Vector3 = z.global_position
		a.append_array([float(id), p.x, p.y, p.z, z.facing, z.attack_t, float(z.gait_kind), maxf(z.rise_t, 0.0)])
	rpc("z_st", a)


@rpc("authority", "unreliable_ordered")
func z_st(a: PackedFloat32Array) -> void:
	if game.zm == null or game.state == "menu" or a.size() < 1:
		return
	game.zm.remote_left = int(a[0])
	var i := 1
	while i + 7 < a.size():
		var id := int(a[i])
		var pos := Vector3(a[i + 1], a[i + 2], a[i + 3])
		var z = zombies.get(id)
		if z == null or not is_instance_valid(z):
			if not zdead.has(id):
				z = game.zm.spawn_replica(id, pos, a[i + 4], int(a[i + 6]), a[i + 7])
				zombies[id] = z
		if z != null and is_instance_valid(z) and not z.dead:
			z.net_pos = pos
			z.facing = a[i + 4]
			# start the swipe animation when the host's zombie starts it
			if a[i + 5] > z.attack_t + 0.2:
				z.attack_t = a[i + 5]
				game.sfx.play3d("zattack", pos + Vector3(0, 1.4, 0), -3.0)
			z.net_seen = game.clock
		i += 8


## Client: our bullet / knife / explosion hit a zombie replica.
func z_send_hit(id: int, dmg: float, head: bool, melee: bool) -> void:
	if active and not is_host:
		rpc_id(1, "z_hit", id, dmg, head, melee)


@rpc("any_peer", "reliable")
func z_hit(id: int, dmg: float, head: bool, melee: bool) -> void:
	if not is_host:
		return
	var z = zombies.get(id)
	if z == null or not is_instance_valid(z) or z.dead:
		return
	z_attacker = multiplayer.get_remote_sender_id()
	z_melee = melee
	z.take_damage(dmg, head)
	z_attacker = 0
	z_melee = false


## Host: a zombie died (by = killer peer, 0 = the host itself, -1 = nobody).
func z_died(z, head: bool, by: int) -> void:
	zombies.erase(z.net_id)
	zdead[z.net_id] = true
	var killer := my_id() if by == 0 else by
	var melee: bool = z_melee if by > 0 else bool(game.kill_ctx.get("melee", false))
	if killer > 0 and players.has(killer):
		players[killer].kills += 1
	rpc("z_die", z.net_id, head, z.headless, killer, melee)


@rpc("authority", "reliable")
func z_die(id: int, head: bool, headless: bool, killer: int, melee: bool) -> void:
	zdead[id] = true
	var z = zombies.get(id)
	zombies.erase(id)
	if z != null and is_instance_valid(z):
		z.net_die(headless)
	if killer > 0 and players.has(killer):
		players[killer].kills += 1
	if killer == my_id() and game.zm:
		game.zm.add_points(game.zm.kill_points(head, melee))
		var hp: float = game.player.health if game.player else 100.0
		game.kill_ctx = {"weapon": -1, "melee": melee, "last": false, "dist": 10.0, "hp": hp}
		game.register_kill(head, z)
		game.kill_ctx = {}
		game.ui.hitmarker(true)


## Host: a zombie clawed a teammate.
func z_hurt(peer: int, dmg: float, from: Vector3) -> void:
	if active and players.has(peer):
		rpc_id(peer, "z_claw", dmg, from)


@rpc("authority", "reliable")
func z_claw(dmg: float, from: Vector3) -> void:
	if not ended:
		game.damage_player(dmg, from)


@rpc("authority", "reliable")
func z_round(r: int, total: int) -> void:
	if game.zm:
		game.zm.begin_round(r, total)


@rpc("authority", "reliable")
func z_round_end() -> void:
	if game.zm:
		game.zm.end_round()


@rpc("any_peer", "reliable")
func z_door(idx: int) -> void:
	if game.zm:
		game.zm.open_door(idx)


@rpc("authority", "reliable")
func z_drop(id: int, kind: String, pos: Vector3) -> void:
	if game.zm:
		game.zm._spawn_drop(pos, kind, id)


@rpc("any_peer", "reliable")
func z_take_req(id: int) -> void:
	if is_host and game.zm and game.zm.has_drop(id):
		rpc("z_take", id)
		game.zm.take_drop(id)


@rpc("authority", "reliable")
func z_take(id: int) -> void:
	if game.zm:
		game.zm.take_drop(id)


## The local player went down in co-op.
func coop_local_died() -> void:
	rpc("coop_dead", my_id())
	coop_dead(my_id())
	game.ui.notice("HAS CAÍDO", "Vuelves al empezar la siguiente ronda si tu equipo sobrevive", 4.0)


@rpc("any_peer", "reliable")
func coop_dead(id: int) -> void:
	if players.has(id):
		players[id].dead = true
		players[id].deaths += 1
		if id != my_id():
			game.ui.feed_line("%s ha caído" % players[id].name, false)
	var pp = puppets.get(id)
	if pp != null and is_instance_valid(pp) and not pp.dead:
		pp.net_die(false)
	if is_host:
		_coop_check()


## Host: if every player is down the match is over.
func _coop_check() -> void:
	if ended or not coop():
		return
	if game.player and is_instance_valid(game.player) and game.player.alive:
		return
	for id in players:
		if id != my_id() and not players[id].get("dead", false):
			return
	var rnd: int = game.zm.round_n if game.zm else 0
	rpc("coop_over", rnd)
	coop_over(rnd)


@rpc("authority", "reliable")
func coop_over(rnd: int) -> void:
	ended = true
	if rnd > game.best_round:
		game.best_round = rnd
		game.save_settings()
	game.ui.notice("TODO EL EQUIPO HA CAÍDO", "Sobrevivisteis %d rondas · nueva partida en 10 segundos" % rnd, 9.5)
	game.sfx.play("round")
	if is_host:
		get_tree().create_timer(10.0, false).timeout.connect(func():
			if active and is_host and coop():
				for id in players:
					players[id].kills = 0
					players[id].deaths = 0
					players[id].dead = false
				rpc("coop_restart", players)
				coop_restart(players)
		)


@rpc("authority", "reliable")
func coop_restart(p: Dictionary) -> void:
	players = p
	ended = false
	game.start_mp(map_idx)


# ---------------------------------------------------------------- HUD helpers
func leader() -> Array:
	var best_id := 0
	var best := -1
	for id in players:
		if players[id].kills > best:
			best = players[id].kills
			best_id = id
	return [players[best_id].name if players.has(best_id) else "-", maxi(best, 0)]


func me() -> Dictionary:
	return players.get(my_id(), {"name": my_name, "kills": 0, "deaths": 0})


func board() -> String:
	var ids := players.keys()
	ids.sort_custom(func(a, b): return players[a].kills > players[b].kills)
	var t := "%-18s %6s %8s\n" % ["JUGADOR", "BAJAS", "MUERTES"]
	for id in ids:
		var p: Dictionary = players[id]
		t += "%-18s %6d %8d%s\n" % [p.name, p.kills, p.deaths, "   <" if id == my_id() else ""]
	return t
