class_name ArcadeBlock
extends AnimatableBody3D
## Pixel Panic: a FALLING TETROMINO. A flat piece of 1.2 m cells keeps a loop on the course clock
## (identical for every racer; Game.course_time):
##   TELL   `tell` s (at least 0.9): a pixel outline blinks faster and faster where it will land, a
##          light column stands over the spot and a ticking beep sounds. Nothing is there yet.
##   FALL   `fall` s: it drops from `drop_h` above. The cells are deadly while it falls.
##   HOLD   `hold` s: settled, solid, safe - a step in the stack.
##   CLEAR  `clear` s (at least 0.9): still solid, but flashing white faster and faster. The row is
##          about to clear.
##   GONE   the rest of `period`: it bursts into pixels and is gone until the next loop.
## The node's position is the CENTRE of the anchor cell's body (cell (0,0)); `cells` are x/z offsets
## in cell units. A route should plan on solid_over(): it holds for hold + clear seconds.

@export var cells: Array[Vector2] = [Vector2(0, 0)]
@export var cell: float = 1.2
@export var thick: float = 0.6
@export var tint: Color = Color(0.1, 0.92, 1.0)
@export var period: float = 7.0
## Fraction of the cycle this piece starts at.
@export var phase: float = 0.0
@export var tell: float = 1.1
@export var fall: float = 0.4
@export var hold: float = 3.2
@export var clear: float = 1.0
@export var drop_h: float = 12.0

var _origin: Vector3
var _shapes: Array[CollisionShape3D] = []
var _body: Node3D
var _ghost: Node3D
var _column: MeshInstance3D
var _col_mat: StandardMaterial3D
var _mat: ShaderMaterial
var _ghost_mat: ShaderMaterial
var _kills: Array[Area3D] = []
var _solid: bool = false
var _state: int = -1
var _land_fx: GPUParticles3D
var _land_ring: GPUParticles3D
var _clear_fx: GPUParticles3D
var _beep: float = -1.0

enum S { TELL, FALL, HOLD, CLEAR, GONE }


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var box_size := Vector3(cell, thick, cell)
	_body = Node3D.new()
	add_child(_body)
	_ghost = Node3D.new()
	add_child(_ghost)
	_mat = ArcadeFx.block_mat(tint, box_size - Vector3(0.04, 0, 0.04))
	_ghost_mat = ArcadeFx.ghost_mat(tint, box_size)
	var ext := Vector3.ZERO
	for c: Vector2 in cells:
		var off := Vector3(c.x * cell, 0, c.y * cell)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box_size
		cs.shape = bs
		cs.position = off
		cs.disabled = true
		add_child(cs)
		_shapes.append(cs)
		_body.add_child(Look.box(box_size - Vector3(0.04, 0, 0.04), _mat, off))
		var g := Look.box(box_size, _ghost_mat, off)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost.add_child(g)
		var kz: Area3D = ArcadeFx.hazard_area(Vector3(cell * 0.94, thick + 0.5, cell * 0.94), off)
		kz.monitoring = false
		add_child(kz)
		_kills.append(kz)
		ext = ext.max(Vector3(absf(off.x), 0, absf(off.z)))
	# the light column over the landing spot
	_col_mat = ArcadeFx.glow_mat(tint, 1.0, 0.0).duplicate()
	_col_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_col_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_col_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cm := BoxMesh.new()
	cm.size = Vector3(cell * 0.9 + ext.x * 2.0, drop_h, cell * 0.9 + ext.z * 2.0)
	_column = Look.mesh_node(cm, _col_mat, Vector3(0, drop_h * 0.5 + thick * 0.5, 0))
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_column)
	var vis := AABB(Vector3(-8, -4, -8), Vector3(16, drop_h + 10.0, 16))
	var hot: Color = Fx.hot(tint, 1.8)
	_land_fx = Fx.debris({"amount": 22, "chunk": 0.16, "shape": "box", "extents": Vector3(cell * 0.5 + ext.x, 0.1, cell * 0.5 + ext.z),
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(2.0, 5.0), "gravity": Vector3(0, -14.0, 0),
		"color": tint, "lifetime": 0.8, "aabb": vis})
	_land_fx.position = Vector3(0, thick * 0.5, 0)
	add_child(_land_fx)
	_land_ring = Fx.shockwave(cell * 2.2, {"lifetime": 0.45, "color": hot, "aabb": vis})
	_land_ring.position = Vector3(0, thick * 0.5 + 0.05, 0)
	add_child(_land_ring)
	_clear_fx = Fx.burst({"amount": 34, "lifetime": 0.9, "facing": "mesh", "mesh": ArcadeFx.pixel_mesh(),
		"shape": "box", "extents": Vector3(cell * 0.5 + ext.x, 0.2, cell * 0.5 + ext.z), "dir": Vector3.UP, "spread": 60.0,
		"speed": Vector2(1.5, 5.0), "gravity": Vector3(0, -6.0, 0), "scale": Vector2(0.6, 1.5),
		"color": hot, "curve": "shrink", "aabb": vis})
	add_child(_clear_fx)
	add_to_group("course_clock")
	_apply(Game.course_time)
	_physics_apply(Game.course_time)


## Seconds into this piece's loop at `time`.
func cycle_at(time: float) -> float:
	return fposmod(time + phase * period, period)


func state_at(time: float) -> int:
	var u: float = cycle_at(time)
	if u < tell:
		return S.TELL
	if u < tell + fall:
		return S.FALL
	if u < tell + fall + hold:
		return S.HOLD
	if u < tell + fall + hold + clear:
		return S.CLEAR
	return S.GONE


## True while the cells are solid (settled and clearing).
func solid_at(time: float) -> bool:
	var s: int = state_at(time)
	return s == S.HOLD or s == S.CLEAR


## True when it stays solid over all of [time + a, time + b].
func solid_over(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not solid_at(time + s):
			return false
		s += 0.05
	return solid_at(time + b)


## True when nothing is falling or about to fall onto the spot over [time + a, time + b]
## (the tell is not a danger, so only the FALL state counts).
func no_fall_over(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if state_at(time + s) == S.FALL:
			return false
		s += 0.05
	return true


## World top-centre of cell i at rest.
func cell_top(i: int) -> Vector3:
	var c: Vector2 = cells[i]
	return _origin + Vector3(c.x * cell, thick * 0.5, c.y * cell)


func snap_to_clock() -> void:
	_apply(Game.course_time)
	_physics_apply(Game.course_time)
	reset_physics_interpolation()


func _physics_process(_dt: float) -> void:
	_physics_apply(Game.course_time)


func _physics_apply(t: float) -> void:
	var st: int = state_at(t)
	var u: float = cycle_at(t)
	var want_solid: bool = st == S.HOLD or st == S.CLEAR
	if want_solid != _solid:
		_solid = want_solid
		for cs: CollisionShape3D in _shapes:
			cs.set_deferred("disabled", not want_solid)
	# the falling cells are deadly (monitoring on while FALL, plus the landing tick)
	var fall_on: bool = st == S.FALL
	var h: float = 0.0
	if fall_on:
		var k: float = clampf((u - tell) / maxf(fall, 0.05), 0.0, 1.0)
		h = drop_h * (1.0 - k * k)
	position = _origin + Vector3(0, h, 0)
	for kz: Area3D in _kills:
		if kz.monitoring != fall_on:
			kz.set_deferred("monitoring", fall_on)


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var st: int = state_at(t)
	var u: float = cycle_at(t)
	var prev: int = _state
	_state = st
	_body.visible = st == S.FALL or st == S.HOLD or st == S.CLEAR
	_ghost.visible = st == S.TELL
	var show_col: bool = st == S.TELL or st == S.FALL
	_column.visible = show_col
	if st == S.TELL:
		var k: float = clampf(u / maxf(tell, 0.1), 0.0, 1.0)
		var rate: float = lerpf(4.0, 16.0, k)
		var blink: float = 0.5 + 0.5 * sin(t * rate * TAU)
		_ghost_mat.set_shader_parameter("pulse", lerpf(0.2, 1.0, k) * (0.4 + 0.6 * blink))
		var c: Color = _col_mat.albedo_color
		c.a = lerpf(0.04, 0.2, k) * (0.6 + 0.4 * blink)
		_col_mat.albedo_color = c
		# SOUND: arcade_block_tick - a rising pixel ticking while the ghost blinks (~1 s ahead)
		var tk: int = int(floor(t * rate))
		if tk != int(_beep):
			_beep = float(tk)
			if k < 0.98 and WorldAudio.once("arcade_block_tick_%d" % get_instance_id(), 0.12):
				WorldAudio.at(self, "arcade_block_tick", global_position, 0.45, 26.0)
	elif st == S.FALL:
		var c2: Color = _col_mat.albedo_color
		c2.a = 0.3
		_col_mat.albedo_color = c2
	if st == S.CLEAR:
		var k2: float = clampf((u - (tell + fall + hold)) / maxf(clear, 0.1), 0.0, 1.0)
		var rate2: float = lerpf(3.0, 14.0, k2)
		_mat.set_shader_parameter("flash", (0.5 + 0.5 * sin(t * rate2 * TAU)) * lerpf(0.3, 1.0, k2))
	else:
		_mat.set_shader_parameter("flash", 0.0)
	if prev != st and prev >= 0:
		if st == S.HOLD:
			# the thud, a ring of pixels and dust
			Fx.fire(_land_fx, _land_fx.global_position)
			Fx.fire(_land_ring, _land_ring.global_position)
			# SOUND: arcade_block_land - a dull 8-bit thud as the piece locks in
			WorldAudio.at(self, "arcade_block_land", global_position, 0.8, 38.0)
		elif st == S.CLEAR:
			# SOUND: arcade_block_clear_warn - a rising warble: this row is about to clear (~1 s ahead)
			WorldAudio.at(self, "arcade_block_clear_warn", global_position, 0.55, 28.0)
		elif st == S.GONE:
			_clear_fx.restart()
			_clear_fx.emitting = true
			# SOUND: arcade_block_clear - the row clears with a bright arpeggio
			WorldAudio.at(self, "arcade_block_clear", global_position, 0.7, 34.0)
		elif st == S.FALL:
			# SOUND: arcade_block_drop - a falling whistle
			WorldAudio.at(self, "arcade_block_drop", global_position, 0.5, 30.0)
