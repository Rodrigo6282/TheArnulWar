extends SceneTree
## Converts the Mixamo downloads into light game assets.
##   1. Copy the FBX files to godot/assets/mixamo/raw/ (characters, short names below) and
##      godot/assets/mixamo/anims/ (animations, original Mixamo names), then run `--import`.
##   2. Godot_v4.7.2-stable_win64_console.exe --headless --path godot -s ../herramientas/convertir_mixamo.gd
##   3. Delete raw/ and anims/ (the originals stay wherever they were downloaded).
## Output: assets/mixamo/chars/<name>.glb (textures shrunk from 4K to 1K/512, no animation player)
## and assets/mixamo/anims.res (AnimationLibrary with short names, looping set per clip).

const CHARS := {"ch15": "soldado_camo", "ch35": "swat", "ch49": "infanteria",
	"zcop": "zombi_policia", "zgirl": "zombi_mujer", "zwar": "zombi_soldado"}

# file name -> [clip name, loops]
const ANIMS := {
	"Rifle Idle": ["idle", true], "Rifle Aiming Idle": ["aim", true], "Rifle Walk": ["walk", true],
	"Rifle Run": ["run", true], "Walking Backwards": ["back", true], "Strafe Left": ["left", true],
	"Strafe Right": ["right", true], "Rifle Crouch Walk": ["crouch", true], "Firing Rifle": ["fire", true],
	"Reloading": ["reload", false], "Hit Reaction": ["hit", false], "Death From The Front": ["die_front", false],
	"Death From The Back": ["die_back", false], "Death From Front Headshot": ["die_head", false],
	"Zombie Idle": ["z_idle", true], "Zombie Walk": ["z_walk", true], "Zombie Running": ["z_run", true],
	"Zombie Attack": ["z_attack", false], "Zombie Scream": ["z_scream", false], "Zombie Stand Up": ["z_rise", false],
	"Zombie Death": ["z_die", false], "Zombie Reaction Hit": ["z_hit", false]}

var cache := {}


func _shrink(tex: Texture2D, size: int, normal: bool) -> Texture2D:
	if tex == null:
		return null
	var key := "%d|%d" % [tex.get_instance_id(), size]
	if cache.has(key):
		return cache[key]
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	if img.get_width() > size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	if normal:
		# normal maps may come back as RG only: rebuild Z
		img.convert(Image.FORMAT_RGB8)
		var sample := img.get_pixel(size / 2, size / 2)
		if sample.b < 0.05:
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					var nx := c.r * 2.0 - 1.0
					var ny := c.g * 2.0 - 1.0
					c.b = sqrt(maxf(0.0, 1.0 - nx * nx - ny * ny)) * 0.5 + 0.5
					img.set_pixel(x, y, c)
	var out := ImageTexture.create_from_image(img)
	cache[key] = out
	return out


func _fix_materials(n: Node) -> bool:
	var alpha := false
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh.duplicate()
		for i in mesh.get_surface_count():
			var src = mi.get_active_material(i)
			if not (src is BaseMaterial3D):
				continue
			var m: BaseMaterial3D = src.duplicate()
			m.albedo_texture = _shrink(m.albedo_texture, 1024, false)
			m.normal_texture = _shrink(m.normal_texture, 512, true)
			m.roughness_texture = _shrink(m.roughness_texture, 512, false)
			m.metallic_texture = _shrink(m.metallic_texture, 512, false)
			m.emission_texture = _shrink(m.emission_texture, 512, false)
			m.ao_texture = null
			if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				alpha = true
			mesh.surface_set_material(i, m)
			mi.set_surface_override_material(i, null)
		mi.mesh = mesh
	for c in n.get_children():
		alpha = _fix_materials(c) or alpha
	return alpha


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/mixamo/chars")
	for src in CHARS:
		var path := "res://assets/mixamo/raw/%s.fbx" % src
		if not ResourceLoader.exists(path):
			print("MIXAMO falta ", path)
			continue
		var n: Node = (load(path) as PackedScene).instantiate()
		for c in n.find_children("*", "AnimationPlayer", true, false):
			c.get_parent().remove_child(c)
			c.free()
		var alpha := _fix_materials(n)
		var doc := GLTFDocument.new()
		doc.image_format = "PNG" if alpha else "JPEG"
		doc.lossy_quality = 0.85
		var st := GLTFState.new()
		var err := doc.append_from_scene(n, st)
		var out := "res://assets/mixamo/chars/%s.glb" % CHARS[src]
		if err == OK:
			err = doc.write_to_filesystem(st, ProjectSettings.globalize_path(out))
		print("MIXAMO ", src, " -> ", out, " err=", err, " alpha=", alpha)
		n.free()
	var lib := AnimationLibrary.new()
	for f in ANIMS:
		var path := "res://assets/mixamo/anims/%s.fbx" % f
		if not ResourceLoader.exists(path):
			print("MIXAMO falta ", path)
			continue
		var n: Node = (load(path) as PackedScene).instantiate()
		var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
		var a: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
		a.loop_mode = Animation.LOOP_LINEAR if ANIMS[f][1] else Animation.LOOP_NONE
		lib.add_animation(ANIMS[f][0], a)
		print("MIXAMO anim ", ANIMS[f][0], " len=%.2f tracks=%d" % [a.length, a.get_track_count()])
		n.free()
	var e2 := ResourceSaver.save(lib, "res://assets/mixamo/anims.res", ResourceSaver.FLAG_COMPRESS)
	print("MIXAMO anims.res err=", e2)
	quit()
