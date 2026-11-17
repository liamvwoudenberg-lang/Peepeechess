class_name HostPanel
extends VBoxContainer
## What the host sees while hosting: progress, the invite with a copy button, the address and port, the router result and, when needed,
## plain manual port-forwarding steps. Light text on dark card panels, touch-sized buttons, no hover-only information.
const Kit = preload("res://ui/theme/ui_kit.gd")
signal stop_requested
signal detect_requested
signal manual_address_submitted(text: String)
var _reveal: Button
var _passphrase: Label
var _manual_edit: LineEdit
var _detect: Button
var _privacy: Label
var _revealed = false
var _card: VBoxContainer
var _status: Label
var _invite: LineEdit
var _copy: Button
var _fingerprint: Label
var _address: Label
var _reach: Label
var _manual: Label
var _copied: Label

func _ready() -> void:
	name = "HostPanel"
	_card = Kit.card(self)
	Kit.section_header(_card, "HOSTING ON THIS PC", "cloud")
	_status = Kit.label(_card, "Preparing a secure game…")
	_status.name = "Status"
	_invite = LineEdit.new()
	_invite.name = "Invite"
	_invite.editable = false
	_invite.placeholder_text = "The invite appears here when your game is ready"
	_invite.custom_minimum_size.y = Kit.target_height()
	_invite.select_all_on_focus = true
	_card.add_child(_invite)
	var row = Kit.flow(_card)
	_copy = Kit.primary(row, "Copy invite", _copy_invite)
	_copy.name = "CopyInvite"
	_copy.disabled = true
	Kit.secondary(row, "Stop hosting", func(): stop_requested.emit())
	_reveal = Kit.secondary(row, "Show invite", _toggle_reveal)
	_reveal.name = "RevealInvite"
	_copied = Kit.muted(_card, "")
	_copied.name = "Copied"
	_passphrase = Kit.label(_card, "")
	_passphrase.name = "Passphrase"
	var address_row = Kit.flow(_card)
	_manual_edit = LineEdit.new()
	_manual_edit.name = "ManualAddress"
	_manual_edit.placeholder_text = "Your public address (optional, typed by you)"
	_manual_edit.custom_minimum_size = Vector2(260, Kit.target_height())
	_manual_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_manual_edit.text_submitted.connect(func(text): manual_address_submitted.emit(text))
	address_row.add_child(_manual_edit)
	Kit.secondary(address_row, "Use this address", func(): manual_address_submitted.emit(_manual_edit.text)).name = "UseAddress"
	_detect = Kit.secondary(address_row, "Detect my address (asks a website)", func(): detect_requested.emit())
	_detect.name = "DetectAddress"
	_privacy = Kit.muted(_card, "Privacy: your address is hidden here and sealed inside the invite. Only someone with the invite AND the word code can read it. A direct game necessarily shows your address to the friend you invite.")
	_privacy.name = "Privacy"
	_fingerprint = Kit.muted(_card, "")
	_fingerprint.name = "Fingerprint"
	_address = Kit.muted(_card, "")
	_address.name = "Address"
	_reach = Kit.label(_card, "")
	_reach.name = "Reach"
	_manual = Kit.muted(_card, "")
	_manual.name = "Manual"

var _last_state: Dictionary = {}

func update_state(state: Dictionary) -> void:
	if _status == null:
		return
	_last_state = state
	var phase: String = str(state.get("phase", ""))
	var invite: String = str(state.get("invite", ""))
	match phase:
		"certificate":
			_status.text = "Creating a secure certificate for this game…"
		"opening":
			_status.text = "Opening the game port and finding your address…"
		"ready":
			_status.text = "Ready. Send your friend the invite. Only the person with this invite can join (one opponent)."
		"failed":
			_status.text = str(state.get("error", "Hosting failed."))
		"stopped":
			_status.text = "Hosting stopped."
	_invite.text = invite
	_invite.secret = not _revealed   # the invite is hidden on screen (streams, screenshots) until the host shows it
	_copy.disabled = invite.is_empty()
	var word_code: String = str(state.get("passphrase", ""))
	_passphrase.text = "Word code (tell your friend by voice or another chat, not together with the invite): %s" % word_code if not word_code.is_empty() and _revealed else ("Word code hidden: press Show invite." if not word_code.is_empty() else "")
	var fingerprint: String = str(state.get("fingerprint", ""))
	_fingerprint.text = "Security check: %s (your friend sees the same code when they join)." % HostInvite.short_fingerprint(fingerprint) if not fingerprint.is_empty() else ""
	# Addresses are never printed: only whether the invite has an internet address and the UDP port that must be open.
	var lines: Array = []
	lines.append("Internet address in the invite: %s" % ("yes (hidden)" if bool(state.get("has_internet_address", false)) else "not yet"))
	lines.append("Same-network addresses: %d (hidden)" % state.get("lan", []).size())
	if int(state.get("port", 0)) > 0:
		lines.append("UDP port %d" % int(state.get("port", 0)))
	_address.text = "\n".join(lines)
	var reach: Dictionary = state.get("reach", {})
	_reach.text = str(reach.get("text", ""))
	_manual.text = manual_steps(int(state.get("port", 0))) if str(reach.get("level", "")) == "manual" else ""

func _toggle_reveal() -> void:
	_revealed = not _revealed
	_reveal.text = "Hide invite" if _revealed else "Show invite"
	update_state(_last_state)

func _copy_invite() -> void:
	DisplayServer.clipboard_set(_invite.text)
	_copied.text = "Invite copied. Paste it to your friend in a chat message."

static func manual_steps(port_number: int) -> String:
	return "Manual port forwarding:\n1. Open your router's settings page (often 192.168.0.1 or 192.168.1.1).\n2. Find \"Port forwarding\" (also \"Virtual server\" or \"NAT\").\n3. Add a rule: protocol UDP, external and internal port %d, destination = this PC's address from the list above.\n4. Allow the game in the Windows Firewall when asked.\nThen share the invite again." % port_number
