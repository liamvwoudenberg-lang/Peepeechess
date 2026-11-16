class_name HostCertificate
extends RefCounted
## A fresh self-signed certificate and key for one hosting session. The key never leaves the host's machine
## (it is written to a session folder under user:// that is removed again when hosting stops); the certificate goes into the invite.
const DIRECTORY = "user://host-session"
var certificate_path = ""
var key_path = ""
var certificate_pem = ""
var fingerprint = ""

## Generates the key pair (RSA 2048: a second or two) and writes both files. Returns OK or an Error.
func generate(directory: String = DIRECTORY) -> Error:
	var crypto = Crypto.new()
	var key = crypto.generate_rsa(2048)
	if key == null:
		return ERR_CANT_CREATE
	var now = Time.get_unix_time_from_system()
	var cert = crypto.generate_self_signed_certificate(key, "CN=%s,O=Peepeechess" % HostInvite.CERT_HOSTNAME, _stamp(now - 86400.0), _stamp(now + 30.0 * 86400.0))
	if cert == null:
		return ERR_CANT_CREATE
	DirAccess.make_dir_recursive_absolute(directory)
	certificate_path = directory.path_join("host.crt")
	key_path = directory.path_join("host.key")
	if cert.save(certificate_path) != OK or key.save(key_path) != OK:
		remove()
		return ERR_FILE_CANT_WRITE
	var raw = FileAccess.get_file_as_bytes(certificate_path)   # read back the file: save_to_string() trips an engine warning on mbedTLS' trailing NUL
	while not raw.is_empty() and raw[raw.size() - 1] == 0:
		raw.resize(raw.size() - 1)
	certificate_pem = raw.get_string_from_ascii()
	fingerprint = HostInvite.fingerprint(HostInvite.pem_to_der(certificate_pem))
	return OK

## Deletes the session's key and certificate files.
func remove() -> void:
	for path in [certificate_path, key_path]:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	certificate_path = ""
	key_path = ""

static func _stamp(unix: float) -> String:
	var d = Time.get_datetime_dict_from_unix_time(int(unix))
	return "%04d%02d%02d%02d%02d%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
