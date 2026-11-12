extends Node
## Internet play without opening ports: the players connect with WebRTC data channels (direct,
## NAT traversal with public STUN servers). To find each other they exchange the WebRTC
## offer/answer/ICE messages on a public message board (ntfy.sh). The board topic and an AES key
## are derived from the invite code, so the messages (which contain addresses) are unreadable
## without the code. Once a WebRTCMultiplayerPeer is connected, Godot's high-level multiplayer
## (RPCs in net.gd) works exactly as with ENet.

signal failed(msg: String)

const NTFY_HOST := "ntfy.sh"
const ICE := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302", "stun:stun.cloudflare.com:3478"]}]}
const CODE_ABC := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
const JOIN_TIMEOUT := 25.0

var net
var code := ""
var role := ""               # "" | "host" | "client"
var rtc: WebRTCMultiplayerPeer
var key := PackedByteArray()
var topic := ""
var my_uid := ""
# host: one connection per joining player
var conns := {}              # uid -> {"id": int, "pc": WebRTCPeerConnection}
var next_id := 2
# client
var pc: WebRTCPeerConnection
var join_t := 0.0
var hello_t := 0.0
var got_offer := false
var early_ice: Array = []     # candidates that arrived before the offer (messages can be reordered)
# message board stream
var http: HTTPClient
var requested := false
var stream_ready := false
var buf := ""
var since := ""
var retry_t := 0.0
var outbox: Array = []
var sending := 0


# ---------------------------------------------------------------- invite codes
## 7 random letters + 1 check letter (weighted sum with odd weights: every single-letter
## typo changes it, so mistyped codes are rejected before contacting anybody).
static func new_code() -> String:
	var c := ""
	for i in 7:
		c += CODE_ABC[randi() % 32]
	c += _check(c)
	return c.substr(0, 4) + "-" + c.substr(4, 4)


static func _check(seven: String) -> String:
	var s := 0
	for i in 7:
		s += CODE_ABC.find(seven[i]) * (2 * i + 1)
	return CODE_ABC[s % 32]


static func normalize(c: String) -> String:
	return c.to_upper().replace("-", "").replace(" ", "")


static func valid_code(c: String) -> bool:
	var n := normalize(c)
	if n.length() != 8:
		return false
	for ch in n:
		if CODE_ABC.find(ch) < 0:
			return false
	return _check(n.substr(0, 7)) == n[7]


func _setup_room(c: String) -> void:
	code = c
	var n := normalize(c)
	topic = "taw" + (n + "|arnul-topic").sha256_text().substr(0, 26)
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update((n + "|arnul-key").to_utf8_buffer())
	key = hc.finish()
	my_uid = "%08x%08x" % [randi(), randi()]
	since = str(int(Time.get_unix_time_from_system()) - 5)


# ---------------------------------------------------------------- start / stop
## Host: create the room. Returns the multiplayer peer to install.
func host_room() -> WebRTCMultiplayerPeer:
	close()
	role = "host"
	_setup_room(new_code())
	rtc = WebRTCMultiplayerPeer.new()
	rtc.create_server()
	conns.clear()
	next_id = 2
	_open_stream()
	return rtc


## Client: look for the room with this code (the peer is installed when the host answers).
func join_room(c: String) -> void:
	close()
	role = "client"
	_setup_room(c)
	join_t = 0.0
	hello_t = 0.0
	got_offer = false
	early_ice.clear()
	_open_stream()


func close() -> void:
	for uid in conns:
		var p: WebRTCPeerConnection = conns[uid].pc
		p.close()
	conns.clear()
	if pc:
		pc.close()
		pc = null
	rtc = null
	if http:
		http.close()
		http = null
	role = ""
	code = ""
	stream_ready = false
	requested = false
	buf = ""
	outbox.clear()
	early_ice.clear()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if role == "":
		return
	_poll_stream(delta)
	_flush_outbox()
	if role == "client":
		join_t += delta
		if not got_offer:
			# keep knocking until the host answers (it may have reconnected to the board)
			hello_t -= delta
			if stream_ready and hello_t <= 0.0:
				hello_t = 3.0
				_send({"t": "hello", "from": my_uid})
			if join_t > JOIN_TIMEOUT:
				_fail("No se encontró la partida. Comprueba el código y que el anfitrión siga con la partida abierta.")
		elif pc and pc.get_connection_state() == WebRTCPeerConnection.STATE_FAILED:
			_fail("No se pudo conectar directamente con el anfitrión: alguna de las dos conexiones no lo permite (4G o CG-NAT). Probad con otra red o con una VPN de juegos.")
		elif pc and pc.get_connection_state() != WebRTCPeerConnection.STATE_CONNECTED and join_t > JOIN_TIMEOUT + 15.0:
			_fail("La conexión con el anfitrión tarda demasiado. Inténtalo otra vez.")
		elif pc and pc.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTED and http:
			# connected: the board is no longer needed
			http.close()
			http = null
	elif role == "host":
		for uid in conns.keys():
			var p: WebRTCPeerConnection = conns[uid].pc
			var st := p.get_connection_state()
			if st == WebRTCPeerConnection.STATE_FAILED or st == WebRTCPeerConnection.STATE_CLOSED:
				if rtc and rtc.has_peer(conns[uid].id):
					rtc.remove_peer(conns[uid].id)
				conns.erase(uid)


func _fail(msg: String) -> void:
	close()
	failed.emit(msg)


# ---------------------------------------------------------------- signalling messages
func _on_message(m: Dictionary) -> void:
	if m.get("from", "") == my_uid:
		return
	var t: String = m.get("t", "")
	if role == "host":
		var uid: String = str(m.get("from", ""))
		if uid == "":
			return
		if t == "hello" and not conns.has(uid):
			if conns.size() >= net.MAX_PLAYERS - 1:
				return
			var id := next_id
			next_id += 1
			var p := WebRTCPeerConnection.new()
			p.initialize(ICE)
			p.session_description_created.connect(_on_local_sdp.bind(p, uid, id))
			p.ice_candidate_created.connect(_on_local_ice.bind(uid))
			rtc.add_peer(p, id)
			conns[uid] = {"id": id, "pc": p, "ready": false, "ice": []}
			p.create_offer()
		elif t == "answer" and conns.has(uid):
			var c: Dictionary = conns[uid]
			if not c.ready:
				c.ready = true
				c.pc.set_remote_description("answer", str(m.get("sdp", "")))
				for q in c.ice:
					c.pc.add_ice_candidate(str(q.m), int(q.i), str(q.n))
				c.ice.clear()
		elif t == "ice" and conns.has(uid):
			# a candidate can overtake the answer: keep it until the answer is set
			if conns[uid].ready:
				conns[uid].pc.add_ice_candidate(str(m.m), int(m.i), str(m.n))
			else:
				conns[uid].ice.append(m)
	elif role == "client":
		if m.get("to", "") != my_uid:
			return
		if t == "offer" and not got_offer:
			got_offer = true
			join_t = 0.0
			rtc = WebRTCMultiplayerPeer.new()
			rtc.create_client(int(m.id))
			pc = WebRTCPeerConnection.new()
			pc.initialize(ICE)
			pc.session_description_created.connect(_on_local_sdp.bind(pc, "", 1))
			pc.ice_candidate_created.connect(_on_local_ice.bind(""))
			rtc.add_peer(pc, 1)
			pc.set_remote_description("offer", str(m.sdp))
			for q in early_ice:
				pc.add_ice_candidate(str(q.m), int(q.i), str(q.n))
			early_ice.clear()
			net.use_peer(rtc)
		elif t == "ice":
			if pc:
				pc.add_ice_candidate(str(m.m), int(m.i), str(m.n))
			elif early_ice.size() < 64:
				early_ice.append(m)


func _on_local_sdp(type: String, sdp: String, p: WebRTCPeerConnection, uid: String, id: int) -> void:
	p.set_local_description(type, sdp)
	if role == "host":
		_send({"t": type, "to": uid, "id": id, "sdp": sdp, "from": my_uid})
	else:
		_send({"t": type, "from": my_uid, "sdp": sdp})


func _on_local_ice(media: String, index: int, cand: String, uid: String) -> void:
	if role == "host":
		_send({"t": "ice", "to": uid, "m": media, "i": index, "n": cand, "from": my_uid})
	else:
		_send({"t": "ice", "from": my_uid, "m": media, "i": index, "n": cand})


# ---------------------------------------------------------------- encryption (AES-256-CBC)
func _encrypt(d: Dictionary) -> String:
	var data := JSON.stringify(d).to_utf8_buffer()
	var pad := 16 - data.size() % 16
	for i in pad:
		data.append(pad)
	var iv := Crypto.new().generate_random_bytes(16)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv)
	var ct := aes.update(data)
	aes.finish()
	return Marshalls.raw_to_base64(iv + ct)


func _decrypt(s: String) -> Variant:
	var raw := Marshalls.base64_to_raw(s.strip_edges())
	if raw.size() < 32 or raw.size() % 16 != 0:
		return null
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, key, raw.slice(0, 16))
	var pt := aes.update(raw.slice(16))
	aes.finish()
	var pad := pt[pt.size() - 1]
	if pad < 1 or pad > 16:
		return null
	var d = JSON.parse_string(pt.slice(0, pt.size() - pad).get_string_from_utf8())
	return d if typeof(d) == TYPE_DICTIONARY else null


# ---------------------------------------------------------------- message board (ntfy.sh)
func _send(d: Dictionary) -> void:
	outbox.append(_encrypt(d))


func _flush_outbox() -> void:
	# a few posts in flight at most (the board limits bursts)
	while not outbox.is_empty() and sending < 3:
		var body: String = outbox.pop_front()
		var req := HTTPRequest.new()
		req.timeout = 10.0
		add_child(req)
		sending += 1
		req.request_completed.connect(func(_r, _c, _h, _b):
			sending -= 1
			req.queue_free()
		)
		req.request("https://%s/%s" % [NTFY_HOST, topic], ["Content-Type: text/plain"], HTTPClient.METHOD_POST, body)


func _open_stream() -> void:
	http = HTTPClient.new()
	requested = false
	stream_ready = false
	buf = ""
	if http.connect_to_host(NTFY_HOST, 443, TLSOptions.client()) != OK:
		http = null
		retry_t = 2.0


func _poll_stream(delta: float) -> void:
	if http == null:
		if role == "host" or (role == "client" and not got_offer):
			retry_t -= delta
			if retry_t <= 0.0:
				_open_stream()
		return
	http.poll()
	match http.get_status():
		HTTPClient.STATUS_CONNECTED:
			if requested:
				# the server ended the stream: reconnect from the last message
				http.close()
				http = null
				retry_t = 0.5
			else:
				requested = true
				http.request(HTTPClient.METHOD_GET, "/%s/json?since=%s" % [topic, since], ["Accept: application/x-ndjson"])
		HTTPClient.STATUS_BODY:
			var chunk := http.read_response_body_chunk()
			if chunk.size() > 0:
				buf += chunk.get_string_from_utf8()
				var lines := buf.split("\n")
				buf = lines[lines.size() - 1]
				for i in lines.size() - 1:
					_on_board_line(lines[i])
		HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			http = null
			retry_t = 2.0


func _on_board_line(line: String) -> void:
	var ev = JSON.parse_string(line)
	if typeof(ev) != TYPE_DICTIONARY:
		return
	var e: String = ev.get("event", "")
	if e == "open":
		stream_ready = true
	elif e == "message":
		since = str(ev.get("id", since))
		var m = _decrypt(str(ev.get("message", "")))
		if m != null:
			_on_message(m)
