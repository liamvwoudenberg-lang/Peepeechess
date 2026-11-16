class_name HostPanel
extends VBoxContainer
## What the host sees while hosting: progress, the invite with a copy button, the address and port, the router result and, when needed,
## plain manual port-forwarding steps. Light text on dark card panels, touch-sized buttons, no hover-only information.
const Kit = preload("res://ui/theme/ui_kit.gd")
signal stop_requested
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
	_copied = Kit.muted(_card, "")
	_copied.name = "Copied"
	_fingerprint = Kit.muted(_card, "")
	_fingerprint.name = "Fingerprint"
	_address = Kit.muted(_card, "")
	_address.name = "Address"
	_reach = Kit.label(_card, "")
	_reach.name = "Reach"
	_manual = Kit.muted(_card, "")
	_manual.name = "Manual"

func update_state(state: Dictionary) -> void:
	if _status == null:
		return
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
	_copy.disabled = invite.is_empty()
	var fingerprint: String = str(state.get("fingerprint", ""))
	_fingerprint.text = "Security check: %s (your friend sees the same code when they join)." % HostInvite.short_fingerprint(fingerprint) if not fingerprint.is_empty() else ""
	var addresses: Array = []
	var public = str(state.get("public_ip", ""))
	var router: Dictionary = state.get("router", {})
	if router.get("ok", false) and not str(router.get("external_ip", "")).is_empty() and not router.get("private_external", false):
		public = str(router.external_ip)
	if not public.is_empty():
		addresses.append("Internet: %s:%d" % [public, int(state.get("port", 0))])
	for lan in state.get("lan", []):
		addresses.append("Same network: %s:%d" % [lan, int(state.get("port", 0))])
	_address.text = "\n".join(addresses) + ("\nUDP port %d" % int(state.get("port", 0)) if int(state.get("port", 0)) > 0 else "")
	var reach: Dictionary = state.get("reach", {})
	_reach.text = str(reach.get("text", ""))
	_manual.text = manual_steps(int(state.get("port", 0))) if str(reach.get("level", "")) == "manual" else ""

func _copy_invite() -> void:
	DisplayServer.clipboard_set(_invite.text)
	_copied.text = "Invite copied. Paste it to your friend in a chat message."

static func manual_steps(port_number: int) -> String:
	return "Manual port forwarding:\n1. Open your router's settings page (often 192.168.0.1 or 192.168.1.1).\n2. Find \"Port forwarding\" (also \"Virtual server\" or \"NAT\").\n3. Add a rule: protocol UDP, external and internal port %d, destination = this PC's address from the list above.\n4. Allow the game in the Windows Firewall when asked.\nThen share the invite again." % port_number
