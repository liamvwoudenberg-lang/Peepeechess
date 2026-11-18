class_name RelayBridge
extends Node
## Carries the game's UDP datagrams through a relay's WebSocket. ENet + DTLS keep running END-TO-END between host and guest: this node only
## moves opaque datagrams, so the relay sees ciphertext and neither player learns the other's IP address.
##   host:  WebSocket /h/<session>  <->  a loopback UDP socket that talks to this PC's own game server (127.0.0.1:server_port)
##   guest: WebSocket /g/<session>  <->  a loopback UDP socket (local_port) that the guest's ENet client dials as if it were the server
## Reconnects on its own after a dropped WebSocket; drops datagrams (it is UDP) instead of queueing when the relay link is congested.
signal state_changed(state: String)   # connecting | ready | peer | peer_left | closed | failed
const MAX_DATAGRAM = 2000
const MAX_BUFFERED = 262144
const RETRY_MS = 2000
const MAX_FAILURES = 6
var role = "host"
var server_port = 0     # host: the local game server's UDP port
var local_port = 0      # guest: where the ENet client must connect (127.0.0.1)
var state = "idle"
var peer_present = false
var packets_up = 0
var packets_down = 0
var packets_dropped = 0
var _url = ""
var _ws: WebSocketPeer
var _udp: PacketPeerUDP
var _peer_ip = ""
var _peer_port = 0
var _failures = 0
var _retry_at = 0
var _running = false

func start_host(relay_url: String, session_id: String, game_port: int) -> Error:
	role = "host"
	server_port = game_port
	return _start(relay_url.trim_suffix("/") + "/h/" + session_id)

func start_guest(relay_url: String, session_id: String) -> Error:
	role = "guest"
	return _start(relay_url.trim_suffix("/") + "/g/" + session_id)

func _start(url: String) -> Error:
	stop()
	_url = url
	_failures = 0
	var made = _open_udp()
	if made != OK:
		_set_state("failed")
		return made
	_running = true
	_connect()
	return OK

func stop() -> void:
	_running = false
	if _ws != null:
		_ws.close()
		_ws = null
	if _udp != null:
		_udp.close()
		_udp = null
	peer_present = false
	if state != "idle" and state != "closed":
		_set_state("closed")

func _open_udp() -> Error:
	if _udp != null:
		_udp.close()
	_udp = PacketPeerUDP.new()
	var bound = _udp.bind(0, "127.0.0.1")   # never reachable from outside this PC
	if bound != OK:
		return bound
	if role == "host":
		_udp.set_dest_address("127.0.0.1", server_port)
	else:
		local_port = _udp.get_local_port()
		_peer_ip = ""
		_peer_port = 0
	return OK

func _connect() -> void:
	_ws = WebSocketPeer.new()
	_ws.outbound_buffer_size = MAX_BUFFERED
	_ws.inbound_buffer_size = MAX_BUFFERED
	_ws.max_queued_packets = 4096
	if "heartbeat_interval" in _ws:
		_ws.heartbeat_interval = 15.0
	_set_state("connecting")
	var opened = _ws.connect_to_url(_url)
	if opened != OK:
		_fail_once()

func _fail_once() -> void:
	_ws = null
	_failures += 1
	peer_present = false
	if _failures >= MAX_FAILURES:
		_running = false
		_set_state("failed")
		return
	_retry_at = Time.get_ticks_msec() + RETRY_MS
	_set_state("connecting")

func _process(_delta: float) -> void:
	if not _running:
		return
	if _ws == null:
		if Time.get_ticks_msec() >= _retry_at:
			_connect()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while _ws.get_available_packet_count() > 0:
				var packet = _ws.get_packet()
				if _ws.was_string_packet():
					_control(packet.get_string_from_utf8())
				else:
					_down(packet)
			_up()
		WebSocketPeer.STATE_CLOSED:
			var was_open = state == "ready" or state == "peer" or state == "peer_left"
			if was_open:
				_failures = 0   # a working link that dropped: try again from scratch
			_fail_once()

func _control(text: String) -> void:
	var message = JSON.parse_string(text)
	if not message is Dictionary:
		return
	match str(message.get("t", "")):
		"ready":
			_failures = 0
			_set_state("ready")
		"guest":
			if bool(message.get("on", false)):
				if role == "host":
					_open_udp()   # a new guest is a new ENet peer: a fresh source port, no stale connection state
				peer_present = true
				_set_state("peer")
			else:
				peer_present = false
				_set_state("peer_left")
		"host":
			if bool(message.get("on", false)):
				peer_present = true
				_set_state("peer")
			else:
				peer_present = false
				_set_state("peer_left")

## relay -> local UDP
func _down(packet: PackedByteArray) -> void:
	if _udp == null or packet.size() == 0 or packet.size() > MAX_DATAGRAM:
		return
	if role == "guest":
		if _peer_port <= 0:
			packets_dropped += 1   # the ENet client has not sent anything yet: nobody to deliver to
			return
		_udp.set_dest_address(_peer_ip, _peer_port)
	_udp.put_packet(packet)
	packets_down += 1

## local UDP -> relay
func _up() -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var packet = _udp.get_packet()
		if role == "guest":
			_peer_ip = _udp.get_packet_ip()
			_peer_port = _udp.get_packet_port()
		if packet.size() > MAX_DATAGRAM or _ws.get_current_outbound_buffered_amount() > MAX_BUFFERED / 2:
			packets_dropped += 1
			continue
		_ws.send(packet, WebSocketPeer.WRITE_MODE_BINARY)
		packets_up += 1

func _set_state(value: String) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(value)

func _exit_tree() -> void:
	stop()
