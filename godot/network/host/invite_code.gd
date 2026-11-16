class_name HostInvite
extends RefCounted
## The invite a host shares with a friend: where to connect, which match to join, and the host's self-signed certificate.
## The certificate travels inside the invite, so the friend pins it (DTLS trusts exactly that certificate and nothing else) and no CA is needed.
## The match id is the join token: it is 128 random bits created by the host's server and is only ever sent through the invite.
## Format: "PCHESS1-" + base64url(JSON) + "-" + 8 hex check characters. Whitespace and line breaks are ignored when parsing.
const PREFIX = "PCHESS1-"
const MAX_LENGTH = 6000
const PROTOCOL = "peepeechess-enet-v1"
const CERT_HOSTNAME = "peepeechess-host"
const MATCH_PATTERN = "^match-[0-9a-f]{32}$"
const HOST_PATTERN = "^[A-Za-z0-9]([A-Za-z0-9.:\\-]{0,252}[A-Za-z0-9])?$"

## `fields`: hosts (Array of String, best first), port, matchId, certificate (PEM text), tuning, mode, version.
static func encode(fields: Dictionary) -> String:
	var certificate: String = str(fields.get("certificate", ""))
	var der = pem_to_der(certificate)
	var body = {"v": 1, "h": fields.get("hosts", []), "p": int(fields.get("port", 0)), "m": str(fields.get("matchId", "")),
		"c": Marshalls.raw_to_base64(der), "t": str(fields.get("tuning", "")), "g": str(fields.get("mode", "")),
		"pr": PROTOCOL, "a": str(fields.get("version", ""))}
	var text = _b64url_encode(JSON.stringify(body, "", true).to_utf8_buffer())
	return PREFIX + text + "-" + _check(text)

## Returns {ok: true, hosts, port, matchId, certificate (PEM), fingerprint (hex), tuning, mode, version} or {ok: false, code, message}.
static func decode(raw: String) -> Dictionary:
	var text = raw.strip_edges()
	for blank in [" ", "\n", "\r", "\t"]:
		text = text.replace(blank, "")
	if text.length() > MAX_LENGTH:
		return _fail("TOO_LONG", "That does not look like an invite code.")
	if not text.begins_with(PREFIX):
		return _fail("NOT_AN_INVITE", "This is not a Peepeechess invite. Paste the whole code your friend sent you (it starts with PCHESS1-).")
	var rest = text.trim_prefix(PREFIX)
	var cut = rest.rfind("-")
	if cut <= 0 or rest.length() - cut - 1 != 8:
		return _fail("DAMAGED", "The invite looks cut off. Copy it again, including the end.")
	var payload = rest.substr(0, cut)
	if rest.substr(cut + 1) != _check(payload):
		return _fail("DAMAGED", "The invite is damaged (check characters differ). Copy it again.")
	var bytes = _b64url_decode(payload)
	if bytes.is_empty():
		return _fail("DAMAGED", "The invite could not be read.")
	var parsed = JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		return _fail("DAMAGED", "The invite could not be read.")
	return _validate(parsed)

static func _validate(data: Dictionary) -> Dictionary:
	if int(data.get("v", 0)) != 1 or str(data.get("pr", "")) != PROTOCOL:
		return _fail("VERSION", "This invite was made by a different version of the game (protocol %s). Both players need the same version." % str(data.get("pr", "?")))
	var hosts: Array = []
	var host_regex = RegEx.new()
	host_regex.compile(HOST_PATTERN)
	if not data.get("h") is Array or data.h.is_empty() or data.h.size() > 8:
		return _fail("DAMAGED", "The invite has no host address.")
	for value in data.h:
		if not value is String or host_regex.search(value) == null:
			return _fail("DAMAGED", "The invite contains an invalid host address.")
		hosts.append(value)
	var port = data.get("p")
	if not (port is float or port is int) or floor(port) != port or port < 1 or port > 65535:
		return _fail("DAMAGED", "The invite contains an invalid port.")
	var match_id = data.get("m")
	var match_regex = RegEx.new()
	match_regex.compile(MATCH_PATTERN)
	if not match_id is String or match_regex.search(match_id) == null:
		return _fail("DAMAGED", "The invite contains an invalid match code.")
	if not data.get("c") is String or data.c.length() > 4096:
		return _fail("DAMAGED", "The invite has no host certificate.")
	var der = Marshalls.base64_to_raw(data.c)
	if der.size() < 64 or der.size() > 3072:
		return _fail("DAMAGED", "The invite has an invalid host certificate.")
	var pem = der_to_pem(der)
	var test = X509Certificate.new()
	if test.load_from_string(pem) != OK:
		return _fail("DAMAGED", "The invite has an invalid host certificate.")
	var mode = str(data.get("g", ""))
	if mode not in ["classic", "battle"]:
		return _fail("DAMAGED", "The invite names an unknown game mode.")
	return {"ok": true, "hosts": hosts, "port": int(port), "matchId": match_id, "certificate": pem, "fingerprint": fingerprint(der),
		"tuning": str(data.get("t", "")), "mode": mode, "version": str(data.get("a", ""))}

static func fingerprint(der: PackedByteArray) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(der)
	return ctx.finish().hex_encode()

## "AB12-CD34-EF56-7890": what both players can read aloud to confirm they talk about the same host.
static func short_fingerprint(hex: String) -> String:
	var upper = hex.substr(0, 16).to_upper()
	return "%s-%s-%s-%s" % [upper.substr(0, 4), upper.substr(4, 4), upper.substr(8, 4), upper.substr(12, 4)]

static func pem_to_der(pem: String) -> PackedByteArray:
	var body = ""
	for line in pem.split("\n"):
		var clean = line.strip_edges()
		if clean.is_empty() or clean.begins_with("-----"):
			continue
		body += clean
	return Marshalls.base64_to_raw(body)

static func der_to_pem(der: PackedByteArray) -> String:
	var body = Marshalls.raw_to_base64(der)
	var lines = PackedStringArray(["-----BEGIN CERTIFICATE-----"])
	var at = 0
	while at < body.length():
		lines.append(body.substr(at, 64))
		at += 64
	lines.append("-----END CERTIFICATE-----")
	return "\n".join(lines) + "\n"

## Version check before connecting: a different tuning stamp means different combat numbers, so the duel would not match.
static func compatible(invite: Dictionary, own_tuning: String) -> Dictionary:
	if not str(invite.get("tuning", "")).is_empty() and str(invite.tuning) != own_tuning:
		return {"ok": false, "code": "TUNING", "message": "The host plays a different version of the combat rules (%s, you have %s). Update the game so both of you run the same version." % [str(invite.tuning), own_tuning]}
	return {"ok": true}

static func _check(text: String) -> String:
	return text.sha256_text().substr(0, 8)

static func _b64url_encode(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

static func _b64url_decode(text: String) -> PackedByteArray:
	var padded = text.replace("-", "+").replace("_", "/")
	while padded.length() % 4 != 0:
		padded += "="
	return Marshalls.base64_to_raw(padded)

static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
