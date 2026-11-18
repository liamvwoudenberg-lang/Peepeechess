class_name RelaySettings
extends RefCounted
## Where the relay lives. Order: environment PEEPEECHESS_RELAY_URL, then the player's saved choice (Settings > Online), then the build's
## project setting "peepeechess/network/relay_url" (bake a default into an export). Empty = no relay: direct mode only.
const ENV = "PEEPEECHESS_RELAY_URL"
const PROJECT_SETTING = "peepeechess/network/relay_url"
const CONFIG_FILE = "user://preferences.cfg"
const URL_PATTERN = "^wss?://[A-Za-z0-9.\\-]{1,200}(:[0-9]{1,5})?(/[A-Za-z0-9._~\\-/]{0,100})?$"

static var _saved = ""
static var _loaded = false

static func url() -> String:
	var from_env = OS.get_environment(ENV).strip_edges()
	if not from_env.is_empty():
		return from_env.trim_suffix("/")
	if not _loaded:
		_loaded = true
		var config = ConfigFile.new()
		if config.load(CONFIG_FILE) == OK:
			_saved = str(config.get_value("network", "relayUrl", ""))
	if not _saved.is_empty():
		return _saved
	return str(ProjectSettings.get_setting(PROJECT_SETTING, "")).strip_edges().trim_suffix("/")

static func configured() -> bool:
	return not url().is_empty()

## Checks and stores the player's relay address. Returns {ok, message}. An empty text clears it.
static func save(text: String) -> Dictionary:
	var clean = text.strip_edges().trim_suffix("/")
	if not clean.is_empty():
		var check = validate(clean)
		if not check.ok:
			return check
	var config = ConfigFile.new()
	config.load(CONFIG_FILE)   # keep the other preferences
	config.set_value("network", "relayUrl", clean)
	if config.save(CONFIG_FILE) != OK:
		return {"ok": false, "message": "Could not save the relay address."}
	_saved = clean
	_loaded = true
	return {"ok": true, "message": "Relay address saved." if not clean.is_empty() else "Relay address cleared (direct mode only)."}

## ws:// is accepted only for this PC and private networks (testing); anything on the internet must be wss:// (TLS).
static func validate(text: String) -> Dictionary:
	var regex = RegEx.new()
	regex.compile(URL_PATTERN)
	if regex.search(text) == null:
		return {"ok": false, "message": "That is not a relay address. Use a link like wss://relay.example.com"}
	if text.begins_with("ws://") and not is_private_host(host_of(text)):
		return {"ok": false, "message": "Use wss:// (encrypted) for a relay on the internet. Plain ws:// is only for testing on this PC or your own network."}
	return {"ok": true, "message": ""}

static func host_of(text: String) -> String:
	var rest = text.substr(text.find("://") + 3)
	var cut = rest.find("/")
	if cut >= 0:
		rest = rest.substr(0, cut)
	var colon = rest.rfind(":")
	return rest.substr(0, colon) if colon >= 0 else rest

static func is_private_host(host: String) -> bool:
	if host == "localhost" or host.begins_with("127.") or host.begins_with("10.") or host.begins_with("192.168."):
		return true
	if host.begins_with("172."):
		var second = int(host.split(".")[1]) if host.split(".").size() > 1 else 0
		return second >= 16 and second <= 31
	return false

static func reset_cache() -> void:
	_loaded = false
	_saved = ""
