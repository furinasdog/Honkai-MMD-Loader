class_name HonkaiMMDMaterials
extends RefCounted

const TOON: Shader = preload("res://plugins/honkai_mmd/render/toon.gdshader")
const OUTLINE: Shader = preload("res://plugins/honkai_mmd/render/outline.gdshader")
const CATEGORY := {"face": 0, "skin": 1, "hair": 2, "cloth": 3, "metal": 4, "eye": 5}

var materials: Array[ShaderMaterial] = []
var outlines: Array[ShaderMaterial] = []
var shadows_enabled: bool = true
var _head_bone := "頭"
var _head_index := -1
var _head_rest := Transform3D.IDENTITY
var _head_origin := Transform3D.IDENTITY
var _shader_variants := {}
var _edge_weights: bool = false
var use_pmx_outline_colors: bool = false
var _source_outline_colors: Array[Color] = []
var _game_outline_colors: Array[Color] = []
var _textures := {}
var _edge_weight_scale := 1.0


static func classify_material(name: String) -> String:
	var value := name.to_lower()
	if value in ["面", "颜", "顔", "顏"] or _contains(value, ["脸", "臉", "顔", "颜", "顏", "face", "facial"]):
		return "face"
	if value in ["目", "口", "舌", "齿", "齒", "歯"] or _contains(value, ["眼", "瞳", "眉", "睫", "白目", "目光", "目影", "口腔", "牙", "歯", "齿", "齒", "eye", "lash", "brow", "teeth"]):
		return "eye"
	if _contains(value, ["金属", "金屬", "metal"]):
		return "metal"
	if _contains(value, ["饰", "飾", "リボン", "ribbon", "bow"]):
		return "cloth"
	if _contains(value, ["发", "髪", "髮", "hair"]):
		return "hair"
	if _contains(value, ["衣", "裙", "服", "cloth", "dress", "coat", "glove", "套"]):
		return "cloth"
	if _contains(value, ["肌", "皮肤", "皮膚", "skin", "手", "腿", "body", "脖", "颈", "頸", "neck"]):
		return "skin"
	return "cloth"


static func _contains(value: String, words: Array) -> bool:
	for word: String in words:
		if word in value:
			return true
	return false


func apply(model_root: Node3D, metadata: Dictionary = {}) -> void:
	if model_root == null:
		return
	var parsed: Dictionary = metadata
	_edge_weights = bool(parsed.get("vertex_edge_weights", false))
	_edge_weight_scale = float(parsed.get("vertex_edge_scale", 1.0))
	_textures.clear()
	var head: Dictionary = parsed.get("head", {})
	_head_bone = head.get("bone", "頭")
	var by_name := {}
	for entry in parsed.get("materials", []):
		by_name[entry.name] = entry
	materials.clear()
	outlines.clear()
	_source_outline_colors.clear()
	_game_outline_colors.clear()
	_head_index = -1
	for node in model_root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var previous := instance.mesh.surface_get_material(surface)
			var surface_name: String = previous.resource_name if previous != null else str(surface)
			var entry: Dictionary = by_name.get(surface_name, {"name": surface_name, "category": "cloth", "texture": "", "base_color": [1.0, 1.0, 1.0, 1.0]})
			entry = entry.duplicate()
			entry.category = classify_material(str(entry.get("source_name", entry.name)))
			var material := _make_material(entry, head, previous)
			instance.set_surface_override_material(surface, material)
	var skeletons := model_root.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		update_head(skeletons[0] as Skeleton3D)


func update_head(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	if _head_index < 0:
		_head_index = skeleton.find_bone(_head_bone)
		if _head_index < 0:
			for alias in ["頭", "head", "Head", "mixamorig:Head"]:
				_head_index = skeleton.find_bone(alias)
				if _head_index >= 0:
					break
		if _head_index < 0:
			return
		_head_rest = skeleton.get_bone_global_rest(_head_index)
		_head_origin = Transform3D(Basis.IDENTITY, _head_rest.origin)
	# Remove rest-bone roll; the authored face field uses the model's +Y up, +Z forward axes.
	var head_world := skeleton.get_global_transform_interpolated() * skeleton.get_bone_global_pose(_head_index) * _head_rest.affine_inverse() * _head_origin
	var inverse := head_world.affine_inverse()
	for material in materials:
		material.set_shader_parameter("head_to_world", head_world)
		material.set_shader_parameter("world_to_head", inverse)


func set_shadows_enabled(enabled: bool) -> void:
	shadows_enabled = enabled
	for material in materials:
		material.set_shader_parameter("shadows_enabled", enabled)


func set_shadow_threshold(value: float) -> void:
	for material in materials:
		var kind: int = material.get_shader_parameter("category")
		var offset := -0.08 if kind == CATEGORY.hair else 0.0
		material.set_shader_parameter("shadow_threshold", clampf(value + offset, -0.5, 0.7))


func set_outline_width(pixels: float) -> void:
	for material in outlines:
		material.set_shader_parameter("outline_width", clampf(pixels, 0.0, 4.0))


func set_pmx_outline_colors(enabled: bool) -> void:
	use_pmx_outline_colors = enabled
	for index in outlines.size():
		outlines[index].set_shader_parameter("outline_color", _source_outline_colors[index] if enabled else _game_outline_colors[index])


func _make_material(entry: Dictionary, head: Dictionary, previous: Material) -> ShaderMaterial:
	var name: String = entry.get("source_name", entry.name)
	var kind: String = entry.get("category", "cloth")
	if not CATEGORY.has(kind):
		kind = "cloth"
	var rgba: Array = entry.get("base_color", [1.0, 1.0, 1.0, 1.0])
	var texture: Texture2D
	var texture_path: String = str(entry.get("texture", ""))
	if _textures.has(texture_path):
		texture = _textures[texture_path]
	elif previous is BaseMaterial3D and previous.albedo_texture != null:
		texture = previous.albedo_texture
	elif texture_path.begins_with("res://"):
		texture = load(texture_path) as Texture2D
	elif not texture_path.is_empty() and FileAccess.file_exists(texture_path):
		var source_image := Image.new()
		if source_image.load(texture_path) == OK:
			texture = ImageTexture.create_from_image(source_image)
	if texture == null and previous is BaseMaterial3D:
		texture = previous.albedo_texture
	if texture == null:
		var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		white.fill(Color.WHITE)
		texture = ImageTexture.create_from_image(white)
	if not texture_path.is_empty():
		_textures[texture_path] = texture
	var material := ShaderMaterial.new()
	material.resource_name = name
	material.shader = TOON
	var transparent := float(rgba[3]) < 0.99
	var double_sided := bool(entry.get("double_sided", previous is BaseMaterial3D and previous.cull_mode == BaseMaterial3D.CULL_DISABLED))
	var variant := int(transparent) + int(double_sided) * 2
	if variant != 0:
		if not _shader_variants.has(variant):
			var shader := Shader.new()
			var code := TOON.code
			if transparent:
				code = code.replace("ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;", "// Preserve original partial alpha.")
			if double_sided:
				code = code.replace("cull_back", "cull_disabled")
			shader.code = code
			_shader_variants[variant] = shader
		material.shader = _shader_variants[variant]
	if transparent:
		material.render_priority = 1
	material.set_shader_parameter("texture_albedo", texture)
	material.set_shader_parameter("shadows_enabled", shadows_enabled)
	# PMX diffuse and the baseline ramp are linear multipliers; Godot converts Color uniforms from sRGB.
	material.set_shader_parameter("base_color", Color(rgba[0], rgba[1], rgba[2], rgba[3]).linear_to_srgb())
	material.set_shader_parameter("category", CATEGORY[kind])
	material.set_shader_parameter("face_half_width", head.get("half_width", 0.0817))
	material.set_shader_parameter("nose_height", head.get("nose_height", 0.02770555))
	material.set_shader_parameter("face_bottom", head.get("face_bottom", -0.06))
	material.set_shader_parameter("face_top", head.get("face_top", 0.12))
	var shadow := Color(0.54, 0.51, 0.70)
	var ink := Color(0.15, 0.10, 0.23)
	var gain := Vector3.ONE
	if kind in ["face", "skin"]:
		shadow = Color(0.88, 0.49, 0.46)
		ink = Color(0.46, 0.20, 0.17)
	elif kind == "hair":
		shadow = Color(0.61, 0.32, 0.42)
		ink = Color(0.44, 0.25, 0.34)
		material.set_shader_parameter("specular_strength", 0.06)
		material.set_shader_parameter("shadow_threshold", 0.22)
	elif kind == "metal":
		material.set_shader_parameter("specular_strength", 0.25)
		material.set_shader_parameter("specular_color", Color(1.0, 0.94, 0.80))
	elif kind == "eye":
		gain = Vector3.ONE
		if "眉" in name:
			material.set_shader_parameter("detail_kind", 1)
	material.set_shader_parameter("shadow_color", shadow.linear_to_srgb())
	material.set_shader_parameter("color_gain", gain)
	materials.append(material)
	var edge_enabled: bool = bool(entry.get("edge_enabled", kind != "eye" and float(rgba[3]) >= 0.99))
	if edge_enabled and float(rgba[3]) > 0.001:
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE
		outline.resource_name = name + " / Outline"
		outline.set_shader_parameter("texture_albedo", texture)
		var edge_color: Array = entry.get("edge_color", [ink.r, ink.g, ink.b, 1.0])
		var original := Color(edge_color[0], edge_color[1], edge_color[2], edge_color[3])
		var game_ink := Color(0.14, 0.13, 0.15, original.a)
		if kind in ["face", "skin"]:
			game_ink = Color(0.36, 0.24, 0.20, original.a)
		elif kind == "hair":
			game_ink = Color(0.28, 0.21, 0.24, original.a)
		_source_outline_colors.append(original)
		_game_outline_colors.append(game_ink)
		outline.set_shader_parameter("outline_color", original if use_pmx_outline_colors else game_ink)
		outline.set_shader_parameter("outline_world_width", 0.0018 * maxf(0.0, float(entry.get("edge_size", 1.0))))
		outline.set_shader_parameter("use_mmd_edge_weights", _edge_weights)
		outline.set_shader_parameter("mmd_edge_scale_max", _edge_weight_scale)
		material.next_pass = outline
		outlines.append(outline)
	return material



