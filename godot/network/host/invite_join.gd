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

## Validates the invite text and starts connecting. Returns {ok} or {ok: false, code, message} (nothing was started then).
func begin(chess_client: OnlineChessClient, invite_text: String, tuning: String) -> Dictionary:
	client = chess_client
	own_tuning = tuning
	var parsed = HostInvite.decode(invite_text)
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
	_active = true
	_joining = false
	_index = -1
	_next_address()
	return {"ok": true}

func cancel() -> void:
	_active = false
	if client != null:
		client.disconnect_server(true)

func _next_address() -> void:
	_index += 1
	if _index >= invite.hosts.size():
		_active = false
		client.disconnect_server(true)
		failed.emit("UNREACHABLE", "Could not reach the host. Check that your friend is still hosting, that the invite is complete, and that their router forwards UDP port %d (see the hosting guide)." % int(invite.port))
		return
	var host: String = invite.hosts[_index]
	status.emit("Connecting to %s (%d of %d)…" % [host, _index + 1, invite.hosts.size()])
	client.disconnect_server(true)
	_attempt_started = Time.get_ticks_msec()
	client.auto_reconnect = false
	var started = client.connect_server(host, int(invite.port), _ca_path, false, HostInvite.CERT_HOSTNAME)
	if started != OK:
		_next_address()

func _process(_delta: float) -> void:
	if _active and not _joining and not client.authenticated and Time.get_ticks_msec() - _attempt_started > ATTEMPT_MS:
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
