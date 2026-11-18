class_name HostedGame
extends Node
## "Host a game on my PC": runs the authoritative DedicatedChessServer inside this process (listen-server), protected by a per-session
## self-signed DTLS certificate, opens the UDP port with UPnP when the router allows it, finds the public address, and builds the invite.
## The host's own client connects to this server over loopback exactly like a friend does, so there is one game path for both.
## Nothing here touches the wire protocol; the join token is the unguessable match id created by the server (see invite_code.gd).
signal changed(state: Dictionary)
const Server = preload("res://network/server/dedicated_server.gd")
const DEFAULT_PORT = 2456
const PORT_TRIES = 16
var server: DedicatedChessServer
var certificate: HostCertificate
var mapper: PortMapper
var ip_lookup: PublicIpLookup
var port = 0
var host_token = ""   # resume token of the host seat: used only by the host's own client, never put in an invite
var mode = "classic"
var match_id = ""
var version_text = ""
var state: Dictionary = {"phase": "idle", "port": 0, "router": {}, "public_ip": "", "lan": [], "invite": "", "reach": {}, "fingerprint": ""}
const DEFAULT_INVITE_TTL_MS = 900000   # 15 minutes to use the invite; after the guest joined nobody else can
var seal_invite = true
var passphrase = ""
var manual_address = ""
var invite_ttl_ms = DEFAULT_INVITE_TTL_MS
var _router_done = false
var _ip_done = false
var _stopped = false
## Relay mode (network/relay/, docs/deployment/RELAY.md): "relay" = only through the relay (no port forwarding, the game port is not exposed at
## all and the invite carries no IP address), "direct" = UDP port + UPnP as before, "both" = the relay first, direct addresses as a fallback.
var connection = "direct"
var relay_url = ""
var relay_session = ""
var relay_bridge: RelayBridge
var _relay_ready = false
var _relay_failed = false

## options: mode "classic"|"battle", color "w"|"b", port (0 = first free from 2456), mapper (PortMapper or null for UPnP),
## lookup_ip (bool, default true), version (string shown to the friend).
func begin(options: Dictionary) -> Error:
	mode = str(options.get("mode", "classic"))
	seal_invite = bool(options.get("seal", true))
	passphrase = HostInvite.generate_passphrase()
	invite_ttl_ms = int(options.get("invite_ttl_ms", DEFAULT_INVITE_TTL_MS))
	version_text = str(options.get("version", ProjectSettings.get_setting("application/config/version", "")))
	_set_phase("certificate")
	certificate = HostCertificate.new()
	var made = certificate.generate()
	if made != OK:
		_set_phase("failed", {"error": "Could not create the secure session certificate (%s)." % error_string(made)})
		return made
	server = Server.new()
	add_child(server)
	server.configure_hosting(str(options.get("color", "w")), invite_ttl_ms)
	host_token = server.create_host_session()
	connection = str(options.get("connection", "direct"))
	relay_url = str(options.get("relay_url", ""))
	if connection != "direct" and relay_url.is_empty():
		connection = "direct"   # no relay configured: direct mode only
	var wanted = int(options.get("port", 0))
	var started = ERR_CANT_CREATE
	var tries = [wanted] if wanted > 0 else range(DEFAULT_PORT, DEFAULT_PORT + PORT_TRIES)
	for candidate in tries:
		# relay only: the game port listens on this PC's loopback and is never exposed to any network
		started = server.start("127.0.0.1" if connection == "relay" else "0.0.0.0", int(candidate), certificate.certificate_path, certificate.key_path, false)
		if started == OK:
			port = int(candidate)
			break
	if started != OK:
		_set_phase("failed", {"error": "Could not open a game port (%s). Is another copy of the game already hosting?" % error_string(started)})
		certificate.remove()
		return started
	state.port = port
	state.fingerprint = certificate.fingerprint
	state.lan = PublicIpLookup.local_addresses()
	_set_phase("opening")
	mapper = options.get("mapper", null)
	if mapper == null:
		mapper = UpnpPortMapper.new()
	add_child(mapper)
	mapper.finished.connect(_router_finished)
	if connection == "relay":
		_router_done = true   # no router mapping is needed (or wanted) through the relay
		state.router = {"ok": false, "skipped": true}
	else:
		mapper.start(port)
	if connection != "direct":
		relay_session = Crypto.new().generate_random_bytes(16).hex_encode()
		relay_bridge = RelayBridge.new()
		add_child(relay_bridge)
		relay_bridge.state_changed.connect(_relay_state)
		if relay_bridge.start_host(relay_url, relay_session, port) != OK:
			_relay_failed = true
	# PRIVACY: no website is asked for the public address unless the host consents (detect_public_ip(), a button in the host panel).
	ip_lookup = PublicIpLookup.new()
	add_child(ip_lookup)
	ip_lookup.finished.connect(_ip_finished)
	_ip_done = true
	if bool(options.get("lookup_ip", false)) and connection != "relay":
		detect_public_ip()
	return OK

func _relay_state(value: String) -> void:
	if value in ["ready", "peer", "peer_left"]:
		_relay_ready = true
		_relay_failed = false
	elif value == "failed":
		_relay_ready = false
		_relay_failed = true
		if connection == "relay":
			_set_phase("failed", {"error": "Could not reach the relay. Check your internet connection and the relay address in Settings, or choose Direct."})
			return
	_rebuild()

## The host agreed to ask a plain-text HTTPS endpoint for the public address (a third party then sees the host's address).
func detect_public_ip() -> void:
	if ip_lookup == null or _stopped:
		return
	ip_lookup.consented = true
	_ip_done = false
	ip_lookup.lookup()
	_rebuild()

## The host typed the address (or a name) friends should use: nothing is sent anywhere.
func set_manual_address(text: String) -> bool:
	var clean = text.strip_edges()
	var regex = RegEx.new()
	regex.compile(HostInvite.HOST_PATTERN)
	if not clean.is_empty() and regex.search(clean) == null:
		return false
	manual_address = clean
	_rebuild()
	return true

## The host's client created the match: from now on the invite can be built.
func set_match(id: String) -> void:
	match_id = id
	_rebuild()

func _router_finished(result: Dictionary) -> void:
	_router_done = true
	state.router = result
	_rebuild()   # no website is asked automatically: the host may press "Detect my address" (consent) or type it

func _ip_finished(address: String) -> void:
	_ip_done = true
	state.public_ip = address
	_rebuild()

func _public_address() -> String:
	var router: Dictionary = state.router
	if router.get("ok", false) and not router.get("private_external", false) and not str(router.get("external_ip", "")).is_empty():
		return str(router.external_ip)
	return str(state.public_ip)

func _rebuild() -> void:
	if _stopped or certificate == null:
		return
	var public = _public_address()
	var hosts: Array = []
	if connection != "relay":
		if not manual_address.is_empty():
			hosts.append(manual_address)
		if not public.is_empty() and public not in hosts:
			hosts.append(public)
		for lan in state.lan:
			hosts.append(lan)
		if hosts.is_empty():
			hosts.append("127.0.0.1")
	state.connection = connection
	state.relay_ready = _relay_ready
	state.reach = reachability(state.router, public if not manual_address.is_empty() else str(state.public_ip), port, _router_done and _ip_done)
	var relay_wait = connection != "direct" and not _relay_ready and not _relay_failed
	if connection == "relay":
		state.reach = {"level": "good", "text": "Relay connection: works through any home router, no port forwarding. Your address is not in the invite." if _relay_ready else "Connecting to the relay…"}
	elif connection == "both" and _relay_ready:
		state.reach = {"level": "good", "text": "Relay connection is ready (works through any home router). Direct addresses stay in the invite as a fallback. " + str(state.reach.get("text", ""))}
	state.invite = ""
	if not match_id.is_empty() and _router_done and _ip_done and not relay_wait:
		var fields = {"hosts": hosts, "port": port, "matchId": match_id, "certificate": certificate.certificate_pem,
			"tuning": Server.Room.Balance.stamp(), "mode": mode, "version": version_text}
		if _relay_ready:
			fields["relay"] = relay_url
			fields["session"] = relay_session
		var code = HostInvite.encode(fields)
		state.invite = HostInvite.seal(code, passphrase) if seal_invite else code
	state.passphrase = passphrase if seal_invite else ""
	state.has_internet_address = not public.is_empty() or not manual_address.is_empty() or _relay_ready
	_set_phase("ready" if not state.invite.is_empty() else "opening")

## What to tell the host about reachability. level: checking | good | maybe | manual | blocked.
static func reachability(router: Dictionary, public_ip: String, port_number: int, settled: bool) -> Dictionary:
	if not settled:
		return {"level": "checking", "text": "Checking your router and address…"}
	if router.get("ok", false):
		if router.get("private_external", false):
			return {"level": "blocked", "text": "Your router's outside address is not a public internet address, so your provider shares one address between several homes (CGNAT). Friends on other networks cannot reach you directly. Ask the provider for a public IPv4 address, or play on the same network."}
		if not public_ip.is_empty() and public_ip != str(router.get("external_ip", "")):
			return {"level": "maybe", "text": "Your router opened port %d, but the internet sees you under a different address than your router reports. There may be a second router in front of yours; friends may not be able to join." % port_number}
		return {"level": "good", "text": "Your router opened UDP port %d. Friends on the internet should be able to join. Send them the invite." % port_number}
	var base = "The router did not open the port automatically. Open UDP port %d on your router and forward it to this PC (see the hosting guide), then share the invite." % port_number
	if public_ip.is_empty():
		return {"level": "manual", "text": base + " Your public address is not in the invite yet: type it in (your router's status page shows it) or press \"Detect my address\" (that asks a website, which then sees your address)."}
	return {"level": "manual", "text": base}

## Stops hosting: closes the server, removes the router mapping and deletes the session key.
func stop() -> void:
	if _stopped:
		return
	_stopped = true
	if relay_bridge != null:
		relay_bridge.stop()
	if mapper != null:
		mapper.stop()
	if server != null:
		server.shutdown()
	if certificate != null:
		certificate.remove()
	state.phase = "stopped"
	changed.emit(state)

func _set_phase(phase: String, extra: Dictionary = {}) -> void:
	state.phase = phase
	for key in extra:
		state[key] = extra[key]
	changed.emit(state)

func _exit_tree() -> void:
	stop()
