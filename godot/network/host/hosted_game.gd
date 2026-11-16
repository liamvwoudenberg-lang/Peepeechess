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
var _router_done = false
var _ip_done = false
var _stopped = false

## options: mode "classic"|"battle", color "w"|"b", port (0 = first free from 2456), mapper (PortMapper or null for UPnP),
## lookup_ip (bool, default true), version (string shown to the friend).
func begin(options: Dictionary) -> Error:
	mode = str(options.get("mode", "classic"))
	version_text = str(options.get("version", ProjectSettings.get_setting("application/config/version", "")))
	_set_phase("certificate")
	certificate = HostCertificate.new()
	var made = certificate.generate()
	if made != OK:
		_set_phase("failed", {"error": "Could not create the secure session certificate (%s)." % error_string(made)})
		return made
	server = Server.new()
	add_child(server)
	server.configure_hosting(str(options.get("color", "w")))
	host_token = server.create_host_session()
	var wanted = int(options.get("port", 0))
	var started = ERR_CANT_CREATE
	var tries = [wanted] if wanted > 0 else range(DEFAULT_PORT, DEFAULT_PORT + PORT_TRIES)
	for candidate in tries:
		started = server.start("0.0.0.0", int(candidate), certificate.certificate_path, certificate.key_path, false)
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
	mapper.start(port)
	if bool(options.get("lookup_ip", true)):
		ip_lookup = PublicIpLookup.new()
		add_child(ip_lookup)
		ip_lookup.finished.connect(_ip_finished)
	else:
		_ip_done = true
	return OK

## The host's client created the match: from now on the invite can be built.
func set_match(id: String) -> void:
	match_id = id
	_rebuild()

func _router_finished(result: Dictionary) -> void:
	_router_done = true
	state.router = result
	if ip_lookup != null and not result.get("ok", false):
		ip_lookup.lookup()          # no router help: ask an HTTPS endpoint
	elif ip_lookup != null and str(result.get("external_ip", "")).is_empty():
		ip_lookup.lookup()
	else:
		_ip_done = true
	_rebuild()

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
	if not public.is_empty():
		hosts.append(public)
	for lan in state.lan:
		hosts.append(lan)
	if hosts.is_empty():
		hosts.append("127.0.0.1")
	state.reach = reachability(state.router, state.public_ip, port, _router_done and _ip_done)
	state.invite = ""
	if not match_id.is_empty() and _router_done and _ip_done:
		state.invite = HostInvite.encode({"hosts": hosts, "port": port, "matchId": match_id, "certificate": certificate.certificate_pem,
			"tuning": Server.Room.Balance.stamp(), "mode": mode, "version": version_text})
	_set_phase("ready" if not state.invite.is_empty() else "opening")

## What to tell the host about reachability. level: checking | good | maybe | manual | blocked.
static func reachability(router: Dictionary, public_ip: String, port_number: int, settled: bool) -> Dictionary:
	if not settled:
		return {"level": "checking", "text": "Checking your router and address…"}
	if router.get("ok", false):
		if router.get("private_external", false):
			return {"level": "blocked", "text": "Your router's outside address (%s) is not a public internet address, so your provider shares one address between several homes (CGNAT). Friends on other networks cannot reach you directly. Ask the provider for a public IPv4 address, or play on the same network." % str(router.get("external_ip", ""))}
		if not public_ip.is_empty() and public_ip != str(router.get("external_ip", "")):
			return {"level": "maybe", "text": "Your router opened port %d, but the internet sees you as %s, not %s. There may be a second router in front of yours; friends may not be able to join." % [port_number, public_ip, str(router.get("external_ip", ""))]}
		return {"level": "good", "text": "Your router opened UDP port %d. Friends on the internet should be able to join. Send them the invite." % port_number}
	var base = "The router did not open the port automatically. Open UDP port %d on your router and forward it to this PC (see the hosting guide), then share the invite." % port_number
	if public_ip.is_empty():
		return {"level": "manual", "text": base + " Your public address could not be detected: look it up on your router's status page and tell your friend."}
	return {"level": "manual", "text": base}

## Stops hosting: closes the server, removes the router mapping and deletes the session key.
func stop() -> void:
	if _stopped:
		return
	_stopped = true
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
