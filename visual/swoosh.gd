class_name Swoosh
extends MeshInstance3D
## A smooth camera-facing ribbon left behind a moving point (a mitt, a blade tip, a
## hammer head): no beads, however fast the point moves. World-space, purely cosmetic.
##
##   var s := Swoosh.make(Color(2, 1.6, 0.6), 0.12, 0.2)
##   add_child(s)
##   ... every frame: s.feed(point_global, emitting, delta)

## Seconds a point lives, full half-width at the newest point, HDR colour.
var life: float = 0.2
var width: float = 0.1
var color: Color = Color(1.6, 1.6, 1.6)
## Minimum spacing between stored points (m).
var spacing: float = 0.03

var _pts: PackedVector3Array = PackedVector3Array()
var _ages: PackedFloat32Array = PackedFloat32Array()
var _im: ImmediateMesh

static var _mats: Dictionary = {}
static var _live: int = 0   # swooshes in the tree; the shared materials go with the last one


## `additive` glows (best on dark scenes and for the player's own streaks); false = a
## plain translucent colour that stays readable against bright skies and grass.
static func make(c: Color, half_width: float = 0.1, seconds: float = 0.2, additive: bool = true) -> Swoosh:
	var s := Swoosh.new()
	s.color = c
	s.width = half_width
	s.life = seconds
	if not additive:
		s.material_override = _material(false)
	return s


func _init() -> void:
	top_level = true
	layers = 2
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_im = ImmediateMesh.new()
	mesh = _im
	material_override = _material(true)
	visible = false


static func _material(additive: bool) -> StandardMaterial3D:
	if _mats.has(additive):
		return _mats[additive]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 0.82, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 32
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = tex
	m.disable_receive_shadows = true
	_mats[additive] = m
	return m


func _enter_tree() -> void:
	_live += 1


func _exit_tree() -> void:
	_live -= 1
	if _live <= 0:
		# nothing holds the shared materials past the last ribbon (no leak reports at exit)
		_live = 0
		_mats.clear()


## Drops every stored point (teleports, respawns).
func clear() -> void:
	_pts.clear()
	_ages.clear()
	_im.clear_surfaces()
	visible = false


## Ages the ribbon by `dt` and, while `on`, extends it to `p` (global).
func feed(p: Vector3, on: bool, dt: float) -> void:
	for i: int in _ages.size():
		_ages[i] += dt
	while _ages.size() > 0 and _ages[0] >= life:
		_ages.remove_at(0)
		_pts.remove_at(0)
	if not on and _pts.is_empty():
		if visible:
			_im.clear_surfaces()
			visible = false
		return
	if on:
		# the newest point is a live head that follows `p`; it is left behind as a fixed
		# point once it is `spacing` past the one before it
		var n: int = _pts.size()
		if n < 2 or _pts[n - 2].distance_to(_pts[n - 1]) > spacing:
			_pts.append(p)
			_ages.append(0.0)
		else:
			_pts[n - 1] = p
			_ages[n - 1] = 0.0
		if _pts.size() > 64:
			_pts.remove_at(0)
			_ages.remove_at(0)
	_rebuild()


func _rebuild() -> void:
	_im.clear_surfaces()
	var n: int = _pts.size()
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if n < 2 or cam == null:
		visible = false
		return
	visible = true
	global_transform = Transform3D.IDENTITY
	var eye: Vector3 = cam.global_position
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in n:
		var p: Vector3 = _pts[i]
		var tangent: Vector3 = _pts[mini(i + 1, n - 1)] - _pts[maxi(i - 1, 0)]
		var side: Vector3 = tangent.cross(eye - p)
		if side.length_squared() < 1e-8:
			side = Vector3.UP
		side = side.normalized()
		var k: float = clampf(1.0 - _ages[i] / life, 0.0, 1.0)
		# taper to a point at the old end and ease in over the newest few centimetres
		var w: float = width * k * clampf(float(n - 1 - i + 1) / 2.0, 0.35, 1.0)
		var c := Color(color.r, color.g, color.b, color.a * k * (0.4 + 0.6 * k))
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(k, 0.0))
		_im.surface_add_vertex(p + side * w)
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(k, 1.0))
		_im.surface_add_vertex(p - side * w)
	_im.surface_end()
