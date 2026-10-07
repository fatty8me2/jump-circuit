class_name CpuSkill
extends RefCounted
## What Easy / Normal / Hard mean for a CPU racer, plus the pool of fun names. Every number a
## difficulty changes is in TABLE, so tuning the CPUs is a one-table job.
##   speed       run speed as a share of the player's top speed (jumps always take the time they
##               physically need - the share only slows the running between them)
##   react       seconds a CPU needs to notice a timed obstacle opened / a platform arrived
##   hesitate    extra random dither (s) before a jump or after a wait
##   jump_fail   chance a long jump is botched (it falls short and respawns like a human)
##   wait_fail   chance it mistimes a timed obstacle and gets caught (respawns)
##   pause       standing still after a respawn (s)
##   cut         takes corners (skips walk waypoints when the straight line is clear)
##   shove       chance to shove a rival it is level with (Hard: also seeks edges)
##   item_wait   seconds it holds a fresh item before it considers using it
##   greed       how eagerly it swerves for an item box (share of boxes it detours to)

const EASY: String = "easy"
const NORMAL: String = "normal"
const HARD: String = "hard"
const LEVELS: Array[String] = [EASY, NORMAL, HARD]

const TABLE: Dictionary = {
	"easy": {"label": "Easy", "speed": 0.62, "react": 0.55, "hesitate": 0.7, "jump_fail": 0.10, "wait_fail": 0.06,
		"pause": 1.4, "cut": false, "shove": 0.2, "item_wait": [3.5, 9.0], "greed": 0.5},
	"normal": {"label": "Normal", "speed": 0.8, "react": 0.28, "hesitate": 0.32, "jump_fail": 0.04, "wait_fail": 0.025,
		"pause": 0.9, "cut": false, "shove": 0.5, "item_wait": [2.0, 6.0], "greed": 0.8},
	"hard": {"label": "Hard", "speed": 0.94, "react": 0.1, "hesitate": 0.08, "jump_fail": 0.012, "wait_fail": 0.007,
		"pause": 0.5, "cut": true, "shove": 0.85, "item_wait": [0.8, 3.0], "greed": 1.0},
}

const NAMES: Array[String] = [
	"Bolt", "Pixel", "Turbo", "Zippy", "Nova", "Biscuit", "Comet", "Noodle", "Rocket", "Waffle", "Sprout", "Blitz",
	"Gizmo", "Pogo", "Mochi", "Dash", "Fizz", "Tango", "Pebble", "Ziggy", "Pudding", "Kiwi", "Jolt", "Maple",
	"Gadget", "Echo", "Sparky", "Bean", "Orbit", "Clover", "Taco", "Vortex",
]


static func valid(diff: String) -> bool:
	return TABLE.has(diff)


static func label(diff: String) -> String:
	return str((TABLE.get(diff, TABLE[NORMAL]) as Dictionary)["label"])


## A CPU's own numbers: the difficulty's, nudged so no two CPUs drive alike.
static func personal(diff: String, rng: RandomNumberGenerator) -> Dictionary:
	var p: Dictionary = (TABLE.get(diff, TABLE[NORMAL]) as Dictionary).duplicate(true)
	p["speed"] = float(p["speed"]) * rng.randf_range(0.94, 1.06)
	p["react"] = float(p["react"]) * rng.randf_range(0.8, 1.25)
	p["jump_fail"] = float(p["jump_fail"]) * rng.randf_range(0.6, 1.5)
	p["wait_fail"] = float(p["wait_fail"]) * rng.randf_range(0.6, 1.5)
	p["diff"] = diff
	return p
