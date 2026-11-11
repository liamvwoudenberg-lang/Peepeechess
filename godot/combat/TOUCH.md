# Landscape touch controls (keyboard / gamepad bindings: see CONTROLS.md) (`touch_controls.gd`, `LocalInputSource` scheme `touch`)

Offline and online use the same control. It is a pure input device: it owns no gameplay and emits exactly the
intent that the keyboard/pad schemes do.

| Output | Meaning |
| --- | --- |
| `move_vector` | x right, y forward, length <= 1, screen/camera relative. `LocalInputSource` converts it to the world-space move vector with the camera heading (`heading(yaw) = (sin, 0, cos)`, `right = (-h.z, 0, h.x)`), like every other scheme. |
| `sprint` | stick pushed to the rim (enter 92 %, exit 80 % - hysteresis). |
| `block_held` | the BLOCK finger is down. |
| `action_pressed(action)` | one signal per tap: `light heavy dodge parry ability` (becomes one counter increment through `CombatInputBuilder`, or `CombatNetClient.press` online). |
| `lock_pressed` | toggles `camera.toggle_lock()`. |
| `pause_pressed` | `LocalInputSource.pause_requested` (the test arena returns to its menu). |
| `look_delta(px)` | camera drag; `add_look(dx * 4.5 / viewport_height, dy * ...)`. |

## Using it

* Scheme: `arena.configure_seats({"player-white": {"type": "human", "scheme": "touch"}})`. `LocalInputSource._ready()`
  creates a `CanvasLayer` (layer 20: above the HUD at 10, below menus at 50) holding the control, full rect.
  All existing fields (`scheme builder fighter camera submit mouse_look enabled net_client`) behave as before;
  `enabled = false` hides and releases the touch UI.
* Test arena: the menu has "P1 controls: Touch (landscape)"; it is auto-selected when
  `DisplayServer.is_touchscreen_available()` and can be forced with `-- --touch` (headless/desktop mouse is not touch:
  enable *Emulate touch from mouse* or use a device).
* Standalone: `preload("res://combat/presentation/touch_controls.gd").new()` on any `CanvasLayer`, connect the signals, read
  the properties. User knobs: `ui_scale` (clamped 9-16 % of the height per button unit), `opacity`, `haptics_enabled`,
  `ability_state` (read-only `Callable -> {cooldown, total, active}`; cosmetic grey/arc only, a press is still sent and the
  server decides).
* Haptics: `Input.vibrate_handheld` (guarded by `OS.has_feature("mobile")`): light tap 12 ms, hit 20 ms, parry 35 ms,
  guard break 80 ms (events from the authority simulation, only for this fighter).

## Finger rules (every finger is tracked independently by its touch index)

1. A touch that lands on a button (12 % hit slop, nearest centre wins) is **bound to that button until it lifts**. Dragging
   off a button neither releases nor repeats it; BLOCK is held while its own finger is down.
2. Action buttons fire once on press. Taps are never repeated by drags.
3. A touch in the left stick zone (left 40 % of the width, below 34 % of the height) is the **floating joystick**; its origin is
   where the finger landed. A second finger there is ignored.
4. Any other touch is the **camera finger** (drag = orbit; no two-finger gesture). One at a time.
5. Releasing one finger never changes another. `InputEventScreenTouch.canceled`, `NOTIFICATION_APPLICATION_FOCUS_OUT`,
   `WM_WINDOW_FOCUS_OUT`, `APPLICATION_PAUSED` and `enabled = false` release everything.
6. The control marks its handled touches as handled. Godot also synthesises `InputEventMouse*` from touch
   (`device == InputEvent.DEVICE_ID_EMULATION`, created before the handled flag matters), so `LocalInputSource._unhandled_input`
   drops every emulated mouse event.

## Layout (unit `d = 11.5 % of the height`, clamped 9-16 % with `ui_scale`; margin 3.5 % of the height)

Inside `DisplayServer.get_display_safe_area()` (mobile builds; scaled to the viewport). Circles, diameters at 1280x720 / 2400x1080:
LIGHT 108 / 161 px, BLOCK 103 / 154, ABILITY 99 / 149, HEAVY 96 / 144, DODGE and PARRY 91 / 137, LOCK and PAUSE 83 / 124,
stick base 182 / 274 (9 % minimum is 65 / 97 px). 1920x1080, 2560x1080 and 1600x720 use the same height-based sizes.
Right thumb arc around LIGHT (bottom-right); LOCK above HEAVY; PAUSE top-left below the HUD bars (`HUD_BOTTOM = 17.5 %`);
the central 30 % x 60 % of the screen is free.

## Verification

`godot --headless --path godot --script res://combat/tests/test_runner.gd -- touch` (97 checks): layout at 1280x720, 1920x1080, 2400x1080, 2560x1080 and 1600x720 with and without safe-area insets and four user
scales (no overlap, inside safe area, >= 9 % size, centre clear at scale <= 1.0, stick zone clear); dead zone, response curve, sprint
hysteresis; one counter per tap; simultaneous stick + block + camera + taps; all 6 release orders; cancel, focus loss, disabling;
ten fingers with random input; ability display; and a full `CombatArena` (AUTHORITY mode) fight driven only by injected
touch events through `Input.parse_input_event` (walks, light attack with exactly one server-side counter, block, lock, camera orbit,
emulated mouse ignored). Screenshots were taken and reviewed at 2400x1080 and 1280x720 (software GL under Xvfb).

**Not verified: no physical Android device was available.** Unverified: real multi-touch hardware behaviour and latency,
thumb comfort and button sizes in hand, real notch/cutout insets, `vibrate_handheld` feel, GPU/Android rendering and performance,
app-pause behaviour on a device, Godot's `emulate_mouse_from_touch` setting on Android exports.

## Android specifics (Codex-owned export/project files - not changed here)

* Export preset: **landscape** orientation (`screen/orientation = sensor_landscape` or `landscape`); project
  `display/window/handheld/orientation`.
* Keep `input_devices/pointing/emulate_mouse_from_touch = true` if desktop-mouse UI relies on it: the control does not need it
  and `LocalInputSource` ignores the emulated events. Keep `emulate_touch_from_mouse = false` in shipping builds.
* Enable the `VIBRATE` permission in the export preset for haptics; use `display/window/stretch/mode = canvas_items` with
  `aspect = expand` so the touch layer follows the screen shape (the layout uses the viewport size).
* Immersive/edge-to-edge is fine: the layout reads the display safe area.

## Known issues / adoption

* `arena.gd` (`_controls_hint`) now shows a touch hint (generated by `ControlBindings.hint_text("touch")`); the HUD help label may still sit under the touch area.
* Codex's online view can replace `OnlineTouchCombatInput` with `LocalInputSource` (`scheme = "touch"`, `net_client` set) or use
  `touch_controls.gd` directly; both emit the world-space intent. Ability presses are sent even on cooldown by design.
* Block releases when its own finger lifts (documented rule), so sliding a thumb off BLOCK keeps the guard up.
