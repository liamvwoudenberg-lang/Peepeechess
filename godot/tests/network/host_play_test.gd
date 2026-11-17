extends SceneTree
## Hosting on the host's own PC: invite codec, certificate pinning, router/IP interfaces (with fakes) and a real DTLS loopback game
## (host as Black, friend as White) through HostedGame + InviteJoin, plus the listen-server policy (one guest, no strangers).
const Client = preload("res://network/client/network_client.gd")
const Balance = preload("res://combat/data/balance_data.gd")
const AppSettings = preload("res://ui/application_settings.gd")
const Lobby = preload("res://network/client/online_lobby.tscn")
var checks = 0
var failures = 0
var test_dir = "user://host-test"

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", label)

func wait_for(test: Callable, milliseconds: int = 8000) -> bool:
	var deadline = Time.get_ticks_msec() + milliseconds
	while not test.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await process_frame
	return true

func run() -> void:
	if "--pinning" in OS.get_cmdline_user_args():
		await _pinning()
		print("HOST PINNING: %d checks; failures=%d" % [checks, failures])
		quit(1 if failures > 0 else 0)
		return
	await _codec()
	_interfaces()
	await _game()
	await _battle_game()
	await _lobby_screens()
	await _privacy()
	await _relay_units()
	print("HOST PLAY: %d checks; failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

# ---- invite codec, certificate pinning ----------------------------------------------------------------------------------------
func _codec() -> void:
	var cert = HostCertificate.new()
	check(cert.generate(test_dir) == OK, "a session certificate is generated")
	check(FileAccess.file_exists(cert.key_path) and FileAccess.file_exists(cert.certificate_path), "key and certificate are written under user://")
	check(cert.fingerprint.length() == 64, "the fingerprint is a SHA-256 (64 hex characters)")
	var fields = {"hosts": ["203.0.113.7", "192.168.1.20"], "port": 2456, "matchId": "match-" + "ab".repeat(16), "certificate": cert.certificate_pem, "tuning": Balance.stamp(), "mode": "battle", "version": "0.4.0-rc1"}
	var code = HostInvite.encode(fields)
	check(code.begins_with("PCHESS1-"), "the invite has its prefix")
	print("invite length: ", code.length())
	var decoded = HostInvite.decode(code)
	check(decoded.ok, "a fresh invite decodes")
	if decoded.ok:
		check(decoded.hosts == ["203.0.113.7", "192.168.1.20"] and decoded.port == 2456 and decoded.matchId == fields.matchId and decoded.mode == "battle", "host list, port, match id and mode survive")
		check(decoded.fingerprint == cert.fingerprint, "the certificate in the invite has the host's fingerprint (this is what gets pinned)")
		check(HostInvite.pem_to_der(decoded.certificate) == HostInvite.pem_to_der(cert.certificate_pem), "the certificate round-trips exactly")
	var broken = code.substr(0, 40) + ("A" if code[40] != "A" else "B") + code.substr(41)
	check(not HostInvite.decode(broken).ok and HostInvite.decode(broken).code == "DAMAGED", "one changed character is detected")
	check(HostInvite.decode(code.substr(0, code.length() - 12)).code == "DAMAGED", "a truncated invite is detected")
	check(HostInvite.decode("hello").code == "NOT_AN_INVITE", "text that is not an invite is refused with advice")
	check(HostInvite.decode("").code == "NOT_AN_INVITE", "an empty field is refused")
	check(HostInvite.decode(code.insert(30, "\n") + "  \n").ok, "line breaks and spaces from a chat window are ignored")
	check(HostInvite.decode("PCHESS1-" + "x".repeat(7000)).code == "TOO_LONG", "a huge paste is refused early")
	for bad in [{"port": 0}, {"port": 70000}, {"matchId": "match-zz"}, {"hosts": []}, {"hosts": ["bad host!"]}, {"mode": "blitz"}]:
		var altered = fields.duplicate()
		altered.merge(bad, true)
		var verdict = HostInvite.decode(HostInvite.encode(altered))
		check(not verdict.ok, "an invite with %s is refused" % str(bad))
	var other = HostCertificate.new()
	check(other.generate(test_dir.path_join("other")) == OK and other.fingerprint != cert.fingerprint, "every session gets its own certificate")
	var swapped = fields.duplicate()
	swapped.certificate = other.certificate_pem
	var swapped_decoded = HostInvite.decode(HostInvite.encode(swapped))
	check(swapped_decoded.ok and swapped_decoded.fingerprint == other.fingerprint and swapped_decoded.fingerprint != cert.fingerprint, "the fingerprint follows the embedded certificate, so a swapped certificate cannot pass as the original")
	check(HostInvite.compatible(decoded, Balance.stamp()).ok, "the same tuning stamp is compatible")
	var mismatch = HostInvite.compatible(decoded, "balance-v1:0000")
	check(not mismatch.ok and mismatch.code == "TUNING", "a different tuning stamp is refused with a clear message")
	check(HostInvite.short_fingerprint(cert.fingerprint).length() == 19, "the short security code is four groups of four")
	cert.remove()
	other.remove()
	check(not FileAccess.file_exists(cert.key_path) and cert.key_path.is_empty(), "removing the session deletes the private key file")

# ---- router and public address interfaces ------------------------------------------------------------------------------------
func _interfaces() -> void:
	for address in ["10.0.0.5", "192.168.1.9", "172.16.0.1", "172.31.255.1", "100.64.3.3", "127.0.0.1", "169.254.1.1", "fe80::1", "fd00::2"]:
		check(PortMapper.is_private_address(address), "%s is not reachable from the internet" % address)
	for address in ["203.0.113.7", "8.8.8.8", "172.32.0.1", "100.128.0.1", ""]:
		check(not PortMapper.is_private_address(address), "'%s' is treated as a public address" % address)
	check(PublicIpLookup.valid_ipv4("203.0.113.7") and not PublicIpLookup.valid_ipv4("999.1.1.1") and not PublicIpLookup.valid_ipv4("<html>") and not PublicIpLookup.valid_ipv4("1.2.3"), "the public address answer is validated as IPv4")
	var good = HostedGame.reachability({"ok": true, "external_ip": "203.0.113.7", "private_external": false}, "203.0.113.7", 2456, true)
	check(good.level == "good", "router opened the port and the internet agrees: good")
	var cgnat = HostedGame.reachability({"ok": true, "external_ip": "100.64.1.1", "private_external": true}, "", 2456, true)
	check(cgnat.level == "blocked" and cgnat.text.contains("CGNAT"), "a shared provider address is reported as blocked")
	var double_nat = HostedGame.reachability({"ok": true, "external_ip": "203.0.113.7", "private_external": false}, "198.51.100.9", 2456, true)
	check(double_nat.level == "maybe", "a router address that differs from the internet's view is a warning")
	var manual = HostedGame.reachability({"ok": false}, "198.51.100.9", 2456, true)
	check(manual.level == "manual" and manual.text.contains("2456"), "no UPnP: manual port forwarding for the right port")
	check(HostedGame.reachability({}, "", 2456, false).level == "checking", "before the answers arrive: checking")
	check(HostPanel.manual_steps(2456).contains("UDP") and HostPanel.manual_steps(2456).contains("2456"), "the manual steps name the protocol and port")
	var fake = FakePortMapper.new()
	root.add_child(fake)
	fake.start(2456)
	check(fake.started_ports == [2456] and fake.mapped_port == 2456, "the fake router records the mapping")
	fake.stop()
	fake.stop()
	check(fake.stopped == 1 and fake.mapped_port == 0, "the mapping is removed exactly once")
	fake.free()
	var none = PortMapper.new()
	root.add_child(none)
	var answer = []
	none.finished.connect(func(result): answer.append(result))
	none.start(2456)
	check(answer.size() == 1 and not answer[0].ok, "the base mapper (no router help) answers 'not available' at once")
	none.free()

# ---- a real game over DTLS loopback --------------------------------------------------------------------------------------------
## The host seat is a prepared session (host_token), not an address, so a guest on the same machine is a guest all the same.
func _lan_address() -> String:
	return "127.0.0.1"

func _game() -> void:
	var lan = _lan_address()
	if lan.is_empty():
		print("NOTE: no private LAN address on this machine; the loopback game test is skipped (the guest must not appear as loopback)")
		return
	var fake = FakePortMapper.new()
	fake.scripted = {"ok": true, "external_ip": lan, "message": "Port opened (fake).", "private_external": false}
	var hosted = HostedGame.new()
	root.add_child(hosted)
	check(hosted.begin({"mode": "classic", "color": "b", "port": 24993, "mapper": fake, "lookup_ip": false, "version": "test"}) == OK, "the host server starts with DTLS and a session certificate")
	var host_client = Client.new()
	root.add_child(host_client)
	var host_frames = []
	host_client.session_ready.connect(func(_welcome): host_client.create_match("classic", 600000, 0))
	host_client.frame_received.connect(func(frame):
		host_frames.append(frame)
		hosted.set_match(str(frame.state.matchId)))
	host_client.session_token = hosted.host_token
	check(host_client.connect_server("127.0.0.1", hosted.port, hosted.certificate.certificate_path, false, HostInvite.CERT_HOSTNAME) == OK, "the host's own client connects over loopback with the pinned certificate")
	check(await wait_for(func(): return not hosted.state.invite.is_empty()), "the invite is ready once the match exists and the router answered")
	check(hosted.state.reach.level == "good", "the host is told the port is open")
	var invite_text: String = hosted.state.invite
	# the friend joins with the invite
	var friend = Client.new()
	root.add_child(friend)
	var join = InviteJoin.new()
	root.add_child(join)
	var joined = []
	var failures_seen = []
	join.joined.connect(func(invite): joined.append(invite))
	join.failed.connect(func(code, message): failures_seen.append(code))
	var begun = join.begin(friend, invite_text, Balance.stamp(), hosted.passphrase)
	check(begun.ok, "the invite is accepted by the join flow")
	check(await wait_for(func(): return not joined.is_empty() or not failures_seen.is_empty(), 12000) and not joined.is_empty(), "the friend connects securely and joins the host's match (failures: %s)" % str(failures_seen))
	check(friend.frame.get("state", {}).get("players", {}).get("w") == friend.player_id and friend.frame.get("state", {}).get("players", {}).get("b") == host_client.player_id, "the host chose Black, so the friend sits at White")
	# a second stranger with a valid certificate and match id is turned away: one guest only
	var late_client = Client.new()
	root.add_child(late_client)
	var late_join = InviteJoin.new()
	root.add_child(late_join)
	var late_failed = []
	late_join.failed.connect(func(code, _message): late_failed.append(code))
	late_join.begin(late_client, invite_text, Balance.stamp(), hosted.passphrase)
	check(await wait_for(func(): return not late_failed.is_empty(), 12000), "a third player with the invite is refused (one opponent only)")
	late_join.cancel()
	# both ready, White moves, Black sees it
	host_client.command("ready")
	friend.command("ready")
	check(await wait_for(func(): return friend.frame.get("status") == "active" and host_client.frame.get("status") == "active", 6000), "after both press Ready the game is active")
	friend.chess_move("e2", "e4")
	check(await wait_for(func(): return host_client.frame.get("state", {}).get("chess", {}).get("history", []).size() == 1, 6000), "the host sees the friend's move through the authoritative server")
	# the host's tuning and version are what the friend checked
	check(HostInvite.decode(invite_text, hosted.passphrase).tuning == Balance.stamp(), "the invite carries the tuning stamp")
	# stopping removes the router mapping and the key
	var key_path = hosted.certificate.key_path
	friend.disconnect_server(true)
	host_client.disconnect_server(true)
	for _i in 10:
		await process_frame
	hosted.stop()
	check(fake.stopped == 1, "stopping the host closes the router port")
	check(not FileAccess.file_exists(key_path), "stopping the host deletes the private key")
	for node in [host_client, friend, join, late_client, late_join]:
		node.queue_free()
	hosted.queue_free()
	await process_frame

# ---- privacy: sealed invites, no automatic IP lookup, masked UI, locked listener ------------------------------------------------
func _privacy() -> void:
	var cert = HostCertificate.new()
	cert.generate(test_dir.path_join("privacy"))
	var plain = HostInvite.encode({"hosts": ["203.0.113.77"], "port": 2456, "matchId": "match-" + "cd".repeat(16), "certificate": cert.certificate_pem, "tuning": Balance.stamp(), "mode": "classic", "version": "t"})
	var word = HostInvite.generate_passphrase()
	check(word.length() == 14 and word.count("-") == 2, "the word code has three groups of four (%s)" % word)
	var sealed = HostInvite.seal(plain, word)
	check(sealed.begins_with("PCHESS2-") and HostInvite.is_sealed(sealed), "a sealed invite has its own prefix")
	check(not sealed.contains("203.0.113.77") and not Marshalls.base64_to_raw(sealed.trim_prefix("PCHESS2-").replace("-", "+").replace("_", "/")).get_string_from_ascii().contains("203.0.113.77"), "the address is not readable inside the sealed invite")
	check(HostInvite.decode(sealed).code == "SEALED", "without the word code a sealed invite is refused with a clear message")
	var opened = HostInvite.decode(sealed, word.to_lower())
	check(opened.ok and opened.hosts == ["203.0.113.77"] and opened.matchId == "match-" + "cd".repeat(16), "with the word code (any case) the invite opens")
	check(HostInvite.decode(sealed, "AAAA-BBBB-CCCC").code == "WRONG_PASSPHRASE", "a wrong word code is refused")
	var tampered = sealed.substr(0, 60) + ("A" if sealed[60] != "A" else "B") + sealed.substr(61)
	check(not HostInvite.decode(tampered, word).ok, "a changed character is detected")
	check(HostInvite.seal(plain, word) != sealed, "sealing twice gives different text (random salt and iv)")
	# no automatic website lookup
	var lookup = PublicIpLookup.new()
	root.add_child(lookup)
	var answered = []
	lookup.finished.connect(func(address): answered.append(address))
	lookup.lookup()
	await process_frame
	await process_frame
	check(answered == [""] and lookup._request == null, "the public-address lookup does nothing (no network request) without the host's consent")
	lookup.queue_free()
	var fake = FakePortMapper.new()
	fake.scripted = {"ok": false, "message": "no router"}
	var hosted = HostedGame.new()
	root.add_child(hosted)
	check(hosted.begin({"mode": "classic", "color": "w", "port": 24997, "mapper": fake}) == OK, "hosting starts with default privacy settings")
	check(hosted.ip_lookup != null and not hosted.ip_lookup.consented, "by default no website is asked for the host's address")
	check(not hosted.set_manual_address("bad address!") and hosted.set_manual_address("example.org") and hosted.manual_address == "example.org", "a typed address is validated and used")
	hosted.set_match("match-" + "ef".repeat(16))
	await wait_for(func(): return not hosted.state.invite.is_empty(), 6000)
	check(HostInvite.is_sealed(hosted.state.invite) and hosted.state.passphrase == hosted.passphrase, "the invite is sealed by default and the word code is kept separate")
	var decoded = HostInvite.decode(hosted.state.invite, hosted.passphrase)
	check(decoded.ok and decoded.hosts[0] == "example.org", "the typed address comes first in the invite")
	# the host server: expiry and locking
	var server = hosted.server
	server.host_policy["invite_expires"] = Time.get_ticks_msec() - 1
	server.attach(901, "198.51.100.9", Time.get_ticks_msec())
	check(not server.connections.has(901), "an expired invite: a stranger's connection is dropped without a reply")
	server.attach(902, "127.0.0.1", Time.get_ticks_msec())
	check(server.connections.has(902), "the host's own loopback client is never locked out")
	server.host_policy["invite_expires"] = 0
	server.host_policy["locked"] = true
	server.host_policy["guest_address"] = "198.51.100.20"
	server.attach(903, "198.51.100.9", Time.get_ticks_msec())
	server.attach(904, "198.51.100.20", Time.get_ticks_msec())
	check(not server.connections.has(903) and server.connections.has(904), "once the guest is seated only the guest's address may connect")
	hosted.stop()
	hosted.queue_free()
	await process_frame

func other_certificate_attempt(client, address: String, port: int) -> void:
	var other = HostCertificate.new()
	other.generate(test_dir.path_join("stranger"))
	client.connect_server(address, port, other.certificate_path, false, HostInvite.CERT_HOSTNAME)
	client.auto_reconnect = false

## Run on its own (--pinning): the handshake failure it provokes is logged by the engine as an ERROR line, which the shared runner would flag.
func _pinning() -> void:
	var hosted = HostedGame.new()
	root.add_child(hosted)
	var fake = FakePortMapper.new()
	hosted.begin({"mode": "classic", "color": "w", "port": 24994, "mapper": fake, "lookup_ip": false})
	var friend = Client.new()
	root.add_child(friend)
	var ok = []
	friend.session_ready.connect(func(_welcome): ok.append(true))
	friend.connect_server("127.0.0.1", hosted.port, hosted.certificate.certificate_path, false, HostInvite.CERT_HOSTNAME)
	friend.auto_reconnect = false
	check(await wait_for(func(): return not ok.is_empty(), 5000), "a client pinned to the real certificate connects and gets a guest session")
	var stranger = Client.new()
	root.add_child(stranger)
	var authenticated = []
	stranger.session_ready.connect(func(_welcome): authenticated.append(true))
	other_certificate_attempt(stranger, "127.0.0.1", hosted.port)
	await wait_for(func(): return not authenticated.is_empty(), 2500)
	check(authenticated.is_empty(), "a client pinned to a different certificate never authenticates (no man in the middle)")
	friend.disconnect_server(true)
	stranger.disconnect_server(true)
	hosted.stop()

## The two screens a player sees: the host's lobby (invite + copy) and the friend's lobby after pasting the invite.
func _lobby_screens() -> void:
	AppSettings.loaded = true
	var fake = FakePortMapper.new()
	fake.scripted = {"ok": false, "external_ip": "", "message": "No UPnP router answered.", "private_external": false}
	AppSettings.launch = {"host": {"mode": "battle", "color": "r", "initialMs": 0, "incrementMs": 0, "mapper": fake, "lookup_ip": false, "view3d": false}}
	var host_screen = Lobby.instantiate()
	root.add_child(host_screen)
	for _i in 5:
		await process_frame
	check(host_screen.host_panel != null and host_screen.hosted != null, "the host lobby shows the hosting panel")
	var ready = await wait_for(func(): return host_screen.host_panel != null and not host_screen.host_panel._invite.text.is_empty(), 10000)
	check(ready, "the host's invite appears in the panel")
	check(not host_screen.host_panel._copy.disabled, "the copy button is enabled once the invite exists")
	check(host_screen.host_panel._reach.text.contains("2456") or host_screen.host_panel._reach.text.contains("245"), "the panel explains the router/port result (manual steps when UPnP is missing)")
	check(host_screen.host_panel._manual.text.contains("UDP"), "manual port-forwarding steps are shown when the router did not help")
	check(host_screen.host_panel._fingerprint.text.contains("-"), "the security code is shown")
	var invite_text: String = host_screen.host_panel._invite.text
	AppSettings.launch = {"invite": invite_text, "passphrase": host_screen.hosted.passphrase, "view3d": false}
	var friend_screen = Lobby.instantiate()
	root.add_child(friend_screen)
	var joined = await wait_for(func(): return friend_screen.notices.text.begins_with("Joined"), 12000)
	check(joined, "the friend's lobby joins from the pasted invite (%s)" % friend_screen.notices.text)
	AppSettings.launch = {"invite": "PCHESS1-garbage", "view3d": false}
	var bad_screen = Lobby.instantiate()
	root.add_child(bad_screen)
	for _i in 5:
		await process_frame
	check(bad_screen.notices.text.length() > 10 and not bad_screen.notices.text.begins_with("Joined"), "a bad invite shows a clear message (%s)" % bad_screen.notices.text)
	for screen in [bad_screen, friend_screen, host_screen]:
		screen.queue_free()
	await process_frame
	await process_frame

## A Battle Chess capture through the hosted path: the capture starts the real server-side combat simulation on the host's PC.
func _battle_game() -> void:
	var fake = FakePortMapper.new()
	fake.scripted = {"ok": true, "external_ip": "127.0.0.1", "message": "Port opened (fake).", "private_external": false}
	var hosted = HostedGame.new()
	root.add_child(hosted)
	check(hosted.begin({"mode": "battle", "color": "w", "port": 24996, "mapper": fake, "lookup_ip": false}) == OK, "a Battle game can be hosted")
	var host_client = Client.new()
	root.add_child(host_client)
	host_client.session_ready.connect(func(_welcome): host_client.create_match("battle", 0, 0))
	host_client.frame_received.connect(func(frame): hosted.set_match(str(frame.state.matchId)))
	host_client.session_token = hosted.host_token
	host_client.connect_server("127.0.0.1", hosted.port, hosted.certificate.certificate_path, false, HostInvite.CERT_HOSTNAME)
	check(await wait_for(func(): return not hosted.state.invite.is_empty()), "the Battle invite is ready")
	var friend = Client.new()
	root.add_child(friend)
	var join = InviteJoin.new()
	root.add_child(join)
	var joined = []
	join.joined.connect(func(invite): joined.append(invite.mode))
	join.begin(friend, hosted.state.invite, Balance.stamp(), hosted.passphrase)
	check(await wait_for(func(): return not joined.is_empty(), 12000) and joined[0] == "battle", "the friend joins the Battle game")
	host_client.command("ready")
	friend.command("ready")
	await wait_for(func(): return friend.frame.get("status") == "active" and host_client.frame.get("status") == "active", 6000)
	host_client.chess_move("e2", "e4")
	await wait_for(func(): return friend.frame.get("state", {}).get("chess", {}).get("history", []).size() == 1, 4000)
	friend.chess_move("d7", "d5")
	await wait_for(func(): return host_client.frame.get("state", {}).get("chess", {}).get("history", []).size() == 2, 4000)
	host_client.chess_move("e4", "d5")
	var room = hosted.server.rooms.values()[0]
	check(await wait_for(func(): return room.game.phase != "board", 6000), "the capture leaves the board phase on the host's server")
	check(room.game.phase in ["preview", "combat", "countdown"], "the host's server runs the capture duel (phase: %s)" % room.game.phase)
	friend.disconnect_server(true)
	host_client.disconnect_server(true)
	for _i in 5:
		await process_frame
	hosted.stop()
	for node in [host_client, friend, join]:
		node.queue_free()
	hosted.queue_free()
	await process_frame


# ---- relay mode: invite fields, address rules, settings and screens (the real relay path is scripts/test-relay-play.mjs) ------------
func _relay_units() -> void:
	var cert = HostCertificate.new()
	cert.generate(test_dir)
	var session = "ab".repeat(16)
	var fields = {"hosts": [], "port": 2456, "matchId": "match-" + "cd".repeat(16), "certificate": cert.certificate_pem, "tuning": Balance.stamp(), "mode": "classic",
		"version": "t", "relay": "wss://relay.example.com", "session": session}
	var decoded = HostInvite.decode(HostInvite.encode(fields))
	check(decoded.ok and decoded.hosts.is_empty() and decoded.relay == "wss://relay.example.com" and decoded.session == session, "a relay-only invite carries the relay and session and no host address at all")
	var sealed = HostInvite.seal(HostInvite.encode(fields), "K7QM-X2PD-9WTR")
	var opened = HostInvite.decode(sealed, "K7QM-X2PD-9WTR")
	check(opened.ok and opened.relay == "wss://relay.example.com", "a sealed relay invite opens with the word code")
	var no_hosts_no_relay = fields.duplicate()
	no_hosts_no_relay.erase("relay")
	no_hosts_no_relay.erase("session")
	check(not HostInvite.decode(HostInvite.encode(no_hosts_no_relay)).ok, "an invite with neither host addresses nor a relay is refused")
	var bad = fields.duplicate()
	bad.relay = "ws://relay.example.com"
	check(not HostInvite.decode(HostInvite.encode(bad)).ok, "an unencrypted ws:// relay on the internet is refused")
	bad = fields.duplicate()
	bad.session = "nothex"
	check(not HostInvite.decode(HostInvite.encode(bad)).ok, "a bad session id is refused")
	bad = fields.duplicate()
	bad.relay = "wss://exa mple.com/<x>"
	check(not HostInvite.decode(HostInvite.encode(bad)).ok, "a malformed relay address is refused")
	var local = fields.duplicate()
	local.relay = "ws://127.0.0.1:8080"
	check(HostInvite.decode(HostInvite.encode(local)).ok, "ws:// is fine for this PC (testing)")
	check(RelaySettings.validate("wss://relay.example.com/path").ok and RelaySettings.validate("ws://192.168.1.5:8080").ok and RelaySettings.validate("ws://172.20.0.4").ok, "wss:// anywhere, ws:// on private networks")
	check(not RelaySettings.validate("ws://172.32.0.4").ok and not RelaySettings.validate("ws://8.8.8.8").ok and not RelaySettings.validate("http://x.example.com").ok and not RelaySettings.validate("relay.example.com").ok, "public ws://, http:// and bare names are refused")
	RelaySettings.reset_cache()
	check(RelaySettings.save("https://nope").ok == false, "an invalid relay address is not saved")
	check(RelaySettings.save("wss://relay.example.com/").ok and RelaySettings.url() == "wss://relay.example.com", "a valid address is saved without the trailing slash")
	check(RelaySettings.save("").ok and RelaySettings.url().is_empty(), "an empty address clears the relay (direct mode only)")
	# HostedGame without a relay address falls back to direct mode; with one it listens on loopback only and builds a relay invite after the relay answers
	var fake = FakePortMapper.new()
	fake.scripted = {"ok": true, "external_ip": "127.0.0.1", "message": "fake", "private_external": false}
	var direct = HostedGame.new()
	root.add_child(direct)
	check(direct.begin({"mode": "classic", "color": "w", "port": 24970, "mapper": fake, "connection": "relay", "relay_url": ""}) == OK and direct.connection == "direct", "no relay address: hosting falls back to direct mode")
	direct.stop()
	direct.queue_free()
	var bridge = RelayBridge.new()
	root.add_child(bridge)
	var states = []
	bridge.state_changed.connect(func(value): states.append(value))
	check(bridge.start_guest("ws://127.0.0.1:1", "ab".repeat(16)) == OK and bridge.local_port > 0, "the guest bridge opens a loopback port for the game client")
	check(await wait_for(func(): return "failed" in states, 30000), "a relay that cannot be reached ends in 'failed' (retries, then gives up)")
	bridge.stop()
	bridge.queue_free()
	await process_frame
	# the Play page and the Settings page
	AppSettings.loaded = true
	AppSettings.intro_seen = true
	AppSettings.launch.clear()
	RelaySettings.save("")
	var shell = load("res://ui/application.tscn").instantiate()
	root.add_child(shell)
	for _i in 6:
		await process_frame
	shell.online = true
	shell.navigate("play")
	for _i in 4:
		await process_frame
	check(shell.find_child("NoRelayNotice", true, false) != null and shell.find_child("ConnectionChoice", true, false) == null, "no relay address: the Play page says direct mode only and offers no relay choice")
	check(shell.hosting_launch().host.connection == "direct", "no relay address: hosting is launched in direct mode")
	RelaySettings.save("wss://relay.example.com")
	shell.online = true
	shell.navigate("play")
	for _i in 4:
		await process_frame
	check(shell.find_child("ConnectionChoice", true, false) != null, "with a relay address the Play page offers Relay / Direct")
	var launch = shell.hosting_launch().host
	check(launch.connection == "relay" and launch.relay_url == "wss://relay.example.com", "with a relay address, hosting defaults to the relay")
	shell.navigate("settings")
	for _i in 4:
		await process_frame
	var relay_field = shell.find_child("RelayAddress", true, false)
	check(relay_field != null and relay_field.text == "wss://relay.example.com", "Settings has a relay address field showing the saved address")
	RelaySettings.save("")
	shell.queue_free()
	await process_frame
