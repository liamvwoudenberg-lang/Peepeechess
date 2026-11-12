# Board customization

Device-local presentation settings. They never enter match state, contracts or the network, and they never change what the opponent sees.

| Setting | Values | Applies to |
| --- | --- | --- |
| Theme | `slate` (default, the shipped look), `classic_wood`, `marble`, `tournament_green`, `midnight` | 2D tiles/frame/labels; 3D tiles, plinth, trim, labels, backdrop |
| Move highlights | `dots` (default), `rings`, `tile tint` | 2D and 3D legal-destination marks |
| Coordinates | on / off | 2D labels, 3D `Label3D`s |
| Piece set (3D) | `procedural` (default, `piece_meshes.gd`), `carved` (GLB marble/basalt set in `assets/world/pieces/`, LOD1 on mobile, procedural fallback if the files are missing) | 3D pieces; the 2D board always uses the illustrated atlas |
| Animation speed | `off`, `normal` (default), `fast` (x0.5 durations) | 2D and 3D piece movement; `off` also clears the older "Piece animations" switch |
| Piece shadows | `low` (key-light shadow and piece shadow casting off), `high` (default) | 3D; the pit world's own low-quality mode keeps priority |

Files: `board_theme.gd` (`BoardTheme`: presets, statics, `events().changed`, `save_to` / `load_from`, 2D destination drawing),
`board_theme_view.gd` (`BoardThemeView`: 3D application, GLB piece builder, shadow flags, 3D destination marks, `Binder` node),
`ui/board_settings.gd` (settings card with live 2D and 3D preview). Persistence is the `[board]` section of `user://preferences.cfg`, written
and read by `ApplicationSettings.save_preferences()` / `load_preferences()`. The default theme (`slate`) never overrides the 3D board's own
materials, so new board art keeps showing until the player chooses another theme.

## Hooks in shared files (keep these when merging)

- `boards/board_2d.gd`: connects `BoardTheme.events().changed` to `queue_redraw`; tile / frame / label colours, coordinates and destination marks come from
  `BoardTheme`; tween duration `BoardTheme.anim_seconds(0.2)`.
- `boards/board_3d.gd` (four one-line hooks): at the end of `setup()` `BoardThemeView.attach_3d(self)`; in `update_marks()` the destination loop calls
  `BoardThemeView.destination_3d(self, m.to, not game.engine.board[m.to].is_empty() or m.flag == "ep")` instead of `_mark(...)`; in `sync_state()` the
  animation condition adds `and BoardTheme.anim_scale() > 0.0` and the tween duration is `BoardTheme.anim_seconds(0.24)`.
  `BoardThemeView` works for the pit-world board too (`scene = world.board_root`, lights on `board.world`, marks re-tagged to render layer 2,
  the world's `quality == "low"` keeps shadows off); it only needs `scene`, `pieces`, `_piece_roles`, `_last_match_id`, `marks` and `sync_state()`.
- `boards/piece_meshes.gd`: `build()` asks `BoardThemeView.build_piece()` first and returns through `BoardThemeView.finish_piece()` (shadow flags).
- `ui/application_settings.gd`: `BoardTheme.load_from(config)` / `save_to(config)`.
- `ui/application.gd`: `BoardSettingsPage.build(self)` in the Settings page.
