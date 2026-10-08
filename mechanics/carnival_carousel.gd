class_name CarnivalCarousel
extends RotatingPlatform
## Carnival Chaos: a CAROUSEL. A round deck turns steadily on the course clock (use RotatingPlatform's
## `period`; negative turns the other way) under a striped canopy, with a ring of painted horses that
## bob up and down on their poles. Only the deck is solid: the horses, poles and canopy are scenery, so
## you stand anywhere on the boards and the ride just carries you round. The deck turns slowly (a rim
## speed of about 2 m/s) - the challenge is boarding and leaving a moving floor, not surviving it.
##
## `radius` is the deck's radius; `horses` how many; `canopy_height` how high the roof is (kept well
## above the jump so it never gets in the way).

@export var radius: float = 4.5
@export var horses: int = 6
@export var canopy_height: float = 5.2
@export var tint: Color = Color(0.95, 0.25, 0.3)
@export var tint2: Color = Color(0.98, 0.9, 0.7)

var _horse_nodes: Array[Node3D] = []
var _bulbs: Array[StandardMaterial3D] = []


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_base_basis = basis
	hub_radius = radius
	hub_height = 0.5
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = hub_height
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	add_child(cs)
	_build()
	_apply(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	var hum: AudioStreamPlayer3D = WorldAudio.loop("carnival_carousel_loop", self, -16.0, 24.0, 4.0)
	if hum != null:
		hum.pitch_scale = 1.0


## Where a point at local (x, z) on the deck is in the world at `time` (the deck is turning).
func world_at(local: Vector3, time: float) -> Vector3:
	return global_position + Basis(Vector3.UP, angle_at(time)) * local


func _build() -> void:
	var top: float = hub_height * 0.5
	var red: StandardMaterial3D = Look.flat(tint, 0.45)
	var cream: StandardMaterial3D = Look.flat(tint2, 0.5)
	var gold: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.25), 0.3, 0.8, 0.15)
	var pole_mat: StandardMaterial3D = Look.flat(Color(1.0, 0.85, 0.4), 0.25, 0.9)
	# the boards: a painted wheel of slices (tinted pairs), a gold rim and a hub
	add_child(Look.platform_round(radius, hub_height, "alt"))
	var slices: int = 12
	var deck_mat := ShaderMaterial.new()
	deck_mat.shader = preload("res://visual/carnival_stripe.gdshader")
	deck_mat.set_shader_parameter("color_a", tint.lerp(Color.WHITE, 0.15))
	deck_mat.set_shader_parameter("color_b", tint2)
	deck_mat.set_shader_parameter("stripes", float(slices))
	var deck_disc := Look.cylinder(radius * 0.985, 0.05, deck_mat, Vector3(0, top + 0.026, 0), -1.0, 48)
	deck_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(deck_disc)
	var rim := Look.cylinder(radius + 0.12, 0.2, gold, Vector3(0, top - 0.06, 0), -1.0, 40)
	add_child(rim)
	# the centre column
	add_child(Look.cylinder(0.75, canopy_height, cream, Vector3(0, top + canopy_height * 0.5, 0), 0.6, 16))
	for k: int in 3:
		add_child(Look.cylinder(0.8, 0.18, gold, Vector3(0, top + 0.9 + float(k) * 1.5, 0), -1.0, 16))
	# the canopy: a wide striped cone, scalloped, with bulbs round the lip
	var roof := CylinderMesh.new()
	roof.top_radius = 0.1
	roof.bottom_radius = radius + 0.5
	roof.height = 1.9
	roof.radial_segments = 24
	var roof_mat := ShaderMaterial.new()
	roof_mat.shader = preload("res://visual/carnival_stripe.gdshader")
	roof_mat.set_shader_parameter("color_a", tint)
	roof_mat.set_shader_parameter("color_b", tint2)
	roof_mat.set_shader_parameter("stripes", 12.0)
	var rf := Look.mesh_node(roof, roof_mat, Vector3(0, top + canopy_height + 0.9, 0))
	add_child(rf)
	add_child(Look.cylinder(radius + 0.55, 0.28, gold, Vector3(0, top + canopy_height - 0.02, 0), -1.0, 24))
	add_child(Look.sphere(0.32, gold, Vector3(0, top + canopy_height + 1.95, 0)))
	var nb: int = 14
	for i3: int in nb:
		var a3: float = TAU * float(i3) / float(nb)
		var bm: StandardMaterial3D = Look.flat(Color(1.0, 0.85, 0.45) if i3 % 2 == 0 else Color(1.0, 0.45, 0.6), 0.3, 0.0, 2.0).duplicate() as StandardMaterial3D
		_bulbs.append(bm)
		var bulb := Look.sphere(0.12, bm, Vector3(cos(a3) * (radius + 0.4), top + canopy_height - 0.3, sin(a3) * (radius + 0.4)))
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bulb)
	# the horses on their poles, ringed at 0.66 of the radius, each bobbing on its own beat
	for h: int in horses:
		var a4: float = TAU * float(h) / float(horses)
		var holder := Node3D.new()
		holder.position = Vector3(cos(a4) * radius * 0.66, top, sin(a4) * radius * 0.66)
		holder.rotation.y = -a4 + PI * 0.5
		add_child(holder)
		holder.add_child(Look.cylinder(0.05, canopy_height - 0.2, pole_mat, Vector3(0, (canopy_height - 0.2) * 0.5, 0), -1.0, 8))
		var horse := Node3D.new()
		holder.add_child(horse)
		_build_horse(horse, h)
		_horse_nodes.append(horse)


func _build_horse(n: Node3D, idx: int) -> void:
	var coat_cols: Array[Color] = [Color(1.0, 0.97, 0.92), Color(0.95, 0.65, 0.35), Color(0.55, 0.6, 0.95), Color(0.98, 0.55, 0.7)]
	var coat: StandardMaterial3D = Look.flat(coat_cols[idx % coat_cols.size()], 0.5)
	var mane: StandardMaterial3D = Look.flat(tint.darkened(0.1), 0.5)
	var saddle: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.25), 0.3, 0.6)
	# a little cartoon horse seen side-on (it faces +X of the holder = the direction of travel)
	n.add_child(Look.box(Vector3(1.0, 0.48, 0.42), coat, Vector3(0, 1.3, 0)))
	var neck := Look.box(Vector3(0.32, 0.7, 0.3), coat, Vector3(0.52, 1.7, 0))
	neck.rotation.z = -0.4
	n.add_child(neck)
	n.add_child(Look.box(Vector3(0.52, 0.28, 0.28), coat, Vector3(0.88, 1.98, 0)))
	n.add_child(Look.box(Vector3(0.38, 0.32, 0.5), saddle, Vector3(0.0, 1.58, 0)))
	var tail := Look.box(Vector3(0.16, 0.6, 0.12), mane, Vector3(-0.58, 1.18, 0))
	tail.rotation.z = 0.3
	n.add_child(tail)
	var mane_b := Look.box(Vector3(0.12, 0.62, 0.1), mane, Vector3(0.4, 1.9, 0))
	mane_b.rotation.z = -0.35
	n.add_child(mane_b)
	for lx: float in [-0.34, 0.34]:
		for lz: float in [-0.14, 0.14]:
			var leg := Look.box(Vector3(0.12, 0.62, 0.12), coat, Vector3(lx, 0.82, lz))
			leg.rotation.z = 0.12 if lx > 0.0 else -0.12
			n.add_child(leg)
	n.add_child(Look.sphere(0.05, Look.flat(Color(0.1, 0.08, 0.1), 0.4), Vector3(1.0, 2.04, 0.15)))
	n.add_child(Look.sphere(0.05, Look.flat(Color(0.1, 0.08, 0.1), 0.4), Vector3(1.0, 2.04, -0.15)))


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	for i: int in _horse_nodes.size():
		# neighbours bob in opposition, like the real ride
		_horse_nodes[i].position.y = 0.22 * sin(t * 1.9 + float(i) * PI) - 0.1
	for j: int in _bulbs.size():
		var on: float = 0.5 + 0.5 * sin(t * 3.0 - float(j) * 0.9)
		_bulbs[j].emission_energy_multiplier = 0.6 + 2.4 * on
