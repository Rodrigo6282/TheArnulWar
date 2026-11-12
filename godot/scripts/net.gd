extends Node
## Multiplayer (ENet, host + clients): free-for-all deathmatch on the Operación maps.
## Every peer simulates its own player; positions are streamed unreliably, hits/deaths/scores
## go reliably. Remote players are "puppet" soldiers that forward damage to their owner.

const SoldierScript := preload("res://scripts/soldier.gd")
const WB := preload("res://scripts/world.gd")
const PORT := 7777
const SEND_HZ := 20.0
const KILL_GOAL := 20
const TEAM_GOAL := 40
const RESPAWN_T := 3.0
## Game modes: id -> [title, short description]
const MODES := {
	"ffa": ["TODOS CONTRA TODOS", "Cada uno por su cuenta · primero en llegar a 20 bajas gana"],
	"tdm": ["DUELO POR EQUIPOS", "Equipo Alfa contra equipo Bravo · el primer equipo en llegar a 40 bajas gana"],
	"gun": ["JUEGO DE ARMAS", "Cada baja te da un arma nueva · completa todas las armas para ganar · el cuchillo roba un nivel"],
	"zombies": ["ZOMBIS COOPERATIVO", "Todos juntos contra las rondas de zombis · si caes, vuelves en la siguiente ronda"],
}
const MODE_ORDER := ["ffa", "tdm", "gun", "zombies"]
## Gun game ladder (weapon indices from player.gd) and kills needed per weapon.
const GUN_LADDER := [0, 3, 1, 5, 4, 2]
const GUN_KILLS := 2
const TEAM_NAMES := ["ALFA", "BRAVO"]
const TEAM_COLS := [Color(0.35, 0.65, 1.0), Color(1.0, 0.45, 0.3)]

var game
var active := false
var is_host := false
var my_name := "Jugador"
var map_idx := 0
var gmode := "ffa"
var team_kills := [0, 0]
var zsend_t := 0.0
var znext_id := 1
var players := {}        # id -> {name, kills, deaths}
var puppets := {}        # id -> soldier puppet node
var send_t := 0.0
var alive_map := {}      # id -> alive (from the state stream)
var respawn_t := 0.0
var ended := false
var status := ""

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
	# host side: announce the LAN game while it is running (online games use the invite code)
	if active and is_host and not ended and not online_mode:
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
		"map": "%s · %s" % [WB.MAPS[map_idx].name, mode_title()],
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
		var g := {"name": str(d.get("name", "?")).substr(0, 16), "map": str(d.get("map", "")),
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
	_make_online()


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1


static func local_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a)
	return out


# ---------------------------------------------------------------- host / join / leave
# ---------------------------------------------------------------- online (internet) play
# Without opening ports: WebRTC through online.gd (encrypted signalling on a public message board,
# direct peer-to-peer connection with STUN). ENet stays for the local network and typed IPs.
const OnlineScript := preload("res://scripts/online.gd")
signal online_changed
var online: Node
var online_mode := false     # this game was created / joined with an invite code
var invite_code := ""


func _make_online() -> void:
	online = OnlineScript.new()
	online.name = "Online"
	online.net = self
	add_child(online)
	online.failed.connect(_on_online_failed)


## online.gd found the host: install the WebRTC peer (connected_to_server fires when it opens).
func use_peer(p: MultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = p
	status = "Conectando con el anfitrión..."
	game.ui.mp_status(status)


func _on_online_failed(msg: String) -> void:
	if is_host:
		return
	leave()
	game.ui.mp_status(msg)


## Join an online game with its invite code.
func join_code(player_name: String, c: String) -> String:
	if not OnlineScript.valid_code(c):
		return "Código no válido: revisa que tenga 8 caracteres (por ejemplo 7K3M-9QX4)."
	leave()
	multiplayer.multiplayer_peer = null
	active = true
	is_host = false
	online_mode = true
	my_name = player_name
	status = "Buscando la partida %s..." % c.to_upper()
	online.join_room(c)
	return ""


## One line for the HUD / scoreboard / pause menu.
func online_line() -> String:
	if active and is_host and online_mode and invite_code != "":
		return "Código para invitar: %s" % invite_code
	return ""

func mode_title() -> String:
	return MODES.get(gmode, MODES.ffa)[0]


func is_coop() -> bool:
	return active and gmode == "zombies"


func team_of(id: int) -> int:
	return int(players.get(id, {}).get("team", 0))


## True when peer `id` is on the local player's team (team deathmatch only).
func is_ally(id: int) -> bool:
	if not active:
		return false
	if gmode == "zombies":
		return true
	return gmode == "tdm" and team_of(id) == team_of(my_id())


func _new_player(pname: String, op_i: int) -> Dictionary:
	# balance teams: join the smaller one
	var n := [0, 0]
	for id in players:
		n[team_of(id)] += 1
	return {"name": pname.substr(0, 16), "kills": 0, "deaths": 0, "op": op_i, "team": 0 if n[0] <= n[1] else 1, "lvl": 0, "lk": 0}


## online = internet game with an invite code (WebRTC, no ports to open); else LAN (ENet).
func host(player_name: String, map_i: int, port := PORT, mode_id := "ffa", online_game := false) -> String:
	leave()
	gmode = mode_id if MODES.has(mode_id) else "ffa"
	if online_game:
		multiplayer.multiplayer_peer = online.host_room()
		invite_code = online.code
		online_mode = true
	else:
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
	team_kills = [0, 0]
	znext_id = 1
	players = {}
	players[1] = _new_player(my_name, int(game.settings.get("op", 0)))
	game.start_mp(map_idx)
	if online_mode:
		game.ui.notice("PARTIDA ONLINE", "Código para invitar: %s  ·  lo tienes en Tab y en el menú de pausa (con botón para copiarlo)" % invite_code, 7.0)
		online_changed.emit()
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
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	active = false
	is_host = false
	ended = false
	team_kills = [0, 0]
	if online:
		online.close()
	online_mode = false
	invite_code = ""


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


# ---------------------------------------------------------------- lobby RPCs
@rpc("any_peer", "reliable")
func hello(player_name: String, op_i: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = _new_player(player_name, op_i)
	rpc_id(id, "welcome", map_idx, gmode, team_kills, game.zm.snapshot_state() if game.zm else {})
	rpc("sync_players", players)
	var tn := ""
	if gmode == "tdm":
		tn = " (equipo %s)" % TEAM_NAMES[players[id].team]
	game.ui.feed_line("%s se unió a la partida%s" % [player_name, tn], true)


@rpc("authority", "reliable")
func welcome(map_i: int, mode_id: String, tk: Array, zstate: Dictionary) -> void:
	map_idx = map_i
	gmode = mode_id
	team_kills = tk
	ended = false
	game.start_mp(map_idx)
	if game.zm and not zstate.is_empty():
		game.zm.apply_state(zstate)


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
	if is_host and gmode == "zombies" and game.zm:
		zsend_t -= delta
		if zsend_t <= 0.0:
			zsend_t = 0.1
			_send_zombies()
		_check_coop_wipe()
	# in co-op zombies a downed player waits for the next round (zmode calls coop_round_start)
	if not pl.alive and not ended and gmode != "zombies":
		respawn_t -= delta
		if respawn_t <= 0.0:
			game.mp_respawn()


@rpc("any_peer", "unreliable_ordered")
func st(pos: Vector3, yaw: float, pitch: float, flags: int, wpn: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id) or game.state == "menu":
		return
	var alive := (flags & 1) != 0
	alive_map[id] = alive
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
	if gmode == "tdm":
		s.label_col = TEAM_COLS[team_of(id)]
		s.display_name += "  [%s]" % TEAM_NAMES[team_of(id)]
	elif gmode == "zombies":
		s.label_col = TEAM_COLS[0]
	game.add_child(s)
	s.global_position = pos
	s.facing = yaw
	s.net_pos = pos
	puppets[id] = s
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
	if active and players.has(victim) and not is_ally(victim):
		var melee: bool = bool(game.kill_ctx.get("melee", false)) if game.kill_ctx else false
		rpc_id(victim, "hit", dmg, head, game.player.global_position if game.player else Vector3.ZERO, melee)


@rpc("any_peer", "reliable")
func hit(dmg: float, head: bool, from: Vector3, melee := false) -> void:
	var pl = game.player
	if pl == null or not pl.alive or ended:
		return
	var from_id := multiplayer.get_remote_sender_id()
	if gmode != "zombies" and is_ally(from_id):
		return
	last_attacker = from_id if gmode != "zombies" else 0
	last_head = head
	last_melee = melee
	pl.take_damage(dmg, from)


var last_attacker := 0
var last_head := false
var last_melee := false


## Host only: a host-side zombie swiped at a remote player.
func zombie_hit(victim: int, dmg: float, from: Vector3) -> void:
	if active and players.has(victim):
		rpc_id(victim, "hit", dmg, false, from, false)


## The local player died (from player.take_damage).
func local_died() -> void:
	respawn_t = RESPAWN_T
	var killer := last_attacker
	rpc("died", my_id(), killer, last_head, last_melee)
	last_attacker = 0
	last_melee = false
	if gmode == "zombies":
		game.ui.notice("HAS CAÍDO", "Vuelves al empezar la siguiente ronda · tus compañeros siguen luchando", 4.0)
	else:
		game.ui.notice("HAS CAÍDO", "Reapareces en %d segundos" % int(RESPAWN_T), RESPAWN_T)


@rpc("any_peer", "call_local", "reliable")
func died(victim: int, killer: int, head: bool, melee := false) -> void:
	alive_map[victim] = false
	if players.has(victim):
		players[victim].deaths += 1
	var valid_kill: bool = killer != 0 and killer != victim and players.has(killer)
	if valid_kill:
		players[killer].kills += 1
		if gmode == "tdm":
			team_kills[team_of(killer)] += 1
		elif gmode == "gun":
			_gun_progress(killer, victim, melee)
	var vn: String = players[victim].name if players.has(victim) else "?"
	var kn: String = players[killer].name if players.has(killer) else ""
	if gmode == "zombies":
		game.ui.feed_line("%s ha caído" % vn, false)
	elif not valid_kill:
		game.ui.feed_line("%s se eliminó a sí mismo" % vn, false)
	else:
		var how := "  (cabeza)" if head else ("  (cuchillo)" if melee else "")
		game.ui.feed_line("%s eliminó a %s%s" % [kn, vn, how], killer == my_id())
	var pp = puppets.get(victim)
	if pp != null and is_instance_valid(pp) and not pp.dead:
		pp.net_die(head)
	if killer == my_id() and valid_kill:
		game.register_kill(head, null)
		game.ui.hitmarker(true)
	if is_host and not ended and valid_kill:
		var won := -1
		match gmode:
			"ffa":
				if players[killer].kills >= KILL_GOAL:
					won = killer
			"tdm":
				if team_kills[team_of(killer)] >= TEAM_GOAL:
					won = 1000 + team_of(killer)
			"gun":
				if int(players[killer].lvl) >= GUN_LADDER.size():
					won = killer
		if won >= 0:
			rpc("match_end", won)


## Gun game: the killer climbs the ladder; a knife kill also takes one level from the victim.
func _gun_progress(killer: int, victim: int, melee: bool) -> void:
	var k: Dictionary = players[killer]
	k.lk = int(k.lk) + 1
	if k.lk >= GUN_KILLS or melee:
		k.lk = 0
		k.lvl = int(k.lvl) + 1
		if killer == my_id() and int(k.lvl) < GUN_LADDER.size():
			game.gun_game_loadout(true)
	if melee and players.has(victim):
		var v: Dictionary = players[victim]
		if int(v.lvl) > 0:
			v.lvl = int(v.lvl) - 1
			v.lk = 0
			if victim == my_id():
				game.ui.feed_line("¡Humillado! Bajas un nivel de arma", false)


func gun_weapon(id: int) -> int:
	return GUN_LADDER[clampi(int(players.get(id, {}).get("lvl", 0)), 0, GUN_LADDER.size() - 1)]


@rpc("authority", "call_local", "reliable")
func match_end(winner: int) -> void:
	ended = true
	var title := ""
	if winner >= 1000:
		var t := winner - 1000
		title = "GANA EL EQUIPO %s" % TEAM_NAMES[t]
		if t == team_of(my_id()):
			title = "¡VICTORIA! " + title
	elif winner < 0:
		title = "LOS ZOMBIS HAN GANADO"
	else:
		var wn: String = players[winner].name if players.has(winner) else "?"
		title = "%s GANA LA PARTIDA" % wn.to_upper()
	var sub := "Nueva partida en 10 segundos"
	if winner < 0 and game.zm:
		sub = "Habéis sobrevivido %d rondas · %s" % [maxi(game.zm.round_n - 1, 0), sub]
	game.ui.notice(title, sub, 9.5)
	game.sfx.play("round")
	if is_host:
		get_tree().create_timer(10.0, false).timeout.connect(func():
			if active and is_host:
				for id in players:
					players[id].kills = 0
					players[id].deaths = 0
					players[id].lvl = 0
					players[id].lk = 0
				rpc("match_restart", players)
		)


@rpc("authority", "call_local", "reliable")
func match_restart(p: Dictionary) -> void:
	players = p
	ended = false
	team_kills = [0, 0]
	if gmode == "zombies":
		# fresh map (closed doors) and round 1 for everyone
		game.map_dirty = true
		game.start_mp(map_idx)
		return
	game.mp_respawn()
	game.ui.notice(mode_title(), MODES[gmode][1], 3.0)


# ---------------------------------------------------------------- co-op zombies
# The host owns every zombie (AI, rounds, damage). Clients see "remote" zombies that follow
# a 10 Hz snapshot; their hits are sent to the host, which answers with points / deaths.

func _send_zombies() -> void:
	var arr := []
	for e in game.enemies:
		if is_instance_valid(e) and e.has_method("net_flags") and not e.dead:
			arr.append([e.nid, e.global_position, e.facing, e.net_flags()])
	var zm = game.zm
	rpc("zsnap", arr, zm.round_n, zm.to_spawn, zm.inter)


@rpc("authority", "unreliable_ordered")
func zsnap(arr: Array, round_n: int, to_spawn: int, inter: float) -> void:
	if game.zm:
		game.zm.client_snapshot(arr, round_n, to_spawn, inter)


func zspawn(z) -> void:
	if not is_coop() or not is_host:
		return
	z.nid = znext_id
	znext_id += 1
	rpc("zspawn_rpc", z.nid, z.global_position, z.facing, z.round_n, z.gait_kind, z.speed)


@rpc("authority", "reliable")
func zspawn_rpc(nid: int, pos: Vector3, facing: float, rnd: int, gait: int, spd: float) -> void:
	if game.zm:
		game.zm.client_spawn(nid, pos, facing, rnd, gait, spd)


## Client hit a remote zombie: the host applies the damage.
func zhit_send(nid: int, dmg: float, head: bool) -> void:
	var melee: bool = bool(game.kill_ctx.get("melee", false)) if game.kill_ctx else false
	rpc_id(1, "zhit", nid, dmg, head, melee)


@rpc("any_peer", "reliable")
func zhit(nid: int, dmg: float, head: bool, melee: bool) -> void:
	if not is_host or game.zm == null:
		return
	var z = game.zm.find_zombie(nid)
	if z == null or z.dead:
		return
	z.attacker = multiplayer.get_remote_sender_id()
	game.kill_ctx = {"melee": melee}
	z.take_damage(dmg, head)
	z.attacker = 0


## Host: tell a client how many points it earned (and whether that was a kill).
func zpoints(peer: int, pts: int, killed: bool, head: bool) -> void:
	rpc_id(peer, "zpts", pts, killed, head)


@rpc("authority", "reliable")
func zpts(pts: int, killed: bool, head: bool) -> void:
	if game.zm == null:
		return
	game.zm.add_points(pts)
	if killed:
		game.register_kill(head, null)
		game.ui.hitmarker(true)


func zdie(nid: int, head: bool) -> void:
	if is_coop() and is_host:
		rpc("zdie_rpc", nid, head)


@rpc("authority", "reliable")
func zdie_rpc(nid: int, head: bool) -> void:
	if game.zm:
		var z = game.zm.find_zombie(nid)
		if z != null and not z.dead:
			z.remote_die(head)


@rpc("authority", "reliable")
func zcleared(n: int) -> void:
	game.ui.notice("RONDA %d SUPERADA" % n, "La siguiente empieza en 9 segundos", 3.5)
	game.sfx.play("wave")


func zround(n: int, total: int) -> void:
	if is_coop() and is_host:
		rpc("zround_rpc", n, total)


@rpc("authority", "reliable")
func zround_rpc(n: int, total: int) -> void:
	if game.zm:
		game.zm.client_round(n, total)


## Round start: everybody that was down comes back.
func coop_round_start() -> void:
	var pl = game.player
	if pl != null and is_instance_valid(pl) and not pl.alive and not ended:
		game.mp_respawn(true)
		game.ui.notice("¡DE VUELTA!", "Has vuelto a la lucha", 2.0)


func _check_coop_wipe() -> void:
	if ended:
		return
	var pl = game.player
	if pl == null or pl.alive:
		return
	for id in players:
		if id != my_id() and alive_map.get(id, true):
			return
	rpc("match_end", -1)


## Debris removed by anyone: open it on every peer.
func zdoor(idx: int) -> void:
	if is_coop():
		rpc("zdoor_rpc", idx)


@rpc("any_peer", "reliable")
func zdoor_rpc(idx: int) -> void:
	if game.zm:
		game.zm.open_door(idx, false)


func zdrop(nid: int, pos: Vector3, kind: String) -> void:
	if is_coop() and is_host:
		rpc("zdrop_rpc", nid, pos, kind)


@rpc("authority", "reliable")
func zdrop_rpc(nid: int, pos: Vector3, kind: String) -> void:
	if game.zm:
		game.zm.spawn_drop(pos, kind, nid)


## Someone touched a power-up: the host confirms it once and everybody gets it.
func zdrop_take(nid: int) -> void:
	if is_host:
		_zdrop_take_host(nid, my_id())
	else:
		rpc_id(1, "zdrop_take_rpc", nid)


@rpc("any_peer", "reliable")
func zdrop_take_rpc(nid: int) -> void:
	_zdrop_take_host(nid, multiplayer.get_remote_sender_id())


func _zdrop_take_host(nid: int, who: int) -> void:
	if not is_host or game.zm == null or not game.zm.has_drop(nid):
		return
	rpc("zdrop_apply", nid, who)
	zdrop_apply(nid, who)


@rpc("authority", "reliable")
func zdrop_apply(nid: int, who: int) -> void:
	if game.zm:
		game.zm.take_drop(nid, who == my_id())


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
	if gmode == "gun":
		ids.sort_custom(func(a, b): return int(players[a].lvl) * 10 + int(players[a].lk) > int(players[b].lvl) * 10 + int(players[b].lk))
	else:
		ids.sort_custom(func(a, b): return players[a].kills > players[b].kills)
	var t := mode_title() + "\n"
	if gmode == "tdm":
		t += "ALFA %d  ·  BRAVO %d   (meta %d)\n" % [team_kills[0], team_kills[1], TEAM_GOAL]
	t += "\n"
	var extra := "EQUIPO" if gmode == "tdm" else ("ARMA" if gmode == "gun" else "")
	t += "%-18s %6s %8s %10s\n" % ["JUGADOR", "BAJAS", "MUERTES", extra]
	for id in ids:
		var p: Dictionary = players[id]
		var ex := ""
		if gmode == "tdm":
			ex = TEAM_NAMES[team_of(id)]
		elif gmode == "gun":
			ex = "%d/%d" % [mini(int(p.lvl) + 1, GUN_LADDER.size()), GUN_LADDER.size()]
		t += "%-18s %6d %8d %10s%s\n" % [p.name, p.kills, p.deaths, ex, "   <" if id == my_id() else ""]
	return t


## One-line HUD status for the current mode.
func hud_line() -> String:
	var m := me()
	match gmode:
		"tdm":
			var mt := team_of(my_id())
			return "DUELO POR EQUIPOS · Tu equipo: %s\nALFA %d  ·  BRAVO %d  (meta %d)" % [TEAM_NAMES[mt], team_kills[0], team_kills[1], TEAM_GOAL]
		"gun":
			var lvl := int(m.get("lvl", 0))
			var wn: String = game.player.weapons[gun_weapon(my_id())].short if game.player else ""
			return "JUEGO DE ARMAS · Arma %d/%d: %s (%d/%d bajas)\nLíder: %s" % [mini(lvl + 1, GUN_LADDER.size()), GUN_LADDER.size(), wn, int(m.get("lk", 0)), GUN_KILLS, _gun_leader()]
		"zombies":
			return ""
	var ld: Array = leader()
	return "TODOS CONTRA TODOS · %d jugadores\nTú %d bajas / %d muertes · Líder: %s (%d/%d)" % [players.size(), m.kills, m.deaths, ld[0], ld[1], KILL_GOAL]


func _gun_leader() -> String:
	var best_id := 0
	var best := -1
	for id in players:
		var v := int(players[id].lvl) * 10 + int(players[id].lk)
		if v > best:
			best = v
			best_id = id
	return "%s (arma %d)" % [players[best_id].name, mini(int(players[best_id].lvl) + 1, GUN_LADDER.size())] if players.has(best_id) else "-"
