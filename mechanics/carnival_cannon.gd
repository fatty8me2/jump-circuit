class_name CarnivalCannon
extends LaunchBarrel
## Carnival Chaos: THE HUMAN CANNONBALL. The circus cannon of the finale: a LaunchBarrel (walk in, sit out
## the tell while the fuse spits and the cannon shudders, get fired along its fixed arc) dressed as a great
## red-and-cream striped cannon on a gilded carriage with a star on the muzzle. On the shot it blows a
## cloud of confetti and a burst of sparks from the muzzle. All timing is the barrel's (fire_time_after,
## fired_within, loaded_player...): firing is on the course-clock grid, so every racer waits the same way.

@export var gaudy: Color = Color(0.95, 0.2, 0.25)

var _confetti: GPUParticles3D


func _build() -> void:
	super._build()
	# re-skin the barrel: striped canvas-red staves
	var stripe := ShaderMaterial.new()
	stripe.shader = preload("res://visual/carnival_stripe.gdshader")
	stripe.set_shader_parameter("color_a", gaudy)
	stripe.set_shader_parameter("color_b", Color(0.99, 0.94, 0.82))
	stripe.set_shader_parameter("stripes", 12.0)
	var staves: MeshInstance3D = _tube.get_child(0) as MeshInstance3D
	if staves != null:
		staves.material_override = stripe
	var gold: StandardMaterial3D = Look.flat(Color(1.0, 0.82, 0.28), 0.25, 0.9, 0.2)
	# gilded muzzle ring and a flared lip
	_tube.add_child(Look.cylinder(mouth * 1.32, 0.22, gold, Vector3(0, 0.95, 0), mouth * 1.18, 20))
	# the carriage: two big spoked wheels and a cradle on the floor
	var wood: StandardMaterial3D = Look.flat(Color(0.5, 0.3, 0.18), 0.8)
	for sx: float in [-1.0, 1.0]:
		var wheel := Look.cylinder(1.0, 0.22, wood, Vector3(sx * (mouth * 1.55), -0.2, 0.3), -1.0, 18)
		wheel.rotation.z = PI * 0.5
		add_child(wheel)
		var hub := Look.cylinder(0.3, 0.3, gold, Vector3(sx * (mouth * 1.55 + sx * 0.05), -0.2, 0.3), -1.0, 10)
		hub.rotation.z = PI * 0.5
		add_child(hub)
		for i: int in 4:
			var spoke := Look.box(Vector3(0.14, 1.9, 0.1), gold, Vector3(sx * (mouth * 1.55 + sx * 0.12), -0.2, 0.3))
			spoke.rotation.x = PI * 0.25 * float(i)
			add_child(spoke)
	add_child(Look.box(Vector3(mouth * 3.2, 0.4, 1.7), wood, Vector3(0, -0.85, 0.3)))
	# a big gold star over the mouth, seen from the front
	var star := Look.box(Vector3(0.9, 0.9, 0.12), gold, Vector3(0, 0.15, -mouth * 1.18))
	star.rotation = Vector3(0, 0, PI * 0.25)
	_tube.add_child(star)
	var star2 := Look.box(Vector3(0.9, 0.9, 0.12), gold, Vector3(0, 0.15, -mouth * 1.18))
	_tube.add_child(star2)
	_confetti = Fx.burst({"amount": 90, "lifetime": 2.6, "explosiveness": 0.95, "shape": "point",
		"dir": _vel.normalized(), "spread": 32.0, "speed": Vector2(5.0, 15.0), "gravity": Vector3(0, -4.0, 0),
		"damping": Vector2(0.6, 1.2), "tex": Fx.Tex.PETAL, "size": 0.32, "angle": Vector2(0, 360), "spin": Vector2(-400, 400),
		"pick": PackedColorArray([Color(2.0, 0.4, 0.5), Color(2.2, 1.9, 0.5), Color(0.5, 1.6, 2.2), Color(0.6, 2.0, 0.8), Color(2.0, 0.8, 1.8)]),
		"curve": "shrink", "aabb": AABB(Vector3(-30, -10, -30), Vector3(60, 40, 60))})
	_confetti.position = _vel.normalized() * 1.4
	add_child(_confetti)


func _fire() -> void:
	super._fire()
	if _confetti != null:
		_confetti.restart()
		_confetti.emitting = true
	# SOUND: carnival_cannon_fanfare - a brass "ta-daaa" and a streamer pop over the usual cannon boom
	WorldAudio.at(self, "carnival_cannon_fanfare", global_position, 1.0, 70.0)
