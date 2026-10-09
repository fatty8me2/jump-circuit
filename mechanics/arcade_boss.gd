class_name ArcadeBoss
extends Node3D
## Pixel Panic's set piece: the PIXEL BOSS. A colossal voxel invader looms over the end of the arena,
## and every so often it spends its eyes on a spot of the course. Each attack is a loop on the course
## clock (identical for every racer; Game.course_time):
##   TELL  `tell` s (at least 0.9): a red target square pulses on the spot, corner rays climb, the
##         boss's eyes flare and a rising charge whine sounds. Nothing hurts yet.
##   FIRE  `on` s: a column of white-hot pixels slams down on the square from the sky. Anything inside
##         it is sent back to the checkpoint.
##   REST  the rest of the loop.
## The boss itself is scenery with a pulse: it bobs, its eyes blaze at every tell, and (finish_burst)
## it bursts into pixels when the high-score gate is reached.
##   add_attack(...) registers an attack; window_clear() / fire_at() let a route predict them.

const BITMAP: Array[String] = [
	"..#.....#..",
	"...#...#...",
	"..#######..",
	".##.###.##.",
	"###########",
	"#.#######.#",
	"#.#.....#.#",
	"...##.##...",
]

@export var voxel: float = 1.5
## World point of the bottom centre of the boss, and the direction it faces (horizontal).
@export var boss_pos: Vector3 = Vector3.ZERO
@export var face_dir: Vector3 = Vector3(0, 0, 1)

class Attack:
	var pos: Vector3
	var half: Vector2
	var period: float
	var phase: float
	var tell: float
	var on: float
	var kill: Area3D
	var reticle: MeshInstance3D
	var rays: Node3D
	var beam: Node3D
	var burst: GPUParticles3D
	var reticle_mat: ShaderMaterial
	var state: int = -1

var _attacks: Array[Attack] = []
var _boss: Node3D
var _eye_mat: StandardMaterial3D
var _boss_base_y: float = 0.0
var _parts: GPUParticles3D
var _ray_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("course_clock")
	_ray_mat = ArcadeFx.glow_mat(ArcadeFx.RED, 2.4, 0.8).duplicate()
	_beam_mat = ArcadeFx.glow_mat(ArcadeFx.MAGENTA, 2.0, 0.45).duplicate()
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_core_mat = ArcadeFx.glow_mat(Color(1, 1, 1), 3.0, 0.9).duplicate()
	_core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_build_boss()


## Registers an attack on the floor point `pos` (world); `phase_s` shifts its loop (s). Returns its index.
func add_attack(pos: Vector3, half: Vector2, period: float, phase_s: float, tell: float = 1.1, on: float = 0.6) -> int:
	var a := Attack.new()
	a.pos = pos
	a.half = half
	a.period = period
	a.phase = fposmod(phase_s / period, 1.0)
	a.tell = tell
	a.on = on
	var size := Vector3(half.x * 2.0, 0.3, half.y * 2.0)
	a.reticle_mat = ArcadeFx.ghost_mat(ArcadeFx.RED, size)
	a.reticle = Look.box(size, a.reticle_mat, pos + Vector3(0, 0.12, 0))
	a.reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.reticle.visible = false
	add_child(a.reticle)
	a.rays = Node3D.new()
	a.rays.position = pos
	add_child(a.rays)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var r := Look.box(Vector3(0.1, 4.0, 0.1), _ray_mat, Vector3(sx * half.x, 2.0, sz * half.y))
			r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			a.rays.add_child(r)
	a.rays.visible = false
	a.beam = Node3D.new()
	a.beam.position = pos
	add_child(a.beam)
	var bm := Look.box(Vector3(half.x * 2.0, 34.0, half.y * 2.0), _beam_mat, Vector3(0, 17.0, 0))
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.beam.add_child(bm)
	var core := Look.box(Vector3(half.x * 1.2, 34.0, half.y * 1.2), _core_mat, Vector3(0, 17.0, 0))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.beam.add_child(core)
	a.beam.visible = false
	a.kill = ArcadeFx.hazard_area(Vector3(half.x * 2.0 * 0.96, 28.0, half.y * 2.0 * 0.96), pos + Vector3(0, 14.0, 0))
	a.kill.monitoring = false
	add_child(a.kill)
	a.burst = ArcadeFx.pop(ArcadeFx.MAGENTA, 40, Vector2(3.0, 9.0), 75.0)
	a.burst.position = pos + Vector3(0, 0.3, 0)
	add_child(a.burst)
	_attacks.append(a)
	return _attacks.size() - 1


func attack_count() -> int:
	return _attacks.size()


## Seconds into attack i's loop at `time`.
func cycle_at(i: int, time: float) -> float:
	var a: Attack = _attacks[i]
	return fposmod(time + a.phase * a.period, a.period)


## True while attack i is firing.
func fire_at(i: int, time: float) -> bool:
	var a: Attack = _attacks[i]
	var u: float = cycle_at(i, time)
	return u >= a.tell and u < a.tell + a.on


## True when attack i does not fire at any time in [time + a, time + b] (padded by `pad` s each side).
func window_clear(i: int, time: float, a: float, b: float, pad: float = 0.1) -> bool:
	var s: float = a - pad
	while s <= b + pad:
		if fire_at(i, time + s):
			return false
		s += 0.04
	return true


func snap_to_clock() -> void:
	_apply(Game.course_time)


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	for i: int in _attacks.size():
		var a: Attack = _attacks[i]
		var on: bool = fire_at(i, t)
		if a.kill.monitoring != on:
			a.kill.set_deferred("monitoring", on)


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var soonest: float = INF
	for i: int in _attacks.size():
		var a: Attack = _attacks[i]
		var u: float = cycle_at(i, t)
		var st: int = 0
		if u < a.tell:
			st = 1
		elif u < a.tell + a.on:
			st = 2
		a.reticle.visible = st == 1
		a.rays.visible = st == 1
		a.beam.visible = st == 2
		if st == 1:
			var k: float = clampf(u / maxf(a.tell, 0.1), 0.0, 1.0)
			a.reticle_mat.set_shader_parameter("pulse", lerpf(0.3, 1.0, k) * (0.5 + 0.5 * sin(t * lerpf(6.0, 24.0, k) * TAU)))
			a.rays.scale = Vector3(1.0, lerpf(0.3, 1.3, k), 1.0)
			soonest = minf(soonest, a.tell - u)
		elif st == 2:
			var f: float = clampf((u - a.tell) / maxf(a.on, 0.1), 0.0, 1.0)
			a.beam.scale = Vector3(lerpf(1.0, 0.6, f), 1.0, lerpf(1.0, 0.6, f))
		if st != a.state:
			if st == 1 and a.state >= 0:
				# SOUND: arcade_boss_charge - a rising whine as the boss's eyes lock on (~1.1 s ahead)
				WorldAudio.at(self, "arcade_boss_charge", a.pos, 0.8, 70.0)
			elif st == 2:
				a.burst.restart()
				a.burst.emitting = true
				Fx.flash(self, a.pos + Vector3(0, 2.0, 0), ArcadeFx.MAGENTA, 5.0, 12.0, 0.4)
				# SOUND: arcade_boss_blast - the column slams down with a crunchy 8-bit boom
				WorldAudio.at(self, "arcade_boss_blast", a.pos, 1.0, 60.0)
			a.state = st
	if _eye_mat != null:
		var glow: float = 1.0
		if soonest < INF:
			glow = 1.0 + 3.0 * (1.0 - clampf(soonest / 1.2, 0.0, 1.0)) * (0.6 + 0.4 * sin(t * 30.0))
		_eye_mat.albedo_color = Color(2.2 * glow, 0.2 * glow, 0.2 * glow)
	if _boss != null:
		_boss.position.y = _boss_base_y + sin(t * 1.3) * 0.35


## The boss bursts into pixels (the finish).
func finish_burst() -> void:
	if _parts != null:
		_parts.restart()
		_parts.emitting = true
	if _boss != null:
		_boss.visible = false
	# SOUND: arcade_boss_defeat - the boss pops into pixels with a falling chiptune sweep
	WorldAudio.at(self, "arcade_boss_defeat", boss_pos, 1.0, 120.0)


func _build_boss() -> void:
	_boss = Node3D.new()
	_boss.position = boss_pos
	_boss_base_y = boss_pos.y
	add_child(_boss)
	var dir: Vector3 = Vector3(face_dir.x, 0.0, face_dir.z)
	if dir.length() < 0.01:
		dir = Vector3(0, 0, 1)
	_boss.look_at_from_position(boss_pos, boss_pos + dir.normalized(), Vector3.UP)
	# the voxels face the player (+Z local after look_at faces -Z, so flip: the boss's face is its local -Z? no:
	# look_at points -Z at the target; the bitmap's front is -Z, which then faces `dir`)
	var rows: int = BITMAP.size()
	var cols: int = BITMAP[0].length()
	var body: Array[Vector3] = []
	for r: int in rows:
		for c: int in cols:
			if BITMAP[r][c] == "#":
				for z: int in range(0, 3):
					body.append(Vector3((float(c) - float(cols - 1) * 0.5) * voxel, (float(rows - 1 - r) + 0.5) * voxel + 6.0, float(z) * voxel))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * (voxel - 0.06)
	mm.mesh = bm
	mm.instance_count = body.size()
	for i: int in body.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, body[i]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat: ShaderMaterial = ArcadeFx.block_mat(ArcadeFx.MAGENTA, Vector3.ONE * voxel, 0.55)
	mat.set_shader_parameter("bevel", voxel * 0.1)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_boss.add_child(mi)
	# eyes: two blazing cubes in the gaps of row 3
	_eye_mat = ArcadeFx.glow_mat(ArcadeFx.RED, 2.2).duplicate()
	for ex: int in [3, 7]:
		var e := Look.box(Vector3(voxel * 0.9, voxel * 0.9, voxel * 0.5), _eye_mat,
			Vector3((float(ex) - float(cols - 1) * 0.5) * voxel, (float(rows - 1 - 3) + 0.5) * voxel + 6.0, -voxel * 0.55))
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_boss.add_child(e)
	# when it is defeated: its voxels as flying pixels
	_parts = Fx.burst({"amount": 160, "lifetime": 2.6, "facing": "mesh", "mesh": ArcadeFx.pixel_mesh(), "shape": "box",
		"extents": Vector3(cols * voxel * 0.5, rows * voxel * 0.5, voxel), "dir": Vector3.UP, "spread": 180.0,
		"speed": Vector2(4.0, 16.0), "gravity": Vector3(0, -6.0, 0), "damping": Vector2(0.3, 1.0), "scale": Vector2(1.5, 4.5),
		"angle": Vector2(0, 360), "spin": Vector2(-200, 200),
		"pick": PackedColorArray([Fx.hot(ArcadeFx.MAGENTA, 2.2), Fx.hot(ArcadeFx.CYAN, 2.0), Fx.hot(ArcadeFx.YELLOW, 2.0), Fx.hot(ArcadeFx.WHITE, 1.8)]),
		"curve": "shrink", "aabb": AABB(Vector3(-60, -20, -60), Vector3(120, 100, 120))})
	_parts.position = Vector3(0, 6.0 + float(rows) * voxel * 0.5, 0)
	_boss.add_child(_parts)
