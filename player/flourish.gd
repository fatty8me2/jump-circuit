class_name Flourish
extends RefCounted
## Idle fidgets 4-7 (everyone) and the per-character idle flourish (fidget 8). Pure data and
## maths, like Emotes: PlayerVisual keeps the clock and blends a sampled Pose over the hands,
## feet, torso, hop, spin and eyes that animate() just set. The existing fidgets 0-3 stay in
## animate(). Visual only: nothing here touches physics.
##
## A flourish may also drive the body's secondary motion through the Pose extras: `sway` (more
## flapping on every tail, ear, plume, cape and the parrot), `ant_scale` / `ant_kick` / `flare`
## (the antenna: the wizard's orb, the bulb) and `prop` (the knight's sword, built on demand).

const HAND := Vector3(0.49, 0.43, 0.02)
const FOOT := Vector3(0.17, 0.09, 0.0)

## Fidget ids: 0-3 are animate()'s own (look around, flick the antenna, foot tap, stretch).
const FIRST_NEW: int = 4
const FLOURISH: int = 8
const COUNT: int = 9
const NAMES: Array[String] = ["look", "antenna", "tap", "stretch", "shadowbox", "shakeout", "bounce", "skygaze"]

## Seconds each new clip plays (the old fidgets run 1.7).
const LEN: Dictionary = {
	"shadowbox": 1.9, "shakeout": 1.8, "bounce": 1.7, "skygaze": 2.2,
	"power_up": 2.2, "glitch": 2.0, "shine": 2.4, "sword_twirl": 2.6, "crane": 2.6, "float": 2.8,
	"tail_wag": 2.4, "rattle": 2.0, "wash": 2.4, "quickdraw": 2.8, "orb_pulse": 2.6, "parrot": 2.6,
	"chest_pound": 2.6, "scratch": 2.4, "blocky_hop": 2.4,
}
## Each character's own flourish (fidget 8).
const OF_CHARACTER: Dictionary = {
	"volt": "power_up", "cyber": "glitch", "golden": "shine", "knight": "sword_twirl", "ninja": "crane",
	"astronaut": "float", "dino": "tail_wag", "skeleton": "rattle", "catbot": "wash", "outlaw": "quickdraw",
	"wizard": "orb_pulse", "pirate": "parrot", "yeti": "chest_pound", "robopup": "scratch", "pixel": "blocky_hop",
}
## Small particle puffs, as Emotes.PUFFS: clip -> [[time, type], ...] ("stars", "dust", "sparks").
const PUFFS: Dictionary = {
	"power_up": [[1.45, "sparks"]], "glitch": [[0.9, "sparks"]], "shine": [[0.9, "stars"], [1.7, "stars"]],
	"float": [[0.5, "stars"]], "rattle": [[0.3, "dust"]], "quickdraw": [[1.5, "sparks"]],
	"orb_pulse": [[1.0, "stars"], [2.0, "stars"]], "chest_pound": [[0.45, "dust"], [1.6, "dust"]],
	"blocky_hop": [[1.9, "stars"]], "bounce": [[0.9, "dust"]],
}
## Characters whose wide skirt would dig into the floor when the torso pitches or rolls.
const TILT_SCALE: Dictionary = {"wizard": 0.35}


## One sampled pose: Emotes.Frame plus the secondary-motion extras.
class Pose extends Emotes.Frame:
	var sway: float = 0.0               # extra flapping on every sway part, 0..1
	var ant_scale: float = 1.0          # antenna scale (the wizard's orb pulses)
	var ant_kick: Vector2 = Vector2.ZERO  # push on the antenna spring, rad/s per second
	var flare: float = 0.0              # bulb flare (0 = leave it alone)
	var prop_on: bool = false           # the knight's sword is out
	var prop_angle: float = 0.0         # its pitch about the hand

	func clear() -> void:
		reset()
		sway = 0.0
		ant_scale = 1.0
		ant_kick = Vector2.ZERO
		flare = 0.0
		prop_on = false
		prop_angle = 0.0


## The clip id fidget `fid` plays for `character` ("" for the old fidgets 0-3).
static func clip_for(fid: int, character: String) -> String:
	if fid >= FIRST_NEW and fid < FLOURISH:
		return NAMES[fid]
	if fid == FLOURISH:
		return String(OF_CHARACTER.get(character, "power_up"))
	return ""


## Seconds fidget `fid` lasts.
static func length(fid: int, character: String) -> float:
	if fid < FIRST_NEW:
		return 1.7
	return float(LEN.get(clip_for(fid, character), 2.0))


## Which fidget comes next: the original look / antenna / stretch / tap rotation, with the new
## ones and the character's flourish worked in. `n` counts fidgets so far; `r1` / `r2` are
## 0..1 hashes of it.
static func pick(n: int, r1: float, r2: float) -> int:
	const ROTATION: Array[int] = [0, 1, 8, 3, 4, 2, 5, 8, 6, 7]
	if r1 < 0.7:
		return ROTATION[n % ROTATION.size()]
	return clampi(int(r2 * float(COUNT)), 0, COUNT - 1)


## 0 -> 1 over the first 0.2 s, back to 0 over the last 0.3 s.
static func weight(t: float, len: float) -> float:
	return smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(len - 0.3, len, t))


static func _h(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898 + 78.233) * 43758.5453, 1.0)


static func _mir(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## Fills `f` with clip `id` at `t` seconds. Positions are in the spaces Emotes.Frame documents.
static func sample(f: Pose, id: String, t: float) -> void:
	f.clear()
	match id:
		"shadowbox":
			var s: float = sin(t * 8.0)
			f.hr = Vector3(0.3, 0.72, -0.5 * maxf(s, 0.0))
			f.hl = Vector3(-0.3, 0.72, -0.5 * maxf(-s, 0.0))
			f.fr = Vector3(0.2, 0.09, 0.08)
			f.fl = Vector3(-0.2, 0.09, -0.12)
			f.torso_rot = Vector3(-0.1, s * 0.3, 0.0)
			f.root_y = 0.025 * absf(s)
			f.eye = 0.8
		"shakeout":
			f.hr = Vector3(0.5 + sin(t * 29.0) * 0.06, 0.3 + cos(t * 26.0) * 0.05, 0.05 + sin(t * 22.0) * 0.04)
			f.hl = Vector3(-0.5 + sin(t * 27.0 + 1.0) * 0.06, 0.3 + cos(t * 24.0 + 1.0) * 0.05, 0.05 + sin(t * 21.0) * 0.04)
			f.fr = Vector3(0.17, 0.09 + maxf(sin(t * 9.0), 0.0) * 0.05, 0.0)
			f.fl = Vector3(-0.17, 0.09 + maxf(-sin(t * 9.0), 0.0) * 0.05, 0.0)
			f.torso_rot = Vector3(0.0, sin(t * 4.5) * 0.12, sin(t * 9.0) * 0.04)
			f.eye = 0.5
		"bounce":
			var h: float = absf(sin(t * 9.5)) * 0.1
			f.root_y = h
			f.hr = Vector3(0.2, 0.55 + h * 0.8, -0.25)
			f.hl = Vector3(-0.2, 0.55 + h * 0.8, -0.25)
			f.fr = Vector3(0.17, 0.09 + h * 1.4, 0.0)
			f.fl = Vector3(-0.17, 0.09 + h * 1.4, 0.0)
			f.eye = 0.45
		"skygaze":
			var lean: float = smoothstep(0.0, 0.5, t)
			f.torso_rot = Vector3(0.2 * lean, sin(t * 1.8) * 0.35, 0.0)
			f.hr = Vector3(0.22, 1.0, -0.28)
			f.hl = Vector3(-0.38, 0.4, 0.3)
			f.fl = Vector3(-0.19, 0.09, 0.0)
			f.fr = Vector3(0.19, 0.09, -0.04)
		"power_up":
			# hunch, shiver and glow, then burst
			var burst: float = smoothstep(1.3, 1.5, t)
			var pump: float = sin(t * 20.0)
			f.hr = Vector3(0.4, 0.5 + 0.04 * pump, 0.05).lerp(Vector3(0.58, 1.1, -0.04), burst)
			f.hl = Vector3(-0.4, 0.5 - 0.04 * pump, 0.05).lerp(Vector3(-0.58, 1.1, -0.04), burst)
			f.torso_y = lerpf(0.15, 0.24, burst)
			f.root_y = 0.012 * pump * (1.0 - burst)
			f.flare = 1.4 * (0.5 + 0.5 * sin(t * 9.0)) + burst
			f.fr = Vector3(0.22, 0.09, 0.0)
			f.fl = Vector3(-0.22, 0.09, 0.0)
			f.eye = lerpf(0.6, 1.2, burst)
		"glitch":
			var k: int = floori(t * 14.0)
			var jump: bool = _h(k + 50) > 0.45
			f.torso_rot = Vector3(0.0, (_h(k) - 0.5) * 0.9 if jump else 0.0, (_h(k + 4) - 0.5) * 0.1 if jump else 0.0)
			f.eye = 0.2 if _h(k + 9) > 0.6 else 1.0
			f.root_y = (_h(k + 2) - 0.3) * 0.03 if jump else 0.0
			f.hl = Vector3(-0.25, 0.7, -0.32)
			f.hr = Vector3(0.3, 0.62 + 0.06 * sin(t * 25.0), -0.3)
			f.ant_kick = Vector2(0.0, (_h(k + 7) - 0.5) * 120.0)
		"shine":
			var chest: float = smoothstep(0.0, 0.4, t)
			f.torso_rot = Vector3(0.12 * chest, 0.0, 0.0)
			f.hr = Vector3(0.15, 1.0 + 0.03 * sin(t * 6.0), -0.3)
			f.hl = Vector3(-0.42, 0.5, 0.1)
			f.eye = 0.45
			f.flare = 0.6
		"sword_twirl":
			# a three-turn twirl about the wrist, then a salute with the blade held upright
			var u: float = clampf(t / 1.5, 0.0, 1.0)
			var a: float = TAU * 3.0 * (u * u * (3.0 - 2.0 * u))
			var salute: float = smoothstep(1.5, 1.9, t)
			var twirl := Vector3(0.5 + 0.06 * cos(a), 0.8 + 0.1 * sin(a), -0.3)
			f.hr = twirl.lerp(Vector3(0.42, 0.95, -0.22), salute)
			f.hl = Vector3(-0.45, 0.45, 0.05)
			f.torso_rot = Vector3(0.0, 0.25, 0.0)
			f.prop_on = true
			f.prop_angle = a
		"crane":
			# balanced on one foot, arms wide, then reaching overhead
			var up: float = smoothstep(1.2, 1.7, t)
			var wob: float = sin(t * 9.0) * 0.015
			f.fr = Vector3(0.12, 0.45, -0.12)
			f.fl = Vector3(-0.12, 0.09, 0.0)
			f.hr = Vector3(0.72, 0.62 + 0.05 * sin(t * 3.0), 0.0).lerp(Vector3(0.3, 1.12, 0.0), up)
			f.hl = Vector3(-0.72, 0.62 + 0.05 * sin(t * 3.0 + 1.0), 0.0).lerp(Vector3(-0.3, 1.12, 0.0), up)
			f.torso_rot = Vector3(0.0, 0.0, 0.05 + wob)
			f.eye = 0.6
		"float":
			f.root_y = (0.12 + 0.03 * sin(t * 3.0)) * smoothstep(0.0, 0.5, t)
			f.spin = 0.5 * sin(t * 1.6)
			f.fl = Vector3(-0.2, 0.09 + 0.05 * sin(t * 2.7), 0.08)
			f.fr = Vector3(0.2, 0.09 + 0.05 * sin(t * 2.7 + 2.0), -0.1)
			f.hr = Vector3(0.62, 0.72 + 0.06 * sin(t * 2.2), 0.1)
			f.hl = Vector3(-0.62, 0.72 + 0.06 * sin(t * 2.2 + 1.5), 0.1)
			f.torso_rot = Vector3(sin(t * 1.7) * 0.1, 0.0, 0.0)
			f.ant_kick = Vector2(sin(t * 2.0), cos(t * 1.6)) * 14.0
		"tail_wag":
			var s2: float = sin(t * 7.0)
			f.sway = 1.0
			f.torso_rot = Vector3(0.0, 0.0, s2 * 0.1)
			f.root_y = 0.03 * absf(s2)
			f.hr = Vector3(0.3 + 0.03 * s2, 0.62, -0.22)
			f.hl = Vector3(-0.3 + 0.03 * s2, 0.62, -0.22)
			f.eye = 0.5
		"rattle":
			f.torso_rot = Vector3(0.0, sin(t * 31.0) * 0.05, sin(t * 38.0) * 0.06)
			f.hr = Vector3(0.12, 0.78 + sin(t * 30.0) * 0.03, -0.25)
			f.hl = Vector3(-0.12, 0.78 - sin(t * 30.0) * 0.03, -0.25)
			f.root_y = 0.012 * sin(t * 34.0)
			f.eye = 0.7
		"wash":
			var a2: float = t * 9.0
			f.sway = 0.8
			f.hr = Vector3(0.14 + 0.06 * cos(a2), 0.72 + 0.05 * sin(a2), -0.34)
			f.torso_rot = Vector3(-0.12, 0.0, 0.0)
			f.eye = 0.4
		"quickdraw":
			# spin the pistol, aim (a recoil), blow the smoke off the barrel
			var a3: float = t * 16.0
			var aim: float = smoothstep(1.35, 1.5, t)
			var blow: float = smoothstep(1.9, 2.2, t)
			var spin := Vector3(0.45 + 0.1 * cos(a3), 0.52 + 0.12 * sin(a3), -0.24)
			var hr: Vector3 = spin.lerp(Vector3(0.38, 0.74, -0.62), aim)
			hr = hr.lerp(Vector3(0.12, 0.9, -0.34), blow)
			var recoil: float = 0.25 * maxf(1.0 - (t - 1.5) * 6.0, 0.0) if t > 1.5 and t < 1.67 else 0.0
			f.hr = hr + Vector3(0.0, recoil * 0.3, recoil * 0.4)
			f.hl = Vector3(-0.4, 0.45, 0.0)
			f.torso_rot = Vector3(recoil * 0.4, -0.2 * aim * (1.0 - blow), 0.0)
			f.eye = 0.35 if aim > 0.5 and blow < 0.5 else 0.8
		"orb_pulse":
			var pulse: float = 0.5 - 0.5 * cos(t * 5.0)
			f.ant_scale = 1.0 + 0.8 * pulse
			f.hr = Vector3(0.55, 0.95 + 0.04 * sin(t * 4.0), -0.28)
			f.hl = Vector3(-0.55, 0.95 + 0.04 * sin(t * 4.0 + 1.0), -0.28)
			f.torso_rot = Vector3(0.05, 0.0, 0.0)
			f.ant_kick = Vector2(0.0, sin(t * 5.0) * 40.0)
			f.eye = 0.8
		"parrot":
			f.sway = 1.0
			f.hr = Vector3(0.36, 0.95, -0.02)
			f.torso_rot = Vector3(0.0, -0.3 * smoothstep(0.0, 0.4, t), 0.0)
			f.eye = 0.7
		"chest_pound":
			var lean2: float = smoothstep(0.0, 0.5, t) * (1.0 - smoothstep(0.5, 0.7, t))
			var s3: float = sin(t * 10.0)
			var beat: float = smoothstep(0.6, 0.8, t)
			var out_r := Vector3(0.55, 0.85, -0.1)
			var in_r := Vector3(0.14, 0.6, -0.45)
			f.hr = out_r.lerp(in_r, maxf(s3, 0.0) * beat)
			f.hl = _mir(out_r).lerp(_mir(in_r), maxf(-s3, 0.0) * beat)
			f.torso_rot = Vector3(0.2 * lean2, 0.0, 0.0)
			f.root_y = 0.02 * absf(s3) * beat
			f.sway = 0.5
			f.eye = 0.6
		"scratch":
			f.sway = 0.9
			f.fr = Vector3(0.3, 0.78 + 0.05 * sin(t * 32.0), -0.12)
			f.torso_rot = Vector3(0.0, 0.0, 0.12 * smoothstep(0.0, 0.3, t))
			f.ant_kick = Vector2(0.0, sin(t * 20.0) * 60.0)
			f.eye = 0.5
		"blocky_hop":
			# three hops in blocky steps, then the hero salute
			var hp: float = absf(sin(t * PI * 1.5)) if t < 1.9 else 0.0
			var step_h: float = floorf(hp * 0.3 / 0.05) * 0.05
			var hero: float = smoothstep(1.9, 2.1, t)
			f.root_y = step_h
			f.hr = Vector3(0.55, 0.8 + step_h, 0.0).lerp(Vector3(0.4, 1.0, -0.3), hero)
			f.hl = Vector3(-0.55, 0.8 + step_h, 0.0).lerp(Vector3(-0.45, 0.5, 0.0), hero)
			f.fr = Vector3(0.17, 0.09 + step_h * 0.6, 0.0)
			f.fl = Vector3(-0.17, 0.09 + step_h * 0.6, 0.0)
			f.sway = 0.8
			f.eye = 0.7
