extends RefCounted
## Rounded (bevelled) box meshes: smooth normals on the curved edges, flat faces elsewhere.
## Godot has no bevelled box primitive; this replaces BoxMesh wherever things shouldn't look blocky.

static var _cache := {}


static func _samples(h: float, r: float, seg: int) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	var inner := h - r
	for k in range(seg, 0, -1):
		s.append(-inner - r * sin(float(k) / seg * PI * 0.5))
	s.append(-inner)
	if inner > 0.0001:
		s.append(inner)
	for k in range(1, seg + 1):
		s.append(inner + r * sin(float(k) / seg * PI * 0.5))
	return s


static func rbox(size: Vector3, radius := -1.0, seg := 3) -> Mesh:
	var r := radius if radius >= 0.0 else minf(size.x, minf(size.y, size.z)) * 0.28
	r = minf(r, minf(size.x, minf(size.y, size.z)) * 0.49)
	var key := "%s|%.4f|%d" % [size, r, seg]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var inner := h - Vector3.ONE * r
	for a in 3:
		var u := (a + 1) % 3
		var v := (a + 2) % 3
		var su := _samples(h[u], r, seg)
		var sv := _samples(h[v], r, seg)
		for sgn in [-1.0, 1.0]:
			var face_n := Vector3.ZERO
			face_n[a] = sgn
			var grid := []
			for i in su.size():
				var row := []
				for j in sv.size():
					var p := Vector3.ZERO
					p[a] = sgn * h[a]
					p[u] = su[i]
					p[v] = sv[j]
					var c := Vector3(clampf(p.x, -inner.x, inner.x), clampf(p.y, -inner.y, inner.y), clampf(p.z, -inner.z, inner.z))
					var d := p - c
					var n := face_n
					if d.length() > 0.000001:
						n = d.normalized()
						p = c + n * r
					row.append([p, n, Vector2(p[u] / size[u] + 0.5, p[v] / size[v] + 0.5)])
				grid.append(row)
			for i in su.size() - 1:
				for j in sv.size() - 1:
					var q00: Array = grid[i][j]
					var q10: Array = grid[i + 1][j]
					var q11: Array = grid[i + 1][j + 1]
					var q01: Array = grid[i][j + 1]
					var tri_n: Vector3 = (q10[0] - q00[0]).cross(q11[0] - q00[0])
					var order := [q00, q11, q10, q00, q01, q11] if tri_n.dot(face_n) > 0.0 else [q00, q10, q11, q00, q11, q01]
					for q in order:
						st.set_normal(q[1])
						st.set_uv(q[2])
						st.add_vertex(q[0])
	st.generate_tangents()
	var m := st.commit()
	_cache[key] = m
	return m
