import bpy, math, sys, os
args = sys.argv[sys.argv.index("--")+1:]
role = args[0]
clip = args[1] if len(args) > 1 else "Sword_slash"
project = os.getcwd()
from mathutils import Matrix

pawn=os.path.join(project, 'godot/assets/paladins', role + '.glb')
source=os.path.join(project, 'tools/paladins/animation_source/' + clip + '.glb')
out='/tmp/pp_retarget_' + role + '_' + clip + '.glb'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=source)
source_objects={o.name:o for o in bpy.context.scene.objects}
# Preserve the transforms in the source file, before evaluating its action.
for o in source_objects.values():
 if o.animation_data and o.animation_data.action:
  o.animation_data.action=None
bpy.context.view_layer.update()
rest={n:o.matrix_world.to_quaternion().copy() for n,o in source_objects.items()}
# The GLB importer creates one action per animated node.
for n,o in source_objects.items():
 a=bpy.data.actions.get(clip+'_'+n)
 if a:
  o.animation_data_create(); o.animation_data.action=a
bpy.ops.import_scene.gltf(filepath=pawn)
target=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
# Keep original imported animations as NLA strips, then create one new action.
if target.animation_data:
 target.animation_data.action=None
 for t in target.animation_data.nla_tracks: t.mute=True
mapping={'Hips':'pelvis','Spine':'spine_01','Spine1':'spine_02','Spine2':'spine_03','Neck':'neck_01','Head':'Head'}
for side,suffix in [('Left','l'),('Right','r')]:
 mapping.update({side+'Shoulder':'clavicle_'+suffix,side+'Arm':'upperarm_'+suffix,side+'ForeArm':'lowerarm_'+suffix,side+'Hand':'hand_'+suffix,side+'UpLeg':'thigh_'+suffix,side+'Leg':'calf_'+suffix,side+'Foot':'foot_'+suffix,side+'ToeBase':'ball_'+suffix})
 for finger,src in [('Thumb','thumb'),('Index','index'),('Middle','middle'),('Ring','ring'),('Pinky','pinky')]:
  for i in range(1,4): mapping[side+'Hand'+finger+str(i)]=src+'_%02d_'%i+suffix
bones=[]
for b in target.data.bones:
 key=b.name.removeprefix('mixamorig:')
 if key in mapping and mapping[key] in source_objects:
  bones.append((b,mapping[key]))
def depth(b):
 d=0
 while b.parent: b=b.parent; d+=1
 return d
bones.sort(key=lambda x:depth(x[0]))
print('Mapped',len(bones),'bones')
action=bpy.data.actions.new('CC0_Retargeted')
end_frame = math.ceil(max((a.frame_range[1] for a in bpy.data.actions if a.name.startswith(clip+'_')), default=0))
target.animation_data_create(); target.animation_data.action=action
for frame in range(0, end_frame + 1):
 bpy.context.scene.frame_set(frame)
 for bone,src in bones:
  pb=target.pose.bones[bone.name]
  delta=source_objects[src].matrix_world.to_quaternion() @ rest[src].inverted()
  desired=delta @ bone.matrix_local.to_quaternion()
  current=pb.matrix.copy()
  m=desired.to_matrix().to_4x4(); m.translation=current.translation
  pb.matrix=m
  pb.rotation_mode='QUATERNION'; pb.keyframe_insert(data_path='rotation_quaternion',frame=frame,group=bone.name)
  bpy.context.view_layer.update()
# Restore original tracks for export and add the newly baked action as its own strip.
target.animation_data.action=None
for t in target.animation_data.nla_tracks: t.mute=False
track=target.animation_data.nla_tracks.new(); track.name='CC0_Retargeted'; track.strips.new('CC0_Retargeted',0,action)
# Select the imported target asset and its descendants, not the source rig.
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.context.scene.objects:
 if o==target or (o.type=='MESH' and any(m.type=='ARMATURE' and m.object==target for m in o.modifiers)):
  o.select_set(True)
bpy.context.view_layer.objects.active=target
bpy.ops.export_scene.gltf(filepath=out,export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS')
print('WROTE',out)
