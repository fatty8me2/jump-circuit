class_name TempestScaffold
extends AnimatableBody3D
## Tempest Tower: FAILING SCAFFOLDING - a lift of scaffold boards on a tube frame that the storm has
## already worked loose. It rocks in the wind all the time; stand on it and it starts to go - it
## sways harder and creaks for `delay` seconds - then the couplers let go and the whole bay drops
## away into the cloud, tubes and boards tumbling. A new bay is swung back in `respawn` seconds
## later. reset_state() restores it at once (called when the player respawns).
## Positioned at the centre of the boards' top surface minus half their thickness (like kit.collapse).

@export var size: Vector3 = Vector3(2.4, 0.3, 2.4)
@export var delay: float = 0.9
@export var respawn: float = 3.0
## How far the frame's tubes hang below the boards (looks only).
@export var frame_depth: float = 2.6

enum State { IDLE, SWAYING, FALLING, GONE }

var _state: State = State.IDLE
var _timer: float = 0.0
var _vis: Node3D
var _shape: CollisionShape3D
var _fall_speed: float = 0.0
var _grow: Tween
var _grit: GPUParticles3D
var _snap: GPUParticles3D
var _seed: float = 0.0


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	add_to_group("resettable")
	_seed = fposmod(position.x * 0.37 + position.z * 0.71, TAU)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	_shape.shape = box
	add_child(_shape)
	_vis = Node3D.new()
	add_child(_vis)
	_build()
	_build_fx()


func _build() -> void:
	var board: StandardMaterial3D = Look.flat(Color(0.62, 0.48, 0.3), 0.9)
	var board_dark: StandardMaterial3D = Look.flat(Color(0.5, 0.38, 0.24), 0.9)
	var tube: StandardMaterial3D = Look.flat(Color(0.7, 0.72, 0.75), 0.35, 0.85)
	var clamp: StandardMaterial3D = Look.flat(Color(0.95, 0.72, 0.12), 0.5, 0.4)
	# the boards (planks running along local z) with a yellow toe board on the outer edges
	var n: int = maxi(int(round(size.x / 0.3)), 2)
	var w: float = size.x / float(n)
	for i: int in n:
		var p := Look.box(Vector3(w - 0.03, size.y, size.z), board if i % 2 == 0 else board_dark, Vector3(-size.x * 0.5 + w * (float(i) + 0.5), 0, 0))
		_vis.add_child(p)
	for sz: float in [-1.0, 1.0]:
		_vis.add_child(Look.box(Vector3(size.x, 0.06, 0.08), clamp, Vector3(0, size.y * 0.5 - 0.02, sz * (size.z * 0.5 - 0.04))))
	# the tube frame under it: four standards hanging into the void, ledgers and a diagonal brace
	var hx: float = size.x * 0.5 - 0.08
	var hz: float = size.z * 0.5 - 0.08
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_vis.add_child(Look.cylinder(0.045, frame_depth, tube, Vector3(sx * hx, -frame_depth * 0.5, sz * hz), -1.0, 6))
			_vis.add_child(Look.box(Vector3(0.12, 0.12, 0.12), clamp, Vector3(sx * hx, -size.y * 0.5 - 0.06, sz * hz)))
	for sx: float in [-1.0, 1.0]:
		_vis.add_child(Look.box(Vector3(0.07, 0.07, size.z - 0.1), tube, Vector3(sx * hx, -size.y * 0.5 - 0.15, 0)))
		_vis.add_child(Look.box(Vector3(0.07, 0.07, size.z - 0.1), tube, Vector3(sx * hx, -frame_depth + 0.2, 0)))
		var br := Look.box(Vector3(0.06, 0.06, sqrt(size.z * size.z + frame_depth * frame_depth) * 0.9), tube, Vector3(sx * hx, -frame_depth * 0.5, 0))
		br.rotation.x = atan2(frame_depth, size.z)
		_vis.add_child(br)
	# a torn strip of debris netting snapping off one side
	var net := Look.box(Vector3(0.02, frame_depth * 0.7, size.z * 0.8), Look.flat(Color(0.2, 0.55, 0.35, 0.75), 0.9), Vector3(hx + 0.06, -frame_depth * 0.4, 0))
	_vis.add_child(net)


func _build_fx() -> void:
	var vis := AABB(Vector3(-size.x - 3.0, -20.0, -size.z - 3.0), Vector3(size.x * 2.0 + 6.0, 24.0, size.z * 2.0 + 6.0))
	_grit = Fx.emitter({"amount": 14, "lifetime": 0.7, "emitting": false, "shape": "box",
		"extents": Vector3(size.x * 0.4, 0.02, size.z * 0.4), "dir": Vector3.DOWN, "spread": 20.0, "speed": Vector2(0.4, 1.4),
		"gravity": Vector3(0, -14, 0), "additive": false, "size": 0.08, "scale": Vector2(0.5, 1.2),
		"color": Color(0.5, 0.42, 0.32, 0.95), "fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": vis})
	_grit.position = Vector3(0, -size.y * 0.5 - 0.05, 0)
	add_child(_grit)
	_snap = Fx.sparks({"amount": 22, "shape": "box", "extents": Vector3(size.x * 0.5, 0.1, size.z * 0.5),
		"dir": Vector3.UP, "spread": 80.0, "speed": Vector2(2.0, 6.0), "color": Color(2.4, 1.8, 0.9), "aabb": vis})
	_snap.position = Vector3(0, -size.y * 0.5 - 0.1, 0)
	add_child(_snap)


## Player contract: called every tick while stood on.
func apply_rider_load(_point: Vector3, _force: float) -> void:
	if _state == State.IDLE:
		_state = State.SWAYING
		_timer = 0.0
		# SOUND: the frame groaning as it starts to go
		WorldAudio.at(self, "tempest_scaffold_creak", global_position, 0.9, 30.0)
		_grit.emitting = true


func reset_state() -> void:
	_state = State.IDLE
	_timer = 0.0
	_fall_speed = 0.0
	_vis.position = Vector3.ZERO
	_vis.rotation = Vector3.ZERO
	_vis.scale = Vector3.ONE
	_vis.visible = true
	_shape.set_deferred("disabled", false)
	_grit.emitting = false
	if _grow != null and _grow.is_valid():
		_grow.kill()
	_vis.reset_physics_interpolation()


func _process(_dt: float) -> void:
	if _state == State.IDLE:
		# rocking gently in the storm all the time (looks only)
		var t: float = Game.course_time
		_vis.rotation = Vector3(sin(t * 1.7 + _seed) * 0.012, 0, sin(t * 2.3 + _seed * 1.3) * 0.016)


func _physics_process(dt: float) -> void:
	match _state:
		State.SWAYING:
			_timer += dt
			var k: float = _timer / delay
			var amp: float = 0.02 + 0.07 * k
			_vis.rotation = Vector3(sin(_timer * 13.0) * amp * 0.6, 0, sin(_timer * 9.0) * amp)
			_vis.position = Vector3(sin(_timer * 9.0) * amp * 0.5, -k * 0.1, 0)
			if _timer >= delay:
				_state = State.FALLING
				_timer = 0.0
				_shape.set_deferred("disabled", true)
				# SOUND: the couplers letting go and the bay dropping away
				WorldAudio.at(self, "tempest_scaffold_fall", global_position, 1.0, 40.0)
				_grit.emitting = false
				_snap.restart()
				_snap.emitting = true
		State.FALLING:
			_timer += dt
			_fall_speed += 30.0 * dt
			_vis.position.y -= _fall_speed * dt
			_vis.position.x += dt * 1.5
			_vis.rotation.z += dt * 1.6
			_vis.rotation.x += dt * 0.7
			if _timer > 1.3:
				_state = State.GONE
				_vis.visible = false
				_timer = 0.0
		State.GONE:
			_timer += dt
			if _timer >= respawn:
				reset_state()
				_vis.scale = Vector3.ONE * 0.05
				WorldAudio.at(self, "platform_reform", global_position, 0.5, 30.0)
				_grow = create_tween()
				_grow.tween_property(_vis, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
