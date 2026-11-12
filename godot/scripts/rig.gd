extends RefCounted
## Mixamo characters (assets/mixamo/chars/*.glb, converted by herramientas/convertir_mixamo.gd) driven
## by the shared clip library assets/mixamo/anims.res. Soldiers, puppets and zombies use make();
## if the assets are missing (or --oldchars) they fall back to the procedural bodies.

const SOLDIERS := ["soldado_camo", "swat", "infanteria"]
const ZOMBIES := ["zombi_policia", "zombi_mujer", "zombi_soldado"]

static var _lib: AnimationLibrary
static var _scenes := {}
static var _grip := {}       # body -> gun transform relative to the right hand bone


static func available() -> bool:
	return not ("--oldchars" in OS.get_cmdline_user_args()) and ResourceLoader.exists("res://assets/mixamo/anims.res")


static func lib() -> AnimationLibrary:
	if _lib == null:
		_lib = load("res://assets/mixamo/anims.res")
	return _lib


## Body + AnimationPlayer under `parent`, facing -Z like the game's characters (`tint` multiplies
## the albedo, used to tell operators that share a body apart).
## Returns {node, skel, ap, aim (Aim modifier)}.
static func make(parent: Node3D, id: String, tint := Color.WHITE) -> Dictionary:
	if not _scenes.has(id):
		_scenes[id] = load("res://assets/mixamo/chars/%s.glb" % id)
	var n: Node3D = (_scenes[id] as PackedScene).instantiate()
	n.rotation.y = PI          # Mixamo faces +Z
	parent.add_child(n)
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	sk.name = "Skeleton3D"
	var ap := AnimationPlayer.new()
	sk.get_parent().add_child(ap)
	ap.root_node = ap.get_path_to(sk.get_parent())
	ap.add_animation_library("", lib())
	ap.playback_default_blend_time = 0.22
	var aim := Aim.new()
	sk.add_child(aim)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		m3.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if tint != Color.WHITE:
			for i in m3.mesh.get_surface_count():
				var src = m3.get_active_material(i)
				if src is BaseMaterial3D:
					var m: BaseMaterial3D = src.duplicate()
					m.albedo_color = m.albedo_color * tint
					m3.set_surface_override_material(i, m)
	return {"node": n, "skel": sk, "ap": ap, "aim": aim}


## Node that follows a bone (for effects attached to the body, e.g. the neck stump).
static func bone_node(r: Dictionary, bone: String) -> Node3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	(r.skel as Skeleton3D).add_child(ba)
	return ba


## Mount point in the right hand where the rifle sits, oriented from the "aim" clip so the barrel
## points from the right hand towards the left (support) hand.
static func gun_mount(r: Dictionary, id: String) -> Node3D:
	var sk: Skeleton3D = r.skel
	var ba := BoneAttachment3D.new()
	ba.bone_name = "mixamorig_RightHand"
	sk.add_child(ba)
	if not _grip.has(id):
		var ap: AnimationPlayer = r.ap
		ap.play("aim")
		ap.seek(0.5, true)
		var rh := sk.find_bone("mixamorig_RightHand")
		var lh := sk.find_bone("mixamorig_LeftHand")
		var R := sk.get_bone_global_pose(rh)
		var L := sk.get_bone_global_pose(lh)
		var fwd := (L.origin - R.origin).normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		var up := right.cross(fwd).normalized()
		var b := Basis(right, up, -fwd).orthonormalized()     # gun model: barrel along -Z
		# the grip sits slightly behind and below the gun's centre
		var origin := R.origin + fwd * 0.16 + up * 0.06
		_grip[id] = R.affine_inverse() * Transform3D(b, origin)
		ap.stop()
	var m := Node3D.new()
	m.transform = _grip[id]
	ba.add_child(m)
	return m


## Bends the spine so the upper body follows the aim pitch / yaw (applied after the animation).
class Aim extends SkeletonModifier3D:
	var pitch := 0.0
	var yaw := 0.0
	var head_off := false      # zombie decapitated by a headshot
	var bones: Array = []

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		if head_off:
			var h := sk.find_bone("mixamorig_Head")
			if h >= 0:
				sk.set_bone_pose_scale(h, Vector3.ONE * 0.001)
		if absf(pitch) < 0.001 and absf(yaw) < 0.001:
			return
		if bones.is_empty():
			for nm in ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]:
				var i := sk.find_bone(nm)
				if i >= 0:
					bones.append(i)
		var share := 1.0 / maxf(1.0, bones.size())
		for i in bones:
			var g := sk.get_bone_global_pose(i).basis.orthonormalized()
			# skeleton space: the body faces +Z, so +X is the left side; pitch up = rotate about -X
			var ax := (g.inverse() * Vector3(-1, 0, 0)).normalized()
			var ay := (g.inverse() * Vector3.UP).normalized()
			var q := sk.get_bone_pose_rotation(i)
			q = q * Quaternion(ax, pitch * share) * Quaternion(ay, yaw * share)
			sk.set_bone_pose_rotation(i, q)
