class_name DinoDress
extends RefCounted
## Dino Valley's skins for the generic machines. The machines keep every rule, hitbox and timing; only
## their looks change: the piston ram becomes a charging triceratops head, the crusher a giant stamping
## foot, the spinning hammer an ankylosaur's club tail, the falling block a boulder rolled off the
## volcano, the rolling log wears moss, the laser's posts are fumaroles and the portal a hollow log.
## Visual only.

const SKIN_TRIKE := Color(0.5, 0.45, 0.62)
const SKIN_FOOT := Color(0.55, 0.62, 0.5)
const ROCK := Color(0.46, 0.43, 0.38)
const ROCK_DARK := Color(0.3, 0.28, 0.25)
const MOSS := Color(0.3, 0.5, 0.16)
const BARK := Color(0.4, 0.28, 0.17)
const BONE := Color(0.93, 0.9, 0.78)
const FIRE := Color(1.0, 0.45, 0.1)


static func _hide_meshes(n: Node, except: Node = null) -> void:
	for ch: Node in n.get_children():
		if ch is MeshInstance3D and ch != except:
			(ch as MeshInstance3D).visible = false


static func _ell(parent: Node3D, r: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var s: MeshInstance3D = Look.sphere(1.0, mat, pos)
	s.scale = r
	parent.add_child(s)
	return s


## A triceratops head on the face of a piston ram (forward = local -Z of the ram).
static func trike_ram(p: Piston) -> void:
	_hide_meshes(p)
	var skin: StandardMaterial3D = Look.flat(SKIN_TRIKE, 0.88)
	var frill: StandardMaterial3D = Look.flat(SKIN_TRIKE.lightened(0.15).lerp(Color(0.95, 0.5, 0.2), 0.3), 0.7)
	var horn: StandardMaterial3D = Look.flat(BONE, 0.4)
	var sz: Vector3 = p.size
	var h := Node3D.new()
	h.position = Vector3(0, 0, -sz.z * 0.5)
	p.add_child(h)
	_ell(h, Vector3(sz.x * 0.36, sz.y * 0.42, 0.85), Vector3(0, 0, 0.1), skin)
	_ell(h, Vector3(sz.x * 0.2, sz.y * 0.24, 0.32), Vector3(0, -0.12, -0.7), skin)
	var shield: MeshInstance3D = Look.cylinder(sz.x * 0.62, 0.12, frill, Vector3(0, sz.y * 0.28, 0.75), sz.x * 0.52, 18)
	shield.rotation.x = PI * 0.5 - 0.35
	h.add_child(shield)
	for sx: float in [-1.0, 1.0]:
		var hn: MeshInstance3D = Look.cylinder(0.11, 1.0, horn, Vector3(sx * sz.x * 0.26, sz.y * 0.42, -0.4), 0.0, 6)
		hn.rotation.x = -1.2
		h.add_child(hn)
		h.add_child(Look.sphere(0.08, Look.flat(Color(0.98, 0.95, 0.8), 0.4), Vector3(sx * sz.x * 0.34, sz.y * 0.12, -0.15)))
		h.add_child(Look.sphere(0.04, Look.flat(Color(0.05, 0.04, 0.04), 0.3), Vector3(sx * sz.x * 0.36, sz.y * 0.12, -0.2)))
	var nose: MeshInstance3D = Look.cylinder(0.08, 0.34, horn, Vector3(0, 0.1, -0.95), 0.0, 6)
	nose.rotation.x = -0.9
	h.add_child(nose)
	# the neck behind the head, back into the rock
	var neck: MeshInstance3D = Look.cylinder(sz.x * 0.34, p.stroke + 0.3, skin, Vector3(0, 0, sz.z * 0.5 + (p.stroke + 0.3) * 0.5), -1.0, 10)
	neck.rotation.x = PI * 0.5
	p.add_child(neck)


## A giant dinosaur foot on a crusher: a scaly sole slab, three toes and claws at the front, a heel.
static func foot(c: Crusher) -> void:
	_hide_meshes(c)
	var skin: StandardMaterial3D = Look.flat(SKIN_FOOT, 0.9)
	var dark: StandardMaterial3D = Look.flat(SKIN_FOOT.darkened(0.35), 0.9)
	var claw: StandardMaterial3D = Look.flat(BONE, 0.4)
	var s: Vector3 = c.size
	c.add_child(Look.box(Vector3(s.x * 0.98, s.y * 0.7, s.z * 0.98), skin, Vector3(0, s.y * 0.15, 0)))
	_ell(c, Vector3(s.x * 0.5, s.y * 0.5, s.z * 0.5), Vector3(0, s.y * 0.3, s.z * 0.05), skin)
	for i: int in 3:
		var x: float = (float(i) - 1.0) * s.x * 0.34
		c.add_child(Look.box(Vector3(s.x * 0.3, s.y * 0.42, s.z * 0.34), dark, Vector3(x, -s.y * 0.24, -s.z * 0.5)))
		var cl: MeshInstance3D = Look.cylinder(s.x * 0.1, s.z * 0.28, claw, Vector3(x, -s.y * 0.3, -s.z * 0.7), 0.0, 6)
		cl.rotation.x = -PI * 0.5
		c.add_child(cl)
	c.add_child(Look.box(Vector3(s.x * 0.8, s.y * 0.3, s.z * 0.3), dark, Vector3(0, -s.y * 0.3, s.z * 0.38)))
	# wrinkles across the top
	for k: int in 4:
		c.add_child(Look.box(Vector3(s.x * 0.9, 0.05, 0.06), dark, Vector3(0, s.y * 0.5 + 0.02, -s.z * 0.35 + float(k) * s.z * 0.22)))


## An ankylosaur's club tail on the spinning hammer: the arm becomes a spiked tail ending in a bony club,
## the post wears an armoured back with the head peeking out.
static func club_tail(h: SpinHammer) -> void:
	var arm: Node3D = h.get("_arm") as Node3D
	var glow: StandardMaterial3D = h.get("_glow_mat") as StandardMaterial3D
	_hide_meshes(arm)
	var skin: StandardMaterial3D = Look.flat(Color(0.5, 0.44, 0.3), 0.9)
	var bone: StandardMaterial3D = Look.flat(BONE, 0.5)
	var len: float = h.arm_length
	var tail: MeshInstance3D = Look.cylinder(0.42, len, skin, Vector3(len * 0.5, 0, 0), 0.16, 10)
	tail.rotation.z = -PI * 0.5
	arm.add_child(tail)
	for i: int in 5:
		var x: float = 0.8 + float(i) * (len - 1.6) / 4.0
		for sy: float in [-1.0, 1.0]:
			var sp: MeshInstance3D = Look.cylinder(0.09, 0.4, bone, Vector3(x, 0.0, sy * (0.36 - 0.04 * float(i))), 0.0, 5)
			sp.rotation.x = sy * PI * 0.5
			arm.add_child(sp)
	var club: MeshInstance3D = Look.sphere(h.head_radius * 0.8, glow)
	club.position = Vector3(len, 0, 0)
	club.scale = Vector3(1.1, 0.85, 0.9)
	arm.add_child(club)
	for k: int in 6:
		var a: float = TAU * float(k) / 6.0
		var sp2: MeshInstance3D = Look.cylinder(0.13, 0.5, bone, Vector3(len + cos(a) * h.head_radius * 0.8, 0.0, sin(a) * h.head_radius * 0.8), 0.0, 5)
		sp2.rotation = Vector3(sin(a) * 1.0, 0.0, -cos(a) * 1.4)
		arm.add_child(sp2)
	# the armoured body round the post
	var body := Node3D.new()
	h.add_child(body)
	_ell(body, Vector3(1.05, 0.6, 1.5), Vector3(0, 0.75, 0), skin)
	for i: int in 7:
		var a2: float = TAU * float(i) / 7.0
		body.add_child(Look.cylinder(0.12, 0.42, bone, Vector3(cos(a2) * 0.85, 1.1, sin(a2) * 1.1), 0.0, 5))
	_ell(body, Vector3(0.4, 0.3, 0.45), Vector3(0, 0.75, -1.55), skin)


## A boulder instead of the falling block's slab (the collider is still the slab).
static func boulder(b: FallingBlock) -> void:
	_hide_meshes(b)
	var rock: StandardMaterial3D = Look.flat(ROCK, 0.95)
	var dark: StandardMaterial3D = Look.flat(ROCK_DARK, 0.95)
	var moss: StandardMaterial3D = Look.flat(MOSS, 0.9)
	var s: Vector3 = b.size
	_ell(b, Vector3(s.x * 0.56, s.y * 0.62, s.z * 0.56), Vector3.ZERO, rock)
	_ell(b, Vector3(s.x * 0.32, s.y * 0.4, s.z * 0.34), Vector3(s.x * 0.28, s.y * 0.1, s.z * 0.2), dark)
	_ell(b, Vector3(s.x * 0.3, s.y * 0.36, s.z * 0.3), Vector3(-s.x * 0.3, -s.y * 0.05, -s.z * 0.2), rock)
	_ell(b, Vector3(s.x * 0.36, s.y * 0.16, s.z * 0.34), Vector3(-s.x * 0.1, s.y * 0.42, s.z * 0.1), moss)
	# a skirt of cracks and glowing hot veins (it came off the volcano)
	var vein: StandardMaterial3D = Look.flat(FIRE, 0.4, 0.0, 1.6)
	for k: int in 3:
		var a: float = float(k) * 2.1 + 0.4
		b.add_child(Look.box(Vector3(0.06, s.y * 0.5, 0.06), vein, Vector3(cos(a) * s.x * 0.5, 0.0, sin(a) * s.z * 0.5)))


## Moss and a fringe of ferns on a rolling log (its drum turns, so they ride the roll).
static func mossy_log(lg: RollingLog) -> void:
	var drum: Node3D = lg.get("_drum") as Node3D
	var moss: StandardMaterial3D = Look.flat(MOSS, 0.9)
	var r: float = lg.radius
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i: int in 9:
		var x: float = rng.randf_range(-lg.length * 0.45, lg.length * 0.45)
		var a: float = rng.randf() * TAU
		var lump: MeshInstance3D = _ell(drum, Vector3(rng.randf_range(0.5, 1.1), 0.12, rng.randf_range(0.3, 0.5)), Vector3(x, cos(a) * r * 0.97, sin(a) * r * 0.97), moss)
		lump.rotation.x = a
	var bone: StandardMaterial3D = Look.flat(BONE, 0.5)
	for sx: float in [-1.0, 1.0]:
		var stump: MeshInstance3D = Look.cylinder(r * 0.6, 0.12, Look.flat(BARK.lightened(0.3), 0.8), Vector3(sx * (lg.length * 0.5 + 0.04), 0, 0), -1.0, 14)
		stump.rotation.z = PI * 0.5
		lg.add_child(stump)
	bone.albedo_color = BONE


## A volcanic fumarole cone round each post of a flame-jet laser.
static func vent_posts(g: LaserGate) -> void:
	var rock: StandardMaterial3D = Look.flat(ROCK_DARK, 0.95)
	var ember: StandardMaterial3D = Look.flat(FIRE, 0.4, 0.0, 2.0)
	var post_h: float = maxf(g.size.y + 0.8, 1.2)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (g.size.x * 0.5 + 0.18)
		g.add_child(Look.cylinder(0.75, post_h + 0.4, rock, Vector3(x, 0.0, 0), 0.34, 9))
		g.add_child(Look.cylinder(0.3, 0.08, ember, Vector3(x, post_h * 0.5 + 0.22, 0), -1.0, 9))


## A great hollow log round a warp ring: bark all round, the ring its tunnel mouth.
static func hollow_log(parent: Node3D, floor_pos: Vector3, yaw_deg: float) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), floor_pos)
	parent.add_child(n)
	var bark: StandardMaterial3D = Look.flat(BARK, 0.95)
	var heart: StandardMaterial3D = Look.flat(BARK.lightened(0.4), 0.8)
	var tm := TorusMesh.new()
	tm.inner_radius = 1.5
	tm.outer_radius = 2.35
	tm.rings = 28
	tm.ring_segments = 10
	var ring: MeshInstance3D = Look.mesh_node(tm, bark, Vector3(0, 1.45, 0.0))
	ring.rotation.x = PI * 0.5
	ring.scale = Vector3(1.0, 1.0, 0.7)
	n.add_child(ring)
	var tail: MeshInstance3D = Look.cylinder(2.35, 4.0, bark, Vector3(0, 1.45, 2.2), 2.0, 14)
	tail.rotation.x = PI * 0.5
	n.add_child(tail)
	for k: int in 5:
		var a: float = TAU * float(k) / 5.0 + 0.3
		n.add_child(Look.sphere(0.28, Look.flat(MOSS, 0.9), Vector3(cos(a) * 2.0, 1.45 + sin(a) * 2.0, -0.1)))
	n.add_child(Look.sphere(0.001, heart, Vector3.ZERO))


## A flat stone saddle strapped to a pterodactyl: the creature flies beneath the platform.
static func ptero_mount(m: MovingPlatform, wing_scale: float = 2.4) -> DinoCreature:
	_hide_meshes(m)
	var skin: Material = Look.flat(Color(0.66, 0.5, 0.36), 0.9)
	var strap: Material = Look.flat(Color(0.3, 0.46, 0.14), 0.85)
	var s: Vector3 = m.size
	m.add_child(Look.box(Vector3(s.x, s.y, s.z), skin, Vector3.ZERO))
	m.add_child(Look.box(Vector3(s.x * 1.02, s.y * 1.1, 0.2), strap, Vector3(0, 0, -s.z * 0.25)))
	m.add_child(Look.box(Vector3(s.x * 1.02, s.y * 1.1, 0.2), strap, Vector3(0, 0, s.z * 0.25)))
	var d: DinoCreature = DinoCreature.make("ptero", wing_scale)
	d.position = Vector3(0, -s.y * 0.5 - 0.45 * wing_scale, 0)
	d.rotation.y = PI
	d.auto_flap = 7.5
	m.add_child(d)
	return d
