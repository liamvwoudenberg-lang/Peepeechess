# Keyboard and mouse controls (PC)

The combat controls on PC are **profiles**: ready-made layouts you pick in **Settings > Controls & controllers**, then rebind
freely. Pad and touch controls are unchanged.

## Profiles

| Profile | Who it is for | Left hand | Right hand / mouse |
|---|---|---|---|
| **Souls: keyboard + mouse** (default for new players) | One player with a mouse | `WASD` move, `Shift` sprint (tap = dodge), `Space` dodge, `F` parry, `R` ability, `X` lock-on, `Q` / `E` orbit the free camera | Mouse look. `LMB` light (hold = heavy), `Alt + LMB` heavy, `Mouse 5` heavy, `RMB` block (hold) and a quick tap parries, `MMB` lock-on / free camera, `Mouse 4` ability, wheel zoom |
| **Souls: two hands, keyboard only** | One player, no mouse | `WASD` move, `Shift` sprint (tap = dodge), `Space` dodge | `U` light, `O` heavy, `P` block (hold), `;` parry, `'` ability, `Enter` lock-on, `J` / `L` orbit, `I` / `K` tilt |
| **Classic (WASD + mouse)** | The original layout | `WASD`, `F` light, `G` heavy, `Q` block, `E` parry, `R` ability, `Tab` lock, `Z` / `X` orbit | `LMB` light, `RMB` heavy, `MMB` lock, wheel zoom |
| **Two players: left half / right half** | Two players on one keyboard | Player 1: the Classic keys without the mouse | Player 2: arrow keys, `J K L U I O P`, `,` `.` |

`Esc` (pause), `F1` (controls overlay) and `F11` (fullscreen) are reserved and cannot be bound.

A Souls profile is for **one** local player (the mouse belongs to Player 1). In a two-player match on one keyboard use the two
"Two players" halves, or give the second seat a gamepad. Choosing a profile that reuses keys of the other keyboard set unbinds
those keys there and tells you which ones.

## Ergonomic rule

Every profile keeps each hand on its own side of the keyboard (the tests check this against a standard ANSI layout):

* Souls keyboard + mouse: all keyboard inputs are within the **left hand's** reach; the right hand stays on the mouse.
* Souls keyboard only: movement, sprint and dodge on the **left**; every other action on the **right** (`I J K L U O P ; ' Enter`).
* Two players: Player 1 only uses the left half, Player 2 the right half (Player 2's sprint is Ctrl).

## Rebinding

Open **Settings > Controls & controllers**. For each keyboard set:

* **Control profile**: pick a layout; **Reset this keyboard set to its profile defaults** restores it (keys, mouse buttons and options).
* Every action has a main binding and (for sprint, light, heavy, dodge, block, parry, ability, lock-on) an **alternate** row.
  Select a row and press a key. For Player 1 you can also click a **mouse button** (left, right, middle, Mouse 4 / 5) or turn
  the **wheel**. Movement and camera keys must stay keyboard keys. **Clear** unbinds a row.
* A clash with another action in the same set swaps the two; a clash with the other player's keys is refused and explained.

### Options (per keyboard set)

| Option | Meaning |
|---|---|
| Mouse look speed (Player 1) / Camera speed | Multiplies mouse look and the camera keys |
| Invert camera left/right, up/down | Flips the camera direction |
| Block while held | Off = a press toggles block |
| Hold the light attack button for a heavy attack | Past the threshold (default 200 ms) the press becomes a heavy; a quick tap is a light that fires **on release** |
| Alt + light attack = heavy | Immediate heavy |
| A quick tap of the block button also parries | Within the parry tap time (default 160 ms) |
| A quick tap of sprint dodges | Within 200 ms; holding sprints |
| Hold the lock-on button to free the camera | Off = a press toggles lock-on |

Settings are saved in `user://controls.json` (profile, bindings, mouse codes written as `"mouse:N"`, options). Older files
without profiles load as the Classic layout.

## Hints

The combat HUD line, the **F1 controls overlay** and the Training screen show the inputs of the active profile, including
mouse-button names (`LMB`, `RMB`, `MMB`, `Mouse 4`, `Mouse 5`, `Wheel up/down`) and the tap / hold modifiers.

## What changed technically

`ControlBindings` gained profiles, alternate bindings (mouse codes are negative integers), per-set options and the
`look_up` / `look_down` camera keys; `LocalInputSource` handles tap / hold decisions with an injectable millisecond clock.
It still only produces the same intent packets and press counters as before: the simulation, balance and online contract are
untouched. Tests: `combat/tests/test_keybinds.gd` (suite `keybinds`).
