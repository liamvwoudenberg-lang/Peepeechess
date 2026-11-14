extends SceneTree
## Offline decimation of the Meshy courtyard fortress (1.25M triangles) to a game-sized mesh.
##
##   godot --headless --path godot --script ../tools/environment/decimate_fortress.gd -- <source.fbx> <out.res> [triangles]
##
## (run with the source FBX inside the project, e.g. godot/assets/environment/courtyard_fortress/).
## Uses Godot's meshoptimizer-backed SurfaceTool.generate_lod, which only removes triangles/vertices
## of the source mesh (UVs and normals stay exact, so the 4096 px atlas still lines up), then compacts
## the vertex arrays and stores the result as a binary mesh with its own LOD chain.
const DEFAULT_TRIANGLES := 76000

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var source: String = args[0] if args.size() > 0 else "res://assets/environment/courtyard_fortress/Meshy_AI_castle_courtyard_fortress_20261114_image-to-3d-texture.fbx"
	var out: String = args[1] if args.size() > 1 else "res://assets/environment/courtyard_fortress/fortress_decimated.res"
	var target := int(args[2]) if args.size() > 2 else DEFAULT_TRIANGLES
	var root := (load(source) as PackedScene).instantiate() as Node3D
	get_root().add_child(root)
	var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	var xf := root.global_transform.affine_inverse() * mi.global_transform
	var material := mi.mesh.surface_get_material(0)
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents = arrays[Mesh.ARRAY_TANGENT]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	print("source: %d vertices, %d triangles" % [verts.size(), indices.size() / 3])
	var st := SurfaceTool.new()
	st.create_from(mi.mesh, 0)
	var lod := st.generate_lod(1.0, target * 3)
	print("after generate_lod: %d triangles" % [lod.size() / 3])
	# Compact to the used vertices and bake the model transform (the FBX root carries a 100x unit scale).
	var remap := {}
	var new_v := PackedVector3Array()
	var new_n := PackedVector3Array()
	var new_uv := PackedVector2Array()
	var new_i := PackedInt32Array()
	var basis := xf.basis.inverse().transposed()
	for index in lod:
		if not remap.has(index):
			remap[index] = new_v.size()
			new_v.append(xf * verts[index])
			new_n.append((basis * normals[index]).normalized())
			new_uv.append(uvs[index])
		new_i.append(remap[index])
	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = new_v
	out_arrays[Mesh.ARRAY_NORMAL] = new_n
	out_arrays[Mesh.ARRAY_TEX_UV] = new_uv
	out_arrays[Mesh.ARRAY_INDEX] = new_i
	# Tangents from the surviving triangles (the normal map needs them).
	var tan := SurfaceTool.new()
	tan.create_from_arrays(out_arrays)
	tan.generate_tangents()
	out_arrays = tan.commit_to_arrays()
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, out_arrays, [], {}, material, "fortress")
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	var err := ResourceSaver.save(mesh, out, ResourceSaver.FLAG_COMPRESS)
	print("saved %s (err %d): %d vertices, %d triangles, aabb %s" % [out, err, new_v.size(), new_i.size() / 3, str(mesh.get_aabb())])
	quit(0 if err == OK else 1)
