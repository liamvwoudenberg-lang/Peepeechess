# 3D opening screen

The application opens on a 3D opening screen instead of the flat title page: a moonlit chess castle at the end of a chequered
bridge, the wordmark and a pulsing **"Press any button to start"**. Any key, mouse button, touch or gamepad button glides the
camera (about 2.4 s, eased) up the bridge, between the two giant chess-piece statues and through the gate into a courtyard that is
a giant chessboard; while it flies the title fades out and the existing main menu (`Title.build`) fades in over the
still-rendering scene. The castle stays behind the menu as a living backdrop (slower drift).

It plays **once per application run** (`Settings.intro_seen`); coming back to `home` from a page or a match shows the menu over the
castle with no intro. `--no-intro` on the command line skips it, tests call `Settings.reset_intro()`.

## Screenshots

Software GL (Xvfb, llvmpipe), so frame timings are not representative; the pictures are.
Desktop shots were rendered in a 1280x800 window and downscaled to 960 px wide; phone shots are a 390x844 portrait window.

| File | What it shows |
| --- | --- |
| `01-opening-desktop.png` | the opening shot: title, tagline, pulsing prompt, castle, statues, braziers, crows, moon |
| `02-glide-approach-desktop.png` | 0.6 s into the glide: title already gone, camera between the giant rook / king / knight pieces on the bridge |
| `03-glide-gate-desktop.png` | 1.1 s: passing under the gate arch, the courtyard chessboard glowing ahead |
| `04-menu-desktop.png` | arrived: the main menu over the courtyard (wordmark, tagline and menu column over the 3D scene) |
| `05-opening-phone-portrait.png` | opening screen in a 390x844 portrait window (camera switches to a horizontal fov) |
| `06-glide-gate-phone-portrait.png` | glide through the gate, portrait |
| `07-menu-phone-portrait.png` | menu, portrait (the existing home layout is a landscape design; see limits) |
| `08-opening-low-quality-desktop.png` | the same opening shot with graphics quality "low" (fewer lights, no crows, no clouds, fewer lit windows) |

## How it works

| File | Role |
| --- | --- |
| `godot/ui/opening/opening_screen.gd` | 2D overlay and state machine (`WAITING` -> `TRANSITION` -> `DONE`), input filter, title layout (safe-area aware), drives the camera blend and the menu fade. All timing goes through `advance(delta)`. |
| `godot/ui/opening/opening_scene.gd` | `Node3D` that builds and animates the castle: environment, camera path, lights, merged meshes, halos / flames / embers / crows. `set_blend(0..1)` moves the camera from the opening shot to the menu vantage. |
| `godot/ui/opening/castle_builder.gd` | Pure geometry layout (walls, towers, gatehouse, keep, court, bridge, terrain) into a few `MeshBatch`es plus lists of lights, halos, flames and statues. Creates no nodes. |
| `godot/ui/opening/mesh_batch.gd` | Merges primitives (box, lathe, quad, imported mesh arrays) into one indexed `ArrayMesh` with vertex colour and generated UVs. |
| `godot/ui/opening/opening_assets.gd` | Procedural textures (stone, rock, slate, glow, mist), the shaders (sky, banners, halos, flames, embers, crows, mist) and materials. |
| `godot/ui/application.gd` | `_home_page()` starts the intro the first time, `_ensure_scene3d()` / `_release_scene3d()` build the castle lazily and free it when another page replaces home. |
| `godot/ui/theme/backdrop.gd` | new `"scene"` mode: only a soft scrim (top / bottom bands, dim centre behind the menu) over the 3D scene. |

"Any button": `InputEventKey` (pressed, not a repeat), `InputEventMouseButton` (left / right / middle / extra, not the wheel),
`InputEventScreenTouch` (pressed) and `InputEventJoypadButton` (pressed). Mouse motion, stick axes, releases, key repeats and
everything on the very first frame are ignored. While the glide runs every press is swallowed (it never reaches the menu
underneath); a press more than 0.4 s into the glide skips to the finished menu, earlier ones (a touch also produces an emulated
click) are ignored.

## Settings it honours

* **Reduce motion** (UI preferences): a press cuts straight to the menu; no camera drift, wind, flicker, pulse; embers and crows are hidden.
* **Graphics quality**: `low` = 2 real torch lights + gate light + moon + fill, no clouds / trees / crows / wide halos / mist (3 cards),
  LOD1 statues, about 18k triangles, 20 embers; `balanced` (default) = 4 pooled lights, about 39k triangles, 70 embers; `high` =
  7 pooled lights, moon shadows, glow, LOD0 statues, about 51k triangles (shadow pass included about 100k), 100 embers. The 30 fps cap of `low`
  is the existing `Engine.max_fps` setting.

## Performance notes

* Static geometry is merged: the whole castle, bridge, courtyard and terrain are 6 mesh instances, the giant chess pieces are merged
  per material (about 8 meshes), plus 4 MultiMeshes (halos, flames, embers, crows) and a few mist cards: 18 / 23 / 25 draw nodes for
  low / balanced / high. Measured in a real frame under Xvfb with the UI on top: 30 draw calls (low), 35 (balanced), 50 (high,
  shadow pass included).
* Torches that matter are a small pool of `OmniLight3D`s that relocates while the camera passes the gate, so the lights near the
  camera are always the ones that exist. Everything else is an additive billboard.
* Banners, halos, flames, embers and crows animate in vertex / fragment shaders: no per-frame CPU work except one camera transform,
  a few light energies and two shader uniforms.
* The scene is built when `home` is shown (about 70 / 120 / 125 ms for low / balanced / high on this machine, headless build) and freed when another page opens or the
  application is freed; nothing is cached in statics.

## Tests

`godot/tests/ui/opening_screen_test.gd` (registered in `scripts/test-ui.mjs`, `npm run test:ui`): first state, every kind of
"any button", ignored input, the glide and its timing, skipping, reduce motion, quality tiers, once-per-run, navigation, layout at six sizes
plus a notch inset, resize, leaks (node and object counts across repeated cycles) and cleanup. Other suites that opened on the
home menu (`test_application_ui.gd`, `ui_layout_test.gd`, `ui_theme_test.gd`, `ai_ui_test.gd`, the package smoke) were updated.

## Known limits

* Not measured on a real GPU or on a phone; the frame times from llvmpipe in this environment are only indicative.
* The home / menu layout was designed for landscape (the project forces landscape on handhelds); in a portrait window the menu is
  small because the 1200 px logical width does not stack. The opening screen itself adapts (type scale, horizontal fov).
* The giant chess pieces are the existing low-poly `assets/world/pieces` models (the knight in particular is rough up close).
* Glow (post-process bloom) is only enabled on `high`; on lower tiers the bloom look comes from additive halo quads.
