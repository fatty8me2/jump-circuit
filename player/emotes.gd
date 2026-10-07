class_name Emotes
extends RefCounted
## Procedural emotes (D-pad / keys 1-4) and victory poses (the finish, the party podium).
## Pure data + maths: PlayerVisual keeps the clock and blends a sampled Frame over its own
## animation (hands, feet, torso, hop, spin, eyes). Nothing here touches physics.
##
## A clip is `sample(frame, kind, id, t)`: the frame holds target positions in the same
## local spaces PlayerVisual.animate uses (hands / feet relative to the rig, torso relative
## to the root; -z is forward). `length` is its duration; `weight` is the blend envelope.

const HAND := Vector3(0.49, 0.43, 0.02)   # right mitt at rest (the left mirrors x)
const FOOT := Vector3(0.17, 0.09, 0.0)    # right foot at rest
const TORSO_Y: float = 0.2

## Seconds each clip plays. Emotes run once; poses run once at the finish and hold on the podium.
const EMOTE_LEN: Dictionary = {
	"wave": 2.2, "thumbsup": 1.8, "dance": 3.0, "bow": 2.0, "laugh": 2.2,
	"flex": 2.4, "spin": 1.1, "facepalm": 2.4, "taunt": 2.4, "sit": 3.6,
}
const POSE_LEN: Dictionary = {
	"cheer": 3.4, "strongman": 3.4, "salute": 3.4, "hero": 3.4, "dab": 3.4, "rockstar": 3.4,
}
## Small particle puffs: id -> [[time, type], ...]; type is "stars", "dust" or "sparks".
const PUFFS: Dictionary = {
	"thumbsup": [[0.35, "stars"]], "dance": [[1.0, "stars"]], "flex": [[0.5, "stars"]],
	"spin": [[0.02, "dust"], [0.95, "dust"]], "sit": [[0.25, "dust"]],
	"strongman": [[0.5, "stars"]], "hero": [[0.45, "stars"]], "rockstar": [[0.3, "sparks"], [1.4, "sparks"]],
}


## One sampled pose: where everything should be right now.
class Frame:
	var hr: Vector3
	var hl: Vector3
	var fr: Vector3
	var fl: Vector3
	var torso_y: float = TORSO_Y
	var torso_rot: Vector3 = Vector3.ZERO   # pitch (-x leans forward), yaw, roll
	var root_y: float = 0.0                 # the whole body hops (visual only)
	var spin: float = 0.0                   # extra yaw of the body, radians
	var eye: float = 1.0                    # eye height factor (1 open, 0.4 happy arcs, 0.1 shut)

	func reset() -> void:
		hr = HAND
		hl = Vector3(-HAND.x, HAND.y, HAND.z)
		fr = FOOT
		fl = Vector3(-FOOT.x, FOOT.y, FOOT.z)
		torso_y = TORSO_Y
		torso_rot = Vector3.ZERO
		root_y = 0.0
		spin = 0.0
		eye = 1.0

	## Sets the left mitt to the mirror of `v` (the right one).
	func mirror_hand(v: Vector3) -> void:
		hl = Vector3(-v.x, v.y, v.z)


static func kinds() -> Array[String]:
	return ["emote", "pose"]


static func length(kind: String, id: String) -> float:
	var table: Dictionary = POSE_LEN if kind == "pose" else EMOTE_LEN
	return float(table.get(id, 0.0))


static func has_clip(kind: String, id: String) -> bool:
	return length(kind, id) > 0.0


## Blend 0..1: a quick attack, then (unless held) a soft release over the last 0.3 s.
static func weight(t: float, total: float, hold: bool = false) -> float:
	if t < 0.0:
		return 0.0
	var a: float = smoothstep(0.0, 1.0, clampf(t / 0.18, 0.0, 1.0))
	var r: float = 1.0 if hold else smoothstep(0.0, 1.0, clampf((total - t) / 0.3, 0.0, 1.0))
	return a * r


## Fills `f` for clip `id` of `kind` ("emote" | "pose") at `t` seconds in.
static func sample(f: Frame, kind: String, id: String, t: float) -> void:
	f.reset()
	if kind == "pose":
		_pose(f, id, t)
	else:
		_emote(f, id, t)


static func _emote(f: Frame, id: String, t: float) -> void:
	var total: float = length("emote", id)
	var p: float = clampf(t / maxf(total, 0.01), 0.0, 1.0)
	match id:
		"wave":
			f.hr = Vector3(0.6 + 0.12 * sin(t * 13.0), 1.08 + 0.03 * sin(t * 6.0), 0.0)
			f.torso_rot.z = -0.05
			f.eye = 0.55
		"thumbsup":
			var k: float = 0.5 + 0.5 * sin(t * 9.0)
			f.hr = Vector3(0.42, 0.78 + 0.06 * k, -0.5)
			f.hl = Vector3(-0.36, 0.5, 0.14)
			f.torso_rot.x = 0.12
			f.torso_y -= 0.02 * k
			f.eye = 0.45
		"dance":
			var b: float = sin(t * 8.0)
			f.hr = Vector3(0.55, 0.95 + 0.25 * b, 0.0)
			f.hl = Vector3(-0.55, 0.95 - 0.25 * b, 0.0)
			f.fl.y += maxf(b, 0.0) * 0.12
			f.fr.y += maxf(-b, 0.0) * 0.12
			f.torso_y += 0.04 * absf(b)
			f.torso_rot.y = 0.4 * sin(t * 4.0)
			f.torso_rot.z = 0.1 * sin(t * 4.0 + 1.2)
			f.eye = 0.5
		"bow":
			var k: float = clampf(sin(PI * p) * 1.7, 0.0, 1.0)
			f.torso_rot.x = -0.85 * k
			f.torso_y -= 0.02 * k
			f.hr = HAND.lerp(Vector3(0.12, 0.5, -0.3), k)
			f.hl = Vector3(-HAND.x, HAND.y, HAND.z).lerp(Vector3(-0.3, 0.4, 0.32), k)   # the left mitt behind the back
			f.eye = 1.0 - 0.6 * k
		"laugh":
			var s: float = sin(t * 28.0)
			f.torso_rot.x = 0.25 + 0.04 * s
			f.torso_y += 0.015 * s - 0.02
			f.hr = Vector3(0.28, 0.42 + 0.02 * s, -0.26)
			f.mirror_hand(f.hr)
			f.eye = 0.35
		"flex":
			var k: float = smoothstep(0.0, 1.0, clampf(t / 0.4, 0.0, 1.0))
			var pulse: float = 0.5 + 0.5 * sin(t * 10.0)
			f.hr = HAND.lerp(Vector3(0.58, 0.78 + 0.03 * pulse, -0.02), k)
			f.mirror_hand(f.hr)
			f.fl.x -= 0.09 * k
			f.fr.x += 0.09 * k
			f.torso_y += 0.03 * pulse * k
			f.eye = 0.5
		"spin":
			var e: float = p * p * (3.0 - 2.0 * p)
			var air: float = sin(PI * p)
			f.spin = TAU * 2.0 * e
			f.root_y = 0.18 * air
			f.hr = Vector3(0.7, 0.6, 0.0)
			f.mirror_hand(f.hr)
			f.fl.y += 0.1 * air
			f.fr.y += 0.1 * air
			f.eye = 0.6
		"facepalm":
			var k: float = smoothstep(0.0, 1.0, clampf(t / 0.35, 0.0, 1.0))
			f.hr = HAND.lerp(Vector3(0.08, 0.84, -0.4), k)
			f.torso_rot.x = -0.28 * k
			f.torso_rot.z = sin(t * 5.0) * 0.03 * k
			f.torso_y -= 0.02 * k
			f.eye = 1.0 - 0.85 * k
		"taunt":
			var k: float = smoothstep(0.0, 1.0, clampf(t / 0.3, 0.0, 1.0))
			var curl: float = sin(t * 10.0)
			f.hr = HAND.lerp(Vector3(0.42, 0.62 + 0.12 * curl, -0.46), k)
			f.hl = Vector3(-HAND.x, HAND.y, HAND.z).lerp(Vector3(-0.4, 0.5, 0.1), k)
			f.torso_rot.x = 0.15 * k
			f.torso_rot.z = 0.08 * sin(t * 3.0) * k
			f.fl.x -= 0.05 * k
			f.eye = 0.6
		"sit":
			var k: float = smoothstep(0.0, 1.0, clampf(t / 0.45, 0.0, 1.0))
			f.torso_y = TORSO_Y - 0.1 * k + 0.008 * sin(t * 2.3) * k
			f.torso_rot.x = 0.1 * k
			f.fl = f.fl.lerp(Vector3(-0.17, 0.09, -0.34), k)
			f.fr = f.fr.lerp(Vector3(0.17, 0.09, -0.34), k)
			f.hr = HAND.lerp(Vector3(0.46, 0.17, 0.1), k)
			f.mirror_hand(f.hr)


static func _pose(f: Frame, id: String, t: float) -> void:
	match id:
		"cheer":
			f.hr = Vector3(0.66 + sin(t * 11.0) * 0.08, 1.06 + cos(t * 11.0) * 0.1, -0.06)
			f.hl = Vector3(-0.66 + sin(t * 11.0 + 1.6) * 0.08, 1.06 + cos(t * 11.0 + 1.6) * 0.1, -0.06)
			var ph: float = fposmod(t / 0.52, 1.0)
			f.root_y = 4.0 * ph * (1.0 - ph) * 0.26
			f.fl.y += 0.1 * clampf(f.root_y / 0.2, 0.0, 1.0)
			f.fr.y += 0.1 * clampf(f.root_y / 0.2, 0.0, 1.0)
			f.eye = 0.4
		"strongman":
			var pulse: float = 0.5 + 0.5 * sin(t * 6.0)
			f.hr = Vector3(0.74, 0.78 + 0.04 * pulse, 0.0)
			f.mirror_hand(f.hr)
			f.fl.x -= 0.1
			f.fr.x += 0.1
			f.torso_y += 0.03 + 0.015 * pulse
			f.torso_rot.x = 0.08
			f.eye = 0.5
		"salute":
			f.hr = Vector3(0.17, 1.0, -0.2)
			f.fl.x += 0.07
			f.fr.x -= 0.07
			f.torso_rot.x = 0.08
			f.torso_y += 0.01 * sin(t * 2.3)
			f.eye = 0.9
		"hero":
			f.hr = Vector3(0.5, 1.28 + 0.02 * sin(t * 2.0), -0.05)
			f.hl = Vector3(-0.38, 0.5, 0.12)
			f.fl.x -= 0.1
			f.fr.x += 0.1
			f.torso_rot.x = 0.14
			f.torso_rot.z = 0.05 * sin(t * 2.0)
			f.eye = 0.7
		"dab":
			f.hr = Vector3(0.06, 0.93, -0.36)
			f.hl = Vector3(-0.82, 1.06, -0.02)
			f.torso_rot = Vector3(-0.3, 0.0, -0.12)
			f.torso_y -= 0.02
			f.eye = 0.15
		"rockstar":
			var strum: float = sin(t * 16.0)
			f.hl = Vector3(-0.2, 0.62, -0.42)
			f.hr = Vector3(0.3, 0.45 + 0.1 * strum, -0.2)
			f.torso_rot.x = -0.18 + 0.12 * sin(t * 7.0)
			f.torso_y -= 0.04
			f.root_y = 0.03 * absf(sin(t * 7.0))
			f.fl.x -= 0.1
			f.fr.x += 0.1
			f.fr.z -= 0.1
			f.eye = 0.4
