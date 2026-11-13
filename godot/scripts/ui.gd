extends CanvasLayer
## Menus and HUD, built with Control nodes.

const Medals := preload("res://scripts/medals.gd")
const WB := preload("res://scripts/world.gd")
const GOLD := Color(0.95, 0.69, 0.2)
const RED := Color(0.88, 0.25, 0.18)

var game
var root: Control
var menu: Control
var pause_p: Control
var over_p: Control
var hud: Control
var over_stats: Label
var ammo_l: Label
var wname_l: Label
var wave_l: Label
var stats_l: Label
var notice_l: Label
var notice_s: Label
var notice_t := 0.0
var prompt_l: Label
var feed: VBoxContainer
var hp_fill: ColorRect
var vignette: TextureRect
var ch: Array = []
var hitmark: Control
var hitmark_t := 0.0
var dmg_root: Control
var q_opt: OptionButton
var d_opt: OptionButton
var fs_chk: CheckButton
var sens_sl: HSlider
var sens_l: Label
var fps_l: Label
var map_btns: Array = []
var map_desc: Label
var profile_l: Label
var scope_ov: Control
var round_l: Label
var info_l: Label
var medal_q: Array = []
var medal_t := 0.0
var medal_box: Control
var medal_badge
var medal_name: Label
var medal_pts: Label
var radar_c: Control
var mini: Control
var mp_p: Control
var mp_name: LineEdit
var mp_ip: LineEdit
var mp_map: OptionButton
var mp_mode: OptionButton
var pause_online: Label
var pause_copy: Button
var mp_stat: Label
var upd_p: Control
var upd_msg: Label
var upd_btn: Button
var mp_list: VBoxContainer
var board_p: Control
var board_l: Label
var op_p: Control
var op_name: LineEdit
var op_desc: Label
var op_btns: Array = []
var op_vp: SubViewport
var op_model
var op_btn: Button
var perk_row: HBoxContainer
# multiplayer lobby / chat / co-op player list
var lobby_p: Control
var lob_info: Label
var lob_code: HBoxContainer
var lob_code_l: Label
var lob_list: VBoxContainer
var lob_chat: VBoxContainer
var lob_chat_scroll: ScrollContainer
var lob_in: LineEdit
var lob_start: Button
var lob_team: Button
var lob_wait: Label
var lob_voice: OptionButton
var v_opt: OptionButton
var chat_box: VBoxContainer
var chat_in: LineEdit
var chat_open := false
var coop_box: VBoxContainer
var coop_t := 0.0
var lob_t := 0.0
var mini_tex: ImageTexture
const MINI_SIZE := 210.0
const MINI_RANGE := 34.0          # metres from the centre to the edge


## Medal badge drawn with vector shapes (no image assets needed).
class Badge extends Control:
	var col := Color.WHITE
	var sym := "star"

	func _poly(c: Vector2, r: float, n: int, rot := 0.0) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in n:
			var a := rot + TAU * i / n
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		return pts

	func _star(c: Vector2, r1: float, r2: float, n: int) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in n * 2:
			var a := -PI / 2 + PI * i / n
			pts.append(c + Vector2(cos(a), sin(a)) * (r1 if i % 2 == 0 else r2))
		return pts

	func _draw() -> void:
		var c := size * 0.5
		var gold := Color(0.95, 0.78, 0.35)
		draw_colored_polygon(_poly(c, 46, 8, PI / 8), Color(0.05, 0.05, 0.05, 0.85))
		draw_colored_polygon(_poly(c, 42, 8, PI / 8), col.darkened(0.35))
		var ring := _poly(c, 42, 8, PI / 8)
		ring.append(ring[0])
		draw_polyline(ring, gold, 3.0, true)
		draw_circle(c, 29, col)
		draw_arc(c, 29, 0, TAU, 40, Color(1, 1, 1, 0.5), 2.0, true)
		var w := Color(1, 1, 1)
		var f := ThemeDB.fallback_font
		match sym:
			"star":
				draw_colored_polygon(_star(c, 20, 8, 5), w)
			"crown":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-18, 10), c + Vector2(-18, -8), c + Vector2(-9, 2), c + Vector2(0, -14), c + Vector2(9, 2), c + Vector2(18, -8), c + Vector2(18, 10)]), w)
			"target":
				draw_arc(c, 17, 0, TAU, 32, w, 3.0, true)
				draw_arc(c, 8, 0, TAU, 24, w, 3.0, true)
				draw_line(c + Vector2(-22, 0), c + Vector2(22, 0), w, 2.0)
				draw_line(c + Vector2(0, -22), c + Vector2(0, 22), w, 2.0)
			"drop":
				draw_circle(c + Vector2(0, 5), 11, w)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-10, 1), c + Vector2(0, -18), c + Vector2(10, 1)]), w)
			"blade":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-16, 14), c + Vector2(10, -12), c + Vector2(16, -18), c + Vector2(12, -8), c + Vector2(-12, 18)]), w)
			"bullet":
				draw_rect(Rect2(c + Vector2(-6, -6), Vector2(12, 20)), w)
				draw_colored_polygon(_poly(c + Vector2(0, -6), 6, 12), w)
				draw_rect(Rect2(c + Vector2(-8, 14), Vector2(16, 4)), w)
			"heart":
				draw_circle(c + Vector2(-7, -4), 9, w)
				draw_circle(c + Vector2(7, -4), 9, w)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-15, 0), c + Vector2(15, 0), c + Vector2(0, 17)]), w)
			"shield":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-15, -14), c + Vector2(15, -14), c + Vector2(13, 4), c + Vector2(0, 18), c + Vector2(-13, 4)]), w)
			"burst":
				draw_colored_polygon(_star(c, 20, 9, 8), w)
			_:
				draw_string(f, c + Vector2(-30, 10), sym, HORIZONTAL_ALIGNMENT_CENTER, 60, 28, w)


func setup(g) -> void:
	game = g
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_hud()
	_build_menu()
	_build_pause()
	_build_over()
	_build_mp()
	_build_ops()
	_build_lobby()
	_build_chat()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var normal := StyleBoxFlat.new()
	normal.bg_color = GOLD
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 28
	normal.content_margin_right = 28
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate()
	hover.bg_color = GOLD.lightened(0.15)
	var pressed := normal.duplicate()
	pressed.bg_color = GOLD.darkened(0.15)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color(0.1, 0.08, 0.02))
	t.set_color("font_hover_color", "Button", Color(0.1, 0.08, 0.02))
	t.set_color("font_pressed_color", "Button", Color(0.1, 0.08, 0.02))
	t.set_font_size("font_size", "Button", 20)
	return t


func _label(text: String, size: int, color := Color.WHITE, outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _overlay() -> Control:
	var o := ColorRect.new()
	o.color = Color(0.02, 0.03, 0.03, 0.62)
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(o)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.add_child(cc)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)
	o.set_meta("box", vb)
	return o


func _button(parent: Control, text: String, cb: Callable, secondary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 0)
	if secondary:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.23, 0.27, 0.25)
		sb.set_corner_radius_all(6)
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		b.add_theme_stylebox_override("normal", sb)
		var sh := sb.duplicate()
		sh.bg_color = Color(0.3, 0.35, 0.32)
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_color_override("font_color", Color(0.92, 0.94, 0.93))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(func():
		game.sfx.play("click", -6)
		cb.call()
	)
	parent.add_child(b)
	return b


func _build_menu() -> void:
	menu = _overlay()
	var vb: VBoxContainer = menu.get_meta("box")
	var title := _label("THE ARNUL WAR", 78, GOLD, 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := _label("OPERACIÓN Y ZOMBIS  ·  MOTOR GODOT 4.7", 15, Color(0.85, 0.88, 0.86), 3)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 10)
	vb.add_child(sp)
	var maps := HBoxContainer.new()
	maps.alignment = BoxContainer.ALIGNMENT_CENTER
	maps.add_theme_constant_override("separation", 10)
	vb.add_child(maps)
	for i in WB.MAPS.size():
		var md: Dictionary = WB.MAPS[i]
		var b := _button(maps, "%s\n%s" % [md.name, "ZOMBIS" if md.mode == "zombies" else "OPERACIÓN"], func():
			game.load_map(i)
			game.save_settings()
			sync_settings()
		, true)
		b.custom_minimum_size = Vector2(164, 60)
		b.add_theme_font_size_override("font_size", 14)
		map_btns.append(b)
	map_desc = _label("", 16, Color(0.9, 0.92, 0.9), 3)
	map_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(map_desc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	_button(row, "DESPLEGAR", func(): game.start_game())
	_button(row, "MULTIJUGADOR", func(): show_mp(), true)
	op_btn = _button(row, "OPERADOR", func(): show_ops(), true)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	vb.add_child(gc)
	grid.add_child(_label("Calidad gráfica", 17))
	q_opt = OptionButton.new()
	for n in ["Baja", "Media", "Alta (iluminación global)"]:
		q_opt.add_item(n)
	q_opt.item_selected.connect(func(i):
		game.settings.quality = i
		game.apply_quality()
		game.save_settings()
	)
	grid.add_child(q_opt)
	grid.add_child(_label("Pantalla completa", 17))
	fs_chk = CheckButton.new()
	fs_chk.toggled.connect(func(on):
		game.settings.fullscreen = on
		game.apply_fullscreen()
		game.save_settings()
	)
	grid.add_child(fs_chk)
	grid.add_child(_label("Sensibilidad", 17))
	var sh := HBoxContainer.new()
	sens_sl = HSlider.new()
	sens_sl.min_value = 0.2
	sens_sl.max_value = 3.0
	sens_sl.step = 0.05
	sens_sl.custom_minimum_size = Vector2(200, 0)
	sens_l = _label("1.00", 16)
	sens_sl.value_changed.connect(func(v):
		game.settings.sens = v
		sens_l.text = "%.2f" % v
		game.save_settings()
	)
	sh.add_child(sens_sl)
	sh.add_child(sens_l)
	grid.add_child(sh)
	grid.add_child(_label("Dificultad", 17))
	d_opt = OptionButton.new()
	for n in ["Recluta", "Regular", "Veterano"]:
		d_opt.add_item(n)
	d_opt.item_selected.connect(func(i):
		game.settings.diff = i
		game.save_settings()
	)
	grid.add_child(d_opt)
	grid.add_child(_label("Chat de voz", 17))
	v_opt = _voice_option()
	grid.add_child(v_opt)
	profile_l = _label("", 16, GOLD, 3)
	profile_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(profile_l)
	var help := _label("WASD moverse · Ratón mirar · Clic izq. disparar · Clic der. apuntar · Shift correr · Espacio saltar · C agacharse · Q / E inclinarse\nR recargar · 1-6 o rueda cambiar arma · V cuchillo · G granada · B racha · F interactuar (zombis) · Esc pausa · Alt+Intro pantalla completa\nMultijugador: Intro escribir en el chat · T (mantener) hablar por voz · Tab marcador", 14, Color(0.85, 0.88, 0.86), 3)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(help)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row2)
	_button(row2, "Salir", func(): game.get_tree().quit(), true)
	var ver := _label("Versión %s" % str(ProjectSettings.get_setting("application/config/version", "")), 14, Color(0.75, 0.78, 0.76), 3)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ver)
	if game.updater:
		game.updater.found.connect(func():
			ver.text = "Versión %s  ·  nueva versión %s: actualización obligatoria" % [game.updater.current, game.updater.latest]
			ver.add_theme_color_override("font_color", GOLD)
			if game.state == "menu":
				show_update()
		)
	sync_settings()


func sync_settings() -> void:
	if q_opt == null:
		return
	q_opt.select(game.settings.quality)
	d_opt.select(game.settings.diff)
	fs_chk.set_pressed_no_signal(game.settings.fullscreen)
	sens_sl.set_value_no_signal(game.settings.sens)
	sens_l.text = "%.2f" % game.settings.sens
	for vo in [v_opt, lob_voice]:
		if vo:
			vo.select(int(game.settings.get("voice", 0)))
	for i in map_btns.size():
		var on: bool = i == game.map_idx
		var b: Button = map_btns[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = GOLD if on else Color(0.23, 0.27, 0.25)
		sb.set_corner_radius_all(6)
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02) if on else Color(0.92, 0.94, 0.93))
	if map_desc:
		map_desc.text = WB.MAPS[game.map_idx].desc
	if profile_l:
		profile_l.text = "Récord Operación: %d puntos   ·   Mejor ronda Zombis: %d   ·   Medallas ganadas: %d" % [game.best, game.best_round, game.medal_count()]


func _build_pause() -> void:
	pause_p = _overlay()
	var vb: VBoxContainer = pause_p.get_meta("box")
	var t := _label("PAUSA", 52, Color.WHITE, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	_button(vb, "Continuar", func(): game.resume())
	pause_online = _label("", 17, GOLD, 3)
	pause_online.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_online.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_online.custom_minimum_size = Vector2(560, 0)
	pause_online.visible = false
	vb.add_child(pause_online)
	pause_copy = _button(vb, "Copiar código de invitación", func():
		DisplayServer.clipboard_set(game.net.invite_code)
		pause_online.text = "Código %s copiado: pégalo en el chat con tus amigos" % game.net.invite_code
	, true)
	pause_copy.visible = false
	game.net.online_changed.connect(_refresh_pause_online)
	_button(vb, "Reiniciar", func():
		if not game.net.active:
			game.start_game()
	, true)
	_button(vb, "Pantalla completa", func():
		game.settings.fullscreen = not game.settings.fullscreen
		game.apply_fullscreen()
		game.save_settings()
		sync_settings()
	, true)
	_button(vb, "Menú principal", func(): game.to_menu(), true)
	_button(vb, "Salir del juego", func(): game.get_tree().quit(), true)


func _build_over() -> void:
	over_p = _overlay()
	var vb: VBoxContainer = over_p.get_meta("box")
	var t := _label("CAÍSTE EN COMBATE", 52, RED, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	over_stats = _label("", 22, GOLD, 4)
	over_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(over_stats)
	_button(vb, "Volver a desplegar", func(): game.start_game())
	_button(vb, "Menú principal", func(): game.to_menu(), true)


func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	vignette = TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gr.colors = PackedColorArray([Color(0.55, 0, 0, 0), Color(0.55, 0, 0, 0), Color(0.55, 0, 0, 0.9)])
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 0.5)
	vignette.texture = gt
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.0
	hud.add_child(vignette)
	scope_ov = Control.new()
	scope_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_ov.visible = false
	hud.add_child(scope_ov)
	var sc := TextureRect.new()
	var sg := GradientTexture2D.new()
	var sgr := Gradient.new()
	sgr.offsets = PackedFloat32Array([0.0, 0.86, 0.9, 1.0])
	sgr.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.15), Color(0, 0, 0, 1), Color(0, 0, 0, 1)])
	sg.gradient = sgr
	sg.fill = GradientTexture2D.FILL_RADIAL
	sg.fill_from = Vector2(0.5, 0.5)
	sg.fill_to = Vector2(1.0, 0.5)
	sg.width = 512
	sg.height = 512
	sc.texture = sg
	sc.stretch_mode = TextureRect.STRETCH_SCALE
	sc.set_anchors_preset(Control.PRESET_CENTER)
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_ov.add_child(sc)
	scope_ov.set_meta("lens", sc)
	for side in 2:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scope_ov.add_child(bar)
		scope_ov.set_meta("bar%d" % side, bar)
	for i in 4:
		var ln := ColorRect.new()
		ln.color = Color(0, 0, 0, 0.9)
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scope_ov.add_child(ln)
		scope_ov.set_meta("ln%d" % i, ln)
	var dot := ColorRect.new()
	dot.color = Color(1, 0.15, 0.1)
	dot.size = Vector2(4, 4)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_ov.add_child(dot)
	scope_ov.set_meta("dot", dot)
	var center := Control.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(center)
	for i in 4:
		var r := ColorRect.new()
		r.color = Color.WHITE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.size = Vector2(2, 10) if i < 2 else Vector2(10, 2)
		center.add_child(r)
		ch.append(r)
	hitmark = Control.new()
	hitmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(hitmark)
	for a in [45, 135, 225, 315]:
		var piv := Control.new()
		piv.rotation_degrees = a
		hitmark.add_child(piv)
		var l := ColorRect.new()
		l.size = Vector2(2, 9)
		l.position = Vector2(-1, -18)
		l.color = Color.WHITE
		piv.add_child(l)
	hitmark.modulate.a = 0.0
	dmg_root = Control.new()
	dmg_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(dmg_root)
	wave_l = _label("", 22, Color.WHITE, 5)
	wave_l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wave_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_l.position = Vector2(-300, 14)
	wave_l.size = Vector2(600, 60)
	hud.add_child(wave_l)
	stats_l = _label("", 18, Color.WHITE, 4)
	stats_l.position = Vector2(22, 236)
	hud.add_child(stats_l)
	fps_l = _label("", 13, Color(0.8, 0.85, 0.8), 3)
	fps_l.position = Vector2(22, 336)
	hud.add_child(fps_l)
	notice_l = _label("", 50, Color.WHITE, 8)
	notice_l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notice_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_l.position = Vector2(-500, 180)
	notice_l.size = Vector2(1000, 70)
	hud.add_child(notice_l)
	notice_s = _label("", 18, Color(0.92, 0.94, 0.93), 4)
	notice_s.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notice_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_s.position = Vector2(-500, 250)
	notice_s.size = Vector2(1000, 40)
	hud.add_child(notice_s)
	prompt_l = _label("", 18, GOLD, 4)
	prompt_l.set_anchors_preset(Control.PRESET_CENTER)
	prompt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_l.position = Vector2(-300, 90)
	prompt_l.size = Vector2(600, 40)
	hud.add_child(prompt_l)
	feed = VBoxContainer.new()
	feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	feed.position = Vector2(-420, 18)
	feed.size = Vector2(400, 200)
	feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(feed)
	var br := VBoxContainer.new()
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br.position = Vector2(-340, -120)
	br.size = Vector2(320, 100)
	br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(br)
	wname_l = _label("", 16, Color(0.9, 0.92, 0.9), 4)
	wname_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(wname_l)
	ammo_l = _label("", 52, Color.WHITE, 6)
	ammo_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(ammo_l)
	perk_row = HBoxContainer.new()
	perk_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	perk_row.position = Vector2(22, -230)
	perk_row.add_theme_constant_override("separation", 8)
	perk_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(perk_row)
	round_l = _label("", 68, Color(0.75, 0.08, 0.06), 8)
	round_l.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	round_l.position = Vector2(22, -150)
	hud.add_child(round_l)
	info_l = _label("", 16, Color(0.9, 0.92, 0.9), 4)
	info_l.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_l.position = Vector2(-420, -190)
	info_l.size = Vector2(400, 70)
	hud.add_child(info_l)
	mini = Control.new()
	mini.position = Vector2(18, 18)
	mini.size = Vector2(MINI_SIZE, MINI_SIZE)
	mini.clip_contents = true
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(mini)
	mini.draw.connect(_draw_minimap)
	radar_c = Control.new()
	radar_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	radar_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(radar_c)
	radar_c.draw.connect(_draw_radar)
	medal_box = Control.new()
	medal_box.set_anchors_preset(Control.PRESET_CENTER)
	medal_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal_box.visible = false
	hud.add_child(medal_box)
	medal_badge = Badge.new()
	medal_badge.size = Vector2(100, 100)
	medal_badge.position = Vector2(-50, 110)
	medal_badge.pivot_offset = Vector2(50, 50)
	medal_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal_box.add_child(medal_badge)
	medal_name = _label("", 22, Color.WHITE, 5)
	medal_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	medal_name.position = Vector2(-250, 212)
	medal_name.size = Vector2(500, 30)
	medal_box.add_child(medal_name)
	medal_pts = _label("", 18, GOLD, 4)
	medal_pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	medal_pts.position = Vector2(-250, 240)
	medal_pts.size = Vector2(500, 26)
	medal_box.add_child(medal_pts)
	var hp_box := Control.new()
	hp_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_box.position = Vector2(24, -50)
	hp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hp_box)
	hp_box.add_child(_label("SALUD", 15))
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.55)
	back.position = Vector2(0, 24)
	back.size = Vector2(240, 9)
	hp_box.add_child(back)
	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.5, 0.83, 0.42)
	hp_fill.position = Vector2(0, 24)
	hp_fill.size = Vector2(240, 9)
	hp_box.add_child(hp_fill)


func _build_mp() -> void:
	mp_p = _overlay()
	var vb: VBoxContainer = mp_p.get_meta("box")
	var t := _label("MULTIJUGADOR", 52, GOLD, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var sub := _label("", 16, Color(0.9, 0.92, 0.9), 3)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(640, 0)
	var subc := CenterContainer.new()
	subc.add_child(sub)
	vb.add_child(subc)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	vb.add_child(gc)
	grid.add_child(_label("Tu nombre", 17))
	mp_name = LineEdit.new()
	mp_name.custom_minimum_size = Vector2(260, 0)
	mp_name.max_length = 16
	mp_name.text = game.settings.get("name", "Jugador")
	grid.add_child(mp_name)
	grid.add_child(_label("Operador", 17))
	grid.add_child(_label("(cámbialo en el menú OPERADOR)", 15, Color(0.8, 0.82, 0.8)))
	grid.add_child(_label("Modo de juego (host)", 17))
	mp_mode = OptionButton.new()
	for mid in game.net.MODE_ORDER:
		mp_mode.add_item(game.net.MODES[mid][0])
	grid.add_child(mp_mode)
	grid.add_child(_label("Mapa (host)", 17))
	mp_map = OptionButton.new()
	grid.add_child(mp_map)
	# the map list depends on the mode: zombie maps for co-op, Operación maps for the rest
	var fill_maps := func():
		var mid: String = game.net.MODE_ORDER[mp_mode.selected]
		var want := "zombies" if mid == "zombies" else "ops"
		mp_map.clear()
		for i in WB.MAPS.size():
			if WB.MAPS[i].mode == want:
				mp_map.add_item(WB.MAPS[i].name, i)
		sub.text = game.net.MODES[mid][1]
		game.settings["mp_mode"] = mid
	mp_mode.item_selected.connect(func(_i): fill_maps.call())
	mp_mode.selected = maxi(0, game.net.MODE_ORDER.find(game.settings.get("mp_mode", "ffa")))
	fill_maps.call()
	# ---- two clear sections side by side: local network | online (internet)
	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 24)
	vb.add_child(cols)
	var card := func(title: String, sub: String) -> VBoxContainer:
		var pc := PanelContainer.new()
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = Color(0.03, 0.04, 0.04, 0.72)
		sb2.set_corner_radius_all(8)
		sb2.set_content_margin_all(16)
		sb2.border_color = Color(0.95, 0.69, 0.2, 0.55)
		sb2.set_border_width_all(1)
		pc.add_theme_stylebox_override("panel", sb2)
		pc.custom_minimum_size = Vector2(470, 330)
		cols.add_child(pc)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		pc.add_child(v)
		var h := _label(title, 26, GOLD, 5)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(h)
		var s := _label(sub, 14, Color(0.85, 0.88, 0.86), 3)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(s)
		return v
	var host_with := func(online: bool) -> void:
		_save_mp()
		var err: String = game.net.host(mp_name.text, mp_map.get_item_id(mp_map.selected), game.net.PORT, game.net.MODE_ORDER[mp_mode.selected], online)
		mp_stat.text = err
	# LAN
	var lan: VBoxContainer = card.call("EN TU RED (LAN)", "Misma wifi o cable. Las partidas aparecen solas en la lista.")
	_button(lan, "CREAR PARTIDA LOCAL", func(): host_with.call(false))
	var lt := _label("PARTIDAS EN TU RED", 17, Color(0.95, 0.9, 0.75), 3)
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lan.add_child(lt)
	var lpanel := PanelContainer.new()
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	lsb.set_corner_radius_all(6)
	lsb.set_content_margin_all(8)
	lpanel.add_theme_stylebox_override("panel", lsb)
	lpanel.custom_minimum_size = Vector2(0, 120)
	lan.add_child(lpanel)
	mp_list = VBoxContainer.new()
	mp_list.add_theme_constant_override("separation", 8)
	lpanel.add_child(mp_list)
	game.net.lan_changed.connect(_refresh_lan)
	_refresh_lan()
	# ONLINE
	var onl: VBoxContainer = card.call("ONLINE (POR INTERNET)", "Juega con amigos de cualquier sitio, sin abrir puertos. Al crear la partida recibes un código de invitación para compartir.")
	_button(onl, "CREAR PARTIDA ONLINE", func(): host_with.call(true))
	var jl := _label("¿Te han pasado un código? Escríbelo aquí:", 16, Color(0.95, 0.9, 0.75), 3)
	jl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	onl.add_child(jl)
	var iprow := HBoxContainer.new()
	iprow.alignment = BoxContainer.ALIGNMENT_CENTER
	iprow.add_theme_constant_override("separation", 10)
	onl.add_child(iprow)
	mp_ip = LineEdit.new()
	mp_ip.custom_minimum_size = Vector2(220, 0)
	mp_ip.placeholder_text = "Código, ej.: 7K3M-9QX4"
	mp_ip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var last: String = game.settings.get("last_ip", "")
	mp_ip.text = last if last != "127.0.0.1" else ""
	iprow.add_child(mp_ip)
	var jb := _button(iprow, "UNIRSE CON CÓDIGO", func():
		_save_mp()
		var txt := mp_ip.text.strip_edges()
		# an IP (LAN / game VPN) connects directly; anything else is an online invite code
		var err: String = game.net.join(mp_name.text, txt) if txt.count(".") == 3 else game.net.join_code(mp_name.text, txt)
		mp_stat.text = err if err != "" else game.net.status
	, true)
	jb.custom_minimum_size = Vector2(200, 0)
	var oh := _label("El código aparece al crear la partida online (también con Tab y en el menú de pausa).\nTambién puedes escribir una IP (por ejemplo, la de una VPN de juegos).", 13, Color(0.8, 0.82, 0.8), 3)
	oh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	oh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	onl.add_child(oh)
	var ips: Array = game.net.local_ips()
	var info := _label("Tu IP local: %s  ·  Si Windows pregunta por el firewall, pulsa \"Permitir acceso\" (marca redes privadas y públicas)." % [", ".join(ips) if not ips.is_empty() else "desconocida"], 14, Color(0.85, 0.88, 0.86), 3)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(info)
	mp_stat = _label("", 17, GOLD, 4)
	mp_stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(mp_stat)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row2)
	_button(row2, "Volver", func():
		game.net.leave()
		show_menu()
	, true)
	mp_p.visible = false
	board_p = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.04, 0.82)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	board_p.add_theme_stylebox_override("panel", sb)
	board_p.set_anchors_preset(Control.PRESET_CENTER)
	board_p.position = Vector2(-260, -180)
	board_p.custom_minimum_size = Vector2(520, 0)
	board_p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_l = _label("", 20, Color.WHITE, 3)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	board_l.add_theme_font_override("font", mono)
	board_p.add_child(board_l)
	board_p.visible = false
	hud.add_child(board_p)


const OPS := preload("res://scripts/operators.gd")
const SoldierScript := preload("res://scripts/soldier.gd")


func _build_ops() -> void:
	op_p = _overlay()
	var vb: VBoxContainer = op_p.get_meta("box")
	var t := _label("OPERADOR", 52, GOLD, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	vb.add_child(row)
	# live 3D preview in its own little world
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(330, 440)
	svc.stretch = true
	row.add_child(svc)
	op_vp = SubViewport.new()
	op_vp.own_world_3d = true
	op_vp.size = Vector2i(330, 440)
	op_vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(op_vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.6)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	op_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	op_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.7, 0.8, 1.0)
	op_vp.add_child(rim)
	var floor_m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 0.95
	cyl.height = 0.06
	floor_m.mesh = cyl
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.22, 0.22)
	fm.metallic = 0.5
	fm.roughness = 0.4
	floor_m.material_override = fm
	floor_m.position.y = -0.03
	op_vp.add_child(floor_m)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.25, 3.1)
	cam.fov = 38.0
	op_vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 1.0, 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	row.add_child(col)
	col.add_child(_label("Nombre del jugador", 18))
	op_name = LineEdit.new()
	op_name.max_length = 16
	op_name.custom_minimum_size = Vector2(320, 0)
	op_name.text = game.settings.get("name", "Jugador")
	op_name.text_changed.connect(func(tx):
		game.settings["name"] = tx.strip_edges() if tx.strip_edges() != "" else "Jugador"
		_refresh_preview()
	)
	col.add_child(op_name)
	col.add_child(_label("Elige tu operador", 18))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for i in OPS.LIST.size():
		var b := _button(grid, OPS.LIST[i].name, func():
			game.settings["op"] = i
			game.save_settings()
			_refresh_preview()
		, true)
		b.custom_minimum_size = Vector2(160, 46)
		op_btns.append(b)
	op_desc = _label("", 16, Color(0.9, 0.92, 0.9), 3)
	op_desc.custom_minimum_size = Vector2(320, 0)
	op_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(op_desc)
	_button(col, "Listo", func():
		game.save_settings()
		show_menu()
	)
	op_p.visible = false


func _refresh_preview() -> void:
	var cur := int(game.settings.get("op", 0))
	for i in op_btns.size():
		var on := i == cur
		var b: Button = op_btns[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = GOLD if on else Color(0.23, 0.27, 0.25)
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02) if on else Color(0.92, 0.94, 0.93))
	op_desc.text = OPS.get_op(cur).desc
	if op_btn:
		op_btn.text = "OPERADOR: %s" % OPS.get_op(cur).name.to_upper()
	if op_vp == null:
		return
	if op_model and is_instance_valid(op_model):
		op_model.queue_free()
	op_model = SoldierScript.new()
	op_model.game = game
	op_model.puppet = true
	op_model.op = cur
	op_model.display_name = game.settings.get("name", "Jugador")
	op_model.net_aim = true
	op_vp.add_child(op_model)


func show_ops() -> void:
	menu.visible = false
	op_p.visible = true
	op_name.text = game.settings.get("name", "Jugador")
	_refresh_preview()


func _save_mp() -> void:
	game.settings["name"] = mp_name.text.strip_edges() if mp_name.text.strip_edges() != "" else "Jugador"
	mp_name.text = game.settings["name"]
	game.settings["last_ip"] = mp_ip.text.strip_edges()
	game.save_settings()


func _refresh_lan() -> void:
	if mp_list == null:
		return
	for c in mp_list.get_children():
		c.queue_free()
	var games: Dictionary = game.net.lan_games
	if games.is_empty():
		var msg := "Buscando partidas en la red local..." if game.net.listen_ok or game.net.listen_udp == null else "No se puede buscar partidas (el puerto %d está ocupado por otra copia del juego)." % game.net.LAN_PORT
		var l := _label(msg + "\nCuando alguien de tu red pulse CREAR PARTIDA LOCAL aparecerá aquí.", 16, Color(0.8, 0.82, 0.8), 3)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mp_list.add_child(l)
		return
	for uid in games:
		var g: Dictionary = games[uid]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 14)
		var info := _label("%s  ·  %s  ·  %d/%d jugadores" % [g.name, g.map, g.n, g.max], 18, Color.WHITE, 3)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.add_child(info)
		var full: bool = g.n >= g.max
		var ip: String = g.ip
		var port: int = g.port
		var b := _button(r, "LLENA" if full else "UNIRSE", func():
			_save_mp()
			var err: String = game.net.join(mp_name.text, ip, port)
			mp_stat.text = err if err != "" else game.net.status
		)
		b.custom_minimum_size = Vector2(150, 0)
		b.disabled = full
		mp_list.add_child(r)


func show_mp() -> void:
	menu.visible = false
	if lobby_p:
		lobby_p.visible = false
	over_p.visible = false
	pause_p.visible = false
	hud.visible = false
	mp_p.visible = true
	mp_stat.text = ""
	mp_name.text = game.settings.get("name", "Jugador")
	if game.updater and game.updater.newer:
		show_update()


## "New version" window (updater.gd): updating is mandatory (online play needs the same version on
## every PC), so it covers everything and only offers ACTUALIZAR or quitting.
func show_update() -> void:
	var u = game.updater
	if upd_p == null:
		upd_p = _overlay()
		upd_p.color = Color(0.01, 0.015, 0.015, 0.86)
		var vb: VBoxContainer = upd_p.get_meta("box")
		var t := _label("NUEVA VERSIÓN DISPONIBLE", 44, GOLD, 8)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(t)
		upd_msg = _label("", 19, Color(0.92, 0.94, 0.93), 3)
		upd_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		upd_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		upd_msg.custom_minimum_size = Vector2(720, 0)
		vb.add_child(upd_msg)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 16)
		vb.add_child(row)
		upd_btn = _button(row, "ACTUALIZAR", func():
			upd_btn.disabled = true
			upd_msg.text = "Descargando la versión %s..." % game.updater.latest
			game.updater.download()
		)
		_button(row, "Salir del juego", func(): game.get_tree().quit(), true)
		u.progress.connect(func(done: int, total: int):
			var pct := 100.0 * done / maxf(1.0, total)
			upd_msg.text = "Descargando la versión %s...  %d %%  (%d / %d MB)
Al terminar se abrirá el instalador y el juego se cerrará." % [game.updater.latest, int(pct), done / 1048576, total / 1048576]
		)
		u.failed.connect(func(msg: String):
			upd_msg.text = msg
			upd_btn.disabled = false
		)
	upd_msg.text = "Ya está disponible la versión %s (tienes la %s).
Para seguir jugando hay que actualizar: todos los jugadores deben tener la misma versión.

Al pulsar ACTUALIZAR se descargará el instalador (%d MB), se abrirá y el juego se cerrará. Tu progreso se conserva." % [u.latest, u.current, maxi(1, u.installer_size / 1048576)]
	menu.visible = false
	if mp_p:
		mp_p.visible = false
	upd_btn.disabled = u.downloading
	upd_p.visible = true
	root.move_child(upd_p, root.get_child_count() - 1)


func mp_status(t: String) -> void:
	if mp_stat:
		mp_stat.text = t


func show_menu() -> void:
	if lobby_p:
		lobby_p.visible = false
	if mp_p:
		mp_p.visible = false
	if op_p:
		op_p.visible = false
		if op_model and is_instance_valid(op_model):
			op_model.queue_free()
		op_model = null
	if op_btn:
		op_btn.text = "OPERADOR: %s" % OPS.get_op(int(game.settings.get("op", 0))).name.to_upper()
	menu.visible = true
	pause_p.visible = false
	over_p.visible = false
	hud.visible = false
	sync_settings()
	if game.updater:
		if game.updater.newer:
			show_update()
		else:
			game.updater.recheck()


func show_hud() -> void:
	if mp_p:
		mp_p.visible = false
	menu.visible = false
	pause_p.visible = false
	over_p.visible = false
	hud.visible = true


func show_pause() -> void:
	pause_p.visible = true
	sync_settings()
	_refresh_pause_online()


## Host of an online game: invite code + copy button in the pause menu.
func _refresh_pause_online() -> void:
	if pause_online == null:
		return
	var ol: String = game.net.online_line()
	pause_online.text = ol
	pause_online.visible = ol != ""
	pause_copy.visible = game.net.invite_code != "" and game.net.active and game.net.is_host


func show_gameover(st: Dictionary) -> void:
	var mt := ""
	for id in st.medals:
		mt += "%s x%d   " % [Medals.LIST[id][0], st.medals[id]]
	if mt == "":
		mt = "Sin medallas esta vez"
	if st.mode == "zombies":
		over_stats.text = "Ronda %d   ·   Bajas %d   ·   A la cabeza %d   ·   Puntos %d\nMejor ronda: %d\n\nMEDALLAS: %s" % [st.round, st.kills, st.heads, st.score, st.best_round, mt]
	else:
		over_stats.text = "Puntos %d   ·   Oleada %d   ·   Bajas %d   ·   A la cabeza %d   ·   Precisión %d%%\nRécord: %d\n\nMEDALLAS: %s" % [st.score, st.wave, st.kills, st.heads, st.acc, st.best, mt]
	over_p.visible = true
	hud.visible = false


func notice(t: String, sub := "", dur := 2.5) -> void:
	notice_l.text = t
	notice_s.text = sub
	notice_t = dur
	notice_l.modulate.a = 1.0
	notice_s.modulate.a = 1.0


func feed_line(text: String, head: bool) -> void:
	var l := _label(text, 17, GOLD if head else Color.WHITE, 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	feed.add_child(l)
	feed.move_child(l, 0)
	while feed.get_child_count() > 6:
		feed.get_child(feed.get_child_count() - 1).queue_free()
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func reset_feed() -> void:
	for c in feed.get_children():
		c.queue_free()
	medal_q.clear()
	medal_t = 0.0
	medal_box.visible = false


## Top-down texture of the current map (walls, buildings, props), built once per map load.
func build_minimap(rects: Array) -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.16, 0.19, 0.17, 0.82))
	for q in rects:
		var top: float = q[4]
		if top <= 0.05:
			continue
		var c := Color(0.62, 0.64, 0.6, 0.95) if top > 2.0 else Color(0.38, 0.4, 0.37, 0.9)
		var x0 := clampi(int((q[0] + 64.0) * 2.0), 0, 255)
		var x1 := clampi(int((q[2] + 64.0) * 2.0), 0, 255)
		var y0 := clampi(int((q[1] + 64.0) * 2.0), 0, 255)
		var y1 := clampi(int((q[3] + 64.0) * 2.0), 0, 255)
		img.fill_rect(Rect2i(x0, y0, maxi(1, x1 - x0), maxi(1, y1 - y0)), c)
	mini_tex = ImageTexture.create_from_image(img)


func _draw_minimap() -> void:
	var p = game.player
	if p == null or not is_instance_valid(p) or mini_tex == null:
		return
	var sz := mini.size
	var c := sz * 0.5
	var s := (MINI_SIZE * 0.5) / MINI_RANGE
	mini.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.07, 0.06, 0.7))
	var px: float = p.global_position.x
	var pz: float = p.global_position.z
	# map rotates so the player's view direction is always "up"
	mini.draw_set_transform(c, p.yaw, Vector2(s, s))
	mini.draw_texture_rect(mini_tex, Rect2(-64.0 - px, -64.0 - pz, 128.0, 128.0), false)
	var zm = game.zm
	if zm:
		for d in zm.L.doors:
			if not d.open:
				mini.draw_circle(Vector2(d.pos.x - px, d.pos.z - pz), 1.3, Color(0.65, 0.45, 0.2))
		for b in zm.L.buys:
			mini.draw_circle(Vector2(b.pos.x - px, b.pos.z - pz), 0.9, Color(0.95, 0.95, 0.85))
		for pk in zm.L.perks:
			mini.draw_circle(Vector2(pk.pos.x - px, pk.pos.z - pz), 1.2, Color(0.3, 0.7, 1.0))
		mini.draw_circle(Vector2(zm.L.box.pos.x - px, zm.L.box.pos.z - pz), 1.3, Color(0.45, 0.65, 1.0))
	for pu in game.pickups:
		if is_instance_valid(pu.node):
			mini.draw_circle(Vector2(pu.node.global_position.x - px, pu.node.global_position.z - pz), 0.8, Color(0.95, 0.85, 0.3))
	for e in game.enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var ex: float = e.global_position.x - px
		var ez: float = e.global_position.z - pz
		if e.get("puppet") == true and game.net.is_ally(e.peer_id):
			# teammate: green arrow pointing where they look (blue dots are perks / the box)
			var f: float = e.facing
			var fw := Vector2(-sin(f), -cos(f))
			var sd := Vector2(-fw.y, fw.x)
			var cp := Vector2(ex, ez)
			# out of range: pinned to the edge so you always know which way they are
			var lim: float = MINI_RANGE * 0.9
			if cp.length() > lim:
				cp = cp.normalized() * lim
			mini.draw_circle(cp, 2.3, Color(0.0, 0.0, 0.0, 0.55))
			mini.draw_colored_polygon(PackedVector2Array([cp + fw * 2.6, cp - fw * 1.5 + sd * 1.7, cp - fw * 0.6, cp - fw * 1.5 - sd * 1.7]), Color(0.3, 1.0, 0.45))
			continue
		var seen: bool = game.radar_t > 0.0
		if not seen:
			if e.get("rise_t") != null:
				seen = ex * ex + ez * ez < 18.0 * 18.0
			else:
				seen = game.clock - float(e.get("last_shot")) < 2.0
		if seen:
			mini.draw_circle(Vector2(ex, ez), 1.3, Color(0.95, 0.15, 0.1))
	for c2 in game.air.craft:
		if is_instance_valid(c2.node):
			var ap: Vector3 = c2.node.global_position
			mini.draw_circle(Vector2(ap.x - px, ap.z - pz), 1.6, Color(0.4, 0.85, 1.0))
	mini.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# player arrow + view cone + frame
	mini.draw_colored_polygon(PackedVector2Array([c, c + Vector2(-38, -62), c + Vector2(38, -62)]), Color(1, 1, 1, 0.08))
	mini.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(0, 3), c + Vector2(-6, 6)]), Color(1.0, 0.85, 0.3))
	mini.draw_rect(Rect2(Vector2(1, 1), sz - Vector2(2, 2)), Color(0.95, 0.69, 0.2, 0.8), false, 2.0)
	mini.draw_string(ThemeDB.fallback_font, Vector2(c.x - 5, 16), "N" if absf(wrapf(p.yaw, -PI, PI)) < 0.4 else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))


func _draw_radar() -> void:
	if game.radar_t <= 0.0 or game.player == null or not is_instance_valid(game.player):
		return
	var cam: Camera3D = game.player.camera
	var a := 0.55 + 0.35 * sin(game.clock * 6.0)
	for e in game.enemies:
		if not is_instance_valid(e) or e.dead or (e.get("puppet") == true and game.net.is_ally(e.peer_id)):
			continue
		var wp: Vector3 = e.global_position + Vector3(0, 1.9, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		var r := 7.0
		radar_c.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)]), Color(1, 0.15, 0.1, a))


func medal(id: String) -> void:
	medal_q.append(id)


func _tick_medals(delta: float) -> void:
	if medal_t > 0.0:
		medal_t -= delta
		var k := 1.7 - medal_t
		medal_badge.scale = Vector2.ONE * (1.0 + 0.6 * maxf(0.0, 1.0 - k / 0.18))
		medal_box.modulate.a = clampf(medal_t / 0.35, 0.0, 1.0) * clampf(k / 0.12, 0.0, 1.0)
		if medal_t <= 0.0:
			medal_box.visible = false
	elif not medal_q.is_empty():
		var id: String = medal_q.pop_front()
		var m: Array = Medals.LIST[id]
		medal_badge.col = m[2]
		medal_badge.sym = m[3]
		medal_badge.queue_redraw()
		medal_name.text = m[0].to_upper()
		medal_pts.text = "+%d" % m[1]
		medal_box.visible = true
		medal_t = 1.7 if medal_q.size() < 3 else 1.0
		game.sfx.play("medal", -5)


func hitmarker(kill: bool) -> void:
	hitmark_t = 0.18
	hitmark.modulate = Color(1, 0.3, 0.25, 1) if kill else Color(1, 1, 1, 1)


func damage_from(rel: float) -> void:
	var piv := Control.new()
	piv.rotation = -rel
	dmg_root.add_child(piv)
	var r := ColorRect.new()
	r.color = Color(0.95, 0.12, 0.08, 0.85)
	r.size = Vector2(90, 7)
	r.position = Vector2(-45, -150)
	piv.add_child(r)
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_property(piv, "modulate:a", 0.0, 0.9)
	tw.tween_callback(piv.queue_free)


func tick(delta: float) -> void:
	if notice_t > 0.0:
		notice_t -= delta
		if notice_t <= 0.4:
			notice_l.modulate.a = maxf(0.0, notice_t / 0.4)
			notice_s.modulate.a = notice_l.modulate.a
	if hitmark_t > 0.0:
		hitmark_t -= delta
		hitmark.modulate.a = maxf(0.0, hitmark_t / 0.18)
	_tick_medals(delta)
	if op_model and is_instance_valid(op_model) and op_p.visible:
		op_model.net_yaw += delta * 0.6
	radar_c.queue_redraw()
	mini.queue_redraw()
	_tick_mp(delta)
	if not hud.visible or game.player == null or not is_instance_valid(game.player):
		return
	var p = game.player
	var zm = game.zm
	# sniper scope
	scope_ov.visible = p.scoped
	if p.scoped:
		var vs := get_viewport().get_visible_rect().size
		var d := vs.y * 1.02
		var lens: TextureRect = scope_ov.get_meta("lens")
		lens.size = Vector2(d, d)
		lens.position = vs * 0.5 - Vector2(d, d) * 0.5
		var b0: ColorRect = scope_ov.get_meta("bar0")
		var b1: ColorRect = scope_ov.get_meta("bar1")
		b0.position = Vector2.ZERO
		b0.size = Vector2(lens.position.x + 2, vs.y)
		b1.position = Vector2(lens.position.x + d - 2, 0)
		b1.size = Vector2(vs.x - b1.position.x, vs.y)
		var c := vs * 0.5
		var lines := [[Vector2(c.x - d * 0.45, c.y - 1), Vector2(d * 0.43, 2)], [Vector2(c.x + d * 0.02, c.y - 1), Vector2(d * 0.43, 2)],
			[Vector2(c.x - 1, c.y + d * 0.02), Vector2(2, d * 0.43)], [Vector2(c.x - 1, c.y - d * 0.45), Vector2(2, d * 0.43)]]
		for i in 4:
			var ln: ColorRect = scope_ov.get_meta("ln%d" % i)
			ln.position = lines[i][0]
			ln.size = lines[i][1]
		var dot: ColorRect = scope_ov.get_meta("dot")
		dot.position = c - Vector2(2, 2)
	var w: Dictionary = p.weapons[p.cur]
	wname_l.text = w.name.to_upper()
	var low: bool = w.ammo == 0 or w.ammo <= ceili(w.mag * 0.25)
	ammo_l.text = "%d / %d" % [w.ammo, w.reserve]
	ammo_l.add_theme_color_override("font_color", RED if low else Color.WHITE)
	if zm:
		stats_l.text = "PUNTOS %d" % zm.points
		var extra := []
		if perk_row.get_child_count() != zm.perks_owned.size():
			for ch2 in perk_row.get_children():
				ch2.queue_free()
			for k in zm.perks_owned:
				var vb2 := VBoxContainer.new()
				vb2.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var tr := TextureRect.new()
				tr.texture = WB.perk_icon(k)
				tr.custom_minimum_size = Vector2(54, 54)
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				vb2.add_child(tr)
				var lb := _label({"armor": "Blindaje", "hands": "Manos rápidas", "pulse": "Pulso"}[k], 12, Color(0.92, 0.94, 0.92), 3)
				lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				vb2.add_child(lb)
				perk_row.add_child(vb2)
		if zm.insta_t > 0.0:
			extra.append("Muerte instantánea %ds" % ceili(zm.insta_t))
		if zm.double_t > 0.0:
			extra.append("Doble puntos %ds" % ceili(zm.double_t))
		if not extra.is_empty():
			stats_l.text += "\n" + "\n".join(extra)
		round_l.text = str(zm.round_n) if zm.round_n > 0 else ""
	else:
		if perk_row.get_child_count() > 0:
			for ch3 in perk_row.get_children():
				ch3.queue_free()
		stats_l.text = "PUNTOS %d\nBAJAS %d\nRACHA %d" % [game.score, game.kills, game.streak]
		round_l.text = ""
	info_l.text = game.hud_info()
	fps_l.text = "%d FPS" % Engine.get_frames_per_second()
	board_p.visible = game.net.active and Input.is_physical_key_pressed(KEY_TAB)
	if board_p.visible:
		board_l.text = game.net.board()
		var ol: String = game.net.online_line()
		if ol != "":
			board_l.text += "\n" + ol
	if game.mode == "mp":
		wave_l.text = game.net.hud_line()
	elif zm:
		if zm.inter > 0.0 and zm.round_n > 0:
			wave_l.text = "RONDA %d SUPERADA\nSiguiente en %ds" % [zm.round_n, ceili(zm.inter)]
		elif zm.round_n > 0:
			wave_l.text = "RONDA %d\n%d zombis restantes" % [zm.round_n, game.alive_count() + zm.to_spawn]
		else:
			wave_l.text = ""
	elif game.intermission > 0.0 and game.wave > 0:
		wave_l.text = "OLEADA %d SUPERADA\nSiguiente en %ds" % [game.wave, ceili(game.intermission)]
	elif game.wave > 0:
		wave_l.text = "OLEADA %d\n%d hostiles restantes" % [game.wave, game.alive_count() + game.to_spawn]
	else:
		wave_l.text = ""
	var hp: float = p.health
	var hmax: float = p.max_health
	hp_fill.size.x = 240.0 * hp / hmax
	hp_fill.color = Color(0.5, 0.83, 0.42) if hp > hmax * 0.6 else (GOLD if hp > hmax * 0.3 else RED)
	vignette.modulate.a = clampf((1.0 - hp / hmax) * 0.85, 0.0, 0.8)
	if zm and zm.prompt != "":
		prompt_l.text = zm.prompt
	elif p.reloading:
		prompt_l.text = "Recargando..."
	elif w.ammo == 0 and w.reserve == 0:
		prompt_l.text = "Sin munición: cambia de arma"
	elif low:
		prompt_l.text = "[R] Recargar"
	else:
		prompt_l.text = ""
	var gap: float = 6.0 + p.current_spread() * get_viewport().get_visible_rect().size.y * 0.9 + p.kick * 6.0
	var show: bool = p.aim_k < 0.5 and p.sprint_k < 0.5 and not p.scoped
	for i in 4:
		ch[i].visible = show
	ch[0].position = Vector2(-1, -gap - 10)
	ch[1].position = Vector2(-1, gap)
	ch[2].position = Vector2(-gap - 10, -1)
	ch[3].position = Vector2(gap, -1)


# ---------------------------------------------------------------- multiplayer: lobby, chat, co-op list
func _voice_option() -> OptionButton:
	var o := OptionButton.new()
	for n in ["Mantener T para hablar", "Micrófono abierto", "Desactivado"]:
		o.add_item(n)
	o.select(int(game.settings.get("voice", 0)))
	o.item_selected.connect(func(i):
		game.settings["voice"] = i
		game.save_settings()
		sync_settings()
	)
	return o


## Small microphone icon: green while that player talks.
func _mic_icon() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(16, 22)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var col: Color = Color(0.35, 1.0, 0.45) if c.get_meta("on", false) else Color(1, 1, 1, 0.2)
		c.draw_circle(Vector2(8, 5), 3.5, col)
		c.draw_rect(Rect2(4.5, 5, 7, 6), col)
		c.draw_circle(Vector2(8, 11), 3.5, col)
		c.draw_arc(Vector2(8, 11), 6.0, 0.0, PI, 12, col, 1.5)
		c.draw_line(Vector2(8, 17), Vector2(8, 20), col, 1.5)
		c.draw_line(Vector2(4, 20.5), Vector2(12, 20.5), col, 1.5)
	)
	return c


func _card(parent: Control, title: String, size: Vector2) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.04, 0.75)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	sb.border_color = Color(0.95, 0.69, 0.2, 0.55)
	sb.set_border_width_all(1)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = size
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	var h := _label(title, 22, GOLD, 4)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	return v


func _build_lobby() -> void:
	lobby_p = _overlay()
	var vb: VBoxContainer = lobby_p.get_meta("box")
	var t := _label("SALA DE ESPERA", 48, GOLD, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	lob_info = _label("", 18, Color(0.92, 0.94, 0.92), 3)
	lob_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lob_info)
	lob_code = HBoxContainer.new()
	lob_code.alignment = BoxContainer.ALIGNMENT_CENTER
	lob_code.add_theme_constant_override("separation", 12)
	vb.add_child(lob_code)
	lob_code_l = _label("", 22, Color.WHITE, 4)
	lob_code.add_child(lob_code_l)
	var cb := _button(lob_code, "Copiar código", func():
		DisplayServer.clipboard_set(game.net.invite_code)
		lob_wait.text = "Código copiado: pégalo a tus amigos"
	, true)
	cb.custom_minimum_size = Vector2(170, 0)
	cb.set_meta("copy", true)
	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 20)
	vb.add_child(cols)
	var pl := _card(cols, "JUGADORES", Vector2(380, 340))
	lob_list = VBoxContainer.new()
	lob_list.add_theme_constant_override("separation", 6)
	pl.add_child(lob_list)
	var ch2 := _card(cols, "CHAT", Vector2(560, 340))
	lob_chat_scroll = ScrollContainer.new()
	lob_chat_scroll.custom_minimum_size = Vector2(0, 240)
	lob_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ch2.add_child(lob_chat_scroll)
	lob_chat = VBoxContainer.new()
	lob_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lob_chat_scroll.add_child(lob_chat)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	ch2.add_child(row)
	lob_in = LineEdit.new()
	lob_in.placeholder_text = "Escribe un mensaje..."
	lob_in.max_length = 120
	lob_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lob_in)
	var send := func(_x = null):
		game.net.send_chat(lob_in.text)
		lob_in.text = ""
		lob_in.grab_focus()
	lob_in.text_submitted.connect(send)
	var sbt := _button(row, "Enviar", func(): send.call(), true)
	sbt.custom_minimum_size = Vector2(110, 0)
	var vr := HBoxContainer.new()
	vr.alignment = BoxContainer.ALIGNMENT_CENTER
	vr.add_theme_constant_override("separation", 12)
	vb.add_child(vr)
	vr.add_child(_label("Chat de voz", 17))
	lob_voice = _voice_option()
	vr.add_child(lob_voice)
	vr.add_child(_label("·  En la partida: Intro para escribir, T para hablar", 15, Color(0.85, 0.88, 0.86), 3))
	lob_wait = _label("", 18, GOLD, 4)
	lob_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lob_wait)
	var br := HBoxContainer.new()
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	br.add_theme_constant_override("separation", 14)
	vb.add_child(br)
	lob_start = _button(br, "INICIAR PARTIDA", func(): game.net.start_match())
	lob_team = _button(br, "Cambiar de equipo", func(): game.net.switch_team(), true)
	_button(br, "Salir de la sala", func():
		game.net.leave()
		show_mp()
	, true)
	lobby_p.visible = false
	game.net.lobby_changed.connect(refresh_lobby)
	game.net.chat_added.connect(_refresh_chat)


func show_lobby() -> void:
	menu.visible = false
	if mp_p:
		mp_p.visible = false
	if op_p:
		op_p.visible = false
	over_p.visible = false
	pause_p.visible = false
	hud.visible = false
	if upd_p:
		upd_p.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lobby_p.visible = true
	lob_in.text = ""
	refresh_lobby()
	_refresh_chat()


func hide_lobby() -> void:
	if lobby_p:
		lobby_p.visible = false
	release_chat_focus()


func refresh_lobby() -> void:
	if lobby_p == null or not lobby_p.visible:
		return
	var net = game.net
	lob_info.text = "%s  ·  %s\n%s" % [net.mode_title(), WB.MAPS[net.map_idx].name, net.MODES.get(net.gmode, net.MODES.ffa)[1]]
	lob_code.visible = net.is_host
	for c in lob_code.get_children():
		if c.has_meta("copy"):
			c.visible = net.invite_code != ""
	if net.invite_code != "":
		lob_code_l.text = "Código para invitar: %s" % net.invite_code
	else:
		lob_code_l.text = "Partida local: aparece sola en la lista de tu red"
	for c in lob_list.get_children():
		c.queue_free()
	var ids: Array = net.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = net.players[id]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var mic := _mic_icon()
		mic.set_meta("pid", id)
		r.add_child(mic)
		var sq := ColorRect.new()
		sq.color = net.player_col(id)
		sq.custom_minimum_size = Vector2(6, 22)
		r.add_child(sq)
		var tag := ""
		if id == 1:
			tag += "  (anfitrión)"
		if id == net.my_id():
			tag += "  (tú)"
		var nl := _label(str(p.name) + tag, 18, net.player_col(id), 3)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(nl)
		if net.gmode == "tdm":
			var tm: int = net.team_of(id)
			r.add_child(_label(net.TEAM_NAMES[tm], 16, net.TEAM_COLS[tm], 3))
		lob_list.add_child(r)
	lob_list.add_child(_label("%d / %d jugadores" % [ids.size(), net.MAX_PLAYERS], 14, Color(0.8, 0.82, 0.8), 3))
	lob_start.visible = net.is_host
	lob_start.text = "INICIAR PARTIDA (%d)" % ids.size()
	lob_team.visible = net.gmode == "tdm"
	if net.is_host:
		lob_wait.text = "Cuando estéis todos, pulsa INICIAR PARTIDA. Quien entre después se une directamente."
	else:
		var hn: String = net.players[1].name if net.players.has(1) else "el anfitrión"
		lob_wait.text = "Esperando a que %s inicie la partida..." % hn


## Text for one chat line (BBCode, the player's text escaped).
func _chat_bb(c: Dictionary) -> String:
	var txt: String = str(c.text).replace("[", "[lb]")
	if c.sys:
		return "[color=#c8c8b4][i]%s[/i][/color]" % txt
	return "[color=#%s][b]%s:[/b][/color] %s" % [(c.col as Color).to_html(false), str(c.name).replace("[", "[lb]"), txt]


func _refresh_chat() -> void:
	if lob_chat == null or lobby_p == null or not lobby_p.visible:
		return
	for c in lob_chat.get_children():
		c.queue_free()
	for c in game.net.chat_log.slice(maxi(0, game.net.chat_log.size() - 40)):
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rt.add_theme_font_size_override("normal_font_size", 16)
		rt.add_theme_font_size_override("bold_font_size", 16)
		rt.add_theme_font_size_override("italics_font_size", 15)
		rt.text = _chat_bb(c)
		lob_chat.add_child(rt)
	# scroll to the newest line once the layout has the new height
	get_tree().process_frame.connect(func():
		lob_chat_scroll.scroll_vertical = int(lob_chat_scroll.get_v_scroll_bar().max_value)
	, CONNECT_ONE_SHOT)


func _build_chat() -> void:
	chat_box = VBoxContainer.new()
	chat_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat_box.offset_left = 300
	chat_box.offset_right = 800
	chat_box.offset_top = -96
	chat_box.offset_bottom = -96
	chat_box.alignment = BoxContainer.ALIGNMENT_END
	chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(chat_box)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.custom_minimum_size = Vector2(500, 0)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_font_size_override("bold_font_size", 17)
	rt.add_theme_font_size_override("italics_font_size", 16)
	rt.add_theme_constant_override("outline_size", 4)
	rt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.0)
	bg.set_content_margin_all(6)
	bg.set_corner_radius_all(6)
	rt.add_theme_stylebox_override("normal", bg)
	chat_box.add_child(rt)
	chat_box.set_meta("rt", rt)
	chat_box.set_meta("bg", bg)
	chat_in = LineEdit.new()
	chat_in.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_in.offset_left = 300
	chat_in.offset_right = 800
	chat_in.offset_top = -90
	chat_in.offset_bottom = -56
	chat_in.max_length = 120
	chat_in.placeholder_text = "Escribe y pulsa Intro  ·  Esc para cancelar"
	chat_in.visible = false
	chat_in.text_submitted.connect(func(txt: String):
		game.net.send_chat(txt)
		close_chat()
	)
	hud.add_child(chat_in)
	coop_box = VBoxContainer.new()
	coop_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	coop_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	coop_box.offset_left = 22
	coop_box.offset_right = 282
	coop_box.offset_top = -244
	coop_box.offset_bottom = -244
	coop_box.alignment = BoxContainer.ALIGNMENT_END
	coop_box.add_theme_constant_override("separation", 4)
	coop_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(coop_box)


func open_chat() -> void:
	if chat_in == null or not hud.visible:
		return
	chat_open = true
	var p = game.player
	if p and is_instance_valid(p):
		p.mouse_down = false
		p.aiming = false
	chat_in.text = ""
	chat_in.visible = true
	chat_in.grab_focus()


func close_chat() -> void:
	chat_open = false
	if chat_in:
		chat_in.visible = false
		chat_in.release_focus()


func release_chat_focus() -> void:
	close_chat()
	if lob_in:
		lob_in.release_focus()


func _tick_mp(delta: float) -> void:
	var net = game.net
	# lobby mic icons
	if lobby_p and lobby_p.visible:
		lob_t -= delta
		if lob_t <= 0.0:
			lob_t = 0.1
			for r in lob_list.get_children():
				for c in r.get_children():
					if c.has_meta("pid"):
						var on: bool = net.voice.is_talking(int(c.get_meta("pid")))
						if on != c.get_meta("on", false):
							c.set_meta("on", on)
							c.queue_redraw()
	if chat_box == null:
		return
	chat_box.visible = net.active
	if not net.active:
		if chat_open:
			close_chat()
		coop_box.visible = false
		return
	# in-game chat: recent lines fade out after 10 s; everything recent while typing
	var now := Time.get_ticks_msec() / 1000.0
	var lines := []
	for c in net.chat_log.slice(maxi(0, net.chat_log.size() - 8)):
		if chat_open or now - float(c.t) < 10.0:
			lines.append(_chat_bb(c))
	if net.voice.talking:
		lines.append("[color=#59ff73][i]Hablando...[/i][/color]")
	var rt: RichTextLabel = chat_box.get_meta("rt")
	var txt := "\n".join(lines)
	if rt.text != txt:
		rt.text = txt
	(chat_box.get_meta("bg") as StyleBoxFlat).bg_color = Color(0, 0, 0, 0.45 if chat_open and txt != "" else 0.0)
	# co-op zombies: players + points, bottom left
	var show_coop: bool = net.is_coop() and net.started and game.zm != null
	coop_box.visible = show_coop
	if not show_coop:
		return
	coop_t -= delta
	if coop_t > 0.0:
		return
	coop_t = 0.15
	for c in coop_box.get_children():
		c.queue_free()
	var ids: Array = net.players.keys()
	ids.sort()
	for id in ids:
		var me: bool = id == net.my_id()
		var alive := true
		if me:
			alive = game.player != null and is_instance_valid(game.player) and game.player.alive
		else:
			alive = bool(net.alive_map.get(id, true))
		var p_pts: int = int(game.zm.points) if me else int(net.pts.get(id, 500))
		var col: Color = net.player_col(id)
		var pc := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.5 if me else 0.35)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 6
		sb.content_margin_right = 10
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		if me:
			sb.border_color = Color(col, 0.7)
			sb.set_border_width_all(1)
		pc.add_theme_stylebox_override("panel", sb)
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 7)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(r)
		var bar := ColorRect.new()
		bar.color = col if alive else Color(0.4, 0.4, 0.4)
		bar.custom_minimum_size = Vector2(5, 22)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_child(bar)
		var mic := _mic_icon()
		mic.set_meta("on", net.voice.is_talking(id))
		r.add_child(mic)
		var nm := str(net.players[id].name)
		if not alive:
			nm += "  (caído)"
		var nl := _label(nm, 17, col if alive else Color(0.6, 0.6, 0.6), 3)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		r.add_child(nl)
		var pl := _label(str(p_pts), 19, GOLD if alive else Color(0.6, 0.6, 0.6), 4)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(pl)
		coop_box.add_child(pc)
