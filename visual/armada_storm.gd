class_name ArmadaStorm
extends Node3D
## Storm Armada: the thunderstorm round the fleet (visual and sound only). Forked bolts crack down
## out of the storm deck into the cloud sea all round the course on the course clock (a hash of the
## time slot, so every racer sees the same storm); each lights the cloud sea from inside, flashes the
## gas envelopes, throws a burst of cold light over the fleet, and its thunder rolls in a moment
## later from the right direction. `intensity` (0..1, set by the level) thins the storm out as the
## sunset breaks through. The lightning rods on the course report their strikes here too.

## Horizontal centre and radius band the bolts land in, and the heights they fall between.
var center: Vector3 = Vector3.ZERO
var r_min: float = 120.0
var r_max: float = 420.0
var top_y: float = 140.0
var bottom_y: float = -60.0
var intensity: float = 1.0
var cloud_mat: ShaderMaterial
var balloon_mats: Array[ShaderMaterial] = []

const SLOT: float = 0.45

var _bolts: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _on: int = -1
var _until: float = 0.0
var _last_slot: int = -1
var _flash: float = 0.0
var _thunder: Array[Dictionary] = []   # {"at": time, "pos": Vector3, "vol": float}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7331
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(2.0, 2.3, 3.6, 1.0)
	mat.disable_fog = true
	mat.disable_receive_shadows = true
	for i: int in 6:
		var mi := MeshInstance3D.new()
		mi.mesh = ArmadaLightning.bolt_mesh(top_y - bottom_y, 13, 1.4, 900 + i * 37)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 400.0
		mi.visible = false
		add_child(mi)
		_bolts.append(mi)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.72, 0.8, 1.0)
	_light.omni_range = 650.0
	_light.omni_attenuation = 0.7
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	_light.visible = false
	add_child(_light)


static func _hash(x: float, k: float) -> float:
	return fposmod(sin(x * k) * 43758.5453, 1.0)


func _process(dt: float) -> void:
	var t: float = Game.course_time
	var slot: int = int(floor(t / SLOT))
	if slot != _last_slot:
		_last_slot = slot
		if _hash(float(slot), 12.9898) < 0.07 + 0.13 * intensity:
			_strike(slot, t)
	var fl: float = 0.0
	if _on >= 0:
		var left: float = _until - t
		if left <= 0.0 or left > 1.0:
			_bolts[_on].visible = false
			_on = -1
		else:
			var lit: bool = fposmod(left * 19.0, 1.0) > 0.3
			_bolts[_on].visible = lit
			fl = (1.0 if lit else 0.35) * clampf(left / 0.3, 0.0, 1.0)
	_flash = maxf(fl, _flash - dt * 4.0)
	_light.visible = _flash > 0.01
	_light.light_energy = _flash * 3.5
	if cloud_mat != null:
		cloud_mat.set_shader_parameter("flash", _flash)
	for m: ShaderMaterial in balloon_mats:
		m.set_shader_parameter("flash", _flash * 0.8)
	# thunder rolls in after the flash, later the further away it struck
	var i: int = 0
	while i < _thunder.size():
		var th: Dictionary = _thunder[i]
		if t >= float(th["at"]) or t < float(th["at"]) - 10.0:
			var l: Vector3 = WorldAudio.listener(self)
			if l != Vector3.INF:
				var dir: Vector3 = (th["pos"] as Vector3) - l
				dir.y = 0.0
				var p: Vector3 = l + (dir.normalized() * 12.0 if dir.length() > 0.1 else Vector3.ZERO)
				# the ambience's thunder takes (3 variants); a far strike is quieter (its volume falls with distance)
				WorldAudio.at(self, "amb_armada_thunder", p, float(th["vol"]), 60.0, 0.12)
			_thunder.remove_at(i)
		else:
			i += 1


func _strike(slot: int, t: float) -> void:
	var h1: float = _hash(float(slot), 78.233)
	var h2: float = _hash(float(slot), 39.346)
	var h3: float = _hash(float(slot), 7.13)
	if _on >= 0:
		_bolts[_on].visible = false
	_on = int(h1 * float(_bolts.size())) % _bolts.size()
	var a: float = h2 * TAU
	var r: float = lerpf(r_min, r_max, h3)
	var ground := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
	var b: MeshInstance3D = _bolts[_on]
	b.position = Vector3(ground.x, top_y, ground.z)
	b.rotation.y = h1 * TAU
	b.visible = true
	_until = t + 0.3
	_light.position = Vector3(ground.x, (top_y + bottom_y) * 0.5 + 20.0, ground.z)
	if cloud_mat != null:
		cloud_mat.set_shader_parameter("flash_pos", Vector3(ground.x, bottom_y, ground.z))
	var l: Vector3 = WorldAudio.listener(self)
	var dist: float = 200.0 if l == Vector3.INF else Vector2(ground.x - l.x, ground.z - l.z).length()
	_thunder.append({"at": t + clampf(dist / 340.0, 0.2, 2.5), "pos": ground, "vol": clampf(1.4 - dist / 400.0, 0.4, 1.0)})


## A lightning rod on the course was struck at `pos`: flash the fleet (the rod plays its own crack).
func local_flash(pos: Vector3) -> void:
	_flash = maxf(_flash, 0.75)
	_light.position = pos + Vector3(0, 30.0, 0)
	if cloud_mat != null:
		cloud_mat.set_shader_parameter("flash_pos", pos)
