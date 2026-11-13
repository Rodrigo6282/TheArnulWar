extends RefCounted
## First-person arms: the operator's Mixamo body (rig.gd) reduced to arms + hands, fingers posed by
## the "aim" clip, and a two-bone IK that puts each wrist on the gun: the right hand on the pistol
## grip (WM.right_grip records it as meta "rgrip") and the left hand on the `left` node (meta
## "lgrip"), which the reload choreography moves around. Hand orientation relative to the gun is
## taken from the same "aim" clip, so the curled fingers match the grip.

const RIG := preload("res://scripts/rig.gd")
const SKIN_SH := preload("res://shaders/fp_skin.gdshader")
const KEEP := ["Shoulder", "Arm", "Hand"]     # bones whose triangles are kept (Arm also matches ForeArm)
const ARM_SCALE := 1.3
const BULK := 0.022           # how far the arm skin is pushed out (mesh units ≈ m, before ARM_SCALE)
const SHOULDERS := Vector3(0.03, -0.47, -0.2)   # shoulder midpoint in camera space (below the frame)

var node: Node3D
var skel: Skeleton3D
var ik: IK
var cam: Node3D
var ready := false
# hand basis relative to the gun frame, from the Mixamo aim pose
var rel_r := Basis()
var rel_l := Basis()
var palm_r := Vector3.ZERO      # palm normal in the hand bone's local space
var palm_l := Vector3.ZERO
var fing_r := Vector3.UP        # wrist -> knuckles in the hand bone's local space
var fing_l := Vector3.UP


static func available() -> bool:
	return RIG.available() and not ("--oldhands" in OS.get_cmdline_user_args())


func build(camera: Node3D, body: String, tint: Color) -> void:
	cam = camera
	var r := RIG.make(camera, body)
	node = r.node
	skel = r.skel
	(r.aim as Node).queue_free()
	var ap: AnimationPlayer = r.ap
	# keep the clip "playing" at speed 0: a paused player stops updating the skeleton, and then the
	# IK modifier never runs
	ap.play("aim")
	ap.seek(0.6, true)
	ap.speed_scale = 0.0
	_strip_body(tint)
	_measure()
	# viewmodel cheat used by most shooters: the gun sits well in front of the eye, so the arms are
	# a bit longer and the (invisible) shoulders sit forward and low, out of the frame
	node.scale = Vector3.ONE * ARM_SCALE
	var mid := (skel.get_bone_global_pose(skel.find_bone("mixamorig_LeftArm")).origin + skel.get_bone_global_pose(skel.find_bone("mixamorig_RightArm")).origin) * 0.5
	var mid_cam: Vector3 = cam.to_local(skel.to_global(mid))
	node.position += SHOULDERS - mid_cam
	ik = IK.new()
	ik.fp = self
	skel.add_child(ik)
	ready = true


## Keep only arm/hand triangles and give them the depth-pulled first-person material.
func _strip_body(tint: Color) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var skin: Skin = m3.skin
		var keep_bind := {}
		if skin:
			for b in skin.get_bind_count():
				var nm := skin.get_bind_name(b)
				if nm == "" and skin.get_bind_bone(b) >= 0:
					nm = skel.get_bone_name(skin.get_bind_bone(b))
				for k in KEEP:
					if k in nm:
						keep_bind[b] = true
		var src: Mesh = m3.mesh
		var out := ArrayMesh.new()
		for s in src.get_surface_count():
			var arr: Array = src.surface_get_arrays(s)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if bones.is_empty() or idx.is_empty() or nv == 0:
				continue
			var per := bones.size() / nv
			var arm := PackedByteArray()
			arm.resize(nv)
			for v in nv:
				var best := 0
				var bw := -1.0
				for k in per:
					if weights[v * per + k] > bw:
						bw = weights[v * per + k]
						best = bones[v * per + k]
				arm[v] = 1 if keep_bind.has(best) else 0
			var kept := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				if arm[idx[t]] == 1 and arm[idx[t + 1]] == 1 and arm[idx[t + 2]] == 1:
					kept.append(idx[t])
					kept.append(idx[t + 1])
					kept.append(idx[t + 2])
			if kept.is_empty():
				continue
			arr[Mesh.ARRAY_INDEX] = kept
			# per-vertex "bulk" in UV2.x (read by fp_skin.gdshader, which pushes the skin out
			# along the normal): full on upper arm / forearm, a little on the palm, almost none
			# on the fingers; blended by the bone weights so the wrist has no step
			var bulk := PackedVector2Array()
			bulk.resize(nv)
			for v in nv:
				var f := 0.0
				var wsum := 0.0
				for k in per:
					var w: float = weights[v * per + k]
					if w <= 0.0:
						continue
					f += w * _bulk_of(_bind_name(skin, bones[v * per + k]))
					wsum += w
				bulk[v] = Vector2(f / maxf(wsum, 0.0001), 0.0)
			arr[Mesh.ARRAY_TEX_UV2] = bulk
			var flags: int = src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
			var sm = m3.get_active_material(s)
			var fm := ShaderMaterial.new()
			fm.shader = SKIN_SH
			if sm is BaseMaterial3D:
				fm.set_shader_parameter("albedo_tex", sm.albedo_texture)
				if sm.normal_texture:
					fm.set_shader_parameter("normal_tex", sm.normal_texture)
					fm.set_shader_parameter("has_normal", true)
			fm.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
			fm.set_shader_parameter("bulk", _bulk_amount())
			out.surface_set_material(out.get_surface_count() - 1, fm)
		if out.get_surface_count() == 0:
			m3.queue_free()
			continue
		m3.mesh = out
		for s in out.get_surface_count():
			m3.set_surface_override_material(s, null)


func _bind_name(skin: Skin, b: int) -> String:
	if skin == null or b < 0 or b >= skin.get_bind_count():
		return ""
	var nm := skin.get_bind_name(b)
	if nm == "" and skin.get_bind_bone(b) >= 0:
		nm = skel.get_bone_name(skin.get_bind_bone(b))
	return nm


## How much a bone's skin is thickened (1 = the full `bulk` of the shader).
static func _bulk_of(bone: String) -> float:
	if "Hand" in bone:
		# fingers (HandThumb1, HandIndex2...) stay slim so they still wrap the grips
		for f in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			if f in bone:
				return 0.08
		return 0.35
	if "ForeArm" in bone:
		return 1.0
	if "Arm" in bone or "Shoulder" in bone:
		return 1.0
	return 0.0


## Hand frames from the T-pose rest (palm normal, finger direction) and from the aim pose (how
## the hands sit relative to the rifle in Mixamo's own clip).
func _measure() -> void:
	var rh := skel.find_bone("mixamorig_RightHand")
	var lh := skel.find_bone("mixamorig_LeftHand")
	# rest = T-pose, body facing +Z, arms along X, palms down
	var rr := skel.get_bone_global_rest(rh).basis.orthonormalized()
	var lr := skel.get_bone_global_rest(lh).basis.orthonormalized()
	palm_r = rr.inverse() * Vector3.DOWN
	palm_l = lr.inverse() * Vector3.DOWN
	fing_r = rr.inverse() * Vector3.LEFT     # the right arm points to -X in the T-pose
	fing_l = lr.inverse() * Vector3.RIGHT
	var R := skel.get_bone_global_pose(rh)
	var L := skel.get_bone_global_pose(lh)
	var fwd := (L.origin - R.origin).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	var gb := Basis(right, up, -fwd).orthonormalized()     # gun frame, barrel along -Z
	rel_r = gb.inverse() * R.basis.orthonormalized()
	rel_l = gb.inverse() * L.basis.orthonormalized()


## Called every frame after the viewmodel is posed. `g` = guns[cur] dictionary.
func update(g: Dictionary, show: bool) -> void:
	if not ready:
		return
	var model: Node3D = g.model
	node.visible = show and model.has_meta("rgrip")
	if not node.visible:
		ik.on = false
		return
	var to_skel := skel.global_transform.affine_inverse()
	var gun_basis := model.global_transform.basis.orthonormalized()
	# right hand: wrist behind the grip so the palm wraps it
	var rg: Dictionary = model.get_meta("rgrip")
	var rb: Basis = gun_basis * rel_r
	var rc: Vector3 = model.to_global(rg.c)
	var r_wrist: Vector3 = rc - (rb * fing_r) * 0.055 - (rb * palm_r) * (float(rg.rad) + 0.022)
	ik.t_r = to_skel * Transform3D(rb, r_wrist)
	# left hand: on the `left` node (moves during reloads)
	var left: Node3D = g.left
	var lb: Basis = gun_basis * rel_l
	if left.has_meta("lgrip"):
		var lg: Dictionary = left.get_meta("lgrip")
		var lc: Vector3 = left.to_global(lg.c)
		var l_wrist: Vector3 = lc - (lb * fing_l) * 0.05 - (lb * palm_l) * (float(lg.rad) + 0.022)
		ik.t_l = to_skel * Transform3D(lb, l_wrist)
	ik.on = true


## Two-bone IK for both arms, applied after the (paused) aim clip.
class IK extends SkeletonModifier3D:
	var fp
	var on := false
	var t_r := Transform3D()
	var t_l := Transform3D()
	var ids := {}

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or not on:
			return
		if ids.is_empty():
			for side in ["Right", "Left"]:
				ids[side] = [sk.find_bone("mixamorig_%sArm" % side), sk.find_bone("mixamorig_%sForeArm" % side), sk.find_bone("mixamorig_%sHand" % side)]
		# skeleton space: body faces +Z, its right side is -X; elbows point down and out
		_solve(sk, ids.Right, t_r, Vector3(-0.35, -1.0, -0.15))
		_solve(sk, ids.Left, t_l, Vector3(0.35, -1.0, -0.15))

	func _solve(sk: Skeleton3D, b: Array, t: Transform3D, pole_dir: Vector3) -> void:
		var S := sk.get_bone_global_pose(b[0]).origin
		var E := sk.get_bone_global_pose(b[1]).origin
		var W := sk.get_bone_global_pose(b[2]).origin
		var a := S.distance_to(E)
		var c := E.distance_to(W)
		var T := t.origin
		var d := clampf(S.distance_to(T), absf(a - c) + 0.01, (a + c) * 0.999)
		var dir := (T - S).normalized()
		var cos_a := clampf((a * a + d * d - c * c) / (2.0 * a * d), -1.0, 1.0)
		var pn := pole_dir - dir * pole_dir.dot(dir)
		if pn.length() < 0.001:
			pn = Vector3.DOWN
		pn = pn.normalized()
		var E2 := S + dir * (a * cos_a) + pn * (a * sqrt(1.0 - cos_a * cos_a))
		_aim(sk, b[0], E, E2)
		var w_now := sk.get_bone_global_pose(b[2]).origin
		_aim(sk, b[1], w_now, S + dir * d)
		var h := sk.get_bone_global_pose(b[2])
		sk.set_bone_global_pose(b[2], Transform3D(t.basis, h.origin))

	func _aim(sk: Skeleton3D, bone: int, from_pt: Vector3, to_pt: Vector3) -> void:
		var g := sk.get_bone_global_pose(bone)
		var v1 := (from_pt - g.origin).normalized()
		var v2 := (to_pt - g.origin).normalized()
		if v1.dot(v2) > 0.99999:
			return
		var q := Quaternion(v1, v2)
		sk.set_bone_global_pose(bone, Transform3D(Basis(q) * g.basis, g.origin))


## BULK, or --bulk=X on the command line (to compare thicknesses in screenshots).
static func _bulk_amount() -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bulk="):
			return float(a.get_slice("=", 1))
	return BULK
