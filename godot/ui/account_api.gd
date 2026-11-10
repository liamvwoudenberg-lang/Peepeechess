extends Node
## HTTPS account/matchmaking adapter. Never sends combat results or ratings.
const Settings = preload("res://ui/application_settings.gd")
var base_url = ""
var active_requests = 0

static func permitted_url(value: String) -> bool:
	var re = RegEx.new()
	re.compile("^https://[A-Za-z0-9][A-Za-z0-9.:-]*(/[^?#]*)?$")
	if re.search(value) != null:
		return true
	re.compile("^http://(127\\.0\\.0\\.1|localhost|\\[::1\\])(:[0-9]{1,5})?(/[^?#]*)?$")
	return re.search(value) != null

func call_api(method: int, path: String, body: Dictionary = {}, authenticate: bool = true) -> Dictionary:
	var url = base_url if not base_url.is_empty() else Settings.api_url
	url = url.trim_suffix("/")
	if not permitted_url(url):
		return {"ok": false, "message": "Use HTTPS for your account service. HTTP is allowed only on this device's loopback address."}
	if authenticate and Settings.token.is_empty():
		return {"ok": false, "message": "Sign in to use online play."}
	if active_requests >= 4:
		return {"ok": false, "message": "Please wait for the current request."}
	var request = HTTPRequest.new()
	request.timeout = 12.0
	request.body_size_limit = 1048576
	request.max_redirects = 0
	add_child(request)
	active_requests += 1
	var headers = PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if authenticate:
		headers.append("Authorization: Bearer " + Settings.token)
	var encoded = "" if method in [HTTPClient.METHOD_GET, HTTPClient.METHOD_DELETE] else JSON.stringify(body)
	var error = request.request(url + path, headers, method, encoded)
	if error != OK:
		active_requests -= 1
		request.queue_free()
		return {"ok": false, "message": "The account service could not be contacted."}
	var response: Array = await request.request_completed
	active_requests -= 1
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "message": "The account service is unavailable, or its secure certificate could not be verified."}
	var data = JSON.parse_string(response[3].get_string_from_utf8())
	if not data is Dictionary or data.get("schemaVersion") != 1:
		return {"ok": false, "message": "The account service returned an incompatible response."}
	if response[1] < 200 or response[1] >= 300:
		if response[1] == 401 and authenticate:
			Settings.sign_out()
		return {"ok": false, "message": str(data.get("error", {}).get("message", "Request could not be completed.")).left(200)}
	return {"ok": true, "data": data}

func authenticate(username: String, password: String, display_name: String = "", register: bool = false) -> Dictionary:
	var body = {"username": username, "password": password}
	if register:
		body.displayName = display_name
	var response = await call_api(HTTPClient.METHOD_POST, "/v1/auth/register" if register else "/v1/auth/login", body, false)
	if response.ok:
		if not response.data.get("token") is String or not response.data.get("profile") is Dictionary:
			return {"ok": false, "message": "The account response is incomplete."}
		Settings.token = response.data.token
		Settings.account = response.data.profile.duplicate(true)
	return response
