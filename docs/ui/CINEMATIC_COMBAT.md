# Cinematic combat presentation

Presentation only: no simulation number, tick or wire-contract field changes. Code: `godot/combat/presentation/vfx/combat_vfx.gd`,
`third_person_camera.gd`, `combat_hud.gd`.

Already there before this pass: hit sparks and impact flashes, hit-stop, camera trauma shake / punch / FOV kick, trails, ability auras,
finish orbit on the winner. Added:

- **Knockout slow motion.** The blow that kills spawns a bigger burst and ring, a 5-frame freeze, a heavy camera punch (`final`) and
  `Engine.time_scale = 0.3` for 0.55 real seconds. Only local fights in a real window (`allow_slowmo`, set by the arena); never headless,
  never online (the server clock cannot be slowed), never with `--reduce-motion`. Restored by a real-time timer, on `reset_effects` and in
  `_exit_tree`.
- **Parry.** A ground shockwave ring under the parrier and a longer FOV zoom-in (-6 deg held 0.28 s) so the perfect parry reads.
- **Dodge afterimages.** Faint role-tinted ghosts along the roll path.
- **Defeat.** Embers rising and a ground ring at the defeated fighter(s) when the result arrives.
- **Opening.** The third-person camera starts 3.2 m further out and glides in over 3 s (smoothstep) during the countdown; the HUD fades in a
  "QUEEN vs PAWN / the attacker strikes first" card.
- Tests: `polish` suite, `_test_cinematics` (intro text, push-in, slow-motion safety and restoration, final feedback).

Limits: seen only in software-GL screenshots (`victory-and-impact.png`), not on a real GPU; slow motion has never run in a real window; no new
audio (another pass), no per-role intro cards, no victory title animation beyond the existing result panel.
