# Cinematic menu: one 3D world, the camera flies between pages

Status: **phases 1-2 built** (2026-11-17, branch `ccr-cine-menu-1`); phases 3-5 are still ideas. It extends the opening screen (`godot/ui/opening/*`) and the 3D
plaques (`menu_plaques.gd`), which already exist.

## 1. The idea in one paragraph

The title screen is the best-looking part of the game: a lit castle, a camera that drifts and glides, a menu that lives in the scene.
Today the other pages (Play, Training, Campaign, Friends, Profile, History, Leaderboard, Settings) are flat dark slabs with 3D-looking tabs,
so the game stops feeling like a place after the first click. The idea is to keep **one persistent 3D castle world behind everything**
and make every menu page a **location in that world**. Choosing a page does not swap a screen: the **camera flies there** along a
designed path, past other 3D objects, and arrives at a station where the page's options are 3D props (plaques, banners, doors, a map table).

## 2. Principles

1. **One world, one camera.** No page ever shows a flat background. The same castle, lighting and music bed carry through.
2. **Navigation is travel.** Every page change is a short camera flight (about 0.8 to 1.6 s). The flight tells the player where they
   are relative to everything else ("Training is down the stairs from the Great Hall").
3. **Options are objects.** Mode choices, tabs and big actions are 3D props that react to hover, focus and press.
4. **Dense UI stays crisp.** Forms, lists and text-heavy settings stay screen-space Control nodes (sharp text, accessibility, easy
   focus), anchored to a station and framed by the scene, never texture-mapped onto geometry.
5. **Always skippable and always readable.** Reduce-motion and low-quality fall back to quick cuts or the flat menu. Contrast rules
   (light text on dark surfaces) apply to every overlay.
6. **Every input works.** Mouse, touch, keyboard and pad reach every action. Pad navigation follows the 3D layout.

## 3. The map: pages as locations

| Page | Station in the castle | Hero prop (the 3D buttons) | Camera feel |
|---|---|---|---|
| Home / title | The causeway to the gate (exists) | Mode plaques: Classic, Battle, Online, Profile, Settings, Quit | Slow drift, current look |
| Play | The great hall, chess table in the middle | Two big banners (Classic / Battle), a 3D board on the table that previews the chosen setup | Push in through the gate, settle above the table |
| Training | The training yard / barracks | Weapon rack and practice dummies as lesson plaques, medals on a wall | Turn left, step down into the yard |
| Campaign | The war room | A large map table; the 12 encounters are 3D pieces on the map, boss nodes are tall, locked nodes are covered | High orbit over the table, then dive to the next node |
| Friends | The tavern / common room | Hanging name signs, an invite scroll | Warm light, lower and slower camera |
| Profile and History | The portrait gallery | Framed portraits and trophies; matches as framed paintings | Slow lateral dolly along the wall |
| Leaderboard | The watchtower | Rank banners climbing a spiral stair | Vertical fly-up |
| Settings | The armoury / workshop | Tool-bench categories: Display, Audio, Controls, Online | Close, steady camera, little motion |
| Battle prep (capture) | The trapdoor and the pit (exists in the match world) | Existing pit sequence | Existing |

The stations share one set of landmarks so a flight between two of them visibly passes through the places in between.

## 4. Camera language

- **Rig:** one `MenuCameraRig` with named stations (position, look target, field of view, depth-of-field, fog) and authored
  **paths** between neighbouring stations (Catmull-Rom splines with look-at keys), not straight lerps.
- **Flights:** ease in and out, 0.8 to 1.6 s by distance, with a slight roll and field-of-view change, and a short motion-blur-like
  streak from the existing mist and embers. UI overlays fade (not slide) during a flight and return on arrival.
- **Idle:** each station has a slow drift (the opening screen's `_path` idea) plus a small mouse/pad parallax. The shake is zero.
- **Interrupts:** pressing a new target mid-flight retargets smoothly from the current pose. Back/Escape reverses the last flight.
- **Fly-pasts:** optional "look at" beats on a path (the camera glances at a banner, a torch, a statue) to make the passes feel
  designed. Keep them under 15% of the flight time so players are not made to wait.
- **Reduce motion:** flights become 150 ms crossfades between stations (no spline, no roll, no parallax).

## 5. 3D buttons

- **Plaque / banner / door / lever** prop kinds, built from the existing Meshy models where they fit (banner, archway, torch sconce,
  pillar, ascent) and from `menu_plaques.gd` for plaques.
- **States:** rest, hover/focus (lift towards camera, warm glow, small tilt), press (push back, spark), disabled/locked (covered,
  chained, dimmed), selected (lit rim, ember trail).
- **Hit testing:** use the existing projected rectangles so mouse, touch and the pad cursor all work; the prop is purely visual
  plus a Control that owns focus and tooltip. This keeps accessibility, tests and controller navigation intact.
- **Pad focus:** the focus graph follows the on-screen layout of the props at the station; neighbours are computed from projected
  centres.
- **Sound:** a distinct hover, press and "lock" cue per prop kind, plus a whoosh on each flight (through the audio director).

## 6. Dense pages inside the world

Play options, Settings, Friends lists, Profile stats and History tables are forms. They stay as `Control` trees:

- A single **page frame** anchored to the station: a dark translucent panel with a thin carved border and a soft glow, sized by the
  safe area, never covering the hero props.
- The frame **parallaxes slightly** against the world (a few pixels with mouse or pad) so it feels attached to the scene.
- Content swaps inside the frame while the camera makes small "settle" moves, so changing a sub-tab is cheap and never a full flight.
- Text is always crisp screen-space with the existing outline/contrast rules.

## 7. Technical sketch

- `MenuWorld` (persistent): owns the castle, lights, embers, mist, statues (reuses `OpeningScene` builders) and the `MenuCameraRig`.
  It lives for the whole menu session and is paused (not freed) when a match starts, so returning is instant.
- `MenuStation` resource: id, camera pose, field of view, depth of field, props list, idle drift, audio bed, page id.
- `navigate(page)` keeps its current contract; the new layer wraps it: `await menu_world.fly_to(station)`, then show the page frame.
  Tests keep calling `navigate` and may use a "skip flights" test mode.
- Quality tiers: `low` = the flat menu (as today); `balanced` = full world, fewer lights/embers, no depth of field; `high` = everything.
  Phones: cap lights, embers and draw nodes (the opening scene already has a draw-node budget test).
- Reduce motion and low-power paths are first-class and tested.

## 8. Phased plan

1. **Foundation:** `MenuWorld` + `MenuCameraRig` + stations table; fly between Home, Play and Settings with the existing plaques;
   page frame with parallax; reduce-motion crossfade; tests for station poses, flight timing, interrupt/back, and skip mode.
2. **Play hall:** banner props for Classic/Battle, a live 3D board preview on the table, flow cleanup (which game, who, options).
3. **Campaign war room:** the 3D map table with 12 nodes, locked/boss states, boon pick as props.
4. **Training yard, Gallery, Watchtower, Tavern:** stations and hero props; leaderboard and history as in-world displays.
5. **Polish:** fly-past beats, sound, depth of field, typography pass, loading/empty states, portrait and phone layouts.

## 9. Risks

- **Motion sickness and impatience:** keep flights short, cancellable, off under reduce-motion; never block input for more than a flight.
- **Performance on phones:** one shared world (not one scene per page) and strict budgets; low tier stays flat.
- **Pad/keyboard navigation in 3D:** solved by keeping Controls as the owners of focus and computing neighbours from projections.
- **Content effort:** each station needs props and lighting; start with reuse of existing Meshy models and plaques.
- **Test churn:** many UI tests assume instant page swaps; add a deterministic "no flights" mode first.

## 10. Open questions for the owner

1. Should the world be **daytime/evening variants** per station, or one night look throughout (current)?
2. Should **Online / Friends** be in the castle too, or a distinct "outside the walls" area to separate local from online play?
3. Is a **first-person-feeling walkthrough** wanted (camera follows a path with slight bob), or a smoother cinematic style (current)?
4. How much **waiting** is acceptable per navigation: a 1 s flight every time, or a long flight only the first time then quick cuts?
5. Should a **paladin character** stand at each station and react (nod on hover, bow on select), as the opening statues do?

## 11. Decided 2026-11-17 (owner) and what phases 1-2 built

Decisions: (1) one night look everywhere; (2) Friends, account sign-in and Online play are OUTSIDE the castle walls (the bridge, with a
signpost and a campfire), local pages are inside; (3) a smooth cinematic glide like the title screen, not a walkthrough; (4) the first flight
into each station in a session is long (2.5 s, with fly-past beats), every later flight about 1 s (`MenuCameraRig.LONG_FLIGHT/SHORT_FLIGHT`,
nothing persisted); (5) a paladin stands at each station and reacts (turns and nods on arrival, looks at a hovered prop, bows on select).

Built (godot/ui/opening/): `menu_stations.gd` (nine stations, page -> station map, authored paths, gate pass), `menu_camera_rig.gd` (spline
flights, ease, interrupt/retarget, back, skip, reduce-motion crossfade, instant test mode), `menu_world.gd` (the persistent layer: station
paladins and props built lazily the first time a station is visited, the Play hall banners and a live board preview table, the exterior
signpost and campfire, the armoury rack, the yard dummy). `OpeningScene` gained the `rig` hook, a faint idle drift and pointer parallax,
and `spawn_paladin()`. `application.gd` routes `navigate(page)` through the world (fade during a flight, skip on any key/click/pad button, page
column on the right so the left stays open as the stage, one-row tab bar that falls back to icons, no repeated tagline on inner pages).
Low quality keeps the flat menu. Tests: `godot/tests/ui/menu_world_test.gd` (in `npm run test:ui`).
Limits: the station paladins are the static statue meshes (no skeleton), so "nod", "look" and "bow" are body tilts and turns, not animations;
Training, Campaign, Profile, History and Leaderboard use camera stations with a paladin but no hero props yet (phases 3-4); flight audio reuses
the UI 'back' sound; the 3D props are not clickable (the Controls own input).

## 12. Built in the second pass (2026-11-17, branch ccr-cine-menu-2)
- **Rigged station paladins** (`menu_world.gd`, `menu_look_modifier.gd`, new clips `greet`, `bow`, `salute`, `look_around` in `paladin_clips.gd`): the same
  `PaladinModel` characters as the board and duels, a looping idle, a greeting on arrival, an occasional look-around, a head/spine look-at at the hovered prop
  through a `SkeletonModifier3D`, a bow or salute on select, and a step aside (walk clip) when the camera flies off. Only the paladin at the current station
  (and the one being left) is animated. Reduce-motion keeps the idle pose still. Falls back to the old static statue if the rig is missing.
- **War room** (`menu_hero_props.gd`): a map table with 12 nodes (boss nodes tall and red, locked covered, cleared with a banner, current enlarged and lit)
  and three boon pedestals shown while a boon is offered. The campaign page pushes the run's state (`set_campaign_display`).
- **Hero props**: training yard (weapon rack, dummies, medal wall lit by lesson ratings), gallery and archive (framed matches coloured win/loss/draw),
  watchtower (rank banners with the top names), friend name signs outside the walls. Pages push data through `set_training_medals`, `set_gallery`,
  `set_leaderboard`, `set_friends`; data pushed before a station is built is applied when it is.
- **Clickable props**: `MenuWorld.pick()` casts the mouse ray against each prop's pick sphere; `Application._prop_clicked` maps the prop to the same action as its page control.
- **Flight whoosh**: the existing `dodge` rush of air (no new sound id). **Portrait/phone**: windows taller than wide leave the top 30% to the world.
- **Not done / decisions**: depth of field is not possible on the Compatibility renderer the project uses; the project has no display font, so the typography pass
  is left; the props are positioned for landscape (portrait only shows what falls in the top band); the stations' props have never been watched in motion.
