# Opening-board paladins

These lightweight, static GLBs are posed and decimated copies of the six existing `godot/assets/paladins/*.glb` characters. The opening scene applies the same white/black team textures at runtime. They have no skeleton or animations; the actual game continues to use the original rigged models.

Regenerate with Blender 4.3.2 from the repository root (no random seed):

```sh
for role in pawn knight bishop rook queen king; do
  blender -b -t 2 --python tools/paladins/build_opening_statue.py -- "$role"
done
```

Each mesh targets at most 5,000 triangles. The Godot importer must then run to rebuild its cache.
