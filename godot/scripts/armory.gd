extends RefCounted
## ARMERO: per-weapon attachments, camouflage and upgrade levels, bought with credits earned in play.
## Saved in settings.armory = {"<weapon index>": {"att": {slot: id}, "camo": id, "lvl": {stat: n}, "own": [ids]}}.
## `apply_stats` changes the player's weapon dictionary, `dress` adds the attachment meshes and camo
## to a weapon model built by weapon_models.gd (first person and the Armero preview).

const WM := preload("res://scripts/weapon_models.gd")

const SLOTS := ["mira", "boca", "cargador", "empunadura"]
const SLOT_NAMES := {"mira": "Mira", "boca": "Boca de cañón", "cargador": "Cargador", "empunadura": "Empuñadura"}

## Attachments: cost in credits, multipliers (keys of the weapon dictionary), description.
## "no" lists weapons that can't mount it (1 shotgun, 2 pistol, 4 sniper).
const ATT := {
	"mira": {
		"red": {"name": "Punto rojo", "cost": 250, "desc": "Apuntado más rápido y preciso", "mul": {"aim_spread": 0.8, "ads": 1.2}, "no": [4]},
		"holo": {"name": "Holográfica", "cost": 400, "desc": "Retícula amplia, menos dispersión al apuntar", "mul": {"aim_spread": 0.7, "ads": 1.1}, "no": [2, 4]},
		"acog": {"name": "Óptica 3x", "cost": 600, "desc": "Más aumento, apuntado más lento", "mul": {"aim_spread": 0.55, "ads": 0.8, "zoom": 0.7}, "no": [1, 2, 4]},
	},
	"boca": {
		"supp": {"name": "Silenciador", "cost": 450, "desc": "Disparo silencioso, sin fogonazo; algo menos de alcance", "mul": {"range": 0.85, "dmg": 0.95}, "flag": "quiet", "no": []},
		"comp": {"name": "Compensador", "cost": 300, "desc": "-30 % de retroceso", "mul": {"recoil": 0.7}, "no": []},
		"long": {"name": "Cañón largo", "cost": 500, "desc": "+10 % daño y más alcance efectivo", "mul": {"dmg": 1.1, "falloff_d": 1.35, "move": 0.97}, "no": [2]},
	},
	"cargador": {
		"ext": {"name": "Cargador ampliado", "cost": 350, "desc": "+40 % de munición por cargador, recarga algo más lenta", "mul": {"mag": 1.4, "reload": 1.1}, "no": []},
		"fast": {"name": "Cargador rápido", "cost": 400, "desc": "-25 % tiempo de recarga", "mul": {"reload": 0.75}, "no": []},
	},
	"empunadura": {
		"vert": {"name": "Empuñadura vertical", "cost": 300, "desc": "-25 % de retroceso", "mul": {"recoil": 0.75}, "no": [2]},
		"ang": {"name": "Empuñadura angular", "cost": 300, "desc": "-20 % dispersión sin apuntar, apuntado rápido", "mul": {"spread": 0.8, "ads": 1.15}, "no": [2, 4]},
	},
}

## Camouflages: pattern 0 solid / 1 blotches / 2 digital; matte paint unless metal.
const CAMOS := {
	"none": {"name": "Original", "cost": 0},
	"bosque": {"name": "Bosque", "cost": 150, "pat": 1, "c": [Color(0.27, 0.32, 0.18), Color(0.18, 0.15, 0.09), Color(0.07, 0.08, 0.06)]},
	"desierto": {"name": "Desierto", "cost": 150, "pat": 1, "c": [Color(0.7, 0.6, 0.42), Color(0.5, 0.38, 0.24), Color(0.36, 0.3, 0.22)]},
	"artico": {"name": "Ártico", "cost": 200, "pat": 1, "c": [Color(0.86, 0.88, 0.9), Color(0.6, 0.64, 0.68), Color(0.3, 0.32, 0.35)]},
	"urbano": {"name": "Urbano digital", "cost": 250, "pat": 2, "c": [Color(0.45, 0.46, 0.48), Color(0.25, 0.26, 0.28), Color(0.1, 0.1, 0.11)]},
	"tigre": {"name": "Tigre", "cost": 350, "pat": 1, "c": [Color(0.75, 0.42, 0.12), Color(0.08, 0.06, 0.05), Color(0.08, 0.06, 0.05)], "scale": 14.0},
	"carmesi": {"name": "Carmesí", "cost": 500, "pat": 0, "c": [Color(0.55, 0.06, 0.07)], "metal": 0.6},
	"oro": {"name": "Oro", "cost": 1500, "pat": 0, "c": [Color(0.8, 0.6, 0.22)], "metal": 0.95, "glow": 0.08},
	"diamante": {"name": "Diamante", "cost": 3000, "pat": 2, "c": [Color(0.75, 0.9, 1.0), Color(0.5, 0.75, 0.95), Color(0.9, 0.97, 1.0)], "metal": 0.9, "glow": 0.15, "scale": 22.0},
}

## Upgrade levels (0-3): effect per level, cost of each next level.
const UPG := {
	"dmg": {"name": "Daño", "desc": "+7 % de daño por nivel"},
	"rec": {"name": "Estabilidad", "desc": "-10 % de retroceso por nivel"},
	"rel": {"name": "Recarga", "desc": "-7 % de tiempo de recarga por nivel"},
	"cap": {"name": "Munición", "desc": "+10 % cargador y +15 % reserva por nivel"},
}
const UPG_COST := [300, 600, 1000]
const MAX_LVL := 3


static func slot_ok(slot: String, id: String, wi: int) -> bool:
	if not ATT[slot].has(id):
		return false
	return not (wi in ATT[slot][id].no)


static func cfg(settings: Dictionary, wi: int) -> Dictionary:
	var arm: Dictionary = settings.get("armory", {})
	var k := str(wi)
	if not arm.has(k) or not (arm[k] is Dictionary):
		arm[k] = {}
	var c: Dictionary = arm[k]
	if not c.has("att"):
		c["att"] = {}
	if not c.has("camo"):
		c["camo"] = "none"
	if not c.has("lvl"):
		c["lvl"] = {}
	if not c.has("own"):
		c["own"] = []
	settings["armory"] = arm
	return c


static func owns(c: Dictionary, key: String) -> bool:
	return key in c.own


## Change the weapon dictionary (player.weapons[i]) according to its Armero setup.
static func apply_stats(w: Dictionary, c: Dictionary, wi: int) -> void:
	var mul := {}
	var flags := []
	for slot in SLOTS:
		var id: String = c.att.get(slot, "")
		if id == "" or not slot_ok(slot, id, wi):
			continue
		var a: Dictionary = ATT[slot][id]
		for k in a.mul:
			mul[k] = float(mul.get(k, 1.0)) * float(a.mul[k])
		if a.has("flag"):
			flags.append(a.flag)
	var lv: Dictionary = c.lvl
	mul["dmg"] = float(mul.get("dmg", 1.0)) * (1.0 + 0.07 * int(lv.get("dmg", 0)))
	mul["recoil"] = float(mul.get("recoil", 1.0)) * (1.0 - 0.1 * int(lv.get("rec", 0)))
	mul["reload"] = float(mul.get("reload", 1.0)) * (1.0 - 0.07 * int(lv.get("rel", 0)))
	mul["mag"] = float(mul.get("mag", 1.0)) * (1.0 + 0.1 * int(lv.get("cap", 0)))
	mul["reserve_max"] = 1.0 + 0.15 * int(lv.get("cap", 0))
	for k in ["dmg", "recoil", "reload", "spread", "aim_spread", "range"]:
		if mul.has(k):
			w[k] = float(w[k]) * float(mul[k])
	if mul.has("move"):
		w["move"] = float(w.get("move", 1.0)) * float(mul.move)
	if mul.has("ads"):
		w["ads"] = float(w.get("ads", 1.0)) * float(mul.ads)
	if mul.has("zoom"):
		w["zoom"] = float(mul.zoom)
	if mul.has("falloff_d") and w.has("falloff"):
		var f: Array = (w.falloff as Array).duplicate()
		f[0] = float(f[0]) * float(mul.falloff_d)
		f[1] = float(f[1]) * float(mul.falloff_d)
		w["falloff"] = f
	if mul.has("mag"):
		var extra := 2 if wi == 1 else 0    # shotgun: a longer tube is +2 shells
		w["mag"] = maxi(int(round(int(w.mag) * float(mul.mag))), int(w.mag) + (extra if float(mul.mag) > 1.01 else 0))
	w["reserve_max"] = int(round(int(w.reserve_max) * float(mul.reserve_max)))
	w["ammo"] = w.mag
	w["reserve"] = w.reserve_max
	w["quiet"] = "quiet" in flags


## Stats shown in the Armero bars (0..1) for weapon dictionary w.
static func bars(w: Dictionary) -> Array:
	var pellets: float = float(w.get("pellets", 1))
	var dps: float = float(w.dmg) * pellets / maxf(float(w.rate), 0.05)
	return [
		["Daño", clampf(float(w.dmg) * pellets / 140.0, 0.05, 1.0)],
		["Cadencia", clampf(0.12 / maxf(float(w.rate), 0.05), 0.05, 1.0) if float(w.rate) > 0.12 else clampf(1.0 - (float(w.rate) - 0.06) * 4.0, 0.3, 1.0)],
		["Daño por segundo", clampf(dps / 1400.0, 0.05, 1.0)],
		["Precisión", clampf(1.0 - float(w.spread) / 0.08, 0.05, 1.0)],
		["Control", clampf(1.0 - float(w.recoil) / 0.075, 0.05, 1.0)],
		["Alcance", clampf(float(w.range) / 400.0 * (float(w.falloff[2]) if w.has("falloff") else 1.0) + 0.1, 0.05, 1.0)],
		["Movilidad", clampf(float(w.get("move", 1.0)) - 0.15, 0.05, 1.0)],
		["Recarga", clampf(1.0 - float(w.reload) / 4.0, 0.05, 1.0)],
	]


# ---------------------------------------------------------------- visuals
static var _mats := {}


static func _mat(key: String, col: Color, glow := 0.0) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = WM.SHT
	m.set_shader_parameter("use_arm", 0.0)
	m.set_shader_parameter("camo", 1.0)
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("paint_rough", 0.6)
	m.set_shader_parameter("paint_metal", 0.3)
	if glow > 0.0:
		m.set_shader_parameter("emission", col)
		m.set_shader_parameter("emission_energy", glow)
	_mats[key] = m
	return m


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("armero", true)
	parent.add_child(mi)
	return mi


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func _cyl(r: float, h: float, seg := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## Sight housing you look through: four thin walls around the eye line (open front and back).
static func _frame(g: Node3D, mat: Material, c: Vector3, half: float, ln: float, t := 0.003) -> void:
	_mesh(g, _box(half * 2.0 + t * 2.0, t, ln), mat, c + Vector3(0, half + t * 0.5, 0))
	_mesh(g, _box(half * 2.0 + t * 2.0, t, ln), mat, c - Vector3(0, half + t * 0.5, 0))
	_mesh(g, _box(t, half * 2.0, ln), mat, c + Vector3(half + t * 0.5, 0, 0))
	_mesh(g, _box(t, half * 2.0, ln), mat, c - Vector3(half + t * 0.5, 0, 0))


## Add the Armero attachments + camo to a built gun dictionary (model/aim/flash/mag/left).
## Old attachment meshes are removed first, so it can be called again after a change.
static func dress(gd: Dictionary, wi: int, c: Dictionary) -> void:
	var g: Node3D = gd.model
	for n in g.find_children("*", "", true, false):
		if n.has_meta("armero"):
			n.get_parent().remove_child(n)
			n.queue_free()
	if gd.has("flash_home"):
		(gd.flash as Node3D).position = gd.flash_home
	elif gd.get("flash") is Node3D:
		gd["flash_home"] = (gd.flash as Node3D).position
	if gd.has("mag") and gd.has("mag_scale"):
		(gd.mag as Node3D).scale = gd.mag_scale
	elif gd.has("mag"):
		gd["mag_scale"] = (gd.mag as Node3D).scale
	var dark := _mat("dark", Color(0.06, 0.065, 0.07))
	# the eye looks along gun-local (0, -aim.y) when aiming
	var eye_y: float = -float((gd.aim as Vector3).y)
	var fl: Vector3 = gd.flash_home if gd.has("flash_home") else Vector3(0, eye_y - 0.02, -0.6)
	var att: Dictionary = c.get("att", {})
	var sight: String = att.get("mira", "")
	if sight != "" and slot_ok("mira", sight, wi):
		var z0 := -0.1 if wi != 2 else -0.02
		match sight:
			"red":
				_mesh(g, _box(0.024, 0.012, 0.05), dark, Vector3(0, eye_y - 0.026, z0))
				_frame(g, dark, Vector3(0, eye_y, z0), 0.015, 0.035)
				_mesh(g, SphereMesh.new(), _mat("dot", Color(4.0, 0.2, 0.15), 3.0), Vector3(0, eye_y, z0 - 0.02)).scale = Vector3.ONE * 0.005
			"holo":
				_mesh(g, _box(0.03, 0.014, 0.07), dark, Vector3(0, eye_y - 0.03, z0))
				_frame(g, dark, Vector3(0, eye_y, z0), 0.02, 0.05, 0.004)
				_mesh(g, TorusMesh.new(), _mat("dot", Color(4.0, 0.2, 0.15), 3.0), Vector3(0, eye_y, z0 - 0.03), Vector3(PI / 2, 0, 0)).scale = Vector3.ONE * 0.006
			"acog":
				_mesh(g, _box(0.026, 0.016, 0.06), dark, Vector3(0, eye_y - 0.034, z0))
				_frame(g, dark, Vector3(0, eye_y, z0), 0.018, 0.1, 0.005)
				_mesh(g, SphereMesh.new(), _mat("dot", Color(4.0, 0.2, 0.15), 3.0), Vector3(0, eye_y, z0 - 0.06)).scale = Vector3.ONE * 0.004
	var muz: String = att.get("boca", "")
	if muz != "" and slot_ok("boca", muz, wi):
		var ln: float = {"supp": 0.17 if wi != 2 else 0.12, "comp": 0.05, "long": 0.12}[muz]
		var rad: float = {"supp": 0.02 if wi != 2 else 0.016, "comp": 0.014, "long": 0.009}[muz]
		_mesh(g, _cyl(rad, ln), dark if muz != "comp" else _mat("steel", Color(0.32, 0.33, 0.35)), fl + Vector3(0, 0, -ln * 0.5 + 0.01), Vector3(PI / 2, 0, 0))
		if muz == "comp":
			for sx in [-1.0, 1.0]:
				_mesh(g, _box(0.004, 0.012, 0.03), dark, fl + Vector3(0.014 * sx, 0.004, -0.025))
		if gd.get("flash") is Node3D:
			(gd.flash as Node3D).position = fl + Vector3(0, 0, -ln)
	var mg: String = att.get("cargador", "")
	if mg == "ext" and gd.has("mag") and wi != 1:
		(gd.mag as Node3D).scale = Vector3(gd.mag_scale) * Vector3(1.0, 1.3, 1.0)
	elif mg == "fast" and gd.has("mag"):
		# magazine coupler: a bright pull tab on the magazine
		_mesh(gd.mag, _box(0.012, 0.03, 0.006), _mat("tab", Color(0.85, 0.3, 0.1)), Vector3(0.0, -0.06, 0.02))
	elif mg == "ext" and wi == 1:
		_mesh(g, _cyl(0.013, 0.12), dark, fl + Vector3(0, -0.035, 0.16), Vector3(PI / 2, 0, 0))
	var grip: String = att.get("empunadura", "")
	if grip != "" and slot_ok("empunadura", grip, wi) and gd.get("left") is Node3D:
		var lp: Vector3 = (gd.left as Node3D).position
		if gd.has("left_home"):
			lp = gd.left_home
		var gp := Vector3(0, lp.y - 0.02, lp.z - 0.07)
		if grip == "vert":
			_mesh(g, _cyl(0.013, 0.075, 10), dark, gp + Vector3(0, -0.04, 0))
		else:
			_mesh(g, _box(0.02, 0.03, 0.06), dark, gp + Vector3(0, -0.012, 0), Vector3(-0.5, 0, 0))
	apply_camo(g, str(c.get("camo", "none")))


## Paint the gun (weapon_tex materials get the pattern; the procedural ones a solid colour).
static func apply_camo(g: Node3D, id: String) -> void:
	var cd: Dictionary = CAMOS.get(id, CAMOS.none)
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("armero"):
			continue   # attachments stay matte black, sight dots keep glowing red
		if not mi.has_meta("camo_src"):
			mi.set_meta("camo_src", mi.material_override)
		var src = mi.get_meta("camo_src")
		if id == "none" or not cd.has("c"):
			mi.material_override = src
			continue
		if src is ShaderMaterial and (src as ShaderMaterial).shader == WM.SHT:
			var m: ShaderMaterial = src.duplicate()
			var cols: Array = cd.c
			m.set_shader_parameter("camo", 0.9)
			m.set_shader_parameter("pattern", float(cd.get("pat", 0)))
			m.set_shader_parameter("tint", cols[0])
			m.set_shader_parameter("c2", cols[mini(1, cols.size() - 1)])
			m.set_shader_parameter("c3", cols[mini(2, cols.size() - 1)])
			m.set_shader_parameter("pat_scale", float(cd.get("scale", 9.0)))
			m.set_shader_parameter("paint_metal", float(cd.get("metal", 0.1)))
			m.set_shader_parameter("paint_rough", 0.3 if float(cd.get("metal", 0.1)) > 0.5 else 0.65)
			if cd.has("glow"):
				m.set_shader_parameter("emission", cols[0])
				m.set_shader_parameter("emission_energy", float(cd.glow))
			mi.material_override = m
		elif src is ShaderMaterial and src.get_shader_parameter("albedo") != null and src.get_shader_parameter("detail_nor") != null:
			var dn: Texture2D = src.get_shader_parameter("detail_nor")
			if dn.resource_path.contains("leather") or dn.resource_path.contains("denim") or dn.resource_path.contains("gravel"):
				continue   # gloves / sleeves
			var m2: ShaderMaterial = src.duplicate()
			m2.set_shader_parameter("albedo", (cd.c as Array)[0])
			m2.set_shader_parameter("metallic", float(cd.get("metal", 0.2)))
			m2.set_shader_parameter("roughness", 0.3 if float(cd.get("metal", 0.1)) > 0.5 else 0.6)
			mi.material_override = m2
