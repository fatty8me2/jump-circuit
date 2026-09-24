class_name PartyStatus
extends RefCounted
## Status effects a hit can leave on a racer, and the visuals that show them on every screen
## (the victim applies the effect to its own Player and broadcasts it; ghosts get the look).
##   stun    - dizzy stars, input ignored
##   slow    - storm static, speed x0.6
##   freeze  - encased in an ice block, held in place
##   float   - trapped in a gravity bubble, drifting up helplessly
##   shrink  - tiny: slower, weak jumps, knocked further
##   spin    - spun out (slick puddle): stars + a spin

## effect -> (speed, jump, gravity) multipliers on the victim's Player.
const MODS: Dictionary = {
	"slow": Vector3(0.6, 0.85, 1.0),
	"freeze": Vector3(0.0, 0.0, 0.0),
	"float": Vector3(0.3, 0.0, 0.06),
	"shrink": Vector3(0.75, 0.75, 1.0),
}
## Effects that also stun (input off) for their whole duration.
const STUNNING: Array[String] = ["stun", "freeze", "float", "spin"]


static func mods(effect: String) -> Vector3:
	return MODS.get(effect, Vector3.ONE)


## Visual for an effect, to parent under the racer's root (feet at the origin). null = none.
## Each is a self-animating PartyStatusFx (see party_status_fx.gd).
static func make(effect: String) -> Node3D:
	match effect:
		"freeze", "float", "stun", "spin", "slow", "shrink":
			return PartyStatusFx.create(effect)
	return null


## Tells a status visual how long it has left (it warns in its last moments).
static func feed(v: Variant, seconds_left: float) -> void:
	if v is PartyStatusFx and is_instance_valid(v):
		(v as PartyStatusFx).left = seconds_left


## Removes a status visual with its end effect (the ice shatters, the bubble pops...).
static func retire(v: Variant) -> void:
	if v == null or not is_instance_valid(v):
		return
	if v is PartyStatusFx:
		(v as PartyStatusFx).retire()
	else:
		(v as Node).queue_free()


static func ice_block() -> Node3D:
	return PartyStatusFx.create("freeze")


static func float_bubble() -> Node3D:
	return PartyStatusFx.create("float")


static func dizzy_stars() -> Node3D:
	return PartyStatusFx.create("stun")


static func storm_static() -> Node3D:
	return PartyStatusFx.create("slow")
