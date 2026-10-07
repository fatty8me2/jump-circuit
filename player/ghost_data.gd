class_name GhostData
extends RefCounted
## One recorded solo run (the personal-best ghost): the player's pose sampled at HZ.
##
## File: user://ghosts/<level_id>.ghost
##   header  "JCGH" | u8 version | u8 hz | u16 layout rev | u32 samples | f32 finish time
##           | u32 raw body size | u8 id length | id bytes
##   body    zstd-compressed, 15 bytes per sample: f32 x, f32 y, f32 z, u16 yaw, u8 flags
## A ghost recorded on another layout rev (SaveData.LAYOUT_REV), another version or with
## a damaged body is rejected on load, so a rebuilt course never replays a stale run.

const MAGIC: String = "JCGH"
const VERSION: int = 1
const HZ: int = 15
## Longest recording kept (20 minutes): beyond this a run is not recorded at all.
const MAX_SAMPLES: int = HZ * 1200
const BYTES_PER_SAMPLE: int = 15
const F_GROUNDED: int = 1
const F_WALL: int = 2
## The pose jumped here (a respawn or restart): playback must not slide across the gap.
const F_SNAP: int = 4

var level_id: String = ""
var rev: int = 1
## Finish time of the recorded run (seconds on the course clock).
var time: float = 0.0
var pos: PackedVector3Array = PackedVector3Array()
## Radians, atan2(-dir.x, -dir.z) as PlayerVisual uses (quantised to 16 bits on disk).
var yaw: PackedFloat32Array = PackedFloat32Array()
var flags: PackedByteArray = PackedByteArray()


static func dir() -> String:
	# tests run with a private save: their ghosts go beside it, never into the real folder
	if SaveData.path_override == "":
		return "user://ghosts"
	return SaveData.path_override.get_basename() + "_ghosts"


static func path_for(id: String) -> String:
	return "%s/%s.ghost" % [dir(), id]


static func current_rev(id: String) -> int:
	return int(SaveData.LAYOUT_REV.get(id, 1))


## Removes every ghost file in the active folder (and the folder).
static func delete_all() -> void:
	var d: String = dir()
	if not DirAccess.dir_exists_absolute(d):
		return
	for f: String in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(d + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(d))


func size() -> int:
	return pos.size()


## Time of the last sample.
func duration() -> float:
	return float(maxi(pos.size() - 1, 0)) / float(HZ)


## `moves` = MoveFlags the player showed (the wall bit is stored as F_WALL; the side, mantle,
## kick and knock bits ride the spare high bits, which an older ghost simply has clear).
func add(p: Vector3, facing_yaw: float, grounded: bool, wall: bool, snap: bool, moves: int = 0) -> void:
	pos.append(p)
	yaw.append(facing_yaw)
	var f: int = (F_GROUNDED if grounded else 0) | (F_WALL if wall else 0) | (F_SNAP if snap else 0)
	f |= (MoveFlags.clean(moves) & 0x1E) << 2
	flags.append(f)


static func yaw_of(dir_vec: Vector3) -> float:
	return atan2(-dir_vec.x, -dir_vec.z)


static func facing_of(y: float) -> Vector3:
	return Vector3(-sin(y), 0.0, -cos(y))


func encode() -> PackedByteArray:
	var body := StreamPeerBuffer.new()
	for i: int in pos.size():
		body.put_float(pos[i].x)
		body.put_float(pos[i].y)
		body.put_float(pos[i].z)
		body.put_u16(posmod(roundi(yaw[i] / TAU * 65536.0), 65536))
		body.put_u8(flags[i])
	var raw: PackedByteArray = body.data_array
	var out := StreamPeerBuffer.new()
	out.put_data(MAGIC.to_ascii_buffer())
	out.put_u8(VERSION)
	out.put_u8(HZ)
	out.put_u16(rev)
	out.put_u32(pos.size())
	out.put_float(time)
	out.put_u32(raw.size())
	var idb: PackedByteArray = level_id.to_utf8_buffer().slice(0, 255)
	out.put_u8(idb.size())
	out.put_data(idb)
	out.put_data(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out.data_array


## Null for anything that is not a valid ghost of `want_id` on the current layout rev.
static func decode(bytes: PackedByteArray, want_id: String) -> GhostData:
	if bytes.size() < 22 or bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return null
	var sp := StreamPeerBuffer.new()
	sp.data_array = bytes
	sp.seek(4)
	var version: int = sp.get_u8()
	var hz: int = sp.get_u8()
	var g_rev: int = sp.get_u16()
	var count: int = sp.get_u32()
	var t: float = sp.get_float()
	var raw_size: int = sp.get_u32()
	var id_len: int = sp.get_u8()
	if version != VERSION or hz != HZ or g_rev != current_rev(want_id):
		return null
	if count < 2 or count > MAX_SAMPLES or raw_size != count * BYTES_PER_SAMPLE or not is_finite(t) or t <= 0.0:
		return null
	var at: int = sp.get_position()
	if at + id_len >= bytes.size():
		return null
	if bytes.slice(at, at + id_len).get_string_from_utf8() != want_id:
		return null
	var raw: PackedByteArray = bytes.slice(at + id_len).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		return null
	var g := GhostData.new()
	g.level_id = want_id
	g.rev = g_rev
	g.time = t
	var rd := StreamPeerBuffer.new()
	rd.data_array = raw
	for i: int in count:
		var p := Vector3(rd.get_float(), rd.get_float(), rd.get_float())
		var y: float = float(rd.get_u16()) / 65536.0 * TAU
		var f: int = rd.get_u8()
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return null
		g.pos.append(p)
		g.yaw.append(y)
		g.flags.append(f)
	return g


func save() -> bool:
	var d: String = dir()
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	var p: String = path_for(level_id)
	var tmp: String = p + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(encode())
	var ok: bool = f.get_error() == OK
	f.close()
	if not ok:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(p)) == OK


## The saved ghost of `id`, or null (none, damaged, other version or older layout rev;
## a stale or damaged file is deleted).
static func load_for(id: String) -> GhostData:
	var p: String = path_for(id)
	if not FileAccess.file_exists(p):
		return null
	var g: GhostData = decode(FileAccess.get_file_as_bytes(p), id)
	if g == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	return g


## Pose at course time `t` (clamped to the recording): {"pos", "vel", "yaw", "grounded",
## "wall", "snap", "ended"}. `snap` is true on the sample where the pose jumped.
func sample(t: float) -> Dictionary:
	var n: int = pos.size()
	var ft: float = clampf(t, 0.0, duration()) * float(HZ)
	var i: int = mini(floori(ft), n - 1)
	var j: int = mini(i + 1, n - 1)
	var k: float = ft - float(i)
	var jump: bool = j != i and (flags[j] & F_SNAP) != 0
	var a: Vector3 = pos[i]
	var b: Vector3 = pos[j]
	var p: Vector3 = a if jump else a.lerp(b, k)
	var vel: Vector3 = Vector3.ZERO if (jump or i == j) else (b - a) * float(HZ)
	return {"pos": p, "vel": vel, "yaw": lerp_angle(yaw[i], yaw[j], 0.0 if jump else k),
		"grounded": (flags[i] & F_GROUNDED) != 0, "wall": (flags[i] & F_WALL) != 0,
		"snap": (flags[i] & F_SNAP) != 0, "ended": t >= duration(), "moves": moves_at(i)}


## The MoveFlags of sample `i` (0 for a ghost recorded before moves were kept).
func moves_at(i: int) -> int:
	var f: int = flags[i]
	var m: int = (f >> 2) & 0x1E
	if f & F_WALL != 0:
		m |= MoveFlags.WALL
	return MoveFlags.clean(m)
