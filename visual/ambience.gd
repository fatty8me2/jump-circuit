class_name Ambience
extends Node3D
## Themed air for a level at three depths, following whatever camera is live:
##  near - small motes in a box just ahead of the camera (they fade out as they reach the
##         lens, so nothing ever sits on the player or a landing);
##  mid  - a wider sphere of bigger, slower pieces further down the view;
##  far  - a shell far out that lights the skyline (streaks, sparks, drifting wisps).
## Every emitter is world-space, so the particles hang in the level and parallax as the
## camera moves - only the birthplace follows the camera. Visual only; sized by
## Settings.particle_scale() through Fx.count.

var theme: String = ""
var _layers: Array[Dictionary] = []   # {"p": GPUParticles3D, "ahead": float, "lead": float}
var _last_cam: Vector3 = Vector3.ZERO
var _has_last: bool = false
var _cam_vel: Vector3 = Vector3.ZERO


## Builds the ambience for `theme` (a Look theme id) - add the result to the level.
static func make(theme_id: String) -> Ambience:
	var a := Ambience.new()
	a.name = "Ambience"
	a.theme = theme_id
	a.top_level = true
	for spec: Dictionary in recipe(theme_id):
		a._add_layer(spec)
	return a


func _add_layer(spec: Dictionary) -> void:
	var o: Dictionary = spec.duplicate()
	var depth: String = String(o.get("depth", "near"))
	o.erase("depth")
	var ahead: float = float(o.get("ahead", {"near": 5.0, "mid": 16.0, "far": 0.0}[depth]))
	o.erase("ahead")
	match depth:
		"near":
			if not o.has("shape"):
				o["shape"] = "box"
				o["extents"] = o.get("extents", Vector3(9.0, 5.0, 9.0))
		"mid":
			if not o.has("shape"):
				o["shape"] = "sphere"
				o["radius"] = o.get("radius", 24.0)
		"far":
			if not o.has("shape"):
				o["shape"] = "shell"
				o["radius"] = o.get("radius", 70.0)
	o["local"] = false
	o["aabb"] = AABB(Vector3(-400, -300, -400), Vector3(800, 600, 800))
	if not o.has("preprocess"):
		o["preprocess"] = float(o.get("lifetime", 2.0))
	var p: GPUParticles3D = Fx.emitter(o)
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if depth == "near" and p.draw_pass_1 is QuadMesh:
		# fade out right at the lens: near motes never blot the view
		var q := (p.draw_pass_1 as QuadMesh).duplicate() as QuadMesh
		var m := (q.material as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = 0.8
		m.distance_fade_max_distance = 3.2
		q.material = m
		p.draw_pass_1 = q
	add_child(p)
	# seconds of camera travel to lead by: about half a mote's life (none for the far shell)
	var lead: float = 0.0 if depth == "far" else minf(float(o.get("lifetime", 2.0)) * 0.5, 2.0)
	_layers.append({"p": p, "ahead": ahead, "lead": lead})


func _process(dt: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or dt <= 0.0:
		return
	var at: Vector3 = cam.global_position
	# a respawn / teleport jumps the camera: rebuild the air around the new spot at once
	# (restart re-runs the preprocess) instead of leaving it empty for a few seconds
	var jumped: bool = not _has_last or at.distance_to(_last_cam) > 12.0
	if not jumped:
		_cam_vel = _cam_vel.lerp((at - _last_cam) / dt, 1.0 - exp(-3.0 * dt))
	else:
		_cam_vel = Vector3.ZERO
	_last_cam = at
	_has_last = true
	var fwd: Vector3 = -cam.global_basis.z
	fwd.y *= 0.3
	for l: Dictionary in _layers:
		var p := l["p"] as GPUParticles3D
		# born ahead along the way we are travelling, so a running camera flies into the
		# motes instead of leaving them all behind it
		p.global_position = at + fwd * float(l["ahead"]) + _cam_vel * float(l["lead"])
		if jumped:
			p.restart()


# ---- recipes -------------------------------------------------------------------------------

static func recipe(theme_id: String) -> Array[Dictionary]:
	match theme_id:
		"gardens":
			return [
				# near: golden pollen drifting on the breeze, pink petals tumbling past
				{"depth": "near", "amount": 220, "lifetime": 3.0, "tex": Fx.Tex.DOT, "size": 0.13, "additive": false,
					"color": Color(1.0, 0.66, 0.08), "speed": Vector2(0.05, 0.3), "spread": 180.0,
					"gravity": Vector3(0.25, 0.05, 0.1), "turbulence": 1.0, "turbulence_scale": 6.0,
					"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "scale": Vector2(0.5, 1.2)},
				{"depth": "near", "amount": 110, "lifetime": 3.0, "tex": Fx.Tex.PETAL, "additive": false,
					"size": 0.24, "pick": PackedColorArray([Color(1.0, 0.4, 0.66), Color(1.0, 0.62, 0.8), Color(0.95, 0.3, 0.55)]),
					"speed": Vector2(0.1, 0.4), "spread": 180.0, "gravity": Vector3(0.45, -0.35, 0.2),
					"turbulence": 1.4, "turbulence_scale": 5.0, "angle": Vector2(0, 360), "spin": Vector2(-160, 160),
					"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "scale": Vector2(0.6, 1.1)},
				# mid: dandelion seeds and sun glints floating across the gaps
				{"depth": "mid", "amount": 110, "lifetime": 6.0, "tex": Fx.Tex.STAR, "size": 0.45, "additive": false,
					"color": Color(1.0, 0.8, 0.2), "speed": Vector2(0.2, 0.6), "spread": 180.0,
					"gravity": Vector3(0.5, 0.15, 0.2), "turbulence": 0.8, "curve": "pop",
					"fade": PackedFloat32Array([0.0, 0.9, 0.9, 0.0])},
				{"depth": "mid", "amount": 90, "lifetime": 7.0, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.42,
					"pick": PackedColorArray([Color(1.0, 0.4, 0.66), Color(1.0, 0.95, 0.7), Color(0.45, 0.85, 0.3)]),
					"speed": Vector2(0.2, 0.6), "spread": 180.0, "gravity": Vector3(0.8, -0.4, 0.3), "turbulence": 1.2,
					"angle": Vector2(0, 360), "spin": Vector2(-120, 120), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				# far: big soft sun motes over the islands
				{"depth": "far", "amount": 80, "lifetime": 9.0, "tex": Fx.Tex.PETAL, "size": 1.6, "radius": 60.0, "additive": false,
					"pick": PackedColorArray([Color(1.0, 0.5, 0.72, 0.9), Color(1.0, 0.95, 0.8, 0.9)]), "angle": Vector2(0, 360), "spin": Vector2(-60, 60), "speed": Vector2(0.3, 1.0), "spread": 180.0,
					"gravity": Vector3(0.6, 0.2, 0.0), "fade": PackedFloat32Array([0.0, 0.6, 0.6, 0.0])},
			]
		"foundry":
			return [
				# near: hot embers riding the heat up, flakes of ash sifting down
				{"depth": "near", "amount": 190, "lifetime": 3.0, "tex": Fx.Tex.DOT, "size": 0.1,
					"colors": PackedColorArray([Color(3.2, 1.6, 0.5, 0.0), Color(3.0, 1.1, 0.3, 1.0), Color(2.0, 0.4, 0.1, 0.0)]),
					"speed": Vector2(0.4, 1.4), "dir": Vector3.UP, "spread": 40.0, "gravity": Vector3(0.2, 0.9, 0.0),
					"turbulence": 1.4, "turbulence_scale": 3.0, "scale": Vector2(0.4, 1.2)},
				{"depth": "near", "amount": 80, "lifetime": 3.0, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.12,
					"color": Color(0.22, 0.2, 0.22, 0.85), "speed": Vector2(0.1, 0.3), "spread": 180.0,
					"gravity": Vector3(0.1, -0.4, 0.0), "turbulence": 1.0, "angle": Vector2(0, 360), "spin": Vector2(-200, 200),
					"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				# mid: sparks spitting upward in streaks
				{"depth": "mid", "amount": 110, "lifetime": 1.6, "facing": "velocity", "tex": Fx.Tex.SPARK,
					"size": Vector2(0.08, 0.7), "color": Color(3.4, 1.6, 0.5), "dir": Vector3.UP, "spread": 25.0,
					"speed": Vector2(4.0, 9.0), "gravity": Vector3(0, -8.0, 0), "fade": PackedFloat32Array([0.0, 1.0, 0.0])},
				{"depth": "mid", "amount": 95, "lifetime": 5.0, "tex": Fx.Tex.DOT, "size": 0.35,
					"color": Color(2.6, 0.9, 0.25), "speed": Vector2(0.5, 1.5), "dir": Vector3.UP, "spread": 30.0,
					"gravity": Vector3(0, 0.6, 0), "turbulence": 1.0, "curve": "pop", "fade": PackedFloat32Array([0.0, 1.0, 0.0])},
				# far: a glow haze of big embers climbing past the smelters
				{"depth": "far", "amount": 95, "lifetime": 8.0, "tex": Fx.Tex.DOT, "size": 2.4, "radius": 65.0,
					"color": Color(2.4, 0.8, 0.2, 0.55), "speed": Vector2(1.0, 3.0), "dir": Vector3.UP, "spread": 30.0,
					"curve": "pop", "fade": PackedFloat32Array([0.0, 0.7, 0.0])},
			]
		"balance":
			return [
				# near: sunlit dust and little wind streaks crossing the beams
				{"depth": "near", "amount": 200, "lifetime": 3.0, "tex": Fx.Tex.DOT, "size": 0.11, "additive": false,
					"color": Color(1.0, 0.68, 0.3, 0.9), "speed": Vector2(0.05, 0.25), "spread": 180.0,
					"gravity": Vector3(0.35, 0.02, 0.0), "turbulence": 0.8, "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				{"depth": "near", "amount": 70, "lifetime": 1.2, "facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false,
					"size": Vector2(0.04, 1.6), "color": Color(0.12, 0.42, 0.46, 0.55), "dir": Vector3(1, 0.05, 0.2),
					"spread": 6.0, "speed": Vector2(6.0, 10.0), "fade": PackedFloat32Array([0.0, 0.8, 0.0])},
				# mid: drifting glints off the cables and girders
				{"depth": "mid", "amount": 100, "lifetime": 4.0, "tex": Fx.Tex.STAR, "size": 0.5, "additive": false,
					"color": Color(1.0, 0.55, 0.2), "speed": Vector2(0.1, 0.4), "spread": 180.0, "curve": "pop"},
				{"depth": "mid", "amount": 70, "lifetime": 7.0, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.32,
					"pick": PackedColorArray([Color(1.0, 0.45, 0.35), Color(0.95, 0.95, 0.9), Color(0.3, 0.75, 0.8)]),
					"speed": Vector2(0.2, 0.6), "spread": 180.0, "gravity": Vector3(0.9, -0.3, 0.1), "turbulence": 1.4,
					"angle": Vector2(0, 360), "spin": Vector2(-240, 240), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				# far: long slow wisps of cloud streaming past
				{"depth": "far", "amount": 50, "lifetime": 10.0, "tex": Fx.Tex.SMOKE, "additive": false, "size": 11.0,
					"radius": 70.0, "color": Color(1.0, 1.0, 1.0, 0.5), "speed": Vector2(1.5, 3.0), "dir": Vector3(1, 0, 0.1),
					"spread": 10.0, "angle": Vector2(0, 360), "curve": "puff", "fade": PackedFloat32Array([0.0, 0.8, 0.8, 0.0])},
			]
		"clockwork":
			return [
				# near: brass glitter twinkling in the dusk light, lantern motes
				{"depth": "near", "amount": 190, "lifetime": 3.0, "tex": Fx.Tex.STAR, "size": 0.2,
					"color": Color(3.0, 2.1, 0.8), "speed": Vector2(0.05, 0.3), "spread": 180.0,
					"gravity": Vector3(0.0, -0.1, 0.0), "turbulence": 0.6, "curve": "pop"},
				{"depth": "near", "amount": 90, "lifetime": 3.0, "tex": Fx.Tex.DOT, "size": 0.15,
					"color": Color(3.0, 1.5, 2.8), "speed": Vector2(0.1, 0.4), "spread": 180.0,
					"gravity": Vector3(0.0, 0.2, 0.0), "turbulence": 1.2, "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				# mid: fireflies of warm light and slow falling sparks from the gears
				{"depth": "mid", "amount": 110, "lifetime": 6.0, "tex": Fx.Tex.DOT, "size": 0.5,
					"color": Color(3.2, 2.0, 0.7), "speed": Vector2(0.2, 0.6), "spread": 180.0, "turbulence": 1.5,
					"curve": "pop", "fade": PackedFloat32Array([0.0, 1.0, 0.0])},
				{"depth": "mid", "amount": 70, "lifetime": 2.2, "facing": "velocity", "tex": Fx.Tex.SPARK,
					"size": Vector2(0.06, 0.5), "color": Color(3.0, 2.0, 0.8), "dir": Vector3.DOWN, "spread": 20.0,
					"speed": Vector2(1.0, 2.5), "gravity": Vector3(0, -3.0, 0), "fade": PackedFloat32Array([0.0, 1.0, 0.0])},
				# far: first stars twinkling in the violet sky
				{"depth": "far", "amount": 110, "lifetime": 6.0, "tex": Fx.Tex.STAR, "size": 1.6, "radius": 90.0,
					"color": Color(2.0, 1.8, 2.4), "speed": Vector2.ZERO, "spread": 0.0, "curve": "pop"},
			]
		"reef":
			return [
				# near: marine snow sinking, little bubbles wobbling up
				{"depth": "near", "amount": 210, "lifetime": 3.0, "tex": Fx.Tex.DOT, "size": 0.06, "additive": false,
					"color": Color(0.9, 0.97, 1.0, 0.8), "speed": Vector2(0.02, 0.1), "spread": 180.0,
					"gravity": Vector3(0.05, -0.15, 0.0), "turbulence": 0.6, "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				{"depth": "near", "amount": 70, "lifetime": 3.0, "tex": Fx.Tex.BUBBLE, "size": 0.16,
					"color": Color(1.4, 1.8, 2.0, 0.85), "dir": Vector3.UP, "spread": 10.0, "speed": Vector2(0.6, 1.3),
					"gravity": Vector3(0, 0.4, 0), "turbulence": 1.6, "turbulence_scale": 2.0, "scale": Vector2(0.5, 1.2),
					"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				# mid: glowing plankton and bigger bubble trains
				{"depth": "mid", "amount": 110, "lifetime": 5.0, "tex": Fx.Tex.DOT, "size": 0.22,
					"pick": PackedColorArray([Color(0.4, 2.4, 2.4), Color(1.6, 0.8, 2.6), Color(0.6, 2.6, 1.4)]),
					"speed": Vector2(0.1, 0.3), "spread": 180.0, "turbulence": 1.2, "curve": "pop"},
				{"depth": "mid", "amount": 65, "lifetime": 6.0, "tex": Fx.Tex.BUBBLE, "size": 0.45,
					"color": Color(1.2, 1.6, 1.9, 0.8), "dir": Vector3.UP, "spread": 8.0, "speed": Vector2(1.0, 2.0),
					"turbulence": 1.0, "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				# far: shafts of drifting light motes in the blue
				{"depth": "far", "amount": 95, "lifetime": 9.0, "tex": Fx.Tex.DOT, "size": 2.0, "radius": 55.0,
					"color": Color(0.5, 1.4, 1.6, 0.45), "speed": Vector2(0.3, 0.8), "dir": Vector3.UP, "spread": 40.0,
					"curve": "pop", "fade": PackedFloat32Array([0.0, 0.7, 0.0])},
			]
		"orbital":
			return [
				# near: stardust and violet ion motes adrift in the station's field
				{"depth": "near", "amount": 175, "lifetime": 3.0, "tex": Fx.Tex.DOT, "size": 0.07,
					"color": Color(1.6, 1.9, 2.6), "speed": Vector2(0.05, 0.3), "spread": 180.0, "turbulence": 0.5,
					"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				{"depth": "near", "amount": 65, "lifetime": 3.0, "tex": Fx.Tex.STAR, "size": 0.16,
					"color": Color(2.2, 1.2, 2.8), "speed": Vector2(0.1, 0.4), "spread": 180.0, "turbulence": 1.0, "curve": "pop"},
				# mid: glinting debris sparkles tumbling slowly
				{"depth": "mid", "amount": 95, "lifetime": 5.0, "tex": Fx.Tex.STAR, "size": 0.4,
					"color": Color(1.8, 2.2, 2.8), "speed": Vector2(0.2, 0.6), "spread": 180.0, "curve": "pop"},
				# far: shooting stars streaking across the sky
				{"depth": "far", "amount": 10, "lifetime": 1.4, "facing": "velocity", "tex": Fx.Tex.SPARK,
					"size": Vector2(0.35, 9.0), "radius": 120.0, "color": Color(2.4, 2.6, 3.2), "dir": Vector3(1, -0.25, 0.3),
					"spread": 15.0, "speed": Vector2(50.0, 80.0), "fade": PackedFloat32Array([0.0, 1.0, 0.0])},
				{"depth": "far", "amount": 95, "lifetime": 7.0, "tex": Fx.Tex.DOT, "size": 1.6, "radius": 80.0,
					"pick": PackedColorArray([Color(0.8, 1.2, 2.6, 0.5), Color(1.8, 0.8, 2.4, 0.5)]),
					"speed": Vector2(0.2, 0.6), "spread": 180.0, "curve": "pop"},
			]
		"xeno":
			return [
				# near: spores drifting up in the low gravity, the odd blinking firefly
				{"depth": "near", "amount": 200, "lifetime": 3.0, "tex": Fx.Tex.DOT, "size": 0.09,
					"pick": PackedColorArray([Color(1.6, 0.9, 2.2, 0.9), Color(0.7, 2.0, 1.9, 0.9), Color(2.0, 0.8, 1.6, 0.9)]),
					"speed": Vector2(0.05, 0.3), "dir": Vector3.UP, "spread": 60.0, "gravity": Vector3(0.05, 0.2, 0.0),
					"turbulence": 0.8, "turbulence_scale": 5.0, "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "scale": Vector2(0.5, 1.3)},
				{"depth": "near", "amount": 60, "lifetime": 2.0, "tex": Fx.Tex.DOT, "size": 0.16,
					"pick": PackedColorArray([Color(1.8, 2.6, 0.5), Color(0.6, 2.4, 2.6)]), "speed": Vector2(0.2, 0.8),
					"spread": 180.0, "turbulence": 2.0, "turbulence_scale": 3.0, "fade": PackedFloat32Array([0.0, 1.0, 0.1, 1.0, 0.0])},
				# mid: seed parachutes tumbling slowly past, and big soft spore puffs
				{"depth": "mid", "amount": 90, "lifetime": 7.0, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.34,
					"pick": PackedColorArray([Color(0.85, 0.6, 1.0), Color(0.55, 1.0, 0.9), Color(1.0, 0.55, 0.85)]),
					"speed": Vector2(0.2, 0.5), "spread": 180.0, "gravity": Vector3(0.4, 0.12, 0.2), "turbulence": 1.0,
					"angle": Vector2(0, 360), "spin": Vector2(-90, 90), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				{"depth": "mid", "amount": 100, "lifetime": 6.0, "tex": Fx.Tex.DOT, "size": 0.45,
					"pick": PackedColorArray([Color(1.4, 0.7, 2.4), Color(0.6, 2.2, 2.0)]), "speed": Vector2(0.2, 0.6),
					"dir": Vector3.UP, "spread": 40.0, "turbulence": 1.2, "curve": "pop", "fade": PackedFloat32Array([0.0, 1.0, 0.0])},
				# far: a slow updraft of huge glowing motes round the skyline, and falling stars
				{"depth": "far", "amount": 100, "lifetime": 9.0, "tex": Fx.Tex.DOT, "size": 2.2, "radius": 70.0,
					"pick": PackedColorArray([Color(1.2, 0.6, 2.2, 0.5), Color(0.5, 1.8, 1.6, 0.5), Color(1.8, 1.5, 0.6, 0.45)]),
					"speed": Vector2(0.4, 1.2), "dir": Vector3.UP, "spread": 30.0, "curve": "pop", "fade": PackedFloat32Array([0.0, 0.7, 0.0])},
				{"depth": "far", "amount": 6, "lifetime": 1.4, "facing": "velocity", "tex": Fx.Tex.SPARK,
					"size": Vector2(0.3, 8.0), "radius": 120.0, "color": Color(1.6, 2.6, 2.4), "dir": Vector3(0.6, -0.4, -0.3),
					"spread": 15.0, "speed": Vector2(45.0, 70.0), "fade": PackedFloat32Array([0.0, 1.0, 0.0])},
			]
		"volcano":
			return [
				# near: embers riding the heat up past the lens, grey ash flakes tumbling down through them
				{"depth": "near", "amount": 200, "lifetime": 3.0, "tex": Fx.Tex.DOT, "size": 0.1,
					"colors": PackedColorArray([Color(3.4, 1.5, 0.35, 0.0), Color(3.2, 1.1, 0.25, 1.0), Color(1.8, 0.3, 0.06, 0.0)]),
					"speed": Vector2(0.5, 1.6), "dir": Vector3.UP, "spread": 35.0, "gravity": Vector3(0.3, 1.0, 0.1),
					"turbulence": 1.6, "turbulence_scale": 3.0, "scale": Vector2(0.4, 1.2)},
				{"depth": "near", "amount": 110, "lifetime": 3.0, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.13,
					"color": Color(0.3, 0.27, 0.26, 0.9), "speed": Vector2(0.2, 0.5), "dir": Vector3(0.3, -1.0, 0.1), "spread": 30.0,
					"gravity": Vector3(0.4, -0.5, 0.1), "turbulence": 1.0, "angle": Vector2(0, 360), "spin": Vector2(-240, 240),
					"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				# mid: sparks spitting up in streaks and fat embers drifting on the updraughts
				{"depth": "mid", "amount": 90, "lifetime": 1.8, "facing": "velocity", "tex": Fx.Tex.SPARK,
					"size": Vector2(0.07, 0.8), "color": Color(3.6, 1.8, 0.5), "dir": Vector3.UP, "spread": 22.0,
					"speed": Vector2(5.0, 11.0), "gravity": Vector3(0, -6.0, 0), "fade": PackedFloat32Array([0.0, 1.0, 0.0])},
				{"depth": "mid", "amount": 100, "lifetime": 5.0, "tex": Fx.Tex.DOT, "size": 0.4,
					"color": Color(2.8, 0.9, 0.22), "speed": Vector2(0.6, 1.8), "dir": Vector3.UP, "spread": 30.0,
					"gravity": Vector3(0.3, 0.7, 0), "turbulence": 1.2, "curve": "pop", "fade": PackedFloat32Array([0.0, 1.0, 0.0])},
				# far: a red-lit haze of drifting ash and big glowing embers climbing the sky
				{"depth": "far", "amount": 70, "lifetime": 10.0, "tex": Fx.Tex.SMOKE, "additive": false, "size": 14.0, "radius": 75.0,
					"color": Color(0.22, 0.09, 0.07, 0.45), "speed": Vector2(1.0, 2.5), "dir": Vector3(0.8, 0.2, 0.5), "spread": 15.0,
					"angle": Vector2(0, 360), "curve": "puff", "fade": PackedFloat32Array([0.0, 0.8, 0.8, 0.0])},
				{"depth": "far", "amount": 90, "lifetime": 8.0, "tex": Fx.Tex.DOT, "size": 2.2, "radius": 65.0,
					"color": Color(2.6, 0.8, 0.2, 0.55), "speed": Vector2(1.5, 3.5), "dir": Vector3.UP, "spread": 30.0,
					"curve": "pop", "fade": PackedFloat32Array([0.0, 0.7, 0.0])},
			]
		"glacier":
			return [
				# near: snowflakes driven sideways by the wind, diamond dust glittering in the lamplight
				{"depth": "near", "amount": 230, "lifetime": 2.2, "tex": Fx.Tex.DOT, "size": 0.09, "additive": false,
					"color": Color(1.0, 1.0, 1.0, 0.9), "dir": Vector3(1, -0.35, 0.2), "spread": 20.0, "speed": Vector2(2.0, 4.5),
					"gravity": Vector3(0.6, -0.6, 0.1), "turbulence": 1.1, "turbulence_scale": 3.0, "scale": Vector2(0.5, 1.3),
					"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				{"depth": "near", "amount": 80, "lifetime": 2.5, "tex": Fx.Tex.STAR, "size": 0.14,
					"color": Color(1.6, 2.2, 2.8), "speed": Vector2(0.05, 0.3), "spread": 180.0, "turbulence": 0.6, "curve": "pop"},
				# mid: bigger flakes tumbling past, streaks of blown snow
				{"depth": "mid", "amount": 120, "lifetime": 5.0, "tex": Fx.Tex.PETAL, "additive": false, "size": 0.28,
					"color": Color(0.96, 0.98, 1.0, 0.85), "dir": Vector3(1, -0.3, 0.1), "spread": 25.0, "speed": Vector2(1.5, 3.5),
					"gravity": Vector3(0.4, -0.5, 0.0), "turbulence": 1.3, "angle": Vector2(0, 360), "spin": Vector2(-200, 200),
					"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				{"depth": "mid", "amount": 70, "lifetime": 1.2, "facing": "velocity", "tex": Fx.Tex.SPARK, "additive": false,
					"size": Vector2(0.05, 1.8), "color": Color(0.95, 0.98, 1.0, 0.5), "dir": Vector3(1, -0.08, 0.15),
					"spread": 5.0, "speed": Vector2(12.0, 18.0), "fade": PackedFloat32Array([0.0, 0.8, 0.0])},
				# far: veils of spindrift sweeping the skyline, and faint aurora motes high up
				{"depth": "far", "amount": 45, "lifetime": 10.0, "tex": Fx.Tex.SMOKE, "additive": false, "size": 14.0,
					"radius": 75.0, "color": Color(0.9, 0.95, 1.0, 0.35), "speed": Vector2(2.0, 4.0), "dir": Vector3(1, 0.05, 0.2),
					"spread": 12.0, "angle": Vector2(0, 360), "curve": "puff", "fade": PackedFloat32Array([0.0, 0.8, 0.8, 0.0])},
				{"depth": "far", "amount": 60, "lifetime": 8.0, "tex": Fx.Tex.DOT, "size": 1.6, "radius": 90.0,
					"pick": PackedColorArray([Color(0.6, 2.4, 1.4, 0.45), Color(1.6, 0.9, 2.6, 0.45)]),
					"speed": Vector2(0.2, 0.6), "dir": Vector3.UP, "spread": 60.0, "curve": "pop"},
			]
		"ascent":
			return [
				# near: neon rain slanting down, data glints blinking
				{"depth": "near", "amount": 175, "lifetime": 0.9, "facing": "velocity", "tex": Fx.Tex.SPARK,
					"size": Vector2(0.025, 0.9), "pick": PackedColorArray([Color(0.6, 2.4, 3.0, 0.7), Color(2.6, 0.8, 2.4, 0.7)]),
					"dir": Vector3(0.15, -1, 0.05), "spread": 3.0, "speed": Vector2(12.0, 16.0),
					"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0])},
				{"depth": "near", "amount": 70, "lifetime": 2.0, "tex": Fx.Tex.DOT, "size": 0.1,
					"pick": PackedColorArray([Color(0.6, 2.6, 3.0), Color(3.0, 0.9, 2.6), Color(2.8, 2.8, 3.0)]),
					"speed": Vector2(0.0, 0.2), "spread": 180.0, "curve": "pop"},
				# mid: pixels rising toward the beacon
				{"depth": "mid", "amount": 110, "lifetime": 5.0, "tex": Fx.Tex.DOT, "size": 0.3,
					"pick": PackedColorArray([Color(0.6, 2.2, 3.0), Color(2.6, 0.9, 2.6)]),
					"dir": Vector3.UP, "spread": 15.0, "speed": Vector2(0.8, 2.0), "curve": "pop"},
				# far: a slow updraft of bright motes around the tower, and falling stars
				{"depth": "far", "amount": 110, "lifetime": 8.0, "tex": Fx.Tex.STAR, "size": 1.3, "radius": 75.0,
					"color": Color(1.8, 2.2, 3.0), "dir": Vector3.UP, "spread": 20.0, "speed": Vector2(1.0, 3.0), "curve": "pop"},
				{"depth": "far", "amount": 8, "lifetime": 1.2, "facing": "velocity", "tex": Fx.Tex.SPARK,
					"size": Vector2(0.3, 7.0), "radius": 110.0, "color": Color(2.6, 1.4, 3.0), "dir": Vector3(-0.4, -1, 0.2),
					"spread": 12.0, "speed": Vector2(45.0, 70.0), "fade": PackedFloat32Array([0.0, 1.0, 0.0])},
			]
	return []
