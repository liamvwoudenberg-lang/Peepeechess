# UI overlap audit

"The UI overlaps sometimes." This page records what was looked for, what was found, what was fixed, and the regression test that keeps it fixed.

Everything here was measured in a Linux sandbox: headless Godot 4.6.3 for the numbers, software GL (Xvfb, llvmpipe) for the pictures. No real
phone, tablet, touch screen or GPU was involved, so frame timing and font rendering on a device may differ.

## What the audit does

`godot/tests/ui/ui_overlap_test.gd` (probes in `overlap_check.gd`) opens every application page, the chess screen, its dialogs and a whole battle,
and walks the control tree of each. For every screen it asserts that

* no two **visible content controls** (buttons, inputs, sliders, bars, labels with text) intersect by more than 3 px in both axes; a control inside
  a scroll area only counts where it is actually visible, and a label that does not wrap only counts where its text is;
* nothing sticks out of the window outside a scroll area, has no size, or is smaller than its text needs;
* no pointer / touch target is smaller than 40 px;
* toasts (which float over the page on purpose) stay inside the window, never overlap each other and never swallow a click.

It runs at 1280x800 (the design size), 800x480, 540x960 (phone, portrait), 2400x1080 (wide phone) at 100 % UI scale and at 150 % (the largest the
settings page allows; it is the setting that makes the logical window as small as 853x533), plus the pit-world battle at three of those.
`--full` adds 1920x1080, 1024x600 and 640x360 (the project minimum). The probes are themselves tested on a rig with a known overlap, a wide label
next to a button (not an overlap), a scrolled-out row (not visible) and a button hanging off the window.

```
godot --headless --path godot --script res://tests/ui/ui_overlap_test.gd -- --report            # default matrix, print every finding
godot --headless --path godot --script res://tests/ui/ui_overlap_test.gd -- --full --only=play   # everything, only scenarios containing "play"
xvfb-run -a -s "-screen 0 2560x1440x24" godot --path godot --rendering-driver opengl3 \
    --script res://tests/ui/ui_overlap_test.gd -- --shots=/some/dir --sizes=1280x800 --scales=1.5   # one PNG per scenario
```

It also runs as part of `npm run test:ui`.

## Scenarios

Home (with and without the opening screen), Play (classic / battle, local / computer / king's last stand / online signed in and out, with an
invite pending), Friends (full list with long names; signed out), Profile, History, Leaderboard, Settings, Account, the Controls screen, the
result dialog, toasts; the chess screen in 2D and 3D, classic, untimed, against the computer, Battle and King's last stand, each after a 26-move
opening, with the New game, promotion, draw and position dialogs; the legacy full-screen capture overlay; and one whole battle in the pit world:
capture card, trapdoor drop, countdown, fight (combat HUD) and result.

## Found and fixed

| # | Where | When | Cause | Fix |
| --- | --- | --- | --- | --- |
| 1 | Promotion dialog (chess screen) | every size | the four piece buttons were added straight to the dialog, so they were laid **over** its built-in line "Your pawn has reached the final rank." (4 overlaps, all sizes) | text and buttons in one `VBoxContainer` (`app/main.gd`, same fix the New game dialog already had) |
| 2 | Combat HUD, two bar panels and the round timer | any viewport narrower than about 850 px: the 1280x800 window already shows it ("77Pawn (Black)"), and 150 % UI scale or a phone makes it worse | each panel is a fixed 360 px wide at fixed x, so the two panels and the 34 px timer ran into each other and the names were cut | `CombatHud.panel_width()`: panels shrink so 90 px stay free in the middle, text shrinks with them (`combat/presentation/combat_hud.gd`) |
| 3 | Combat result panel | viewport narrower than 470 px (150 % UI scale, phone) | a 30 px headline in an unwrapped label, wider than the screen, clipped on both sides; and the panel was centred while still empty, so once its text wrapped it hung below the middle | wraps, font 30 / 24 / 19 px by width, centred by a `CenterContainer` |
| 4 | Battle overlay buttons "Acting player resigns" and "Skip animation" | every size; in a portrait layout they sat on the "Animate moves" toggle | the footer was pinned 64 px tall to the bottom of the screen and the buttons stretched to fill it, covering the status line, the toggle and the corner of the board panel | the buttons keep their natural height and sit in the visible bottom-left corner of the board panel, wherever that is (`_place_battle_footer()` in `app/main.gd`) |
| 5 | Capture preview card over the live board and HUD | 150 % UI scale / any window under about 900 logical px | the card (280 px) floats over the board and the right-hand player panel, whose text ran into the card text | a dim scrim behind the card (it also stops clicks on the toolbar underneath) (`app/main.gd`, `battle_scrim`) |
| 6 | Friends list presence chips ("Online", "In a match", "Offline") | rows with two or three lines, narrow widths | the chip stretched to the row's height and turned into a tall oval pressing on the neighbouring rows | `Kit.chip` keeps its own height (`ui/theme/ui_kit.gd`) |
| 7 | Computer opponent difficulty buttons 1-6 | every size | 34 px wide, below the 40 px pointer minimum (touch: 48 px) | 44x44 minimum (`ui/opponent_ui.gd`) |
| 8 | Combat result panel buttons "Rematch" and "Menu" | every size | 31 px tall | 44 px (`combat_hud.gd`) |
| 10 | F1 controls legends (`control_overlay.gd`) | portrait phone, fresh preferences (both legends expanded) | two full legends are ~340 px each: in a 760 px viewport the right one hung off the edge and the pair overlapped | legends are pulled inside the viewport and the type shrinks (down to 10 px) until the pair fits |
| 9 | Combat HUD one-line controls hint | every size | positioned at y = -92 from the **top** of the viewport, i.e. off screen, and 1015 px wide at 150 % | hidden: the F1 controls cheat sheet shows the same information (`combat_hud.gd`) |

Pictures (software GL, so the 3D scenes look flat; only the layout matters):

| | before | after |
| --- | --- | --- |
| battle HUD at 150 % UI scale | `before-hud-150.png` | `after-hud-150.png` |
| result text at 150 % UI scale | `before-result-150.png` | `after-result-150.png` |
| bottom buttons covering the status line, 1280x800 | `before-footer-100.png` | `after-footer-100.png` |
| capture card over the HUD at 150 % | `before-card-150.png` | `after-card-150.png` |
| friends list, phone portrait at 150 % | `before-friends-540x960.png` | `after-friends-540x960.png` |
| promotion dialog | not captured before the fix | `after-promotion-dialog.png` |

## Looked at and left as it is

* **Toasts** cover part of the page for about 3 seconds (at most three at a time, bottom centre). That is what a toast is. They never block input
  (every part ignores the mouse), stay inside the window and do not overlap each other; the test enforces exactly that.
* **Chess screen at 150 % UI scale in landscape** (logical window 853x533): the body is taller than the window (the player panel needs about 600
  px), so it scrolls, and the board panel is as tall as the body. The bottom ranks of the board, and the lower part of a battle (the result
  panel's "Rematch / Menu" buttons in the test arena) are below the fold until you scroll. Nothing overlaps; it is cramped. A board panel that
  fits the visible height would fix it and is a layout change of its own.
* **Control cheat sheet during the 0.3 s fade-out** while the result text appears: they briefly overlap while fading. The audit waits for the fade.

## Not covered

Online combat (`OnlineCombatView`, touch control layer, split-screen cameras), the pad pointer, the pad-menu overlays and a real device's safe
areas (the layout test simulates a notch). The combat HUD's text is checked inside its own SubViewport (its rects are in that viewport's
coordinates), not against what the page's scroll area shows of it. The audit cannot see text that a control draws itself (the combat HUD bars): its width rule is
unit-tested instead, and the pictures were checked by eye.
