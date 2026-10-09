class_name ArcadeGlitch
extends Node3D
## Pixel Panic: a GLITCH TILE. One tile that is never where you left it: it sits on `spots[0]` for
## `hold` s, then glitches across to `spots[1]`, and so on round the list. The hop is on the course
## clock (identical for every racer) and it is announced `warn` s (at least 0.9) ahead, twice over:
##  * the tile tears into red / green / blue copies that jitter, flicker and shed pixels, and a
##    static crackle sounds (it is still solid and safe to stand on until the hop);
##  * the NEXT spot fills in with a pulsing outline that gets brighter as the hop nears.
## Each spot is its own fixed body (nothing teleports under a rider); only the active spot is solid.
## Spots are world top-centres. Never stand on a tile while it hops.

@export var spots: Array[Vector3] = []
@export var size: Vector3 = Vector3(1.3, 0.4, 1.3)
@export var hold: float = 3.0
## Fraction of the whole cycle (hold * spots) this tile starts at.
@export var phase: float = 0.0
@export var warn: float = 1.0
@export var tint: Color = Color(0.95, 0.96, 1.0)
@export var yaw: float = 0.0

var _bodies: Array[StaticBody3D] = []
var _shapes: Array[CollisionShape3D] = []
var _tiles: Array[Node3D] = []
var _ghosts: Array[MeshInstance3D] = []
var _ghost_mats: Array[ShaderMaterial] = []
var _splits: Array[Array] = []
var _pops: Array[GPUParticles3D] = []
var _active: int = -1
var _solid_idx: int = -1
var _warned: int = -1


func _ready() -> void:
	var cyc_n: int = spots.size()
	for i: int in cyc_n:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = spots[i] - Vector3(0, size.y * 0.5, 0)
		body.rotation.y = deg_to_rad(yaw)
		add_child(body)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.disabled = true
		body.add_child(cs)
		var tile := Node3D.new()
		body.add_child(tile)
		var mat: ShaderMaterial = ArcadeFx.block_mat(tint, size, 0.4)
		mat.set_shader_parameter("bevel", 0.1)
		tile.add_child(Look.box(size, mat))
		# the RGB split copies (shown only while glitching)
		var copies: Array[MeshInstance3D] = []
		for col: Color in [ArcadeFx.RED, ArcadeFx.GREEN, ArcadeFx.BLUE]:
			var gm: StandardMaterial3D = ArcadeFx.glow_mat(col, 2.0, 0.5).duplicate()
			gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			var c := Look.box(size + Vector3(0.04, 0.04, 0.04), gm)
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c.visible = false
			body.add_child(c)
			copies.append(c)
		_splits.append(copies)
		var gmat: ShaderMaterial = ArcadeFx.ghost_mat(tint, size)
		var ghost := Look.box(size, gmat)
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.visible = false
		body.add_child(ghost)
		_bodies.append(body)
		_shapes.append(cs)
		_tiles.append(tile)
		_ghosts.append(ghost)
		_ghost_mats.append(gmat)
		var pop: GPUParticles3D = ArcadeFx.pop(tint, 22, Vector2(1.0, 3.5), 70.0)
		body.add_child(pop)
		_pops.append(pop)
	add_to_group("course_clock")
	_apply(Game.course_time, true)
	_physics_process(0.0)


func snap_to_clock() -> void:
	_apply(Game.course_time, true)


func cycle() -> float:
	return hold * float(maxi(spots.size(), 1))


## Which spot the tile is on at `time`.
func idx_at(time: float) -> int:
	var u: float = fposmod(time + phase * cycle(), cycle())
	return mini(int(u / hold), spots.size() - 1)


## Seconds until the next hop at `time`.
func left_at(time: float) -> float:
	var u: float = fposmod(time + phase * cycle(), cycle())
	var into: float = u - floorf(u / hold) * hold
	return hold - into


## True when the tile stays on spot `i` over all of [time + a, time + b].
func at_over(i: int, time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if idx_at(time + s) != i:
			return false
		s += 0.05
	return idx_at(time + b) == i


func _physics_process(_dt: float) -> void:
	var idx: int = idx_at(Game.course_time)
	if idx != _solid_idx:
		_solid_idx = idx
		for i: int in _shapes.size():
			_shapes[i].set_deferred("disabled", i != idx)


func _process(_dt: float) -> void:
	_apply(Game.course_time, false)


func _apply(t: float, force: bool) -> void:
	var idx: int = idx_at(t)
	var left: float = left_at(t)
	var warning: bool = left < warn
	var nxt: int = (idx + 1) % spots.size()
	var k: float = clampf(1.0 - left / warn, 0.0, 1.0) if warning else 0.0
	if idx != _active or force:
		var prev: int = _active
		_active = idx
		if prev >= 0 and not force:
			_pops[idx].restart()
			_pops[idx].emitting = true
			if prev < _pops.size():
				_pops[prev].restart()
				_pops[prev].emitting = true
			# SOUND: arcade_glitch_hop - the tile tears across with a burst of static
			WorldAudio.at(self, "arcade_glitch_hop", spots[idx], 0.7, 34.0)
	for i: int in _tiles.size():
		var here: bool = i == idx
		_tiles[i].visible = here
		var split: bool = here and warning
		var jitter: float = 0.03 + 0.11 * k
		for j: int in 3:
			var c: MeshInstance3D = _splits[i][j]
			c.visible = split
			if split:
				var ph: float = t * (11.0 + 5.0 * float(j)) + float(j) * 2.1
				c.position = Vector3(sin(ph * 3.7) * jitter, 0.0, cos(ph * 2.9) * jitter) * (1.0 if j != 1 else -1.0)
		if split:
			# the tile itself flickers faster and faster
			var blink: float = 0.5 + 0.5 * sin(t * lerpf(14.0, 40.0, k) * TAU)
			_tiles[i].visible = blink > 0.25 * k
		var show_ghost: bool = (i == nxt and warning) and i != idx
		_ghosts[i].visible = show_ghost
		if show_ghost:
			_ghost_mats[i].set_shader_parameter("pulse", lerpf(0.25, 1.0, k) * (0.5 + 0.5 * sin(t * lerpf(6.0, 20.0, k) * TAU)))
	if warning and _warned != idx:
		_warned = idx
		# SOUND: arcade_glitch_warn - a rising static crackle: this tile is about to hop (~1 s ahead)
		WorldAudio.at(self, "arcade_glitch_warn", spots[idx], 0.55, 28.0)
	elif not warning:
		_warned = -1
