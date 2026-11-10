class_name DedicatedAccountBackend
extends Node
## Trusted HTTP bridge plus durable terminal-result outbox. No account token enters this node.
const StrictJSON = preload("res://network/strict_json.gd")
var base_url = ""
var server_id = ""
var _secret = ""
var directory = ""
var configured = false
var healthy = true
var jobs: Dictionary = {}
var _active_requests = 0
var _retry_at = 0
var _delay = 1000

func configure(url: String, identity: String, secret: String, outbox_directory: String, allow_loopback_http: bool = false) -> Error:
	if secret.length() < 32 or identity.is_empty() or identity.length() > 96:
		return ERR_INVALID_PARAMETER
	if not safe_url(url, allow_loopback_http):
		return ERR_INVALID_PARAMETER
	base_url = url.trim_suffix("/")
	server_id = identity
	_secret = secret
	directory = outbox_directory
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return ERR_CANT_CREATE
	var files = DirAccess.get_files_at(directory)
	if files.size() > 512:
		return ERR_OUT_OF_MEMORY
	for filename in files:
		if not filename.ends_with(".json"):
			continue
		var file = FileAccess.open(directory.path_join(filename), FileAccess.READ)
		if file == null or file.get_length() > 1048576:
			return ERR_FILE_CORRUPT
		var value = JSON.parse_string(file.get_as_text())
		if not value is Dictionary or not value.has("report") or not value.has("active") or not value.report is Dictionary or not value.report.get("matchId") is String or filename != value.report.matchId.sha256_text() + ".json":
			return ERR_FILE_CORRUPT
		if value.active:
			value.active = false
			value.report.result = "aborted"
			value.report.reason = "Dedicated server restarted before completion"
			if not _write(value.report.matchId, value):
				return ERR_CANT_CREATE
		jobs[value.report.matchId] = value
	configured = true
	return OK

static func safe_url(url: String, allow_loopback_http: bool) -> bool:
	if url.contains("@") or url.contains("#") or url.contains("?") or url.contains("\\"):
		return false
	if url.begins_with("https://"):
		return url.length() > 8
	if not allow_loopback_http:
		return false
	for host in ["127.0.0.1", "localhost", "[::1]"]:
		if url == "http://" + host or url.begins_with("http://" + host + ":"):
			return true
	return false

func request(path: String, payload: Dictionary) -> Dictionary:
	if not configured or _active_requests >= 32:
		return {"ok": false, "status": 503, "data": {}}
	_active_requests += 1
	var http = HTTPRequest.new()
	http.timeout = 5
	http.body_size_limit = 1048576
	http.max_redirects = 0 # Never forward a server credential through a redirect.
	add_child(http)
	var headers = PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + _secret, "X-Server-Id: " + server_id])
	var status = http.request(base_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(payload, "", true, true))
	if status != OK:
		_active_requests -= 1
		http.queue_free()
		return {"ok": false, "status": 503, "data": {}}
	var response: Array = await http.request_completed
	_active_requests -= 1
	http.queue_free()
	var parsed = StrictJSON.new().decode(response[3], 1048576)
	var data: Dictionary = parsed.value if parsed.ok and parsed.value is Dictionary else {}
	return {"ok": response[0] == HTTPRequest.RESULT_SUCCESS and response[1] >= 200 and response[1] < 300 and data.get("schemaVersion") == 1, "status": response[1], "data": data}

func provision(allocation: Dictionary) -> bool:
	var id: String = allocation.matchId
	if jobs.has(id):
		return jobs[id].active
	if jobs.size() >= 128 or not healthy:
		return false
	var value = {"active": true, "report": {"matchId": id, "result": "aborted", "reason": "Match provisioned", "finalFen": "", "history": []}}
	if not _write(id, value):
		healthy = false
		return false
	jobs[id] = value
	return true

func complete(id: String, result: String, reason: String, fen: String, history: Array) -> void:
	if not jobs.has(id) or not jobs[id].active:
		return
	var report = {"matchId": id, "result": result, "reason": reason.substr(0, 96), "finalFen": fen, "history": history.duplicate(true)}
	jobs[id] = {"active": false, "report": report}
	if not _write(id, jobs[id]):
		healthy = false
		push_error("Unable to persist a match result; new account matches disabled until the outbox recovers.")

func _write(id: String, value: Dictionary) -> bool:
	var filename = directory.path_join(id.sha256_text() + ".json")
	var temporary = filename + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "", true, true))
	file.flush()
	var error = file.get_error()
	file.close()
	return error == OK and DirAccess.rename_absolute(temporary, filename) == OK

func _process(_delta: float) -> void:
	if not configured or _active_requests > 0 or Time.get_ticks_msec() < _retry_at:
		return
	_retry_at = Time.get_ticks_msec() + _delay
	for id in jobs.keys():
		if not jobs[id].active:
			_deliver(id)
			break

func _deliver(id: String) -> void:
	# Persist first, including retry after a temporary disk error.
	if not _write(id, jobs[id]):
		healthy = false
		return
	var response = await request("/internal/results", jobs[id].report)
	if response.ok:
		if DirAccess.remove_absolute(directory.path_join(id.sha256_text() + ".json")) != OK:
			healthy = false
			return
		jobs.erase(id)
		healthy = true
		_delay = 1000
		print("MATCH_PERSISTED match=", id)
	else:
		_delay = mini(30000, _delay * 2)
		if response.status in [400, 401, 403, 409]:
			healthy = false
			printerr("Backend rejected a durable match report; inspect backend credentials/records. status=", response.status)
