extends RefCounted
## Real recordings (tools/audio/build_sonniss.py -> assets/audio/*.ogg + sonniss_manifest.json): the library loads them over the synthesized set, every
## sound the game plays has a stream, the chess / capture / ambience additions exist, BoardSounds picks the right sound for a move, and the shipped files stay small.
const CombatAudio := preload("res://combat/audio/combat_audio.gd")
const Board := preload("res://audio/board_sounds.gd")
const NEEDED := ["swing_sword", "hit_steel_light", "block", "parry", "dodge", "victory", "defeat", "ui_click", "ui_hover", "ui_confirm", "ui_back", "ui_deny", "ui_transition",
	"chess_move", "chess_capture", "chess_castle", "chess_check", "chess_checkmate", "chess_promote", "chess_win", "chess_lose", "capture_shatter", "capture_intro", "amb_torch", "amb_wind", "amb_mystic"]


static func run(h, _tree: SceneTree) -> void:
	h.begin("real audio: manifest, library overlay, variants, size budget")
	h.check(FileAccess.file_exists(CombatAudio.REAL_MANIFEST_PATH), "the real-recordings manifest ships")
	var library: Dictionary = CombatAudio.load_library(true)
	for sound in NEEDED:
		h.check(library.has(sound) and not (library[sound] as Array).is_empty(), "%s has at least one stream" % sound)
	h.check((library["swing_sword"][0] as AudioStream).get_class() == "AudioStreamOggVorbis", "swing_sword is the real recording (Ogg Vorbis), not the synthesized WAV")
	h.check((library["hit_steel_light"] as Array).size() >= 2, "frequent sounds have pitch variants (%d)" % (library["hit_steel_light"] as Array).size())
	var real: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CombatAudio.REAL_MANIFEST_PATH))
	var total := 0
	var biggest := 0
	for sound in real["sounds"]:
		for file in real["sounds"][sound]["files"]:
			var size := FileAccess.open(String(file), FileAccess.READ).get_length() if FileAccess.file_exists(String(file)) else 0
			total += size
			biggest = maxi(biggest, size)
			h.check(size > 0, "%s exists" % file)
	h.check(total < 8 * 1024 * 1024, "all real recordings together stay under 8 MB (%.1f MB)" % (total / 1048576.0))
	h.check(biggest < 1024 * 1024, "no single file over 1 MB (%.2f MB)" % (biggest / 1048576.0))
	h.begin("real audio: which sound a chess move makes")
	h.eq(Board.sound_for({"san": "e4"}), "chess_move", "quiet move")
	h.eq(Board.sound_for({"san": "exd5"}), "chess_capture", "capture")
	h.eq(Board.sound_for({"san": "exd5 [defended]", "outcome": "defender"}), "block", "a defended Battle capture sounds like a block")
	h.eq(Board.sound_for({"san": "Nf3+"}), "chess_check", "check")
	h.eq(Board.sound_for({"san": "Qh7#"}), "chess_checkmate", "checkmate beats check")
	h.eq(Board.sound_for({"san": "O-O"}), "chess_castle", "castling")
	h.eq(Board.sound_for({"san": "e8=Q"}), "chess_promote", "promotion")
	h.eq(Board.sound_for({"san": "exd8=Q+"}), "chess_check", "a capturing promotion with check is a check")
