class_name PartyIcon
extends Control
## Item icon for the HUD slot and the practice list: a glowing badge in the item's colour
## with a simple white glyph drawn from primitives (no image assets).

var item_id: String = "":
	set(v):
		item_id = v
		queue_redraw()
var _spin: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(72, 72)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	if item_id == "":
		_spin += dt * 2.0
		queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	var c: Vector2 = s * 0.5
	var r: float = minf(s.x, s.y) * 0.5
	if item_id == "":
		# empty slot: a dim frame with a slowly turning "?"
		draw_circle(c, r * 0.92, Color(0.1, 0.12, 0.2, 0.7))
		draw_arc(c, r * 0.92, 0.0, TAU, 40, Color(1, 1, 1, 0.25), 2.0, true)
		var f: Font = get_theme_default_font()
		draw_string(f, c + Vector2(-r * 0.2, r * 0.3), "?", HORIZONTAL_ALIGNMENT_CENTER, -1, int(r * 0.9), Color(1, 1, 1, 0.3 + 0.1 * sin(_spin)))
		return
	var col: Color = PartyNames.item_color(item_id)
	draw_circle(c, r * 0.96, col.darkened(0.55))
	draw_circle(c, r * 0.84, col.darkened(0.15))
	draw_circle(c + Vector2(-r * 0.2, -r * 0.25), r * 0.45, Color(1, 1, 1, 0.12))
	draw_arc(c, r * 0.94, 0.0, TAU, 48, col.lightened(0.4), 3.0, true)
	var w := Color(1, 1, 1, 0.95)
	var k: float = r / 36.0
	match item_id:
		"fox":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-16, -4) * k, c + Vector2(-14, -24) * k, c + Vector2(-3, -10) * k]), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(16, -4) * k, c + Vector2(14, -24) * k, c + Vector2(3, -10) * k]), w)
			draw_circle(c + Vector2(0, 2) * k, 14.0 * k, w)
			draw_circle(c + Vector2(-6, 0) * k, 2.5 * k, Color(0.9, 0.1, 0.05))
			draw_circle(c + Vector2(6, 0) * k, 2.5 * k, Color(0.9, 0.1, 0.05))
			for i: int in 3:
				draw_arc(c + Vector2(14, 16) * k, (8.0 + 4.0 * i) * k, -0.4, 1.4, 12, w, 2.5 * k)
		"tunic":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-3, 14) * k, c + Vector2(3, 14) * k, c + Vector2(3, -20) * k, c + Vector2(0, -26) * k, c + Vector2(-3, -20) * k]), w)
			draw_rect(Rect2(c + Vector2(-11, 12) * k, Vector2(22, 4) * k), Color(1.0, 0.85, 0.3))
			draw_rect(Rect2(c + Vector2(-2.5, 16) * k, Vector2(5, 9) * k), Color(0.45, 0.3, 0.2))
		"surge":
			var pts := PackedVector2Array()
			for i: int in 7:
				var x: float = -20.0 + i * 6.66
				pts.append(c + Vector2(x, (i % 2) * 14.0 - 16.0) * k)
			pts.append(c + Vector2(20, 12) * k)
			pts.append(c + Vector2(-20, 12) * k)
			draw_colored_polygon(pts, w)
		"thunder":
			for p: Vector2 in [Vector2(-10, -8), Vector2(0, -13), Vector2(10, -8)]:
				draw_circle(c + p * k, 9.0 * k, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(2, -2) * k, c + Vector2(-8, 12) * k, c + Vector2(0, 12) * k,
				c + Vector2(-6, 26) * k, c + Vector2(10, 6) * k, c + Vector2(2, 6) * k, c + Vector2(8, -2) * k]), Color(1.0, 0.95, 0.4))
		"slick":
			_ellipse(c + Vector2(0, 14) * k, Vector2(20, 7) * k, w)
			draw_circle(c + Vector2(0, -6) * k, 8.0 * k, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -9) * k, c + Vector2(0, -24) * k, c + Vector2(7, -9) * k]), w)
		"glove":
			draw_circle(c + Vector2(-2, -4) * k, 15.0 * k, w)
			draw_rect(Rect2(c + Vector2(-9, 10) * k, Vector2(14, 10) * k), Color(0.95, 0.95, 0.95))
			for i: int in 3:
				draw_line(c + Vector2(-6 + i * 4, 20) * k, c + Vector2(-6 + i * 4, 30) * k, Color(0.7, 0.7, 0.75), 2.0 * k)
		"magnet":
			draw_arc(c + Vector2(0, -2) * k, 13.0 * k, 0.0, PI, 20, w, 9.0 * k)
			draw_rect(Rect2(c + Vector2(-17.5, -8) * k, Vector2(9, 12) * k), Color(0.9, 0.9, 0.95))
			draw_rect(Rect2(c + Vector2(8.5, -8) * k, Vector2(9, 12) * k), Color(0.9, 0.9, 0.95))
		"shrink":
			draw_circle(c, 6.0 * k, w)
			for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * 24.0 * k, c + d * 12.0 * k, w, 3.0 * k)
				draw_colored_polygon(PackedVector2Array([c + d * 10.0 * k, c + (d * 16.0 + d.orthogonal() * 5.0) * k, c + (d * 16.0 - d.orthogonal() * 5.0) * k]), w)
		"swap":
			draw_line(c + Vector2(-16, -8) * k, c + Vector2(14, -8) * k, w, 4.0 * k)
			draw_colored_polygon(PackedVector2Array([c + Vector2(20, -8) * k, c + Vector2(10, -15) * k, c + Vector2(10, -1) * k]), w)
			draw_line(c + Vector2(16, 8) * k, c + Vector2(-14, 8) * k, w, 4.0 * k)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-20, 8) * k, c + Vector2(-10, 1) * k, c + Vector2(-10, 15) * k]), w)
		"balloon":
			_ellipse(c + Vector2(0, -6) * k, Vector2(13, 16) * k, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-3, 11) * k, c + Vector2(3, 11) * k, c + Vector2(0, 7) * k]), w)
			draw_line(c + Vector2(0, 11) * k, c + Vector2(4, 26) * k, w, 1.5 * k)
		"jetpack":
			draw_rect(Rect2(c + Vector2(-14, -16) * k, Vector2(11, 24) * k), w)
			draw_rect(Rect2(c + Vector2(3, -16) * k, Vector2(11, 24) * k), w)
			for x: float in [-8.5, 8.5]:
				draw_colored_polygon(PackedVector2Array([c + Vector2(x - 5, 9) * k, c + Vector2(x + 5, 9) * k, c + Vector2(x, 24) * k]), Color(1.0, 0.8, 0.3))
		"tornado":
			for i: int in 5:
				var hw: float = 20.0 - i * 3.5
				var y: float = -18.0 + i * 8.0
				draw_line(c + Vector2(-hw + i * 1.5, y) * k, c + Vector2(hw + i * 1.5, y) * k, w, 4.0 * k)
		"gravity":
			draw_circle(c, 11.0 * k, w)
			_ellipse_ring(c, Vector2(22, 7) * k, Color(1, 1, 1, 0.9), 3.0 * k)
		"ice":
			for a: float in [0.0, PI / 3.0, PI * 2.0 / 3.0]:
				var d := Vector2(cos(a), sin(a)) * 22.0 * k
				draw_line(c - d, c + d, w, 3.0 * k)
				draw_line(c + d * 0.6, c + d * 0.6 + d.rotated(0.8) * 0.3, w, 2.0 * k)
				draw_line(c + d * 0.6, c + d * 0.6 + d.rotated(-0.8) * 0.3, w, 2.0 * k)
				draw_line(c - d * 0.6, c - d * 0.6 - d.rotated(0.8) * 0.3, w, 2.0 * k)
				draw_line(c - d * 0.6, c - d * 0.6 - d.rotated(-0.8) * 0.3, w, 2.0 * k)
		"homing":
			# a spiky shell with a curving seeker trail
			var dome := PackedVector2Array()
			for i: int in 13:
				var a: float = PI + PI * float(i) / 12.0
				dome.append(c + Vector2(cos(a) * 15.0, sin(a) * 13.0 + 4.0) * k)
			draw_colored_polygon(dome, w)
			draw_rect(Rect2(c + Vector2(-17, 4) * k, Vector2(34, 5) * k), Color(1.0, 0.97, 0.85))
			for x: float in [-8.0, 0.0, 8.0]:
				draw_colored_polygon(PackedVector2Array([c + Vector2(x - 3, -6) * k, c + Vector2(x, -15) * k, c + Vector2(x + 3, -6) * k]), Color(0.95, 1.0, 0.85))
			draw_arc(c + Vector2(-4, 18) * k, 12.0 * k, PI * 0.1, PI * 0.9, 12, Color(1, 1, 1, 0.7), 2.5 * k)
			draw_colored_polygon(PackedVector2Array([c + Vector2(10, 17) * k, c + Vector2(4, 12) * k, c + Vector2(4, 22) * k]), Color(1, 1, 1, 0.8))
		"strike":
			# a crosshair under a falling bolt
			draw_arc(c + Vector2(0, 8) * k, 13.0 * k, 0.0, TAU, 28, w, 3.0 * k)
			for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
				var d := Vector2(cos(a), sin(a))
				draw_line(c + Vector2(0, 8) * k + d * 9.0 * k, c + Vector2(0, 8) * k + d * 19.0 * k, w, 2.5 * k)
			draw_colored_polygon(PackedVector2Array([c + Vector2(3, -26) * k, c + Vector2(-6, -8) * k, c + Vector2(0, -8) * k,
				c + Vector2(-4, 6) * k, c + Vector2(8, -12) * k, c + Vector2(2, -12) * k, c + Vector2(8, -26) * k]), Color(1.0, 0.95, 0.4))
			draw_circle(c + Vector2(0, 8) * k, 3.0 * k, Color(1.0, 0.3, 0.2))
		"fakebox":
			# an item box that is not quite right
			draw_rect(Rect2(c + Vector2(-15, -13) * k, Vector2(30, 28) * k), w)
			draw_rect(Rect2(c + Vector2(-15, -13) * k, Vector2(30, 28) * k), Color(0.3, 0.2, 0.0), false, 2.0 * k)
			var f: Font = get_theme_default_font()
			draw_string(f, c + Vector2(-7, 9) * k, "?", HORIZONTAL_ALIGNMENT_CENTER, -1, int(34.0 * k), Color(0.85, 0.5, 0.05))
			draw_line(c + Vector2(-19, 19) * k, c + Vector2(19, -17) * k, Color(1.0, 0.25, 0.2), 4.0 * k)
		"turbo":
			# a flame with speed lines
			draw_colored_polygon(PackedVector2Array([c + Vector2(6, -24) * k, c + Vector2(18, -2) * k, c + Vector2(10, 4) * k, c + Vector2(13, 22) * k,
				c + Vector2(-2, 10) * k, c + Vector2(-12, 20) * k, c + Vector2(-8, -2) * k, c + Vector2(-16, -4) * k]), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(3, -6) * k, c + Vector2(9, 8) * k, c + Vector2(1, 16) * k, c + Vector2(-6, 6) * k]), Color(1.0, 0.8, 0.3))
			for yy: float in [-10.0, 2.0, 14.0]:
				draw_line(c + Vector2(-24, yy) * k, c + Vector2(-17, yy) * k, Color(1, 1, 1, 0.65), 2.0 * k)
		"ghost":
			var body := PackedVector2Array()
			for i: int in 13:
				var a: float = PI + PI * float(i) / 12.0
				body.append(c + Vector2(cos(a) * 15.0, sin(a) * 17.0 - 3.0) * k)
			body.append(c + Vector2(15, 18) * k)
			body.append(c + Vector2(9, 12) * k)
			body.append(c + Vector2(3, 18) * k)
			body.append(c + Vector2(-3, 12) * k)
			body.append(c + Vector2(-9, 18) * k)
			body.append(c + Vector2(-15, 12) * k)
			draw_colored_polygon(body, w)
			draw_circle(c + Vector2(-5.5, -4) * k, 3.2 * k, Color(0.15, 0.2, 0.4))
			draw_circle(c + Vector2(5.5, -4) * k, 3.2 * k, Color(0.15, 0.2, 0.4))
			draw_circle(c + Vector2(0, 5) * k, 2.4 * k, Color(0.15, 0.2, 0.4))
		"decoy":
			# a solid racer and its translucent double
			draw_circle(c + Vector2(-7, -9) * k, 7.0 * k, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-16, 18) * k, c + Vector2(-14, 0) * k, c + Vector2(0, 0) * k, c + Vector2(2, 18) * k]), w)
			draw_arc(c + Vector2(10, -9) * k, 7.0 * k, 0.0, TAU, 16, Color(1, 1, 1, 0.75), 2.5 * k)
			draw_polyline(PackedVector2Array([c + Vector2(4, 18) * k, c + Vector2(6, 0) * k, c + Vector2(20, 0) * k, c + Vector2(22, 18) * k]), Color(1, 1, 1, 0.75), 2.5 * k)
		"shock":
			# a stomp: rings of force rolling out from the ground
			draw_circle(c + Vector2(0, 12) * k, 5.0 * k, w)
			for i: int in 3:
				var rr: float = (9.0 + 7.0 * float(i)) * k
				draw_arc(c + Vector2(0, 12) * k, rr, PI * 1.08, PI * 1.92, 16, Color(1, 1, 1, 0.95 - 0.25 * float(i)), (3.5 - 0.7 * float(i)) * k)
			draw_line(c + Vector2(-22, 16) * k, c + Vector2(22, 16) * k, Color(1, 1, 1, 0.6), 2.5 * k)
		_:
			draw_circle(c, 10.0 * k, w)


func _ellipse(center: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i: int in 24:
		var a: float = TAU * float(i) / 24.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, col)


func _ellipse_ring(center: Vector2, radii: Vector2, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i: int in 33:
		var a: float = TAU * float(i) / 32.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_polyline(pts, col, width, true)
