class_name OlympusColumn
extends AnimatableBody3D
## Sky Citadel: a CRUMBLING COLUMN. A fluted marble column whose square capital is a stepping stone.
## Stand on it and the old stone remembers its age: gold cracks run down the shaft and dust sifts
## off the capital (the tell), the column shudders for `delay` seconds (at least 0.8), then the
## whole column lets go and falls away. After `respawn` seconds it rises back out of the cloud
## (shown by a gold shimmer a moment before it is solid again). reset_state() restores it at
## once (called on player respawn). Positioned by `top`: the node's origin is the centre of the
## capital's top surface. Same rider contract as CollapsingPlatform (apply_rider_load).
##   states: IDLE -> SHAKING (rider on it) -> FALLING -> GONE -> (re-forms) IDLE

@export var edge: float = 1.5
@export var delay: float = 0.9
@export var respawn: float = 3.4
## Visible length of the shaft below the capital.
@export var shaft: float = 4.0

enum State { IDLE, SHAKING, FALLING, GONE }

const MARBLE := Color(0.95, 0.92, 0.84)
const GOLD := Color(1.0, 0.78, 0.28)

var _state: State = State.IDLE
var _timer: float = 0.0
var _fall_speed: float = 0.0
var _shape: CollisionShape3D
var _body: Node3D          # everything visible (shakes and falls)
var _crack_mat: StandardMaterial3D
var _dust: GPUParticles3D
var _debris: GPUParticles3D
var _shimmer: GPUParticles3D
var _grow: Tween
var _shimmered: bool = false


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	add_to_group("resettable")
	var box := BoxShape3D.new()
	box.size = Vector3(edge, 0.4, edge)
	_shape = CollisionShape3D.new()
	_shape.shape = box
	_shape.position = Vector3(0, -0.2, 0)
	add_child(_shape)
	_build()


## Player contract: called every tick while stood on.
func apply_rider_load(_point: Vector3, _force: float) -> void:
	if _state == State.IDLE:
		_state = State.SHAKING
		_timer = 0.0
		_dust.emitting = true
		# SOUND: olympus_column_crack - old marble groaning and splitting (the tell, `delay` s of it)
		WorldAudio.at(self, "olympus_column_crack", global_position, 0.9, 32.0)


func reset_state() -> void:
	_state = State.IDLE
	_timer = 0.0
	_fall_speed = 0.0
	_shimmered = false
	_body.position = Vector3.ZERO
	_body.rotation = Vector3.ZERO
	_body.scale = Vector3.ONE
	_body.visible = true
	_crack_mat.emission_energy_multiplier = 0.0
	_shape.set_deferred("disabled", false)
	_dust.emitting = false
	if _grow != null and _grow.is_valid():
		_grow.kill()
	_body.reset_physics_interpolation()


## True while the stone is standing (a rider is safe on it right now).
func is_solid() -> bool:
	return _state == State.IDLE or _state == State.SHAKING


func _physics_process(dt: float) -> void:
	match _state:
		State.SHAKING:
			_timer += dt
			var k: float = clampf(_timer / delay, 0.0, 1.0)
			var amp: float = 0.012 + 0.05 * k * k
			_body.position = Vector3(sin(_timer * 67.0), sin(_timer * 49.0) * 0.3 - k * 0.05, cos(_timer * 58.0)) * amp
			_body.rotation = Vector3(sin(_timer * 43.0), 0.0, cos(_timer * 53.0)) * amp * 0.5
			# the cracks fill with gold light, brightening as the stone gives up
			_crack_mat.emission_energy_multiplier = 0.4 + 3.2 * k * (0.7 + 0.3 * sin(_timer * 28.0))
			if _timer >= delay:
				_state = State.FALLING
				_timer = 0.0
				_shape.set_deferred("disabled", true)
				_dust.emitting = false
				_debris.restart()
				_debris.emitting = true
				# SOUND: olympus_column_fall - the column tearing loose and tumbling into the clouds
				WorldAudio.at(self, "olympus_column_fall", global_position, 0.9, 36.0)
		State.FALLING:
			_timer += dt
			_fall_speed += 30.0 * dt
			_body.position.y -= _fall_speed * dt
			_body.rotation.x += dt * 0.9
			_body.rotation.z += dt * 0.4
			_body.scale = Vector3.ONE * maxf(1.0 - _timer * 0.75, 0.05)
			if _timer > 1.2:
				_state = State.GONE
				_body.visible = false
				_timer = 0.0
		State.GONE:
			_timer += dt
			if _timer >= respawn - 0.6 and not _shimmered:
				_shimmered = true
				_shimmer.restart()
				_shimmer.emitting = true
			if _timer >= respawn:
				reset_state()
				_body.scale = Vector3.ONE * 0.05
				# SOUND: olympus_column_reform - gold chimes as the column rises back out of the cloud
				WorldAudio.at(self, "olympus_column_reform", global_position, 0.5, 28.0)
				_grow = create_tween()
				_grow.tween_property(_body, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var marble: StandardMaterial3D = Look.flat(MARBLE, 0.5)
	var worn: StandardMaterial3D = Look.flat(MARBLE.darkened(0.1), 0.6)
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.35, 0.5, 0.35)
	# the capital: a square abacus (the stepping stone), a gold fillet, the rounded echinus under it
	_body.add_child(Look.box(Vector3(edge, 0.3, edge), marble, Vector3(0, -0.15, 0)))
	_body.add_child(Look.box(Vector3(edge + 0.08, 0.05, edge + 0.08), gold, Vector3(0, -0.33, 0)))
	_body.add_child(Look.cylinder(edge * 0.42, 0.28, marble, Vector3(0, -0.5, 0), edge * 0.3, 16))
	# the shaft: fluted drums stacked down into the cloud, narrowing a touch
	var r: float = edge * 0.3
	var drum: float = shaft / 3.0
	for i: int in 3:
		var y: float = -0.65 - drum * (float(i) + 0.5)
		var d := Look.cylinder(r * (1.0 - 0.05 * float(i)), drum - 0.04, worn if i % 2 == 1 else marble, Vector3(0, y, 0), r * (1.0 - 0.05 * float(i + 1)), 14)
		_body.add_child(d)
		# flutes: thin dark grooves down the drum
		for k: int in 6:
			var a: float = TAU * float(k) / 6.0
			var fl := Look.box(Vector3(0.05, drum - 0.1, 0.03), Look.flat(MARBLE.darkened(0.3), 0.8), Vector3(cos(a), 0, sin(a)) * r * (1.0 - 0.05 * float(i)) * 0.98 + Vector3(0, y, 0))
			fl.rotation.y = -a + PI * 0.5
			_body.add_child(fl)
	# gold cracks: glowing jagged lines down the shaft and across the capital's face, dark until the
	# column is stood on (emission rises with the shake)
	_crack_mat = StandardMaterial3D.new()
	_crack_mat.albedo_color = Color(0.25, 0.18, 0.08)
	_crack_mat.emission_enabled = true
	_crack_mat.emission = GOLD
	_crack_mat.emission_energy_multiplier = 0.0
	for k: int in 4:
		var a2: float = TAU * (float(k) + 0.5) / 4.0
		var base := Vector3(cos(a2), 0, sin(a2)) * (r * 0.97)
		var seg_h: float = shaft * 0.28
		for j: int in 3:
			var cy: float = -0.7 - seg_h * (float(j) + 0.5) * 1.1
			var seg := Look.box(Vector3(0.045, seg_h, 0.03), _crack_mat, base + Vector3(sin(float(j) * 2.1 + float(k)) * 0.06, cy, 0))
			seg.rotation = Vector3(0.0, -a2 + PI * 0.5, 0.35 * sin(float(j) * 3.0 + float(k)))
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body.add_child(seg)
		var top_crack := Look.box(Vector3(edge * 0.45, 0.012, 0.04), _crack_mat, Vector3(cos(a2) * edge * 0.2, 0.005, sin(a2) * edge * 0.2))
		top_crack.rotation.y = -a2
		top_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(top_crack)
	var vis := AABB(Vector3(-edge - 3.0, -shaft - 14.0, -edge - 3.0), Vector3(edge * 2.0 + 6.0, shaft + 20.0, edge * 2.0 + 6.0))
	_dust = Fx.emitter({"amount": 16, "lifetime": 1.0, "emitting": false, "shape": "box",
		"extents": Vector3(edge * 0.45, 0.02, edge * 0.45), "offset": Vector3(0, -0.35, 0), "dir": Vector3.DOWN,
		"spread": 25.0, "speed": Vector2(0.2, 0.9), "gravity": Vector3(0, -3.0, 0), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 0.45, "curve": "puff", "color": Color(0.96, 0.92, 0.82, 0.55),
		"fade": PackedFloat32Array([0.0, 0.8, 0.0]), "aabb": vis})
	add_child(_dust)
	_debris = Fx.debris({"amount": 30, "lifetime": 1.2, "shape": "box", "extents": Vector3(edge * 0.4, 0.2, edge * 0.4),
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(1.0, 4.0), "color": Color(0.95, 0.9, 0.8), "chunk": 0.2,
		"aabb": vis})
	add_child(_debris)
	_shimmer = Fx.emitter({"amount": 18, "lifetime": 0.7, "emitting": false, "one_shot": true, "explosiveness": 0.4,
		"shape": "box", "extents": Vector3(edge * 0.5, 0.05, edge * 0.5), "dir": Vector3.UP, "spread": 25.0,
		"speed": Vector2(0.4, 1.2), "tex": Fx.Tex.STAR, "size": 0.22, "color": Fx.hot(GOLD, 2.2), "curve": "pop", "aabb": vis})
	add_child(_shimmer)
