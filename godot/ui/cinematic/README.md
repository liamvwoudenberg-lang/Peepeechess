# Presentation overlays (Wave 1, Agent B)

All overlays are plain Controls: cosmetic, local, non-blocking, driven by `advance(delta)` for tests. Off with Settings > Cinematics
(`GraphicsSettings.cinematics`), reduced with `Prefs.reduce_motion`. They read and write no simulation state.

| File | Use | Hook (NOT wired; the flow files belong to other owners) |
| --- | --- | --- |
| `capture_intro.gd` | letterbox + versus card, 2.2 s, any key/tap skips | `BattleFlow.preview_requested` / `PitSequence.drop_started`: `var i = CaptureIntro.new(); hud_layer.add_child(i); i.play(attacker_name, defender_name)` |
| `finishing_blow.gd` | edge flash + camera shake, 0.35 s | on the duel's final-hit signal: `FinishingBlow.new()` added to a CanvasLayer, `.play(1.0, battle_camera)` |
| `result_screen.gd` | victory / defeat / draw banner, Continue button | on `BattleFlow.result_ready` / game over: `ResultScreen.new()`, `.show_result("victory", headline, detail)`, connect `continued` |
| `loading_screen.gd` | emblem + progress + tip | `begin(text)`, await one frame, load, `end()` |
| `cine_common.gd` | gate helpers + edge vignette shader | |

## Slow-mo / hit-stop: deliberately disabled
`Engine.time_scale` scales the physics tick the duel simulation runs on (and the online authoritative sim), so it could change
timings and determinism. `FinishingBlow.SLOWMO_ENABLED` stays `false`. Enabling it needs a presentation-only clock exposed by the
combat owner (visual/camera delta separate from sim ticks).

## Telegraph safety
Vignettes are edge-weighted (centre clear), flashes are short (<= 0.35 s) and capped, shake is a camera offset only. Do not place
any overlay over the arena centre during an attack telegraph.

## Menu
The 3D menu (embers, fog, drift, banners) already existed in `ui/opening`; Wave 1 gates embers/fog/bloom on `GraphicsSettings`,
drift on Cinematics, and adds a vignette + logo reveal (`title_screen.gd`). Frames: `ui/theme/ui_frames.gd` (procedural 9-slice).
