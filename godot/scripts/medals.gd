extends RefCounted
## Medal definitions: id -> [name, points, colour, symbol]. Symbols are drawn by the UI badge.

const LIST := {
	"first": ["Primera sangre", 100, Color(0.8, 0.15, 0.12), "drop"],
	"head": ["Disparo a la cabeza", 50, Color(0.95, 0.68, 0.2), "target"],
	"double": ["Doble baja", 50, Color(0.3, 0.6, 0.95), "x2"],
	"triple": ["Triple baja", 100, Color(0.45, 0.4, 0.95), "x3"],
	"multi": ["Multibaja", 200, Color(0.75, 0.3, 0.9), "x4"],
	"streak5": ["Racha x5", 150, Color(0.3, 0.75, 0.4), "star"],
	"streak10": ["Racha x10", 300, Color(0.95, 0.55, 0.15), "star"],
	"streak20": ["Imparable", 600, Color(0.95, 0.2, 0.2), "crown"],
	"long": ["Larga distancia", 75, Color(0.3, 0.7, 0.8), "target"],
	"close": ["A quemarropa", 50, Color(0.85, 0.45, 0.2), "burst"],
	"collat": ["Colateral", 100, Color(0.6, 0.6, 0.65), "bullet"],
	"last": ["Último cartucho", 50, Color(0.8, 0.7, 0.3), "bullet"],
	"knife": ["Cuchillada", 75, Color(0.7, 0.72, 0.78), "blade"],
	"edge": ["Al límite", 100, Color(0.85, 0.15, 0.3), "heart"],
	"wave": ["Oleada impecable", 150, Color(0.25, 0.65, 0.95), "shield"],
	"survivor": ["Superviviente", 500, Color(0.55, 0.85, 0.3), "crown"],
	"boom": ["Demolición", 150, Color(0.95, 0.45, 0.1), "burst"],
}
