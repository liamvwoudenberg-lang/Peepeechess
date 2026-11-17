class_name InviteJoin
extends Node
## Joins a friend's hosted game from an invite: pins the host certificate carried in the invite, tries the invite's addresses one after
## another (public address first, then LAN), then sends JoinMatch with the invite's match id. Reconnects after that use the client's
## normal session resume. Emits plain-language progress and failures for the UI.
signal status(text: String)
signal joined(invite: Dictionary)
signal failed(code: String, message: String)
const ATTEMPT_MS = 7000
const CA_FILE = "user://host-invite.crt"
var client: OnlineChessClient
var invite: Dictionary = {}
var own_tuning = ""
var _index = -1
var _attempt_started = 0
var _active = false
var _joining = false
var _ca_path = ""
## Tests and relay mode: {"host": ..., "port": ...} replaces the invite's addresses (a latency proxy or a relay in front of the host).
var address_override: Dictionary = {}
## Relay mode: an invite that names a relay is tried through the relay first (no port forwarding needed, nobody's IP is revealed), then through
## its direct addresses. Tests can switch the relay off to check the direct path.
var relay_enabled = true
var relay_bridge: RelayBridge
const RELAY_WAIT_MS = 9000
var _targets: Array = []
var _waiting_relay = false

## Validates the invite text and starts connecting. Returns {ok} or {ok: false, code, message} (nothing was started then).
func begin(chess_client: OnlineChessClient, invite_text: String, tuning: String, passphrase: String = "") -> Dictionary:
	client = chess_client
	own_tuning = tuning
	var parsed = HostInvite.decode(invite_text, passphrase)
	if not parsed.ok:
		return parsed
	var fit = HostInvite.compatible(parsed, own_tuning)
	if not fit.ok:
		return fit
	invite = parsed
	var file = FileAccess.open(CA_FILE, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "code": "STORAGE", "message": "Could not store the host's certificate."}
	file.store_string(invite.certificate)
	file.close()
	_ca_path = CA_FILE
	if not client.session_ready.is_connected(_session_ready):
		client.session_ready.connect(_session_ready)
		client.protocol_error.connect(_protocol_error)
		client.frame_received.connect(_frame)
	_targets = []
	if not str(invite.get("relay", "")).is_empty() and relay_enabled:
		_targets.append({"kind": "relay"})
	for address in invite.hosts:
		_targets.append({"kind": "direct", "host": address})
	_active = true
	_joining = false
	_index = -1
	_next_address()
	return {"ok": true}

func cancel() -> void:
	_active = false
	_stop_bridge()
	if client != null:
		client.disconnect_server(true)

func _stop_bridge() -> void:
	_waiting_relay = false
	if relay_bridge != null:
		relay_bridge.stop()
		relay_bridge.queue_free()
		relay_bridge = null

func _relay_state(value: String) -> void:
	if not _active or not _waiting_relay:
		return
	if value == "peer":
		_waiting_relay = false
		_dial("127.0.0.1", relay_bridge.local_port)
	elif value == "failed":
		_next_address()

func _next_address() -> void:
	_stop_bridge()
	_index += 1
	if _index >= _targets.size():
		_active = false
		client.disconnect_server(true)
		var relay_only = invite.hosts.is_empty()
		failed.emit("UNREACHABLE", ("Could not reach your friend through the relay. Check that your friend is still hosting, that the invite is complete and that your internet works." if relay_only else "Could not reach the host. Check that your friend is still hosting, that the invite is complete, and that their router forwards UDP port %d (see the hosting guide)." % int(invite.port)))
		return
	var target: Dictionary = _targets[_index]
	status.emit("Connecting to the host (%d of %d)…" % [_index + 1, _targets.size()])   # the address itself is never shown or logged
	client.disconnect_server(true)
	_attempt_started = Time.get_ticks_msec()
	client.auto_reconnect = false
	if target.kind == "relay":
		relay_bridge = RelayBridge.new()
		add_child(relay_bridge)
		relay_bridge.state_changed.connect(_relay_state)
		_waiting_relay = true
		if relay_bridge.start_guest(str(invite.relay), str(invite.session)) != OK:
			_next_address()
		return
	var host: String = str(target.host)
	var dial_port = int(invite.port)
	if not address_override.is_empty():
		host = str(address_override.host)
		dial_port = int(address_override.port)
	_dial(host, dial_port)

func _dial(host: String, dial_port: int) -> void:
	_attempt_started = Time.get_ticks_msec()
	var started = client.connect_server(host, dial_port, _ca_path, false, HostInvite.CERT_HOSTNAME)
	if started != OK:
		_next_address()

func _process(_delta: float) -> void:
	if not _active or _joining or client.authenticated:
		return
	var limit = RELAY_WAIT_MS if _waiting_relay else ATTEMPT_MS
	if Time.get_ticks_msec() - _attempt_started > limit:
		_next_address()

func _session_ready(_welcome: Dictionary) -> void:
	if not _active or _joining:
		return
	_joining = true
	client.auto_reconnect = true
	status.emit("Connected securely. Joining the game…")
	client.join_match(str(invite.matchId))

func _frame(frame: Dictionary) -> void:
	if _active and _joining and str(frame.get("state", {}).get("matchId", "")) == str(invite.matchId):
		_active = false
		joined.emit(invite)

func _protocol_error(error: Dictionary) -> void:
	if not _active or not _joining:
		return
	if str(error.get("code", "")) in ["FORBIDDEN", "UNAUTHENTICATED"]:
		_active = false
		client.disconnect_server(true)
		failed.emit("INVITE_USED", "The host's game is no longer available: it is full, already finished, or the invite is from an older game. Ask your friend for a new invite.")
