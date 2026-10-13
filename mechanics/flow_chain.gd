class_name FlowChain
extends Node
## Per-level chain counter for the flow kit (docs/FLOW_KIT.md). Speed rings and boost gates call
## register() when passed; passes less than WINDOW seconds apart build the chain, a longer gap
## starts it again at 1. Pure bookkeeping on the course clock: it never touches the player.
## The flow meter / HUD (workstream F3) listen to `passed` and `broken`, or read `count`.
##
## One per level: kit.flow_chain() makes it on first use (it lives under the kit's root) and hands
## the same node to every ring and gate. It forgets the chain when the player respawns.

## An unbroken chain needs the next ring or gate within this many seconds of the last.
const WINDOW: float = 1.5
## Chain count that no longer adds speed to rings (see bonus()).
const BONUS_AT: int = 8

## A ring or gate was passed: `count` is the chain after this pass, `speed` the rider's speed
## after the boost, `source` the ring / gate node.
signal passed(count: int, speed: float, source: Node)
## The chain ran out (or the player respawned) at `final_count`.
signal broken(final_count: int)

var count: int = 0
var best: int = 0
## Rings and gates passed since the level started (never reset by a break).
var total: int = 0
var _last: float = -1000.0


func _ready() -> void:
	add_to_group("flow_chain")
	add_to_group("resettable")
	var lvl: Node = _level()
	if lvl != null and lvl.has_signal("player_respawned"):
		lvl.connect("player_respawned", reset_state)


func _level() -> Node:
	var n: Node = get_parent()
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	return n


## The chain for a node in a level (the first one found under the same level, else a new one
## under the level / scene root). Rings made by the kit are handed theirs directly.
static func of(node: Node) -> FlowChain:
	var tree: SceneTree = node.get_tree()
	var root: Node = node
	while root.get_parent() != null and not root.has_method("fail") and root.get_parent() != tree.root:
		root = root.get_parent()
	for c: Node in root.get_children():
		if c is FlowChain:
			return c as FlowChain
	var fc := FlowChain.new()
	fc.name = "FlowChain"
	root.add_child(fc)
	return fc


## Speed multiplier a chain of `c` gives a ring: 1.0 for a lone ring, +12% per ring, to +84%.
static func bonus(c: int) -> float:
	return 1.0 + 0.12 * float(clampi(c, 1, BONUS_AT) - 1)


## True while the chain is alive (the next ring or gate within WINDOW still extends it).
func is_live() -> bool:
	return count > 0 and Game.course_time >= _last and Game.course_time - _last <= WINDOW


## Seconds left to reach the next ring before the chain breaks (0 when dead).
func time_left() -> float:
	return maxf(WINDOW - (Game.course_time - _last), 0.0) if is_live() else 0.0


## Count a pass now; returns the chain after it.
func register(source: Node = null) -> int:
	var t: float = Game.course_time
	if count > 0 and (t < _last or t - _last > WINDOW):
		broken.emit(count)
		count = 0
	count += 1
	total += 1
	best = maxi(best, count)
	_last = t
	return count


## Tell listeners the pass finished (called with the rider's speed after the boost).
func announce(source: Node, speed: float) -> void:
	passed.emit(count, speed, source)


func reset_state() -> void:
	if count > 0:
		broken.emit(count)
	count = 0
	_last = -1000.0


func _physics_process(_dt: float) -> void:
	if count > 0 and not is_live():
		var c: int = count
		count = 0
		broken.emit(c)
