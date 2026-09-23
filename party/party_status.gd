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
static func make(effect: String) -> Node3D:
	match effect:
		"freeze":
			return ice_block()
		"float":
			return float_bubble()
		"stun", "spin":
			return dizzy_stars()
		"slow":
			return storm_static()
	return null


static func ice_block() -> Node3D:
	var root := Node3D.new()
	var mat: StandardMaterial3D = PartyFx.solid_mat(Color(0.7, 0.93, 1.0, 0.5), 0.6, 0.05, 0.2)
	mat.rim_enabled = true
	mat.rim = 1.0
	var block: MeshInstance3D = PartyFx.part(root, PartyFx.box_mesh(Vector3(1.2, 1.7, 1.2)), mat, Vector3(0, 0.85, 0))
	block.rotation_degrees = Vector3(0, 12, 0)
	# frosty shards around the base
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		PartyFx.part(root, PartyFx.cone_mesh(0.12, 0.5, 5), mat, Vector3(cos(a) * 0.7, 0.2, sin(a) * 0.7), Vector3.ONE, Vector3(randf_range(-30, 30), 0, randf_range(-30, 30)))
	root.add_child(PartyFx.emitter({"amount": 14, "lifetime": 1.2, "size": 0.12, "color": Color(0.8, 0.97, 1.0),
		"shape": "box", "extents": Vector3(0.6, 0.85, 0.6), "vmin": 0.05, "vmax": 0.3, "dir": Vector3.DOWN,
		"spread": 40.0, "gravity": Vector3(0, -0.6, 0), "spark": true, "aabb": 2.0}))
	root.scale = Vector3.ONE * 0.2
	root.create_tween().tween_property(root, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


static func float_bubble() -> Node3D:
	var root := Node3D.new()
	var mat: StandardMaterial3D = PartyFx.solid_mat(Color(0.7, 0.45, 1.0, 0.28), 1.2, 0.05, 0.1)
	mat.rim_enabled = true
	mat.rim = 1.0
	mat.rim_tint = 0.8
	PartyFx.part(root, PartyFx.sphere_mesh(0.95, 24), mat, Vector3(0, 0.8, 0))
	root.add_child(PartyFx.emitter({"amount": 20, "lifetime": 1.0, "size": 0.16, "color": Color(0.75, 0.5, 1.0),
		"shape": "shell", "radius": 1.0, "vmin": 0.0, "vmax": 0.1, "tangential": 3.0, "aabb": 2.5,
		"local": true}))
	var e: GPUParticles3D = root.get_child(root.get_child_count() - 1) as GPUParticles3D
	e.position = Vector3(0, 0.8, 0)
	return root


static func dizzy_stars() -> Node3D:
	var root := Node3D.new()
	var e: GPUParticles3D = PartyFx.emitter({"amount": 10, "lifetime": 0.8, "size": 0.22, "color": Color(1.0, 0.95, 0.4),
		"shape": "ring", "radius": 0.45, "inner": 0.4, "vmin": 0.0, "vmax": 0.1, "tangential": 6.0, "spark": true,
		"local": true, "aabb": 1.5, "shrink": false, "colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	e.position = Vector3(0, 1.35, 0)
	root.add_child(e)
	return root


static func storm_static() -> Node3D:
	var root := Node3D.new()
	var e: GPUParticles3D = PartyFx.emitter({"amount": 18, "lifetime": 0.25, "size": 0.14, "color": Color(0.65, 0.75, 1.0),
		"shape": "sphere", "radius": 0.55, "vmin": 1.0, "vmax": 3.0, "spark": true, "aabb": 1.5})
	e.position = Vector3(0, 0.7, 0)
	root.add_child(e)
	return root
