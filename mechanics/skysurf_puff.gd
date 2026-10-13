class_name SkysurfPuff
extends BouncePad
## Sky Surf: a CLOUD PUFF that springs you up. It is a BouncePad with the same fixed, readable rules
## (the same puff always throws you along the same arc), dressed as a fat little cumulus with a pastel
## rim: it squashes under your feet and springs back, breathes out sparkles while it waits, and puffs a
## ring of cloud when it throws. Angled puffs (pitch > 0) lean toward their heading and show it with a
## row of chevrons on the crown. `tint` colours the rim and sparkles.

@export var tint: Color = Color(1.0, 0.62, 0.66)

var _puff_fx: GPUParticles3D


func _build_visual() -> void:
	var rim: Color = tint
	var light: Color = Look.c("cloud_light")
	var shade: Color = Look.c("cloud_shade")
	_top = Node3D.new()
	_top.basis = _tilt_basis()
	add_child(_top)
	var body_mat: StandardMaterial3D = Look.flat(light, 0.9)
	var under_mat: StandardMaterial3D = Look.flat(shade, 0.9)
	# the cumulus: a flat belly and three overlapping domes, the middle one crowned at the pad's top
	var belly := Look.cylinder(radius * 1.05, 0.34, under_mat, Vector3(0, LIP - 0.2, 0), radius * 0.9, 28)
	_top.add_child(belly)
	for i: int in 5:
		var a: float = float(i) / 5.0 * TAU
		var dome := Look.sphere(radius * 0.52, body_mat, Vector3(cos(a), 0.0, sin(a)) * radius * 0.62 + Vector3(0, LIP - 0.16, 0))
		dome.scale = Vector3(1.0, 0.62, 1.0)
		_top.add_child(dome)
	var crown := Look.sphere(radius * 0.8, body_mat, Vector3(0, LIP - 0.3, 0))
	crown.scale = Vector3(1.0, 0.42, 1.0)
	_top.add_child(crown)
	# the rim: a glowing ring where the cushion meets your feet
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.86
	tm.outer_radius = radius * 0.98
	tm.rings = 40
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, Look.flat(rim, 0.4, 0.0, 1.6), Vector3(0, LIP + 0.005, 0))
	ring.scale = Vector3(1, 0.25, 1)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_top.add_child(ring)
	# chevrons toward the launch heading on angled puffs
	if pitch_deg >= 1.0:
		var chev: StandardMaterial3D = Look.flat(rim.lightened(0.15), 0.4, 0.0, 1.8)
		for i: int in 2:
			var z: float = (float(i) - 0.5) * radius * 0.5
			for side: int in [-1, 1]:
				var bar := Look.box(Vector3(radius * 0.5, 0.03, radius * 0.12), chev, Vector3(side * radius * 0.17, LIP + 0.012, z))
				bar.rotation.y = -side * 0.7
				bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_top.add_child(bar)
	_build_puff_fx(rim)


func _build_puff_fx(col: Color) -> void:
	var hot: Color = Fx.hot(col.lerp(Color.WHITE, 0.4), 2.0)
	var vis := AABB(Vector3(-4, -1, -4), Vector3(8, 10, 8))
	# idle: sparkles lifting off the crown
	var shimmer: GPUParticles3D = Fx.emitter({"amount": 7, "lifetime": 1.6, "local": true, "shape": "ring",
		"ring_radius": radius * 0.7, "ring_inner": radius * 0.1, "dir": Vector3.UP, "spread": 10.0,
		"speed": Vector2(0.4, 1.0), "tex": Fx.Tex.STAR, "size": 0.3, "curve": "pop", "color": hot,
		"aabb": vis, "preprocess": 1.6})
	shimmer.position = Vector3(0, LIP + 0.05, 0)
	add_child(shimmer)
	# the throw: a ring of cloud puffing out and a sparkle column along the launch heading
	var up: Vector3 = _local_launch().normalized() if pitch_deg >= 1.0 else Vector3.UP
	_puff_fx = Fx.sparks({"amount": 30, "lifetime": 0.7, "shape": "ring", "ring_radius": radius * 0.7,
		"ring_inner": radius * 0.2, "dir": Vector3.UP, "spread": 14.0, "speed": Vector2(4.0, 11.0),
		"gravity": Vector3(0, -6, 0), "damping": Vector2(2.0, 5.0), "color": hot, "size": Vector2(0.1, 0.5), "aabb": vis})
	_puff_fx.transform = Transform3D(Fx.basis_up(up), Vector3(0, LIP + 0.05, 0))
	add_child(_puff_fx)


func on_bounced(player: Node) -> void:
	super.on_bounced(player)
	if _puff_fx != null:
		_puff_fx.restart()
	# (the pad's own bounce sound plays; a dedicated soft "whumpf" with a chime would suit the cloud)
