class_name PublicIpLookup
extends Node
## Finds the host's public IPv4 address. Order: (1) the router's own answer (UPnP, no third party), (2) a plain-text HTTPS endpoint.
## The endpoints are configurable (environment PEEPEECHESS_IP_LOOKUP_URLS, comma separated) and the lookup can be switched off with PEEPEECHESS_IP_LOOKUP=off;
## it only ever sends an ordinary HTTPS GET without any game data. On failure `finished` reports an empty address and the UI shows manual steps.
signal finished(address: String)
const DEFAULT_URLS = ["https://api.ipify.org", "https://ifconfig.me/ip"]
var urls: Array = []
var timeout_seconds = 4.0
var _queue: Array = []
var _request: HTTPRequest

func lookup() -> void:
	urls = _configured_urls()
	_queue = urls.duplicate()
	if _queue.is_empty():
		finished.emit.call_deferred("")
		return
	_next()

static func _configured_urls() -> Array:
	if OS.get_environment("PEEPEECHESS_IP_LOOKUP") == "off":
		return []
	var custom = OS.get_environment("PEEPEECHESS_IP_LOOKUP_URLS")
	if custom.is_empty():
		return DEFAULT_URLS.duplicate()
	var list: Array = []
	for part in custom.split(","):
		var url = part.strip_edges()
		if url.begins_with("https://"):
			list.append(url)
	return list

func _next() -> void:
	if _queue.is_empty():
		finished.emit("")
		return
	var url: String = _queue.pop_front()
	if _request != null:
		_request.queue_free()
	_request = HTTPRequest.new()
	_request.timeout = timeout_seconds
	_request.body_size_limit = 256
	add_child(_request)
	_request.request_completed.connect(_done)
	if _request.request(url) != OK:
		_next()

func _done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text = body.get_string_from_utf8().strip_edges()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and valid_ipv4(text):
		finished.emit(text)
		return
	_next()

static func valid_ipv4(text: String) -> bool:
	var parts = text.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 255 or part.length() > 3:
			return false
	return true

## Private IPv4 addresses of this machine (for friends on the same network).
static func local_addresses() -> Array:
	var list: Array = []
	for address in IP.get_local_addresses():
		if valid_ipv4(address) and not address.begins_with("127.") and not address.begins_with("169.254.") and PortMapper.is_private_address(address):
			list.append(address)
	return list
