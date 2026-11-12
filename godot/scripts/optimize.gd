extends RefCounted
## Draw-call reduction without touching visuals: static meshes that share a material are merged
## into one mesh (per world-space cell, so frustum culling still works). Shadows, materials and
## geometry stay identical; only the number of draw calls drops.

const CELL := 16.0


static func _excluded(n: Node, stop: Node) -> bool:
	var p := n
	while p != null and p != stop:
		if p.has_meta("nomerge"):
			return true
		p = p.get_parent()
	return false


static func _mat_of(mi: MeshInstance3D) -> Material:
	if mi.material_override:
		return mi.material_override
	if mi.mesh and mi.mesh.get_surface_count() == 1:
		return mi.mesh.surface_get_material(0)
	return null


## Merge every static, visible single-surface mesh under `root` (whole map).
static func merge_world(root: Node3D) -> int:
	var groups := {}
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D) or n.has_meta("nomerge"):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() != 1 or not mi.is_visible_in_tree() or _excluded(mi, root):
			continue
		var mat := _mat_of(mi)
		if mat == null or mat.get_class() == "ShaderMaterial":
			continue
		if mat is BaseMaterial3D and (mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mat.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED):
			continue
		var o := mi.global_position
		var key := "%d|%d|%d|%d" % [mat.get_instance_id(), int(mi.cast_shadow), int(floor(o.x / CELL)), int(floor(o.z / CELL))]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(mi)
	var removed := 0
	var inv := root.global_transform.affine_inverse()
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		for mi in list:
			st.append_from(mi.mesh, 0, inv * mi.global_transform)
		var out := MeshInstance3D.new()
		out.mesh = st.commit()
		out.material_override = _mat_of(list[0])
		out.cast_shadow = list[0].cast_shadow
		root.add_child(out)
		for mi in list:
			mi.get_parent().remove_child(mi)
			mi.queue_free()
			removed += 1
	return removed


## Merge the direct MeshInstance children of `n` that share a material (used for first-person
## weapons and character bones: the pieces move together, so they can be one mesh).
static func merge_children(n: Node3D, exclude: Array = []) -> void:
	if "--nomerge" in OS.get_cmdline_user_args():
		return
	var groups := {}
	for c in n.get_children():
		if not (c is MeshInstance3D) or c in exclude or c.get_child_count() > 0:
			continue
		var mi := c as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() != 1 or not mi.visible:
			continue
		var mat := _mat_of(mi)
		if mat == null:
			continue
		var key := "%d|%d" % [mat.get_instance_id(), int(mi.cast_shadow)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(mi)
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		for mi in list:
			st.append_from(mi.mesh, 0, mi.transform)
		var out := MeshInstance3D.new()
		out.mesh = st.commit()
		out.material_override = _mat_of(list[0])
		out.cast_shadow = list[0].cast_shadow
		n.add_child(out)
		for mi in list:
			n.remove_child(mi)
			mi.queue_free()


## Recursively merge a node tree, treating each node in `keep` as an independent moving part.
static func merge_tree(n: Node3D, keep: Array) -> void:
	for c in n.get_children():
		if c is Node3D and not (c is MeshInstance3D and c.get_child_count() == 0):
			merge_tree(c, keep)
	merge_children(n, keep)
