class_name GardensTrimmer
extends Node3D
## THE TRIMMER - Launch Gardens' hedge-maze set piece. A laser curtain (a LaserGate that
## never switches off) glides up and down a hedge alley on the course clock, eased at both
## ends, shearing the hedges as it goes (a spray of clippings follows each post). The only
## way down the alley is to hop from side pocket to side pocket while it sweeps past.
## Local frame: the beam spans local X (the alley width); it travels from `a` to `b` and back
## once per `period`. Deterministic, identical for every racer.

@export var a: Vector3 = Vector3.ZERO
@export var b: Vector3 = Vector3(0, 0, -20)
@export var period: float = 8.0
@export var phase: float = 0.0
## Beam size (x = alley width between the posts, y = curtain height, z = thickness).
@export var beam_size: Vector3 = Vector3(2.4, 3.0, 0.25)

var gate: LaserGate


func _ready() -> void:
	gate = LaserGate.new()
	gate.size = beam_size
	gate.period = 1.0
	gate.on_fraction = 1.0
	add_child(gate)
	# the shears' motor housings riding on the hedge tops above each post
	var housing: StandardMaterial3D = Look.flat(Color(0.2, 0.22, 0.26), 0.4, 0.7)
	var blade: StandardMaterial3D = Look.flat(Color(1.0, 0.25, 0.15), 0.3, 0.2, 2.2)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (beam_size.x * 0.5 + 0.18)
		gate.add_child(Look.box(Vector3(0.7, 0.35, 0.9), housing, Vector3(x, beam_size.y * 0.5 + 0.55, 0)))
		gate.add_child(Look.box(Vector3(0.9, 0.08, 0.12), blade, Vector3(x, beam_size.y * 0.5 + 0.3, 0)))
		if DisplayServer.get_name() != "headless":
			var clip: GPUParticles3D = GardensFx.clippings(Vector3(0.25, beam_size.y * 0.4, 0.2), 22)
			clip.position = Vector3(x, 0.2, 0)
			gate.add_child(clip)
	add_to_group("course_clock")
	snap_to_clock()


## Beam offset (local to this node) at course time `time`.
func offset_at(time: float) -> Vector3:
	var u: float = fposmod(time / maxf(period, 0.01) + phase, 1.0)
	var tri: float = 1.0 - absf(u * 2.0 - 1.0)
	var k: float = tri * tri * (3.0 - 2.0 * tri)
	return a.lerp(b, k)


## Beam centre in world space at course time `time`.
func beam_at(time: float) -> Vector3:
	return global_transform * offset_at(time)


func snap_to_clock() -> void:
	gate.position = offset_at(Game.course_time)
	gate.reset_physics_interpolation()


func _physics_process(_dt: float) -> void:
	gate.position = offset_at(Game.course_time)
