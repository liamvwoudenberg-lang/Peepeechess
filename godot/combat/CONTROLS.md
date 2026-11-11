# Controls (keyboard, DualShock 4 / Xbox pads, touch)

This is the single description of the control layer. The in-game hints, the test-arena menu and the Controls screen are
generated from the same bindings (`combat/input/control_bindings.gd`), so they cannot drift from this table.

**Verification status (read this first).** No physical DualShock 4 (or any other controller) was available. Everything
below is built against Godot 4.6.3's documented SDL game-controller mapping and tested with *injected*
`InputEventJoypadButton` / `InputEventJoypadMotion` events carrying a `device` id (`Input.parse_input_event`). That proves
the logic (mapping, dead zones, trigger hysteresis, per-device isolation, hot-plug handling, rebinding, persistence, board
cursor, menu focus). It does not prove real hardware: drivers (DS4Windows, Steam Input), Bluetooth, latency, stick/trigger
calibration and comfort were not exercised. See "Known limits" at the end.

## Combat

| Action | Player 1 keyboard (kb1) | Player 2 keyboard (kb2) | DualShock 4 / DualSense | Xbox / XInput | Touch |
| --- | --- | --- | --- | --- | --- |
| Move (camera relative) | WASD | Arrow keys | Left stick | Left stick | Left floating stick |
| Sprint (hold) | Shift | Ctrl | L2 (hold) | LT | Stick to the rim |
| Light attack | F, mouse left | J | Square | X | LIGHT |
| Heavy attack | G, mouse right | K | Triangle, R2 (alias) | Y, RT (alias) | HEAVY |
| Block (hold) | Q | U | L1 (hold) | LB | BLOCK (hold) |
| Parry | E | I | R1 | RB | PARRY |
| Dodge (direction held) | Space | L | Cross | A | DODGE |
| Special ability | R | O | Circle | B | SPECIAL |
| Lock-on / free camera | Tab, mouse middle | P | L3 (left stick click) | LS | LOCK |
| Camera (free camera only) | Mouse, Z / X, wheel zooms | `,` / `.` | Right stick | Right stick | Drag |
| Pause / back to menu (test arena) | Esc | | Options | Menu | PAUSE |
| Rematch / menu after a fight (test arena) | Enter or F5 / Esc | | Cross / Circle or Options | A / B | |

Notes:

* Sticks are fixed (left = move, right = camera). Every other binding can be changed (see Rebinding). R3 (right stick click),
  Share/View, the touchpad click and the D-pad are unused in combat (the touchpad click and D-pad can be bound).
* **Stick**: the vector is read as a whole (radial dead zone, default 0.18, rescaled so the rim of the dead zone is 0 and
  deflection 0.96 is full speed; the outer zone matters because real sticks often cannot reach 1.0 on the diagonals), then
  shaped by a response exponent (default 1 = linear). All three are settings.
* **Triggers** (L2/R2, `JOY_AXIS_TRIGGER_LEFT/RIGHT`) are Schmitt triggers: pressed above 0.50, released below 0.35, so a
  trigger resting near the threshold does not chatter. A trigger that rests at -1 (some drivers) reads as "not pressed".
* **R2** is a heavy-attack alias (same press counter as Triangle, so it is exactly one heavy per press). Unbind it in the
  Controls screen if you prefer. It can also be bound to anything else.
* **Block** is a hold, **sprint** is a hold; everything else is one press = one counter increment in the `CombatInput`.
* **Two pads at once**: each pad is an independent device; every event and every poll carries the device id, so
  pad 0 can never drive pad 1's fighter. Seats are chosen by `InputAssignment` (below).
* DS4 buttons by Godot name (SDL layout): `JOY_BUTTON_A` = Cross, `B` = Circle, `X` = Square, `Y` = Triangle,
  `LEFT_SHOULDER` = L1, `RIGHT_SHOULDER` = R1, `LEFT_STICK` = L3, `START` = Options, `BACK` = Share, `TOUCHPAD` = touchpad
  click, `MISC1` = mic/mute. Names shown in the game follow the connected controller (`ControllerGlyphs`): a name or GUID
  that identifies PlayStation hardware shows Cross/Circle/Square/Triangle/L1/R1/L2/R2/Options/Share; Xbox shows
  A/B/X/Y/LB/RB/LT/RT/Menu/View; Switch shows its own letters. A DS4 presented as an **XInput pad** (DS4Windows, Steam
  Input) reports an Xbox name and is labelled Xbox: the positions are identical, only the printed names differ. A raw DS4 and a
  DS4Windows DS4 go through the same Godot mapping.

## Menus, Classic Chess and Battle Chess boards

| Control | Pad | Keyboard / mouse |
| --- | --- | --- |
| Move focus | D-pad or left stick | Arrow keys / Tab |
| Press the focused control | Cross | Enter / Space |
| Back / close a dialog / leave a sub-page | Circle | Esc (dialogs) |
| Previous / next focus | L1 / R1 | Shift+Tab / Tab |
| Board cursor | D-pad / left stick | Arrow keys (3D view; the 2D board has its own when focused) |
| Select a piece / play to the highlighted square | Cross | Enter / Space, or click |
| Cancel the selection | Circle | Esc |
| Jump to the next piece of the side to move | Triangle | |
| Step through the legal destinations | L1 / R1 | |
| Switch between board cursor and the toolbar buttons | Options | |

* Navigation is shown only once a pad (or navigation keys) has been used; moving the mouse switches it off again.
  Focus is never lost: when a page is rebuilt, a dialog opens or a focused button is disabled, the next control is focused.
  The capture-preview overlay and dialogs keep focus inside themselves.
* **Hot-seat whose pad?** Battle Chess: the pad assigned to the side to move (White = Player 1, Black = Player 2). With a
  single pad connected that pad plays both sides. Classic: either pad can play whoever's turn it is.
* **Promotion**: the existing dialog opens with focus on Queen; D-pad moves, Cross chooses, Circle cancels. (The board
  cursor also has its own Queen/Rook/Bishop/Knight picker for hosts without a dialog; the app uses the dialog.)
* During a fight the menu navigation steps aside completely (Cross is dodge there and must never also press a button);
  0.8 s after the fight ends the result / "Return to board" button gets the focus.
* Text entry (account name, FEN, invite code) needs a keyboard; the pad can reach the fields but not type.

## Who is Player 1 / Player 2 (local battles)

`InputAssignment` resolves the two local seats (White / Black):

1. The seats are **locked when a fight starts**, so a pad that drops mid-fight keeps its seat.
2. Claims from "Press any button to join" (test-arena menu and Controls screen): the first controller (or keyboard set,
   any key of its map) to press becomes Player 1, the next Player 2.
3. Preferences from the Controls screen (Automatic, Keyboard 1, Keyboard 2, first / second controller).
4. Automatic: connected pads sorted by device id, first = Player 1, second = Player 2; a seat without a pad gets its
   keyboard (Player 1 kb1, Player 2 kb2). With no pad at all it is exactly the old kb1 / kb2 behaviour.

**A pad that disconnects mid-fight**: that seat goes neutral, the arena's tick is frozen (the fight is exactly where it
was), a banner explains it, and the fight resumes when the same device id returns (unplug / replug, battery swap) or when
any button (except Options) is pressed on another controller that is not the opponent's: it takes the seat over. Nothing is
ever left frozen or crashed (tested with both pads dropping at once and the guard being freed while holding).

## Rebinding (Settings -> Controls & controllers, or "Controls..." in the test arena)

* Select a row, press the new key / pad button / trigger. Esc cancels; a pad capture also times out after 6 s.
* A key already used in the same set is **swapped** with the action you are changing; a key used by the other player's set is
  **refused** with an explanation; Esc and F11 (menus / fullscreen) and Options (pause) cannot be bound; sticks cannot be bound;
  duplicates are never left in place. Pad rows can be cleared (unbound).
* Pad tuning: stick dead zone, response curve, camera speed, trigger press point, invert camera X / Y (shared by all pads).
* Everything saves immediately to `user://controls.json` (Windows: `%APPDATA%\Godot\app_userdata\Peepeechess\controls.json`).
  Versioned (`"version": 1`), validated on load: a bad entry falls back to its default (and is listed in `warnings`); a
  section with duplicate bindings is restored to defaults; a corrupt / hostile / oversized / future-version file loads the
  defaults and is moved to `controls.json.corrupt` (never silently overwritten); a missing file is simply the defaults.
* Mouse buttons for Player 1 (left = light, right = heavy, middle = lock-on, wheel = zoom, mouse look) are fixed.

## Files

| File | Role |
| --- | --- |
| `combat/input/control_bindings.gd` | bindings, defaults, validation, conflicts, persistence, hint strings |
| `combat/input/input_assignment.gd` | seats, join flow, hot-plug, mid-fight lock |
| `combat/input/controller_glyphs.gd` | DS4 / DualSense / Xbox / Switch detection and button names |
| `combat/input/pad_math.gd` | dead zone / response / trigger hysteresis (pure functions) |
| `combat/input/pad_hold.gd`, `join_prompt.gd` | pause-on-disconnect guard, "press any button" overlay |
| `combat/presentation/local_input_source.gd` | reads the bindings; per-device pad events and polling |
| `boards/board_pad_cursor.gd` | board cursor (uses only `BoardInteraction`) |
| `ui/pad_ui.gd` | menu focus guard, ui_* actions for Cross/Circle/L1/R1, Circle = back |
| `ui/controls_screen.gd` | the rebinding screen |

Hooks in shared (Codex-owned) files: one `PadUi.install(...)` call in `ui/application.gd`, `app/main.gd` and
`network/client/online_lobby.gd`; a "Controls & controllers..." button and a Circle-back handler in `ui/application.gd`;
seat schemes from `InputAssignment` + `PadHold` in `app/battle_combat_adapter.gd`; the lobby's "Gamepad 1" option picks the
first connected pad. `project.godot` is **not** changed: `PadUi` adds the missing joypad events to `ui_accept`, `ui_cancel`,
`ui_focus_next` and `ui_focus_prev` at runtime (for any device id).

## Tests

`godot --headless --path godot --script res://combat/tests/test_runner.gd -- pads` (about 45 s): maths and trigger hysteresis,
glyph detection from joy names / GUIDs, bindings (defaults, edits, conflicts, persistence round trip, corrupt files,
partially invalid files), assignment (deterministic order, preferences, join flow, disconnect / reconnect / take-over),
hints, a real `CombatArena` fight driven by two pads (every action, exact press counters, no cross-talk, foreign devices
ignored, keyboard ignored by pad seats, Options), hot-plug mid-fight, a rebound map and tuned stick in a real fight,
kb1 + kb2 at once, the board cursor (select, legal moves, confirm, cancel, per-turn pad ownership, view rotation, stick
repeat, promotion picker), the real application scene (focus never lost while navigating, Cross / Circle), the controls
screen (rebinding with keys and pad buttons, conflicts, persistence, reset), and the real board screen (hot-seat game with
two pads, promotion dialog, Options toggle, Battle Chess strict turns and overlay focus scope).

What is simulated: every controller event (injected, with a device id) and every "connected pads" fact
(`InputAssignment.connected_provider`, `ControllerGlyphs.fake_devices`). What is real: Godot's Input/InputMap/GUI
pipeline, the real `CombatArena` / simulation, the real application scenes.

## Known limits / not verified

* No physical DS4, DualSense, Xbox or Switch pad was tried. Not verified: DS4Windows / Steam Input / Bluetooth behaviour,
  real stick and trigger ranges and calibration drift, rumble (not implemented), battery-swap reconnects, device-id reuse
  rules on Windows, how Godot orders pads when several are plugged in (we only sort by id).
* A reconnecting pad that comes back under a different device id needs a button press to take its seat back (by design).
* Pad tuning (dead zone, camera speed, invert, trigger point) is shared by all pads, not per player.
* Stick menu navigation uses Godot's `ui_*` actions: holding the stick does not auto-repeat in menus (the board cursor does).
* Pads cannot type text; 3D board orbit / zoom stays on mouse and touch.
* In Battle Chess (inside the application) Options does nothing during a fight (the arena has no pause there); in the test
  arena it returns to the menu.
* `AcceptDialog` closes only on the Escape key in Godot 4.6.3 (observed), so `PadUi` closes dialogs itself on Circle.
