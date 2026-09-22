class_name LevelKit
extends RefCounted
## Building blocks for level scripts. Gameplay pieces take the position of the
## centre of their TOP surface, so level coordinates are "where feet go".
## Everything is an instance of a reusable mechanic script - levels only compose.

var root: Node3D
var rng := RandomNumberGenerator.new()


func _init(level_root: Node3D, seed_value: int = 1) -> void:
	root = level_root
	rng.seed = seed_value


func _add(n: Node3D, pos: Vector3, parent: Node3D = null) -> void:
	n.position = pos
	(parent if parent != null else root).add_child(n)


# ---- static geometry ------------------------------------------------------------------

func plat(top: Vector3, size: Vector3, style: String = "main", keel: float = -1.0, yaw_deg: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(Look.platform_box(size, style))
	var depth: float = keel if keel >= 0.0 else clampf(minf(size.x, size.z) * 0.55, 1.2, 6.0)
	if depth > 0.0:
		body.add_child(Look.underside(size, depth, false))
	body.rotation_degrees.y = yaw_deg
	_add(body, top - Vector3(0, size.y * 0.5, 0))
	return body


func disc(top: Vector3, radius: float, thick: float = 0.7, style: String = "main", keel: float = -1.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = thick
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(Look.platform_round(radius, thick, style))
	var depth: float = keel if keel >= 0.0 else clampf(radius * 1.1, 1.2, 7.0)
	if depth > 0.0:
		body.add_child(Look.underside(Vector3(radius * 2.0, thick, radius * 2.0), depth, true))
	_add(body, top - Vector3(0, thick * 0.5, 0))
	return body


## Sloped slab. `top` is the centre of the sloped surface; rises toward local -Z.
func ramp(top: Vector3, size: Vector3, pitch_deg: float, yaw_deg: float = 0.0, style: String = "alt") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(Look.platform_box(size, style))
	body.rotation_degrees = Vector3(pitch_deg, yaw_deg, 0)
	_add(body, top)
	body.translate_object_local(Vector3(0, -size.y * 0.5, 0))
	return body


## Solid block without walkable styling (walls, towers, machine housings).
func block(center: Vector3, size: Vector3, color: Color, collide: bool = true, yaw_deg: float = 0.0) -> Node3D:
	var node: Node3D
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		node = body
	else:
		node = Node3D.new()
	node.add_child(Look.box(size, Look.flat(color, 0.8)))
	node.rotation_degrees.y = yaw_deg
	_add(node, center)
	return node


# ---- mechanics ---------------------------------------------------------------------------

func pad(top: Vector3, strength: float, pitch_deg: float = 0.0, yaw_deg: float = 0.0, radius: float = 1.1) -> BouncePad:
	var p := BouncePad.new()
	p.strength = strength
	p.pitch_deg = pitch_deg
	p.radius = radius
	p.rotation_degrees.y = yaw_deg
	_add(p, top - Vector3(0, BouncePad.LIP, 0) + Vector3(0, 0.1, 0))
	return p


func mover(top: Vector3, size: Vector3, points: Array[Vector3], period: float, phase: float = 0.0, is_round: bool = false) -> MovingPlatform:
	var m := MovingPlatform.new()
	m.size = size
	m.points = points
	m.period = period
	m.phase = phase
	m.is_round = is_round
	_add(m, top - Vector3(0, size.y * 0.5, 0))
	return m


func orbiter(center: Vector3, radius: float, axis: Vector3, size: Vector3, period: float, phase: float = 0.0) -> MovingPlatform:
	var m := MovingPlatform.new()
	m.mode = MovingPlatform.Mode.ORBIT
	m.size = size
	m.orbit_radius = radius
	m.orbit_axis = axis
	m.period = period
	m.phase = phase
	_add(m, center - Vector3(0, size.y * 0.5, 0))
	return m


func spinner(top: Vector3, period: float, arms: Array[Dictionary], hub_radius: float = 1.4, phase: float = 0.0, hub_height: float = 0.5) -> RotatingPlatform:
	var r := RotatingPlatform.new()
	r.period = period
	r.arms = arms
	r.hub_radius = hub_radius
	r.hub_height = hub_height
	r.phase = phase
	_add(r, top - Vector3(0, hub_height * 0.5, 0))
	return r


func tilt(top: Vector3, size: Vector3, opts: Dictionary = {}) -> TiltPlatform:
	var t := TiltPlatform.new()
	t.size = size
	for key: String in opts:
		t.set(key, opts[key])
	_add(t, top - Vector3(0, size.y * 0.5, 0))
	return t


func collapse(top: Vector3, diameter: float = 2.4, delay: float = 0.7, respawn: float = 2.6) -> CollapsingPlatform:
	var cp := CollapsingPlatform.new()
	cp.size = Vector3(diameter, 0.4, diameter)
	cp.delay = delay
	cp.respawn = respawn
	_add(cp, top - Vector3(0, 0.2, 0))
	return cp


func checkpoint(pos: Vector3, yaw_deg: float = 0.0) -> Checkpoint:
	var cp := Checkpoint.new()
	cp.rotation_degrees.y = yaw_deg
	_add(cp, pos)
	return cp


func finish(pos: Vector3, yaw_deg: float = 0.0) -> FinishGate:
	var f := FinishGate.new()
	f.rotation_degrees.y = yaw_deg
	_add(f, pos)
	return f


## Loose rigid prop the player can shove (purely for fun, never required).
func ball(pos: Vector3, radius: float = 0.45, color: Color = Color.WHITE) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = 8
	rb.collision_mask = 1 | 8
	rb.mass = 6.0
	rb.add_to_group("resettable")
	rb.set_script(preload("res://mechanics/loose_prop.gd"))
	var s := SphereShape3D.new()
	s.radius = radius
	var cs := CollisionShape3D.new()
	cs.shape = s
	rb.add_child(cs)
	rb.add_child(Look.sphere(radius, Look.flat(color, 0.35)))
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.55
	pm.friction = 0.6
	rb.physics_material_override = pm
	_add(rb, pos)
	return rb


# ---- decoration (no collision unless stated) ---------------------------------------------

func pillar(top: Vector3, radius: float, length: float, color: Color = Color(0, 0, 0, 0)) -> void:
	var col: Color = color if color.a > 0.0 else Look.c("side")
	var n := Look.cylinder(radius * 0.7, length, Look.flat(col, 0.85), Vector3.ZERO, radius, 12)
	_add(n, top - Vector3(0, length * 0.5, 0))
	var cap := Look.cylinder(radius * 1.35, 0.3, Look.flat(col.lightened(0.15), 0.8), Vector3.ZERO, -1.0, 12)
	_add(cap, top - Vector3(0, 0.15, 0))


func tree(pos: Vector3, scale: float = 1.0) -> void:
	var t := Node3D.new()
	var trunk_h: float = 1.6 * scale
	t.add_child(Look.cylinder(0.16 * scale, trunk_h, Look.flat(Color(0.45, 0.32, 0.24), 0.9), Vector3(0, trunk_h * 0.5, 0), 0.11 * scale, 8))
	var leaf: Color = Look.c("decor")
	for i: int in 3:
		var r: float = (1.15 - i * 0.28) * scale
		var h: float = 1.35 * scale
		var cone := Look.cylinder(r, h, Look.flat(leaf.lightened(i * 0.09), 0.85), Vector3(0, trunk_h + i * 0.75 * scale + h * 0.35, 0), 0.0, 9)
		cone.rotation.y = rng.randf() * TAU
		t.add_child(cone)
	t.rotation.y = rng.randf() * TAU
	_add(t, pos)


func round_tree(pos: Vector3, scale: float = 1.0, color: Color = Color(0, 0, 0, 0)) -> void:
	var t := Node3D.new()
	var col: Color = color if color.a > 0.0 else Look.c("decor2")
	var trunk_h: float = 1.9 * scale
	t.add_child(Look.cylinder(0.14 * scale, trunk_h, Look.flat(Color(0.5, 0.38, 0.3), 0.9), Vector3(0, trunk_h * 0.5, 0), 0.1 * scale, 8))
	for i: int in 4:
		var off := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.5), rng.randf_range(-0.5, 0.5)) * scale
		t.add_child(Look.sphere(rng.randf_range(0.6, 0.9) * scale, Look.flat(col.lightened(rng.randf_range(0.0, 0.18)), 0.9), Vector3(0, trunk_h + 0.3 * scale, 0) + off))
	_add(t, pos)


func bush(pos: Vector3, scale: float = 1.0) -> void:
	var b := Node3D.new()
	for i: int in 3:
		var off := Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4)) * scale
		b.add_child(Look.sphere(rng.randf_range(0.35, 0.55) * scale, Look.flat(Look.c("decor").lightened(rng.randf_range(0.05, 0.2)), 0.9), off + Vector3(0, 0.25 * scale, 0)))
	_add(b, pos)


func lamp(pos: Vector3, height: float = 3.0, with_light: bool = true, color: Color = Color(0, 0, 0, 0)) -> void:
	var col: Color = color if color.a > 0.0 else Look.c("accent2")
	var l := Node3D.new()
	l.add_child(Look.cylinder(0.07, height, Look.flat(Look.c("metal").darkened(0.3), 0.5, 0.6), Vector3(0, height * 0.5, 0), 0.05, 8))
	l.add_child(Look.sphere(0.22, Look.flat(col, 0.3, 0.0, 3.0), Vector3(0, height + 0.15, 0)))
	if with_light:
		var o := OmniLight3D.new()
		o.light_color = col
		o.light_energy = 1.6
		o.omni_range = 8.0
		o.position = Vector3(0, height + 0.15, 0)
		l.add_child(o)
	_add(l, pos)


func arch(pos: Vector3, width: float, height: float, yaw_deg: float = 0.0, color: Color = Color(0, 0, 0, 0)) -> void:
	var col: Color = color if color.a > 0.0 else Look.c("trim")
	var a := Node3D.new()
	var mat: StandardMaterial3D = Look.flat(col, 0.75)
	for sx: int in [-1, 1]:
		a.add_child(Look.box(Vector3(0.6, height, 0.6), mat, Vector3(sx * width * 0.5, height * 0.5, 0)))
	a.add_child(Look.box(Vector3(width + 1.4, 0.55, 0.8), mat, Vector3(0, height + 0.27, 0)))
	a.add_child(Look.box(Vector3(width + 0.6, 0.12, 0.84), Look.flat(Look.c("accent"), 0.4, 0.0, 1.5), Vector3(0, height - 0.06, 0)))
	a.rotation_degrees.y = yaw_deg
	_add(a, pos)


func banner(pos: Vector3, height: float = 4.0, color: Color = Color(0, 0, 0, 0), yaw_deg: float = 0.0) -> void:
	var col: Color = color if color.a > 0.0 else Look.c("accent")
	var b := Node3D.new()
	b.add_child(Look.cylinder(0.06, height, Look.flat(Look.c("metal").darkened(0.2), 0.5, 0.5), Vector3(0, height * 0.5, 0), -1.0, 8))
	var flag_mat: StandardMaterial3D = Look.flat(col, 0.8).duplicate()
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pm := PrismMesh.new()
	pm.size = Vector3(1.1, 1.5, 0.03)
	pm.left_to_right = 0.0
	var flag := Look.mesh_node(pm, flag_mat, Vector3(0.58, height - 0.85, 0))
	flag.rotation_degrees.z = 180.0
	b.add_child(flag)
	b.rotation_degrees.y = yaw_deg
	_add(b, pos)


func cloud(pos: Vector3, scale: float = 1.0) -> void:
	var cl := Node3D.new()
	cl.set_script(preload("res://visual/drift.gd"))
	cl.set("speed", rng.randf_range(0.25, 0.8))
	var mat: ShaderMaterial = Look.cloud_material()
	for i: int in rng.randi_range(3, 5):
		var s := Look.sphere(1.0, mat, Vector3(rng.randf_range(-5, 5), rng.randf_range(-0.6, 0.8), rng.randf_range(-2.5, 2.5)) * scale)
		s.scale = Vector3(rng.randf_range(3.5, 6.0), rng.randf_range(1.6, 2.4), rng.randf_range(2.8, 4.5)) * scale
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cl.add_child(s)
	_add(cl, pos)


func cloud_field(center: Vector3, extent: Vector3, count: int) -> void:
	for i: int in count:
		var p := center + Vector3(rng.randf_range(-1, 1) * extent.x, rng.randf_range(-1, 1) * extent.y, rng.randf_range(-1, 1) * extent.z)
		cloud(p, rng.randf_range(1.0, 2.6))


## Distant floating architecture for depth. Kept away from the play path by the caller.
func monolith(pos: Vector3, size: Vector3, color: Color = Color(0, 0, 0, 0)) -> void:
	var col: Color = color if color.a > 0.0 else Look.c("side").lerp(Look.c("fog"), 0.35)
	var m := Node3D.new()
	m.add_child(Look.box(size, Look.flat(col, 0.9)))
	m.add_child(Look.box(Vector3(size.x * 1.08, 0.5, size.z * 1.08), Look.flat(Look.c("top").lerp(Look.c("fog"), 0.3), 0.9), Vector3(0, size.y * 0.5 + 0.25, 0)))
	var keel := Look.underside(size, size.x * 1.2, false)
	m.add_child(keel)
	if rng.randf() < 0.6:
		m.add_child(Look.box(Vector3(size.x * 0.12, 0.25, size.z * 1.02), Look.flat(Look.c("accent"), 0.4, 0.0, 2.0), Vector3(0, size.y * 0.2, 0)))
	m.rotation.y = rng.randf() * TAU
	_add(m, pos)


func monolith_ring(center: Vector3, radius_min: float, radius_max: float, count: int, y_spread: float = 30.0) -> void:
	for i: int in count:
		var a: float = (float(i) + rng.randf() * 0.6) / float(count) * TAU
		var r: float = rng.randf_range(radius_min, radius_max)
		var s := Vector3(rng.randf_range(5, 12), rng.randf_range(8, 34), rng.randf_range(5, 12))
		monolith(center + Vector3(cos(a) * r, rng.randf_range(-y_spread, y_spread * 0.6), sin(a) * r), s)


func gear(pos: Vector3, radius: float, teeth: int, thickness: float, spin_period: float, axis_rot_deg: Vector3 = Vector3(90, 0, 0), color: Color = Color(0, 0, 0, 0)) -> Node3D:
	var col: Color = color if color.a > 0.0 else Look.c("metal")
	var holder := Node3D.new()
	holder.rotation_degrees = axis_rot_deg
	var g := Node3D.new()
	g.set_script(preload("res://visual/spin.gd"))
	g.set("period", spin_period)
	var mat: StandardMaterial3D = Look.flat(col, 0.45, 0.7)
	g.add_child(Look.cylinder(radius * 0.86, thickness, mat, Vector3.ZERO, -1.0, 32))
	g.add_child(Look.cylinder(radius * 0.3, thickness * 1.5, Look.flat(col.darkened(0.3), 0.4, 0.8), Vector3.ZERO, -1.0, 16))
	for i: int in teeth:
		var a: float = float(i) / float(teeth) * TAU
		var tooth := Look.box(Vector3(radius * 0.26, thickness * 0.95, radius * 0.2), mat, Vector3(cos(a), 0, sin(a)) * radius * 0.93)
		tooth.rotation.y = -a
		g.add_child(tooth)
	for i: int in 5:
		var a2: float = float(i) / 5.0 * TAU
		g.add_child(Look.cylinder(radius * 0.13, thickness * 1.04, Look.flat(col.darkened(0.55), 0.6, 0.5), Vector3(cos(a2), 0, sin(a2)) * radius * 0.58, -1.0, 12))
	holder.add_child(g)
	_add(holder, pos)
	return holder


func chimney(pos: Vector3, height: float, radius: float = 1.2, smoke: bool = true) -> void:
	var ch := Node3D.new()
	ch.add_child(Look.cylinder(radius, height, Look.flat(Look.c("decor"), 0.85), Vector3(0, height * 0.5, 0), radius * 0.7, 16))
	ch.add_child(Look.cylinder(radius * 0.78, 0.5, Look.flat(Look.c("decor2"), 0.4, 0.0, 2.5), Vector3(0, height + 0.1, 0), radius * 0.74, 16))
	for i: int in 2:
		ch.add_child(Look.cylinder(radius * (0.93 - i * 0.12), 0.35, Look.flat(Look.c("metal"), 0.5, 0.6), Vector3(0, height * (0.35 + i * 0.4), 0), -1.0, 16))
	if smoke:
		var p := GPUParticles3D.new()
		p.amount = 18
		p.lifetime = 7.0
		p.preprocess = 7.0
		p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 50, 40))
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.3, 1, 0)
		pm.spread = 12.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 3.2
		pm.gravity = Vector3(0.5, 0.3, 0)
		pm.scale_min = 2.0
		pm.scale_max = 4.5
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
		var sc: Color = Look.c("cloud_shade")
		g.colors = PackedColorArray([Color(sc.r, sc.g, sc.b, 0.0), Color(sc.r, sc.g, sc.b, 0.5), Color(sc.r, sc.g, sc.b, 0.0)])
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		var qm := StandardMaterial3D.new()
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.vertex_color_use_as_albedo = true
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.albedo_texture = _soft_dot()
		q.material = qm
		p.draw_pass_1 = q
		p.position = Vector3(0, height + 0.5, 0)
		ch.add_child(p)
	_add(ch, pos)


var _dot: GradientTexture2D

func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(0.5, 0.0)
	return _dot


func pipe(from: Vector3, to: Vector3, radius: float = 0.4, color: Color = Color(0, 0, 0, 0)) -> void:
	var col: Color = color if color.a > 0.0 else Look.c("metal")
	var dir: Vector3 = to - from
	var n := Look.cylinder(radius, dir.length(), Look.flat(col, 0.45, 0.6), Vector3.ZERO, -1.0, 12)
	_add(n, (from + to) * 0.5)
	var up: Vector3 = dir.normalized()
	var side: Vector3 = up.cross(Vector3(0.123, 0.4, 0.9)).normalized()
	n.basis = Basis(side, up, side.cross(up))


## Glowing strip light (emissive only), good for leading the eye along a route.
func glow_strip(center: Vector3, size: Vector3, color: Color = Color(0, 0, 0, 0), yaw_deg: float = 0.0) -> void:
	var col: Color = color if color.a > 0.0 else Look.c("accent")
	var n := Look.box(size, Look.flat(col, 0.4, 0.0, 2.5))
	n.rotation_degrees.y = yaw_deg
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(n, center)


func ring(pos: Vector3, radius: float, color: Color = Color(0, 0, 0, 0), rot_deg: Vector3 = Vector3(90, 0, 0), spin_period: float = 0.0) -> void:
	var col: Color = color if color.a > 0.0 else Look.c("accent2")
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.92
	tm.outer_radius = radius
	tm.rings = 48
	tm.ring_segments = 8
	var holder := Node3D.new()
	holder.rotation_degrees = rot_deg
	var n := Look.mesh_node(tm, Look.flat(col, 0.4, 0.2, 1.8))
	if spin_period > 0.0:
		n.set_script(preload("res://visual/spin.gd"))
		n.set("period", spin_period)
		n.set("axis", Vector3(1, 0, 0))
	holder.add_child(n)
	_add(holder, pos)


# ---- momentum + hazard pieces (hard mode toolkit) ------------------------------------------

func _surface(kind: SurfacePlatform.Kind, top: Vector3, size: Vector3, yaw_deg: float, pitch_deg: float, speed: float) -> SurfacePlatform:
	var s := SurfacePlatform.new()
	s.kind = kind
	s.size = size
	s.speed = speed
	s.rotation_degrees = Vector3(pitch_deg, yaw_deg, 0)
	_add(s, top)
	s.translate_object_local(Vector3(0, -size.y * 0.5, 0))
	return s


## Boost strip: accelerates the player along its arrow (local -Z, turned by yaw) up to `speed`.
func boost(top: Vector3, size: Vector3, yaw_deg: float = 0.0, speed: float = 20.0) -> SurfacePlatform:
	return _surface(SurfacePlatform.Kind.BOOST, top, size, yaw_deg, 0.0, speed)


## Conveyor belt dragging toward its arrow at `speed` (run against it, or ride it).
func conveyor(top: Vector3, size: Vector3, yaw_deg: float = 0.0, speed: float = 6.0) -> SurfacePlatform:
	return _surface(SurfacePlatform.Kind.CONVEYOR, top, size, yaw_deg, 0.0, speed)


## Ice. Flat = almost no steering or braking. Pitched (positive pitch rises toward
## local -Z, negative descends) = a slide that builds real speed.
func slick(top: Vector3, size: Vector3, yaw_deg: float = 0.0, pitch_deg: float = 0.0) -> SurfacePlatform:
	return _surface(SurfacePlatform.Kind.SLICK, top, size, yaw_deg, pitch_deg, 0.0)


## Kill brick (centre position, not top).
func hazard(center: Vector3, size: Vector3, yaw_deg: float = 0.0, parent: Node3D = null) -> KillZone:
	var k := KillZone.new()
	k.size = size
	k.rotation_degrees.y = yaw_deg
	_add(k, center, parent)
	return k


## Rotating kill bars. `floor_top` is the floor the hub stands on.
func sweeper(floor_top: Vector3, arm_length: float, bars: int = 2, period: float = 4.0, phase: float = 0.0, bar_height: float = 0.45) -> Sweeper:
	var s := Sweeper.new()
	s.arm_length = arm_length
	s.bar_count = bars
	s.period = period
	s.phase = phase
	s.bar_height = bar_height
	_add(s, floor_top)
	return s


## Swinging hammer hung from `pivot`; swings along the X axis turned by yaw. Knocks the player away.
func pendulum(pivot: Vector3, length: float, period: float = 3.2, phase: float = 0.0, yaw_deg: float = 0.0, swing_deg: float = 55.0) -> Pendulum:
	var p := Pendulum.new()
	p.length = length
	p.period = period
	p.phase = phase
	p.swing_deg = swing_deg
	p.rotation_degrees.y = yaw_deg
	_add(p, pivot)
	return p


func bumper(floor_top: Vector3, strength: float = 16.0, lift: float = 8.0, radius: float = 0.9) -> Bumper:
	var b := Bumper.new()
	b.strength = strength
	b.lift = lift
	b.radius = radius
	_add(b, floor_top)
	return b


## Air current. `push` is an acceleration (m/s^2); gravity is 30 rising / 42 falling, so
## an updraft needs > 42 to lift a falling player.
func wind(center: Vector3, size: Vector3, push: Vector3, max_rise: float = 14.0) -> WindZone:
	var w := WindZone.new()
	w.size = size
	w.push = push
	w.max_rise = max_rise
	_add(w, center)
	return w


## Platform that exists only part of each cycle (deterministic from the course clock).
func blink(top: Vector3, size: Vector3, period: float = 3.0, on_fraction: float = 0.55, phase: float = 0.0) -> BlinkPlatform:
	var b := BlinkPlatform.new()
	b.size = size
	b.period = period
	b.on_fraction = on_fraction
	b.phase = phase
	_add(b, top - Vector3(0, size.y * 0.5, 0))
	return b
