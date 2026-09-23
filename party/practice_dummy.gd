class_name PracticeDummy
extends Node3D
## Party Practice target: a ghostly sandbag with a bullseye, standing on a checkpoint lawn.
## Hits knock it around with a simple ballistic hop (no physics body, so it can never block
## the course); a KO or a fall poofs it, and it pops back home a moment later.
## Counts the hits it took (tests use `hits`).

signal was_hit(src: String)

## Negative, so it can never collide with a peer id.
var id: int = -1
var home: Vector3 = Vector3.ZERO
var hits: int = 0
var last_src: String = ""
var vel: Vector3 = Vector3.ZERO
var grounded: bool = true
var knocked_out: bool = false
var frozen: float = 0.0
var floating: float = 0.0
var stunned: float = 0.0
var shrunk: float = 0.0
var _respawn_left: float = 0.0
var _wobble: float = 0.0
var _wobble_v: float = 0.0
var _model: Node3D
var _label: Label3D
var _ice: Node3D
var _t: float = 0.0


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	var body_mat: StandardMaterial3D = PartyFx.solid_mat(Color(0.55, 0.95, 0.9, 0.55), 0.8, 0.3)
	PartyFx.part(_model, PartyFx.cyl_mesh(0.34, 1.1, 0.3), body_mat, Vector3(0, 0.75, 0))
	PartyFx.part(_model, PartyFx.sphere_mesh(0.3), body_mat, Vector3(0, 1.4, 0))
	PartyFx.part(_model, PartyFx.cyl_mesh(0.42, 0.14, 0.42), PartyFx.solid_mat(Color(0.25, 0.3, 0.38)), Vector3(0, 0.07, 0))
	# bullseye on the front (-Z) and back
	for side: float in [-1.0, 1.0]:
		for i: int in 3:
			var tm := TorusMesh.new()
			tm.inner_radius = 0.06 + 0.08 * float(i)
			tm.outer_radius = tm.inner_radius + 0.04
			tm.rings = 24
			tm.ring_segments = 4
			var col: Color = Color(1.0, 0.3, 0.3) if i % 2 == 0 else Color(1, 1, 1)
			PartyFx.part(_model, tm, PartyFx.glow_mat(col, 1.6), Vector3(0, 0.85, side * 0.335), Vector3.ONE, Vector3(90, 0, 0))
	# eyes
	for sx: float in [-0.1, 0.1]:
		PartyFx.part(_model, PartyFx.sphere_mesh(0.05), PartyFx.glow_mat(Color(0.1, 0.2, 0.25), 1.0), Vector3(sx, 1.45, -0.26))
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0009
	_label.font_size = 30
	_label.outline_size = 8
	_label.modulate = Color(0.6, 1.0, 0.95)
	_label.position = Vector3(0, 2.05, 0)
	_label.no_depth_test = true
	_label.layers = PartyFx.LAYER
	add_child(_label)
	_update_label()
	# idle shimmer
	add_child(PartyFx.emitter({"amount": 6, "lifetime": 1.4, "size": 0.14, "color": Color(0.5, 1.0, 0.9),
		"shape": "sphere", "radius": 0.4, "vmin": 0.1, "vmax": 0.4, "dir": Vector3.UP, "spread": 30.0,
		"aabb": 2.0}))
	global_position = home


## Back home, standing, with no effects (tests; also after a KO).
func reset() -> void:
	knocked_out = false
	visible = true
	global_position = home
	vel = Vector3.ZERO
	grounded = true
	frozen = 0.0
	floating = 0.0
	stunned = 0.0
	shrunk = 0.0
	_respawn_left = 0.0
	_show_ice(false)
	if _model != null:
		_model.scale = Vector3.ONE


func _update_label() -> void:
	_label.text = "DUMMY" if hits == 0 else "DUMMY  x%d" % hits


## Centre of mass for hit checks.
func center() -> Vector3:
	return global_position + Vector3(0, 0.8, 0)


## A hit from the local player. opts as PartyLayer.hit(): st, ko, e, ed, s, add.
func take_hit(kb: Vector3, opts: Dictionary) -> void:
	if knocked_out:
		return
	hits += 1
	last_src = str(opts.get("s", ""))
	_update_label()
	was_hit.emit(last_src)
	_wobble_v += 9.0
	var scale_k: float = 1.5 if shrunk > 0.0 else 1.0
	if bool(opts.get("add", false)):
		vel += kb * 0.8 * scale_k
	else:
		vel = kb * 0.8 * scale_k
	if vel.y > 0.5:
		grounded = false
	stunned = maxf(stunned, float(opts.get("st", 0.0)))
	match str(opts.get("e", "")):
		"freeze":
			frozen = float(opts.get("ed", 1.8))
			vel = Vector3.ZERO
			_show_ice(true)
		"float":
			floating = float(opts.get("ed", 2.5))
			vel = Vector3(0, 2.5, 0)
			grounded = false
		"shrink":
			shrunk = float(opts.get("ed", 6.0))
	if bool(opts.get("ko", false)):
		knock_out()


func knock_out() -> void:
	if knocked_out:
		return
	knocked_out = true
	PartyFx.explosion(get_parent(), center(), Color(0.6, 1.0, 0.95), Color(0.3, 0.8, 1.0), 1.6)
	visible = false
	_respawn_left = 1.6
	_show_ice(false)


func _show_ice(on: bool) -> void:
	if on and _ice == null:
		_ice = PartyStatus.ice_block()
		add_child(_ice)
	elif not on and _ice != null:
		_ice.queue_free()
		_ice = null


func _physics_process(dt: float) -> void:
	_t += dt
	if knocked_out:
		_respawn_left -= dt
		if _respawn_left <= 0.0:
			knocked_out = false
			global_position = home
			vel = Vector3.ZERO
			grounded = true
			frozen = 0.0
			floating = 0.0
			shrunk = 0.0
			visible = true
			scale = Vector3.ONE * 0.1
			create_tween().tween_property(self, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			PartyFx.burst(get_parent(), center(), Color(0.6, 1.0, 0.95), 20, 3.0)
		return
	stunned = maxf(stunned - dt, 0.0)
	shrunk = maxf(shrunk - dt, 0.0)
	var target_scale: float = 0.5 if shrunk > 0.0 else 1.0
	_model.scale = _model.scale.lerp(Vector3.ONE * target_scale, 1.0 - exp(-10.0 * dt))
	if frozen > 0.0:
		frozen -= dt
		if frozen <= 0.0:
			_show_ice(false)
			PartyFx.burst(get_parent(), center(), Color(0.7, 0.95, 1.0), 24, 5.0, 0.2)
		return
	var g: float = 25.0
	if floating > 0.0:
		floating -= dt
		g = 1.5
	if not grounded or vel.length() > 0.01:
		vel.y -= g * dt
		vel.x = move_toward(vel.x, 0.0, (2.0 if not grounded else 14.0) * dt)
		vel.z = move_toward(vel.z, 0.0, (2.0 if not grounded else 14.0) * dt)
		var p: Vector3 = global_position + vel * dt
		# land on whatever is below (ray from just above the old spot)
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.5, 0), p + Vector3(0, -0.05, 0), 1)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and vel.y <= 0.0 and (hit["normal"] as Vector3).y > 0.6:
			p = hit["position"]
			vel = Vector3(vel.x, 0.0, vel.z)
			grounded = true
		else:
			grounded = false
		global_position = p
		if global_position.y < home.y - 12.0:
			knock_out()
	else:
		# spring gently back toward home when knocked a little way along the lawn
		var back: Vector3 = home - global_position
		back.y = 0.0
		if back.length() > 0.05 and back.length() < 6.0:
			global_position += back * minf(dt * 0.6, 1.0)
	# wobble spring
	_wobble_v += (-_wobble * 60.0 - _wobble_v * 6.0) * dt
	_wobble += _wobble_v * dt
	_model.rotation = Vector3(_wobble * 0.08, _t * 9.0 if stunned > 0.0 else 0.0, sin(_t * 1.3) * 0.02)
