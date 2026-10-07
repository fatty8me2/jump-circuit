class_name PartyRadar
extends Control
## Off-screen rival arrows: a small coloured arrow on the screen edge toward each nearby rival
## who is out of view (with the distance), pulsing red with a "!" while that rival is a threat
## (the PartyHud's `danger` table). Teammates get a dimmer arrow. Drawn every frame from the
## level's ghosts and the active camera.

const RANGE: float = 70.0
const MAX_ARROWS: int = 5
const MARGIN: float = 46.0

var party: PartyLayer
## id -> true while that rival is a threat (set by the PartyHud).
var danger: Dictionary = {}
var _t: float = 0.0
## Arrows drawn last frame: [{id, pos, angle, dist, danger}] (tests read this).
var arrows: Array[Dictionary] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	_t += dt
	arrows = _gather()
	queue_redraw()


func _gather() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if party == null or party.level == null or not visible:
		return out
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return out
	var size: Vector2 = get_viewport_rect().size
	var me: Vector3 = party.player.global_position
	for id_v: Variant in party.level._ghosts:
		var id: int = int(id_v)
		var g: Node3D = party.level._ghosts[id_v] as Node3D
		if g == null or not is_instance_valid(g) or not Net.roster.has(id):
			continue
		if float(Net.roster[id].get("finished", -1.0)) >= 0.0:
			continue
		var dist: float = me.distance_to(g.global_position)
		var hot: bool = danger.has(id)
		if dist > RANGE and not hot:
			continue
		var wp: Vector3 = g.global_position + Vector3(0, 1.0, 0)
		var behind: bool = cam.is_position_behind(wp)
		var ep: Dictionary = PartyBoard.edge_point(cam.unproject_position(wp), behind, size, MARGIN)
		if bool(ep["on_screen"]):
			continue
		out.append({"id": id, "pos": ep["pos"], "angle": float(ep["angle"]), "dist": dist, "danger": hot})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["danger"]) != bool(b["danger"]):
			return bool(a["danger"])
		return float(a["dist"]) < float(b["dist"]))
	if out.size() > MAX_ARROWS:
		out.resize(MAX_ARROWS)
	return out


func _draw() -> void:
	var font: Font = get_theme_default_font()
	for a: Dictionary in arrows:
		var id: int = int(a["id"])
		var hot: bool = bool(a["danger"])
		var col: Color = party.team_color_of(id).lerp(Color.WHITE, 0.25)
		var ally: bool = party.rules.is_team() and Net.team_of(id) == Net.team_of(Net.my_id())
		if hot:
			col = Color(1.0, 0.3, 0.25).lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 14.0) * 0.5)
		elif ally:
			col = col.darkened(0.2)
		var alpha: float = 1.0 if hot else (0.55 if ally else 0.85)
		var k: float = 1.25 if hot else 1.0
		var pos: Vector2 = a["pos"]
		var ang: float = float(a["angle"])
		var fwd := Vector2.from_angle(ang)
		var side := Vector2(-fwd.y, fwd.x)
		var tip: Vector2 = pos + fwd * 17.0 * k
		var pts := PackedVector2Array([tip, pos - fwd * 11.0 * k + side * 13.0 * k, pos - fwd * 5.0 * k, pos - fwd * 11.0 * k - side * 13.0 * k])
		var shadow := PackedVector2Array()
		for p: Vector2 in pts:
			shadow.append(p + Vector2(1.5, 2.0))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.45 * alpha))
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, alpha))
		var line: PackedVector2Array = pts.duplicate()
		line.append(pts[0])
		draw_polyline(line, Color(0, 0, 0, 0.7 * alpha), 2.0, true)
		# distance (and a "!" when threatening), pulled in toward the screen centre
		var inward: Vector2 = pos - fwd * 34.0
		var txt: String = ("! " if hot else "") + "%dm" % int(a["dist"])
		var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var tp: Vector2 = inward - Vector2(w * 0.5, -6.0)
		draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.8 * alpha))
		draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, alpha))
