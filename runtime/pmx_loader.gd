class_name HonkaiPMXLoader
extends RefCounted

var error := ""
var _images := {}
var _pixel_count := 0


func load_file(path: String, archive: Dictionary = {}) -> Dictionary:
	error = ""
	_images.clear()
	_pixel_count = 0
	if not ClassDB.class_exists("NativePmxReader"):
		var status := GDExtensionManager.load_extension("res://native/mocap.gdextension")
		if status not in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED]:
			error = "原生 MMD 加载组件不可用。"
			return {}
	var reader = ClassDB.instantiate("NativePmxReader")
	var data = reader.read_file(path)
	if not data is Dictionary:
		error = "PMX 读取失败：" + str(reader.get_error())
		return {}
	if archive.is_empty():
		var folder := path.get_base_dir()
		for depth in 16:
			var index := folder.path_join("archive_index.json")
			if FileAccess.file_exists(index):
				var value = JSON.parse_string(FileAccess.get_file_as_string(index))
				if value is Dictionary and str(value.get("cache_root", "")).simplify_path().to_lower() == folder.simplify_path().to_lower():
					archive = value
				break
			if folder == folder.get_base_dir():
				break
			folder = folder.get_base_dir()
	if archive.is_empty():
		error = "找不到模型的已验证压缩包索引，请重新导入完整 ZIP。"
		return {}
	var metadata: Dictionary = data.metadata
	var root_path: String = str(archive.cache_root).simplify_path()
	var textures: Array[Texture2D] = []
	var texture_paths: Array[String] = []
	for requested: String in data.textures:
		var resolved := _texture_path(requested, path.get_base_dir(), root_path, archive.get("aliases", {}))
		texture_paths.append(resolved)
		textures.append(_load_texture(resolved) if not resolved.is_empty() else null)
	var materials: Array[StandardMaterial3D] = []
	for entry: Dictionary in metadata.materials:
		entry.category = HonkaiMMDMaterials.classify_material(str(entry.source_name))
		entry.texture = ""
		entry.sphere_texture = ""
		var index := int(entry.texture_index)
		if index >= 0:
			if textures[index] == null and float(entry.base_color[3]) > 0.001:
				error = "模型贴图缺失或无法读取：%s。请使用包含全部贴图的原始压缩包。" % data.textures[index]
				return {}
			entry.texture = texture_paths[index]
		var sphere_index := int(entry.sphere_texture_index)
		if sphere_index >= 0:
			entry.sphere_texture = texture_paths[sphere_index]
		var material := StandardMaterial3D.new()
		material.resource_name = str(entry.name)
		var rgba: Array = entry.base_color
		material.albedo_color = Color(rgba[0], rgba[1], rgba[2], rgba[3])
		if index >= 0:
			material.albedo_texture = textures[index]
		material.vertex_color_use_as_albedo = false
		material.roughness = 1.0
		material.cull_mode = BaseMaterial3D.CULL_DISABLED if entry.double_sided else BaseMaterial3D.CULL_BACK
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if float(rgba[3]) < 0.99 else BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		materials.append(material)
	var model := Node3D.new()
	model.name = "MMDModel"
	var rig := Skeleton3D.new()
	rig.name = "MMDSkeleton"
	model.add_child(rig)
	rig.owner = model
	for bone: Dictionary in data.bones:
		rig.add_bone(str(bone.name))
	var tail_offsets := PackedVector3Array()
	for index in data.bones.size():
		var bone: Dictionary = data.bones[index]
		var position := _vector(bone.position)
		var parent := int(bone.parent)
		if parent >= 0:
			rig.set_bone_parent(index, parent)
			position -= _vector(data.bones[parent].position)
		rig.set_bone_rest(index, Transform3D(Basis.IDENTITY, position))
		tail_offsets.append(_vector(bone.get("tail_offset", [0, 0, 0])))
	rig.set_meta("pmx_tail_offsets", tail_offsets)
	rig.reset_bone_poses()
	var skin := rig.create_skin_from_rest_transforms()
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	for name: String in data.morph_names:
		mesh.add_blend_shape(name)
	var face_min := Vector3(INF, INF, INF)
	var face_max := Vector3(-INF, -INF, -INF)
	var triangles := 0
	for surface: Array in data.surfaces:
		if surface[1].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface[1]
		arrays[Mesh.ARRAY_NORMAL] = surface[2]
		arrays[Mesh.ARRAY_TEX_UV] = surface[3]
		arrays[Mesh.ARRAY_COLOR] = surface[4]
		arrays[Mesh.ARRAY_BONES] = surface[5]
		arrays[Mesh.ARRAY_WEIGHTS] = surface[6]
		arrays[Mesh.ARRAY_INDEX] = surface[7]
		var flags := 0
		for index in surface[9].size():
			arrays[Mesh.ARRAY_CUSTOM0 + index] = surface[9][index]
			flags |= (Mesh.ARRAY_FORMAT_CUSTOM0 << index) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << (Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT + Mesh.ARRAY_FORMAT_CUSTOM_BITS * index))
		var shapes := []
		var zeros := PackedVector3Array()
		zeros.resize(surface[1].size())
		for offsets: PackedVector3Array in surface[8]:
			var blend := []
			blend.resize(Mesh.ARRAY_MAX)
			blend[Mesh.ARRAY_VERTEX] = offsets
			blend[Mesh.ARRAY_NORMAL] = zeros
			shapes.append(blend)
		var previous_count := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes, {}, flags)
		if mesh.get_surface_count() != previous_count + 1:
			model.free()
			error = "Godot 无法创建完整 PMX 网格，已取消导入。"
			return {}
		mesh.surface_set_material(previous_count, materials[surface[0]])
		triangles += surface[7].size() / 3
		if metadata.materials[surface[0]].category == "face":
			for point: Vector3 in surface[1]:
				face_min = face_min.min(point)
				face_max = face_max.max(point)
	if triangles != int(metadata.triangle_count):
		model.free()
		error = "PMX 网格面数校验失败。"
		return {}
	var instance := MeshInstance3D.new()
	instance.name = "MMDMesh"
	instance.mesh = mesh
	instance.skin = skin
	model.add_child(instance)
	instance.owner = model
	instance.skeleton = instance.get_path_to(rig)
	var head := rig.find_bone(str(metadata.head.bone))
	if head >= 0 and face_min.is_finite() and face_max.is_finite():
		var origin := rig.get_bone_global_rest(head).origin
		metadata.head.half_width = maxf(0.005, (face_max.x - face_min.x) * 0.5)
		metadata.head.nose_height = (face_min.y + face_max.y) * 0.5 - origin.y
		metadata.head.face_bottom = face_min.y - origin.y
		metadata.head.face_top = face_max.y - origin.y
	metadata["source_pmx"] = path.trim_prefix(root_path + "/")
	metadata["archive_sha256"] = archive.get("sha256", "")
	return {"root": model, "metadata": metadata}


static func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


static func _inside(path: String, root_path: String) -> bool:
	return path.simplify_path().to_lower().begins_with(root_path.simplify_path().to_lower().trim_suffix("/") + "/")


static func _texture_path(requested: String, folder: String, root_path: String, aliases: Dictionary) -> String:
	var relative := requested.replace("\\", "/")
	var candidate := folder.path_join(relative).simplify_path()
	if not relative.is_absolute_path() and _inside(candidate, root_path):
		if FileAccess.file_exists(candidate):
			return candidate
		var key := candidate.trim_prefix(root_path + "/").to_lower()
		if aliases.has(key):
			var target := root_path.path_join(str(aliases[key])).simplify_path()
			if _inside(target, root_path) and FileAccess.file_exists(target):
				return target
	var matches := {}
	for alias: String in aliases:
		if alias.get_file().to_lower() == relative.get_file().to_lower():
			var target := root_path.path_join(str(aliases[alias])).simplify_path()
			if _inside(target, root_path) and FileAccess.file_exists(target):
				matches[target] = true
	return str(matches.keys()[0]) if matches.size() == 1 else ""


func _load_texture(path: String) -> Texture2D:
	if _images.has(path):
		return _images[path]
	var image := Image.new()
	if image.load(path) != OK or image.get_width() > 8192 or image.get_height() > 8192:
		return null
	_pixel_count += image.get_width() * image.get_height()
	if _pixel_count > 128000000:
		return null
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_images[path] = texture
	return texture
