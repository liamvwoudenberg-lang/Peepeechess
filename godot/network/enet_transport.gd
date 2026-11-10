class_name ChessEnetTransport
extends Node
## Raw ENet/DTLS packets only. No SceneMultiplayer RPC or Variant object decoder.
signal connected(peer_id: int)
signal disconnected(peer_id: int)
signal packet_received(peer_id: int, bytes: PackedByteArray, channel: int, flags: int)
signal transport_error(message: String)
var host: ENetConnection
var peers: Dictionary = {}
var server_peer = 0
var listening = false

func listen(address: String, port: int, certificate: String, private_key: String, insecure_local: bool = false, maximum_peers: int = 64) -> Error:
	close()
	if insecure_local and address not in ["127.0.0.1", "::1"]:
		return ERR_UNAUTHORIZED
	host = ENetConnection.new()
	var result = host.create_host_bound(address, port, maximum_peers, 2)
	if result != OK:
		close()
		return result
	if not insecure_local:
		var cert = X509Certificate.new()
		var key = CryptoKey.new()
		if certificate.is_empty() or private_key.is_empty() or cert.load(certificate) != OK or key.load(private_key) != OK:
			close()
			return ERR_INVALID_DATA
		result = host.dtls_server_setup(TLSOptions.server(key, cert))
		if result != OK:
			close()
			return result
	listening = true
	return OK

func connect_to(address: String, port: int, ca_path: String = "", insecure_local: bool = false) -> Error:
	close()
	if insecure_local and address not in ["127.0.0.1", "::1", "localhost"]:
		return ERR_UNAUTHORIZED
	host = ENetConnection.new()
	var result = host.create_host(1, 2)
	if result != OK:
		close()
		return result
	if not insecure_local:
		var ca: X509Certificate = null
		if not ca_path.is_empty():
			ca = X509Certificate.new()
			if ca.load(ca_path) != OK:
				close()
				return ERR_INVALID_DATA
		result = host.dtls_client_setup(address, TLSOptions.client(ca))
		if result != OK:
			close()
			return result
	var peer = host.connect_to_host(address, port, 2)
	if peer == null:
		close()
		return ERR_CANT_CONNECT
	server_peer = peer.get_instance_id()
	peers[server_peer] = peer
	return OK

func poll() -> void:
	if host == null:
		return
	for _index in range(256):
		var event = host.service(0)
		if event[0] == ENetConnection.EVENT_NONE:
			break
		if event[0] == ENetConnection.EVENT_ERROR:
			transport_error.emit("ENet connection failed.")
			close()
			return
		var peer: ENetPacketPeer = event[1]
		var id = peer.get_instance_id()
		match event[0]:
			ENetConnection.EVENT_CONNECT:
				peers[id] = peer
				peer.set_timeout(8, 1500, 3000)
				peer.ping_interval(500)
				connected.emit(id)
			ENetConnection.EVENT_DISCONNECT:
				peers.erase(id)
				disconnected.emit(id)
			ENetConnection.EVENT_RECEIVE:
				var flags = peer.get_packet_flags()
				var packet = peer.get_packet()
				packet_received.emit(id, packet, int(event[3]), flags)
		if host == null:
			return
	host.flush()

func send(peer_id: int, bytes: PackedByteArray, reliable: bool = true) -> Error:
	if not peers.has(peer_id) or bytes.is_empty() or peers[peer_id].get_state() != ENetPacketPeer.STATE_CONNECTED:
		return ERR_UNAVAILABLE
	return peers[peer_id].send(0 if reliable else 1, bytes, ENetPacketPeer.FLAG_RELIABLE if reliable else ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT)

func drop(peer_id: int) -> void:
	if peers.has(peer_id):
		# A failed DTLS peer cannot carry an ENet disconnect datagram. Reset its
		# queues locally; the remote heartbeat/timeout performs its own recovery.
		peers[peer_id].reset()
		peers.erase(peer_id)
		disconnected.emit(peer_id)

func disconnect_gracefully(peer_id: int) -> void:
	if peers.has(peer_id):
		peers[peer_id].peer_disconnect_later()
		if host != null:
			host.flush()

func close() -> void:
	peers.clear()
	server_peer = 0
	listening = false
	if host != null:
		host.destroy()
		host = null

func _exit_tree() -> void:
	close()
