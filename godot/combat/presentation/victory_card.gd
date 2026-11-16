class_name VictoryCard
extends VBoxContainer
## The duel's victory screen: a large "<PIECE> WINS" headline, the reason, and a two-row summary (who attacked, the remaining
## health of both fighters as bars). Presentation only: built from the authoritative BattleResult and fighter info, never touches
## the simulation. `info_for` is pure (unit-tested); `play_in` fades the card in (instantly with reduce motion).

const REASONS := {
	"knockout": "Knockout", "timeout_hp": "Time - more health remaining", "timeout_tie": "Time - tie goes to the defender",
	"double_knockout": "Double knockout - defender holds",
}
const GOLD := Color(1.0, 0.84, 0.45)

var _title: Label
var _subtitle: Label
var _rows: Array = []   # [name label, bar, hp label] per side (attacker, defender)
var info: Dictionary = {}


## Pure: the headline, subtitle and the two summary rows for a finished duel.
## `attacker` / `defender`: {"role": "q", "color": "w", "max_hp": 100}. The result is the BattleResult dictionary.
static func info_for(result: Dictionary, attacker: Dictionary, defender: Dictionary, display_name: Callable) -> Dictionary:
	var outcome := String(result.get("outcome", "defender"))
	var winner: Dictionary = attacker if outcome == "attacker" else defender
	var loser: Dictionary = defender if outcome == "attacker" else attacker
	var reason := String(result.get("reason", ""))
	var winner_name: String = String(display_name.call(String(winner.get("role", "?"))))
	var title := "%s WINS" % winner_name.to_upper()
	if reason == "knockout" and String(loser.get("role", "")) == "k":
		title = "THE KING HAS FALLEN"   # King's last stand: the cutscene's headline
	var rows: Array = []
	for pair in [["Attacker", attacker, int(result.get("attackerHp", 0))], ["Defender", defender, int(result.get("defenderHp", 0))]]:
		var side: Dictionary = pair[1]
		var max_hp := maxi(1, int(side.get("max_hp", 100)))
		var hp: int = pair[2]
		rows.append({
			"side": pair[0], "name": String(display_name.call(String(side.get("role", "?")))), "color": String(side.get("color", "w")),
			"hp": hp, "max_hp": max_hp, "fraction": clampf(float(hp) / float(max_hp), 0.0, 1.0),
			"winner": (pair[0] == "Attacker") == (outcome == "attacker") and reason != "double_knockout",
		})
	return {"title": title, "subtitle": String(REASONS.get(reason, reason)), "rows": rows, "outcome": outcome}


func _init() -> void:
	name = "VictoryCard"
	add_theme_constant_override("separation", 8)
	alignment = BoxContainer.ALIGNMENT_CENTER
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", GOLD)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("outline_size", 8)
	_title.add_theme_font_size_override("font_size", 40)
	add_child(_title)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", Color(0.92, 0.9, 0.84))
	add_child(_subtitle)
	for i in 2:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		add_child(row)
		var who := Label.new()
		who.custom_minimum_size.x = 170
		row.add_child(who)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.custom_minimum_size = Vector2(150, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var hp := Label.new()
		hp.custom_minimum_size.x = 64
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(hp)
		_rows.append([who, bar, hp])


func show_info(p_info: Dictionary, width: float = 640.0) -> void:
	info = p_info
	_title.text = String(info["title"])
	_title.add_theme_font_size_override("font_size", 40 if width >= 640.0 else (30 if width >= 420.0 else 22))
	_subtitle.text = String(info["subtitle"])
	for i in 2:
		var row: Dictionary = info["rows"][i]
		var parts: Array = _rows[i]
		(parts[0] as Label).text = "%s · %s (%s)" % [row["side"], row["name"], "White" if row["color"] == "w" else "Black"]
		(parts[0] as Label).add_theme_color_override("font_color", GOLD if row["winner"] else Color(0.75, 0.75, 0.78))
		(parts[1] as ProgressBar).value = float(row["fraction"])
		(parts[2] as Label).text = "%d HP" % int(row["hp"])


## Fades and eases the card in; with reduce motion (or no tree) it just appears.
func play_in(reduce_motion: bool) -> void:
	if reduce_motion or not is_inside_tree():
		modulate.a = 1.0
		scale = Vector2.ONE
		return
	modulate.a = 0.0
	pivot_offset = size * 0.5
	scale = Vector2(0.92, 0.92)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.35)
	tween.tween_property(self, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
