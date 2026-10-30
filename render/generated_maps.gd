extends RefCounted

const RESOLUTION := 128
const VERSION := "geometry-lighting-v7"


static func build(arrays: Array, kind: String, head: Dictionary, head_origin: Vector3) -> Texture2D:
	if arrays[Mesh.ARRAY_TEX_UV] == null or arrays[Mesh.ARRAY_INDEX] == null:
		return null
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if points.is_empty() or uv.size() != points.size():
		return null
	# Tiled atlases need artist data; keep the head-space fallback instead of baking a clipped map.
	for point in uv:
		if point.x < -0.0001 or point.y < -0.0001 or point.x > 1.0001 or point.y > 1.0001:
			return null
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update((VERSION + kind + JSON.stringify(head) + str(head_origin)).to_utf8_buffer())
	hash.update(points.to_byte_array())
	hash.update(uv.to_byte_array())
	hash.update(arrays[Mesh.ARRAY_INDEX].to_byte_array())
	var path := "user://render_maps/" + hash.finish().hex_encode() + ".png"
	var image := Image.new()
	if not FileAccess.file_exists(path) or image.load(path) != OK or image.get_size() != Vector2i(RESOLUTION, RESOLUTION):
		var bottom := float(head.get("face_bottom", -0.06))
		var top := float(head.get("face_top", 0.12))
		var height := maxf(top - bottom, 0.01)
		var half_width := float(head.get("half_width", 0.08))
		var nose := Vector3(0.0, 0.0, -INF)
		var nose_back := INF
		for point in points:
			var local := point - head_origin
			var row := (local.y - bottom) / height
			if absf(local.x) < half_width * 0.15 and row > 0.2 and row < 0.62:
				nose_back = minf(nose_back, point.z)
				if point.z > nose.z:
					nose = point
		if nose.z - nose_back < height * 0.025:
			nose.z = -INF
		var widths := PackedFloat32Array()
		widths.resize(32)
		for point in points:
			var local := point - head_origin
			var row := clampi(int((local.y - bottom) / height * 31.0), 0, 31)
			widths[row] = maxf(widths[row], absf(local.x))
		var values := PackedColorArray()
		for point in points:
			var local := point - head_origin
			var row := clampi(int((local.y - bottom) / height * 31.0), 0, 31)
			var width := 0.0
			for neighbor in range(maxi(0, row - 2), mini(32, row + 3)):
				width = maxf(width, widths[neighbor])
			var side := clampf(local.x / maxf(width, 0.005), -1.0, 1.0)
			# Angular face thresholds use a smooth cheek envelope, never individual lip/chin normals.
			var threshold := clampf(0.5 + side * 0.495, 0.005, 0.995)
			var crown := (local.y - bottom) / height
			var highlight := exp(-pow((crown - 0.79) / 0.17, 2.0))
			values.append(Color(threshold, 1.0 - threshold, highlight, 1.0))
		image = _rasterize(uv, arrays[Mesh.ARRAY_INDEX], values, points, nose, height, kind)
		if image == null:
			return null
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK:
			image.save_png(path)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func _rasterize(uv: PackedVector2Array, indices: PackedInt32Array, values: PackedColorArray, points: PackedVector3Array, nose: Vector3, height: float, kind: String) -> Image:
	var image := Image.create(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 0.0, 0.0))
	var covered := false
	for triangle in range(0, indices.size(), 3):
		var a := uv[indices[triangle]] * (RESOLUTION - 1)
		var b := uv[indices[triangle + 1]] * (RESOLUTION - 1)
		var c := uv[indices[triangle + 2]] * (RESOLUTION - 1)
		var area := (b - a).cross(c - a)
		if absf(area) < 0.00001:
			continue
		var low := a.min(b).min(c).floor().max(Vector2.ZERO)
		var high := a.max(b).max(c).ceil().min(Vector2.ONE * (RESOLUTION - 1))
		for y in range(int(low.y), int(high.y) + 1):
			for x in range(int(low.x), int(high.x) + 1):
				var point := Vector2(x, y)
				var v := (point - a).cross(c - a) / area
				var w := (b - a).cross(point - a) / area
				var u := 1.0 - v - w
				if minf(u, minf(v, w)) < -0.01:
					continue
				var color := values[indices[triangle]] * u + values[indices[triangle + 1]] * v + values[indices[triangle + 2]] * w
				if kind == "face":
					var distance := absf(color.r - 0.5)
					color.r = 0.5 + distance
					color.g = 0.5 - distance
					color.b = 0.0
					if nose.is_finite():
						var position := points[indices[triangle]] * u + points[indices[triangle + 1]] * v + points[indices[triangle + 2]] * w
						var offset := (position - nose) / height
						var stroke := pow((absf(offset.x) - 0.006) / 0.008, 2.0) + pow((offset.y + 0.003) / 0.016, 2.0)
						color.b = exp(-stroke) * smoothstep(-0.04, -0.01, offset.z) * 0.65
				else:
					color.b = maxf(color.b, image.get_pixel(x,y).b)
				image.set_pixel(x, y, color)
				covered = true
	return image if covered else null
