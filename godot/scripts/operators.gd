extends RefCounted
## Playable operators: body (rig.gd character) + uniform tint, and the colours of the procedural
## fallback body / first-person gloves and sleeves. Used for the player's first-person
## arms, the multiplayer puppet other players see, and the menu preview.

const LIST := [
	{"name": "Halcón", "desc": "Fuerzas especiales · camuflaje digital y chaleco táctico", "body": "soldado_camo", "tint": Color(1, 1, 1), "uniform": Color(0.29, 0.31, 0.25), "uniform2": Color(0.24, 0.26, 0.21),
		"vest": Color(0.17, 0.18, 0.15), "pack": Color(0.32, 0.33, 0.25), "head": "helmet", "helmet": Color(0.23, 0.24, 0.2),
		"skin": Color(0.72, 0.54, 0.41), "glove": Color(0.34, 0.28, 0.2), "sleeve": Color(0.29, 0.32, 0.25)},
	{"name": "Espectro", "desc": "Asalto nocturno · equipo negro y máscara de gas", "body": "swat", "tint": Color(1, 1, 1), "uniform": Color(0.1, 0.1, 0.11), "uniform2": Color(0.08, 0.08, 0.09),
		"vest": Color(0.05, 0.05, 0.06), "pack": Color(0.12, 0.12, 0.13), "head": "balaclava", "helmet": Color(0.07, 0.07, 0.08),
		"skin": Color(0.6, 0.45, 0.35), "glove": Color(0.08, 0.08, 0.08), "sleeve": Color(0.11, 0.11, 0.12)},
	{"name": "Duna", "desc": "Infantería del desierto · uniforme caqui y casco", "body": "infanteria", "tint": Color(1.18, 1.05, 0.82), "uniform": Color(0.62, 0.53, 0.38), "uniform2": Color(0.55, 0.46, 0.32),
		"vest": Color(0.45, 0.38, 0.27), "pack": Color(0.5, 0.43, 0.3), "head": "boonie", "helmet": Color(0.58, 0.5, 0.36),
		"skin": Color(0.55, 0.38, 0.26), "glove": Color(0.5, 0.42, 0.3), "sleeve": Color(0.62, 0.53, 0.38)},
	{"name": "Ártico", "desc": "Montaña e invierno · camuflaje de nieve", "body": "soldado_camo", "tint": Color(1.55, 1.58, 1.65), "uniform": Color(0.82, 0.84, 0.86), "uniform2": Color(0.7, 0.72, 0.75),
		"vest": Color(0.45, 0.47, 0.5), "pack": Color(0.62, 0.64, 0.67), "head": "beanie", "helmet": Color(0.3, 0.32, 0.36),
		"skin": Color(0.85, 0.68, 0.56), "glove": Color(0.8, 0.82, 0.84), "sleeve": Color(0.8, 0.82, 0.85)},
	{"name": "Cobra", "desc": "Unidad urbana · equipo azul grisáceo", "body": "swat", "tint": Color(0.85, 1.05, 1.45), "uniform": Color(0.33, 0.37, 0.42), "uniform2": Color(0.26, 0.29, 0.33),
		"vest": Color(0.15, 0.17, 0.2), "pack": Color(0.2, 0.22, 0.26), "head": "cap", "helmet": Color(0.12, 0.14, 0.18),
		"skin": Color(0.42, 0.29, 0.2), "glove": Color(0.14, 0.15, 0.17), "sleeve": Color(0.33, 0.37, 0.42)},
	{"name": "Jaguar", "desc": "Selva · uniforme verde oliva", "body": "infanteria", "tint": Color(0.8, 1.0, 0.68), "uniform": Color(0.27, 0.3, 0.16), "uniform2": Color(0.2, 0.23, 0.12),
		"vest": Color(0.33, 0.27, 0.16), "pack": Color(0.25, 0.22, 0.14), "head": "bandana", "helmet": Color(0.45, 0.12, 0.1),
		"skin": Color(0.5, 0.35, 0.24), "glove": Color(0.22, 0.2, 0.14), "sleeve": Color(0.27, 0.3, 0.16)},
]


static func get_op(i: int) -> Dictionary:
	return LIST[clampi(i, 0, LIST.size() - 1)]
