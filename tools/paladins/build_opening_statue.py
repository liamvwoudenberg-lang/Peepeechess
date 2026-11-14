"""Build a lightweight posed opening-screen mesh from a shipped paladin GLB.
Run: blender -b -t 2 --python tools/paladins/build_opening_statue.py -- pawn
The game supplies its existing team texture at runtime. Blender 4.3.2; no random seed.
"""
import bpy, os, sys
role = sys.argv[sys.argv.index('--') + 1]
root = os.getcwd()
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=os.path.join(root, 'godot/assets/paladins', role + '.glb'))
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
mesh = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
walk = next((a for a in bpy.data.actions if a.name.startswith('Walking_')), None)
if walk:
    rig.animation_data_create(); rig.animation_data.action = walk
bpy.context.scene.frame_set(0)
bpy.ops.object.select_all(action='DESELECT'); mesh.select_set(True); bpy.context.view_layer.objects.active = mesh
# Bake the current skinned pose, then reduce geometry while retaining UVs.
bpy.ops.object.convert(target='MESH')
mesh.data.calc_loop_triangles()
count = len(mesh.data.loop_triangles)
if count > 5000:
    mod = mesh.modifiers.new('OpeningLOD', 'DECIMATE'); mod.ratio = 5000.0 / count
    bpy.ops.object.modifier_apply(modifier=mod.name)
mesh.data.materials.clear()
plain = bpy.data.materials.new('TeamTexture'); plain.diffuse_color = (1,1,1,1)
mesh.data.materials.append(plain)
mesh.parent = None
bpy.ops.export_scene.gltf(filepath=os.path.join(root, 'godot/assets/paladins/opening', role + '.glb'), export_format='GLB', use_selection=True, export_animations=False)
