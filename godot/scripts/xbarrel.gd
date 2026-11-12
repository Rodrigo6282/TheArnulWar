extends StaticBody3D
## Explosive barrel (the scanned Barrel_01 with the flammable label): bullets, explosions and the
## knife wear it down; then it catches fire for a moment and blows up through game.explode()
## (kind "barrel": medals, kill credit, chain reactions with other barrels). In multiplayer the
## shooter's game explodes it (damage + net.boom effects) and tells the others to remove theirs.

var game
var bid := 0              # stable id (same layout on every peer) for net sync
var health := 40.0
var fuse := -1.0
var gone := false
var fire_fx: Node3D


func _ready() -> void:
	game = get_node_or_null("/root/Main")
	add_to_group("xbarrel")
	set_meta("barrel", true)


func take_damage(d: float, _head := false) -> bool:
	if gone or fuse >= 0.0:
		return false
	health -= d
	if health <= 0.0:
		fuse = 0.18
		if game:
			game.fx.puff(global_position + Vector3(0, 0.9, 0), Color(1.0, 0.55, 0.2), 1.2, 0.6, 0.5)
	return false


func _process(delta: float) -> void:
	if fuse < 0.0 or gone:
		return
	fuse -= delta
	if fuse <= 0.0:
		blow()


func blow() -> void:
	if gone:
		return
	gone = true
	var pos := global_position + Vector3(0, 0.5, 0)
	collision_layer = 0
	visible = false
	if game:
		if game.net.active:
			game.net.zzzz_barrel_send(bid)
		game.explode(pos, 170.0, 7.5, "barrel")
	queue_free()


## Another player blew it up: just remove it (the effects arrive through net.boom).
func remove_quiet() -> void:
	gone = true
	queue_free()
