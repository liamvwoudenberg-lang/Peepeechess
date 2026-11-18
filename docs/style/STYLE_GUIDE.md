# Peepeechess style guide: dark-fantasy castle at dusk

One page. Presentation only: nothing here changes chess rules, duel simulation, hitboxes, frame data, timings or determinism.

## Mood
Weathered stone and iron at dusk. **Warm torchlight against cool blue shadow.** Gold trim, navy and crimson banners, drifting embers,
low fog. Dark surroundings so the board and the fighters are always the brightest, clearest thing on screen.

## Palette
| Role | Colour | Use |
| --- | --- | --- |
| Night | `#0d1016` | background, deep shadow |
| Dusk shadow | `#1b2130` | fog, ambient, panel base |
| Stone | `#6f6d68` / dark `#34353b` | walls, dais, floor, frames |
| Torch | `#ff9a3c` | flame, key accents, warm light |
| Gold | `#c9a24c` (hi `#f6dfa6`) | trim, inlay, headings, selection |
| Navy | `#1d2c52` | banners, cool UI accents |
| Crimson | `#8c1f2c` | banners, danger, captures |
| Orange / ivory | `#c9631c` / `#e9e5db` | board squares (dark / light) |
| Moonlight | `#8fb6ff` | rim light, cool highlights |

Board marks: selected gold, legal green `#59f299`, capture red `#ff4d40`, last move blue `#59a6ff`, check red. Never put a colour effect on top
of an attack telegraph; telegraphs always win (see Rules).

## Light
Warm key (soft shadows) from the upper left, cool blue rim from behind, torch point lights with noise flicker (about 15% energy),
light fog, no pure-white squares (exposure below 1.0). Bloom only on emissive flames and metal.

## Type
* **Display / titles:** Cinzel (SIL OFL 1.1, `godot/assets/fonts/Cinzel.ttf`, licence beside it). Wordmark, H1, H2 only.
* **UI text:** the clean default sans, regular and bold. Never Cinzel below 20 px or for numbers (clocks).
* Sizes come from `ui/theme/ui_tokens.gd`; nothing is hard-coded per screen.

## Shape and surface
Chunky carved stone, gold inlay lines, 9-slice gilded or stone frames, soft inner shadow, 1-2 px gold keyline. Buttons: dark stone fill, gold
text, brighter on hover, pressed one pixel down. Stone textures are triplanar at a fixed texel density; nothing is stretched.

## Motion
Slow and weighty. Menu camera drifts, banners sway, embers rise. UI transitions 150-250 ms, ease-out. Cinematics are **under 3 seconds,
skippable with any key or tap, and toggled by Settings > Cinematics**. Reduce-motion turns drift, sway and shake off.

## Rules
* Effects (fog, bloom, particles, shake, slow-mo) must never hide an attack telegraph or reduce its contrast.
* Cosmetic only: no change to simulation logic, hitboxes, frame data, timings, chess rules or determinism. Hit-stop and slow-mo are
  presentation-clock effects layered on top of the unchanged simulation.
* Everything adjustable: Settings > Graphics and cinematics (presets Low / Medium / High / Ultra plus each toggle), audio sliders by bus.
* Every asset has a licence entry in `CREDITS.md`. Generated models share one Meshy prompt: *"dark fantasy castle, weathered stone, gold
  accents, navy and crimson banners, stylized realistic PBR"*.

## Quality presets (`ui/graphics_settings.gd`, saved in `user://graphics.cfg`)
| | Low | Medium | High | Ultra |
| --- | --- | --- | --- | --- |
| Particles / light shafts | off / off | on / off | on / on | on / on |
| Fog / bloom / SSAO | off / off / off | on / off / off | on / on / off | on / on / on* |
| Shadows | off | low | medium | high |
| Anti-aliasing | off | FXAA | MSAA 2x | MSAA 4x |
| 3D resolution / FPS cap | 75% / 30 | 100% / 60 | 100% / none | 100% / none |

\* SSAO and TAA need the Forward+ renderer; the project uses GL Compatibility, so they are stored and shown but inactive for now.
Also in Settings: VSync, resolution scale slider, frame-rate limit, Cinematics on/off, FPS overlay (F3).
