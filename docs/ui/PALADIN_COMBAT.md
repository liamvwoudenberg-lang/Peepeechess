# Paladin fighters (combat presentation)

The six rigged paladin models (`godot/assets/paladins/*.glb`, white/black texture variants in `textures/`) are the fighters in
Battle Chess duels, in the arena and in the pit world. Rules, simulation, balance and the wire contract are untouched: this is
presentation only.

## How it fits
* `PaladinFighter` (`godot/paladins/paladin_fighter.gd`) **is a `CharacterModel`**: the arena, VFX, hitstop, flinch, flash,
  stowable weapon and trail code treat it like the old Blender characters. `CombatArena` picks it when
  `PaladinFighter.prefer_paladins` is true (the default; the combat test runner switches it off for the old suites, `paladins_on`
  switches it on for chosen suites). The old characters remain the fallback when a model file is missing.
* White / black version = the fighter's side colour (`f.color`).
* `PaladinClips` (`godot/paladins/paladin_clips.gd`) authors every clip the GLBs lack **procedurally at run time** on the Mixamo
  skeleton: idle, light_1..3, heavy, block, parry, dodge, stagger, hit_react_light/heavy, ability, defeat, victory, climb,
  ladder_idle, drop_fall. walk/run/strafe come from the models' own Walking/Running clips (strafe = the walk clip, foot-locked
  to the sideways speed). Poses are keyframes of rotation deltas in skeleton space converted per bone, so they do not depend on bone axes.
  Every clip has a track for every bone (otherwise a bone keeps the previous clip's pose).
* The strike pose sits at 36% of each attack clip; `PaladinFighter._remap_clip_time` maps the simulation's hit window
  (`startup_end`) onto it, so the blow lands exactly when the hit window opens (tested).
* The models carry no weapon: a plain procedural longsword is attached to the right hand (`WeaponSocket_R`), stowed for the ladder climb.
* The pit climb: every role climbs with the compact procedural clip and slims by a few percent while climbing so the broad armour fits the
  1 m shaft (`pit_climb` suite green with paladins).
* Per-role heights: `PaladinFighter.HEIGHTS` (the supplied models are all 1.7 m).

## Rough edges (be honest)
* All of it is hand-keyed in code and judged in software-GL screenshots (`clips-contact-sheet.png`: idle, light_1, heavy, defeat per role).
  It reads as a fight but it is far from mocap quality: arm swings are simple arcs, the idle is a breathing sway, strafing is the walk clip,
  the block holds the sword hanging, parry/dodge are short stylised poses. Nobody has seen it on real hardware.
* The sword is a box mesh; the left hand carries nothing.
* The Mixamo rigs differ (Rook 36 joints, others 66-74): missing finger bones are skipped.
* Tools: `combat/tools/paladin_strip.gd` (renders clip strips), `paladin_bones.gd` (dumps a skeleton), `paladin_sheet.gd`.
* Tests: suite `paladins` (264 checks: clips, sockets, textures, strike remap, a real arena fight with no fallback clip).
