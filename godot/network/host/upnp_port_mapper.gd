class_name UpnpPortMapper
extends PortMapper
## UPnP port mapping through Godot's UPNP class. Discovery and the router calls block, so they run on a thread and the result arrives as a signal.
## The mapping gets a lease (so a crash cannot leave it open forever) and is deleted again on stop() / when the node leaves the tree.
const DISCOVER_MS = 2500
const LEASE_SECONDS = 14400
var _thread: Thread
var _upnp: UPNP
var _done = false
var _pending: Dictionary = {}

func start(port: int) -> void:
	mapped_port = 0
	_done = false
	_thread = Thread.new()
	_thread.start(_work.bind(port))
	set_process(true)

func _ready() -> void:
	set_process(false)

func _work(port: int) -> void:
	var upnp = UPNP.new()
	var found = upnp.discover(DISCOVER_MS, 2, "InternetGatewayDevice")
	if found != UPNP.UPNP_RESULT_SUCCESS or upnp.get_gateway() == null or not upnp.get_gateway().is_valid_gateway():
		_pending = {"ok": false, "external_ip": "", "message": "No UPnP router answered (UPnP may be off in the router, or a firewall blocks it).", "private_external": false}
		_done = true
		return
	var mapping = upnp.add_port_mapping(port, port, "Peepeechess", "UDP", LEASE_SECONDS)
	var external = upnp.query_external_address()
	if mapping != UPNP.UPNP_RESULT_SUCCESS:
		_pending = {"ok": false, "external_ip": external, "message": "The router refused to open the port (UPnP error %d)." % mapping, "private_external": is_private_address(external)}
		_done = true
		return
	_upnp = upnp
	mapped_port = port
	_pending = {"ok": true, "external_ip": external, "message": "Port %d (UDP) opened on your router." % port, "private_external": is_private_address(external)}
	_done = true

func _process(_delta: float) -> void:
	if _done and _thread != null:
		set_process(false)
		_thread.wait_to_finish()
		_thread = null
		_finish(_pending)

func stop() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	if _upnp != null and mapped_port > 0:
		_upnp.delete_port_mapping(mapped_port, "UDP")
	_upnp = null
	mapped_port = 0

func _exit_tree() -> void:
	stop()
