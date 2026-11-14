# Paladin sword animation

The source GLBs come from the KinemIQ Free Animation Pack, based on Quaternius's Universal Animation Library. Both are distributed under CC0 1.0; see `LICENSE.txt` and https://quaternius.com/packs/universalanimationlibrary.html. No random seed is used.

To regenerate the role-specific animation resources from the existing paladin GLBs with Blender 4.3.2 and Godot 4.6.3, from the repository root:

```sh
for role in pawn knight bishop rook queen king; do
  for clip in Sword_slash Idle_with_a_sword Block_with_the_sword Dodge_roll Hit_to_the_chest Hit_knockback Death_fall_backwards; do
    blender -b -t 2 --python tools/paladins/retarget_sword.py -- "$role" "$clip"
  done
done
godot --headless --path godot --script ../tools/paladins/extract_sword.gd
```

The intermediate GLBs are written under `/tmp` and are not shipped. The extraction retimes source frame 10 of 37 to the existing 36% strike marker; `PaladinFighter` maps that marker to the simulation's attack startup end. This is an approximate visual contact point and should be reviewed in motion for every role. The current game sword is attached separately, and its models and hitboxes are unchanged.
