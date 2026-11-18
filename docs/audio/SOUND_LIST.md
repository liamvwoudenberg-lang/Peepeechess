# Sound list (missing sounds)
Combat, UI and music are already procedurally generated (tools/audio/generate_sfx.py, own work, no licence issue).
Network downloads were blocked while preparing this list. Only CC0 or permissive sources (Kenney, OpenGameArt CC0, Freesound CC0). Add every file to /CREDITS.md.
Drop files into godot/assets/audio_incoming/ named exactly `<target>.<any ext>`, then run tools/audio/import_incoming.sh.

| Event | Search term / source | Target name | Length |
|---|---|---|---|
| Chess piece move | Kenney "Board game" / freesound "wood piece place" | chess_move | 0.2 s |
| Chess capture | freesound "wood clack hard" | chess_capture | 0.3 s |
| Check | OpenGameArt "soft gong" | chess_check | 0.8 s |
| Checkmate | OpenGameArt "low bell toll" | chess_checkmate | 2 s |
| Promotion | Kenney "chime" | chess_promote | 0.8 s |
| Castling | freesound "wood slide" | chess_castle | 0.4 s |
| Menu ambience loop | freesound "stone hall room tone" | amb_menu | 30 s loop |
| Duel ambience loop | freesound "wind arena distant crowd" | amb_arena | 30 s loop |
| Board ambience loop | freesound "quiet library fireplace" | amb_board | 30 s loop |
| Cloth/armour rustle (idle) | freesound "armour rustle" | foley_armor | 0.5 s |
| Land after dodge | freesound "boots stone land" | foley_land | 0.25 s |
