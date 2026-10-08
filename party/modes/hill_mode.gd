class_name PartyModeHill
extends PartyMode
## King of the Hill: a glowing zone sits on a checkpoint lawn and moves on every STAY seconds, always to the
## lawn just ahead of the pack. Points (PTS_PER_SEC a second) go to the racer standing in it ALONE - two or more
## inside and nobody scores. Everything else (placement, KOs, bonuses) scores as usual, so the zone is the fight.
##
## The zone's first position is fixed (lawn 1), so every peer starts with the same one; after that the host picks
## the next lawn and says so in its 0.5 s "st" packets (zone, holder, everyone's points).

const RADIUS: float = 4.6
const HEIGHT: float = 3.0
const STAY: float = 20.0
const FIRST_MOVE: float = 14.0
const PTS_PER_SEC: float = 0.8
const SYNC_EVERY: float = 0.5

var zone_i: int = -1
var zone_pos: Vector3 = Vector3.ZERO
var holder: int = 0   # racer alone in the zone, -1 contested, 0 empty
var pts: Dictionary = {}
var next_move: float = FIRST_MOVE
var _seconds: Dictionary = {}
var _sync_t: float = 0.0
var _left: float = FIRST_MOVE
var _disc: MeshInstance3D
var _ring: MeshInstance3D
var _pillar: MeshInstance3D
var _glow: OmniLight3D
var _dust: GPUParticles3D
var _mats: Dictionary = {}
var _last_state: String = ""
var _ping_t: float = 0.0


func _init() -> void:
	id = "hill"


func _setup() -> void:
	_build_visuals()
	_set_zone(clampi(1, 0, layer.level.checkpoints.size()), false)


# ---- the zone ---------------------------------------------------------------------------------------

## World centre of a respawn lawn's zone (a little ahead of the checkpoint itself).
func lawn_center(index: int) -> Vector3:
	var pts_xf: Array[Transform3D] = layer.respawn_points()
	var xf: Transform3D = pts_xf[clampi(index, 0, pts_xf.size() - 1)]
	return xf.origin + (-xf.basis.z).normalized() * 2.2


func _set_zone(index: int, fx: bool) -> void:
	zone_i = index
	zone_pos = lawn_center(index)
	for n: Node3D in [_disc, _ring, _pillar, _glow, _dust]:
		if n != null:
			n.global_position = zone_pos + Vector3(0, 0.06 if n != _pillar else HEIGHT * 0.5, 0)
	if fx and is_inside_tree():
		PartyFx.ring_pulse(layer, zone_pos + Vector3(0, 0.2, 0), Vector3.UP, Color(1.0, 0.85, 0.3), 0.5, RADIUS * 1.2, 0.7, 0.3)
		PartyFx.burst(layer, zone_pos + Vector3(0, 1.0, 0), Color(1.0, 0.9, 0.4), 36, 5.0, 0.3, 0.9)
		layer.sfx.play_at("zone", zone_pos, 0.9)
		announce("The hill moved!", Color(1.0, 0.85, 0.3))


## Which lawn the zone goes to next: just ahead of the pack (its median checkpoint), never behind lawn 1.
func pick_next() -> int:
	return clampi(pack_checkpoint() + 1, 1, maxi(layer.level.checkpoints.size(), 1))


func contains(p: Vector3) -> bool:
	var d: Vector3 = p - zone_pos
	return Vector2(d.x, d.z).length() <= RADIUS and d.y > -1.5 and d.y < HEIGHT


## Racers inside the zone right now (their ghost / body positions).
func inside() -> Array[int]:
	var out: Array[int] = []
	for rid: int in active_ids():
		var p: Vector3 = layer.racer_pos(rid)
		if p != Vector3.INF and contains(p):
			out.append(rid)
	return out


# ---- host rules ----------------------------------------------------------------------------------------

func host_tick(dt: float) -> void:
	var in_zone: Array[int] = inside()
	holder = in_zone[0] if in_zone.size() == 1 else (-1 if in_zone.size() > 1 else 0)
	if holder > 0:
		_seconds[holder] = float(_seconds.get(holder, 0.0)) + dt * PTS_PER_SEC
		pts[holder] = int(_seconds[holder])
	var moved: bool = false
	if Game.course_time >= next_move:
		next_move = Game.course_time + STAY
		_set_zone(pick_next(), true)
		moved = true
	_left = maxf(next_move - Game.course_time, 0.0)
	_sync_t -= dt
	if _sync_t <= 0.0 or moved:
		_sync_t = SYNC_EVERY
		var list: Array = []
		for rid: Variant in pts:
			list.append([int(rid), int(pts[rid])])
		send({"m": "st", "i": zone_i, "h": holder, "p": list, "n": _left})


func on_message(_from_id: int, m: Dictionary) -> void:
	if str(m.get("m", "")) != "st":
		return
	var i: int = clampi(int(m.get("i", zone_i)), 0, layer.level.checkpoints.size())
	if i != zone_i:
		_set_zone(i, true)
	holder = int(m.get("h", 0))
	_left = float(m.get("n", _left))
	var raw: Variant = m.get("p", [])
	if typeof(raw) == TYPE_ARRAY:
		for e: Variant in raw:
			if typeof(e) == TYPE_ARRAY and (e as Array).size() >= 2:
				pts[int((e as Array)[0])] = int((e as Array)[1])


func mode_points() -> Dictionary:
	return pts.duplicate()


func state() -> Dictionary:
	return {"i": zone_i, "h": holder, "p": pts.duplicate()}


func round_note() -> String:
	var best: int = 0
	var best_pts: int = 0
	for rid: Variant in pts:
		if int(pts[rid]) > best_pts:
			best_pts = int(pts[rid])
			best = int(rid)
	return "" if best == 0 else "%s ruled the hill  (%d)" % [name_of(best), best_pts]


func points_label() -> String:
	return "Hill"


func hud_lines() -> Array[String]:
	var who: String = "empty"
	if holder > 0:
		who = "you" if holder == Net.my_id() else name_of(holder)
	elif holder < 0:
		who = "contested"
	var lines: Array[String] = ["KING OF THE HILL", "Zone: checkpoint %d lawn   (moves in %d)" % [zone_i, int(ceil(_left))],
		"Holder: %s" % who, "Your hill points: %d" % int(pts.get(Net.my_id(), 0))]
	return lines


func hud_color() -> Color:
	if holder == Net.my_id():
		return Color(0.4, 1.0, 0.5)
	return Color(1.0, 0.85, 0.3) if holder <= 0 else Color(1.0, 0.5, 0.35)


# ---- visuals (every peer) -----------------------------------------------------------------------------------

func _state_key() -> String:
	if holder == Net.my_id():
		return "mine"
	if holder > 0:
		return "theirs"
	return "contested" if holder < 0 else "empty"


func _color_for(key: String) -> Color:
	match key:
		"mine":
			return Color(0.35, 1.0, 0.5)
		"theirs":
			return Color(1.0, 0.4, 0.3)
		"contested":
			return Color(1.0, 0.6, 0.15)
	return Color(1.0, 0.85, 0.3)


func _build_visuals() -> void:
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = RADIUS
	disc_mesh.bottom_radius = RADIUS
	disc_mesh.height = 0.04
	disc_mesh.radial_segments = 48
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = RADIUS - 0.14
	ring_mesh.outer_radius = RADIUS + 0.04
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 8
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = RADIUS
	pillar_mesh.bottom_radius = RADIUS
	pillar_mesh.height = HEIGHT
	pillar_mesh.radial_segments = 40
	pillar_mesh.cap_top = false
	pillar_mesh.cap_bottom = false
	for key: String in ["empty", "mine", "theirs", "contested"]:
		var c: Color = _color_for(key)
		_mats[key] = [PartyFx.glow_mat(Color(c.r, c.g, c.b, 0.22), 1.1, true), PartyFx.glow_mat(Color(c.r, c.g, c.b, 1.0), 2.4, false),
			PartyFx.glow_mat(Color(c.r, c.g, c.b, 0.07), 1.4, true)]
	var m0: Array = _mats["empty"]
	_disc = PartyFx.part(self, disc_mesh, m0[0], Vector3.ZERO)
	_ring = PartyFx.part(self, ring_mesh, m0[1], Vector3.ZERO)
	_pillar = PartyFx.part(self, pillar_mesh, m0[2], Vector3.ZERO)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.85, 0.3)
	_glow.light_energy = 1.4
	_glow.omni_range = RADIUS * 2.2
	_glow.shadow_enabled = false
	add_child(_glow)
	_dust = PartyFx.emitter({"amount": 40, "lifetime": 1.6, "size": 0.2, "color": Color(1.0, 0.9, 0.5, 0.9), "shape": "ring",
		"radius": RADIUS, "inner": RADIUS * 0.4, "axis": Vector3.UP, "dir": Vector3.UP, "spread": 12.0, "vmin": 0.8, "vmax": 2.2,
		"colors": [Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)], "aabb": 8.0})
	add_child(_dust)


func tick(dt: float) -> void:
	var key: String = _state_key()
	if key != _last_state:
		_last_state = key
		var m: Array = _mats[key]
		_disc.material_override = m[0]
		_ring.material_override = m[1]
		_pillar.material_override = m[2]
		_glow.light_color = _color_for(key)
	_left = maxf(_left - dt, 0.0)
	var pulse: float = 1.0 + 0.02 * sin(clock * 3.0)
	_ring.scale = Vector3(pulse, 1.0, pulse)
	_glow.light_energy = 1.2 + 0.4 * sin(clock * 4.0)
	clock += dt
	if holder == Net.my_id():
		_ping_t -= dt
		if _ping_t <= 0.0:
			_ping_t = 1.0
			layer.sfx.play("tick", 0.35, 1.6)
