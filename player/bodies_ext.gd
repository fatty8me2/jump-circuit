class_name BodiesExt
extends RefCounted
## Characters added in the v2.0 update. PlayerVisual._build_body() calls build() for any id it
## doesn't know; return true when the id was built here. A body must provide every standard
## part the built-in bodies do (body, belt, pack, eyes, antenna / bulb, feet, hands, head anchor
## position via HEADS) - use v._stub(...) for parts it doesn't have. See _body_knight() etc. in
## player/player_visual.gd for the pattern.
##
## Wizard, Pirate, Yeti, Robo-Pup and Pixel Hero. Every body keeps the top of _body clean for
## hats: anything that would poke through a covering hat is registered in v._crown_parts, and
## everything that droops (beards, ears, fur, capes) hangs on a Sway pivot.

## Hat mount per character: [crown position (feet-relative), hat scale], like PlayerVisual.HEADS.
const HEADS: Dictionary = {
	"wizard": [Vector3(0, 1.045, -0.03), 1.0],
	"pirate": [Vector3(0, 1.045, -0.03), 1.0],
	"yeti": [Vector3(0, 1.07, -0.03), 1.12],
	"robopup": [Vector3(0, 1.045, -0.04), 1.0],
	"pixel": [Vector3(0, 1.005, -0.02), 1.08],
}


static func build(v: PlayerVisual, id: String) -> bool:
	match id:
		"wizard":
			_wizard(v)
		"pirate":
			_pirate(v)
		"yeti":
			_yeti(v)
		"robopup":
			_robopup(v)
		"pixel":
			_pixel(v)
		_:
			return false
	return true


## A hanging part: a pivot at its top edge that swings on the antenna spring, with `mesh` hung
## below it (centre `drop` under the pivot). Returns the part. `gains` = pitch, roll, flutter,
## wag, lift (see PlayerVisual.Sway).
static func _hang(v: PlayerVisual, at: Vector3, mesh: Mesh, mat: Material, drop: float, scl: Vector3, rest: Vector3, gains: Array[float]) -> MeshInstance3D:
	var root: Node3D = CosmeticArt.pivot(v._torso, at + PlayerVisual.TZ, rest)
	var mi: MeshInstance3D = CosmeticArt.part(root, mesh, mat, Vector3(0, -drop, 0), scl)
	v._add_sway(v._sways, root, gains[0], gains[1], gains[2], gains[3], gains[4])
	return mi


## Wizard: a deep-blue robe with gold stars, a long white beard and brows (the beard swings), a
## staff on the back whose orb rides the antenna spring, bell sleeves and curled slippers.
static func _wizard(v: PlayerVisual) -> void:
	var robe: Material = CosmeticArt.std(Color(0.26, 0.22, 0.6), 0.65)
	var skin: Material = CosmeticArt.std(Color(0.97, 0.8, 0.68), 0.7)
	var white: Material = CosmeticArt.std(Color(0.96, 0.96, 0.98), 0.9)
	var gold: Material = CosmeticArt.std(Color(1.0, 0.82, 0.3), 0.3, 0.8, 0.5)
	v._body = v._paintable(v._tp(CosmeticArt.sphere(2), robe, Vector3(0, 0.62, 0), Vector3(0.78, 0.86, 0.78)))
	v._paintable(v._tp(CosmeticArt.cyl(0.3, 0.45, 24), robe, Vector3(0, 0.3, 0), Vector3(1, 0.4, 1)))
	v._tp(CosmeticArt.sphere(1), skin, Vector3(0, 0.72, -0.24), Vector3(0.5, 0.4, 0.36))
	v._eyes(CosmeticArt.std(Color(1.0, 0.85, 0.35), 0.3, 0.0, 2.4), Vector3(0.1, 0.78, -0.41), Vector3(0.07, 0.09, 0.05))
	v._tp(CosmeticArt.sphere(0), skin, Vector3(0, 0.7, -0.44), Vector3(0.1, 0.09, 0.09))
	for side: float in [-1.0, 1.0]:
		v._tp(CosmeticArt.sphere(0), white, Vector3(0.1 * side, 0.87, -0.38), Vector3(0.15, 0.05, 0.08), Vector3(0, 0, 0.3 * side))
	# the beard: a cone that swings from the chin
	_hang(v, Vector3(0, 0.64, -0.33), CosmeticArt.cyl(0.5, 0.0, 10), white, 0.2, Vector3(0.3, 0.46, 0.14), Vector3.ZERO, [-0.6, 0.5, 0.1, 0.0, -0.5])
	# gold stars on the robe
	for at: Vector3 in [Vector3(0.14, 0.3, -0.385)]:
		v._tp(CosmeticArt.sphere(0), gold, at, Vector3.ONE * 0.05)
	v._belt(CosmeticArt.torus(0.33, 0.375), Vector3(0, 0.4, 0))
	# the staff (Pack), its orb on the spring
	v._pack(CosmeticArt.cyl(0.5, 0.5, 8), CosmeticArt.std(Color(0.45, 0.3, 0.18), 0.8), Vector3(0.16, 0.6, 0.4), Vector3(0.035, 0.95, 0.035), Vector3(0, 0, -0.2))
	v._antenna_at(Vector3(0.25, 1.08, 0.4), null)
	CosmeticArt.part(v._antenna, CosmeticArt.sphere(1), v._acc_glow, Vector3(0, 0.05, 0), Vector3.ONE * 0.15)
	CosmeticArt.part(v._antenna, CosmeticArt.torus(0.1, 0.12, 16), gold, Vector3(0, 0.05, 0), Vector3.ONE, Vector3(0.5, 0, 0.3))
	v._limbs(CosmeticArt.std(Color(0.2, 0.17, 0.45), 0.7), skin)
	v._on_pair(v._hand_l, v._hand_r, CosmeticArt.sphere(0), robe, Vector3(0.55, 0.4, 0.2), Vector3.ONE * 1.15)
	v._on_pair(v._foot_l, v._foot_r, CosmeticArt.sphere(0), CosmeticArt.std(Color(0.2, 0.17, 0.45), 0.7), Vector3(0, 0.3, -0.75), Vector3(0.5, 0.5, 0.5))


## Pirate: a cream shirt under a red vest, an eyepatch, a black beard and curly moustache, a
## gold earring, a hook for a hand, a peg leg, a cutlass on the back and a parrot on the
## shoulder in the racer colour.
static func _pirate(v: PlayerVisual) -> void:
	var shirt: Material = CosmeticArt.std(Color(0.9, 0.86, 0.76), 0.75)
	var vest: Material = CosmeticArt.std(Color(0.62, 0.15, 0.15), 0.7)
	var skin: Material = CosmeticArt.std(Color(0.95, 0.74, 0.58), 0.7)
	var black: Material = CosmeticArt.std(Color(0.06, 0.05, 0.06), 0.7)
	var leather: Material = CosmeticArt.std(Color(0.3, 0.19, 0.11), 0.75)
	var gold: Material = CosmeticArt.std(Color(1.0, 0.8, 0.3), 0.3, 0.8, 0.4)
	var steel: Material = CosmeticArt.std(Color(0.8, 0.82, 0.86), 0.25, 0.9)
	v._body = v._paintable(v._tp(CosmeticArt.sphere(2), shirt, Vector3(0, 0.62, 0), Vector3(0.78, 0.86, 0.78)))
	v._paintable(v._tp(CosmeticArt.sphere(1), vest, Vector3(0, 0.44, 0), Vector3(0.8, 0.44, 0.8)))
	v._tp(CosmeticArt.sphere(1), skin, Vector3(0, 0.78, -0.2), Vector3(0.58, 0.42, 0.4))
	v._eyes(CosmeticArt.std(Color(1, 1, 1), 0.3), Vector3(0.11, 0.8, -0.36), Vector3(0.1, 0.11, 0.07))
	v._on_pair(v._eye_l, v._eye_r, CosmeticArt.sphere(0), black, Vector3(0.0, 0.0, -0.4), Vector3(0.55, 0.6, 0.4))
	# the eyepatch over the left eye, with its strap round the head
	v._tp(CosmeticArt.sphere(1), black, Vector3(-0.11, 0.8, -0.385), Vector3(0.18, 0.16, 0.06))
	v._tp(CosmeticArt.torus(0.335, 0.36), black, Vector3(0, 0.82, 0), Vector3.ONE, Vector3(0, 0, 0.4))
	# a bushy black beard
	v._tp(CosmeticArt.sphere(1), black, Vector3(0, 0.56, -0.27), Vector3(0.46, 0.24, 0.26))
	# belt and buckle
	v._belt(CosmeticArt.torus(0.315, 0.375), Vector3(0, 0.38, 0), Vector3.ONE, leather)
	v._tp(CosmeticArt.box(), gold, Vector3(0, 0.38, -0.365), Vector3(0.1, 0.09, 0.03))
	# the cutlass (Pack): scabbard across the back, gold guard and hilt
	var tilt := Vector3(0, 0, 1.0)
	var dir := Vector3(-sin(1.0), cos(1.0), 0)
	var c := Vector3(0.0, 0.45, 0.38)
	v._pack(CosmeticArt.box(), leather, c, Vector3(0.07, 0.5, 0.06), tilt)
	v._tp(CosmeticArt.box(), gold, c + dir * 0.25, Vector3(0.16, 0.03, 0.09), tilt)
	# the parrot on the right shoulder
	var bird: Node3D = CosmeticArt.pivot(v._torso, Vector3(0.27, 0.94, 0.0) + PlayerVisual.TZ)
	CosmeticArt.part(bird, CosmeticArt.sphere(0), v._acc_base, Vector3(0, 0.08, 0), Vector3(0.13, 0.17, 0.13))
	CosmeticArt.part(bird, CosmeticArt.sphere(0), v._acc_base, Vector3(0, 0.2, -0.02), Vector3.ONE * 0.1)
	CosmeticArt.part(bird, CosmeticArt.cyl(0.0, 0.5, 6), gold, Vector3(0, 0.2, -0.085), Vector3(0.05, 0.07, 0.05), Vector3(-PI * 0.5, 0, 0))
	v._add_sway(v._sways, bird, 0.25, 0.3, 0.08, 0.0, 0.0)
	v._antenna_at(Vector3(0, 1.02, 0.02), null)
	# boots; the left leg is a peg, the right hand a hook
	v._limbs(leather, CosmeticArt.std(Color(0.9, 0.9, 0.86), 0.7), Vector3(0.25, 0.17, 0.36))
	var wood: Material = CosmeticArt.std(Color(0.5, 0.34, 0.2), 0.9)
	v._foot_l.material_override = wood
	CosmeticArt.part(v._foot_l, CosmeticArt.cyl(0.5, 0.38, 8), wood, Vector3(0, 1.3, 0.1), Vector3(0.42, 2.4, 0.4))
	CosmeticArt.part(v._hand_r, CosmeticArt.arc(3.4, 0.45, 0.12, 8, 10), steel, Vector3(0, 0, -0.55), Vector3.ONE * 0.9, Vector3(-PI * 0.5, 0, 0))


## Yeti: a big shaggy white fur ball with an icy-blue face, a heavy brow, little fangs, fur
## tufts at the shoulders and hips that swing, crystals on its back and huge clawed mitts.
static func _yeti(v: PlayerVisual) -> void:
	var fur: Material = CosmeticArt.std(Color(0.93, 0.95, 1.0), 0.95)
	var dark: Material = CosmeticArt.std(Color(0.07, 0.09, 0.15), 0.6)
	v._body = v._paintable(v._tp(CosmeticArt.sphere(2), fur, Vector3(0, 0.62, 0), Vector3(0.86, 0.9, 0.82)))
	v._tp(CosmeticArt.sphere(1), CosmeticArt.std(Color(0.72, 0.86, 0.96), 0.7), Vector3(0, 0.7, -0.26), Vector3(0.5, 0.4, 0.32))
	v._eyes(CosmeticArt.std(Color(0.45, 0.95, 1.0), 0.3, 0.0, 2.6), Vector3(0.1, 0.76, -0.405), Vector3(0.08, 0.1, 0.05))
	v._tp(CosmeticArt.sphere(1), fur, Vector3(0, 0.87, -0.33), Vector3(0.52, 0.1, 0.2))
	v._tp(CosmeticArt.sphere(0), dark, Vector3(0, 0.58, -0.395), Vector3(0.22, 0.06, 0.06))
	for side: float in [-1.0, 1.0]:
		v._tp(CosmeticArt.cyl(0.5, 0.0, 6), CosmeticArt.std(Color(1, 1, 1), 0.4), Vector3(0.06 * side, 0.55, -0.405), Vector3(0.04, 0.08, 0.03))
	# fur tufts that swing: shoulders and hips
	var tuft: Mesh = CosmeticArt.cyl(0.5, 0.0, 6)
	for side: float in [-1.0, 1.0]:
		v._paintable(_hang(v, Vector3(0.37 * side, 0.82, 0.0), tuft, fur, 0.14, Vector3(0.17, 0.32, 0.17), Vector3(0, 0, 0.35 * side), [-0.5, 0.6, 0.12, 0.0, -0.4]))
		v._paintable(_hang(v, Vector3(0.3 * side, 0.4, 0.12), tuft, fur, 0.13, Vector3(0.16, 0.3, 0.16), Vector3(0, 0, 0.3 * side), [-0.5, 0.6, 0.12, 0.0, -0.4]))
	v._belt(CosmeticArt.torus(0.34, 0.41), Vector3(0, 0.36, 0))
	# icy crystals on the back
	var crystal: Material = CosmeticArt.std(Color(0.7, 0.9, 1.0), 0.15, 0.1, 0.7)
	v._pack(CosmeticArt.cyl(0.0, 0.5, 6), crystal, Vector3(0, 0.74, 0.4), Vector3(0.2, 0.5, 0.16), Vector3(-0.25, 0, 0))
	v._tp(CosmeticArt.cyl(0.0, 0.5, 6), crystal, Vector3(-0.16, 0.62, 0.38), Vector3(0.14, 0.34, 0.12), Vector3(-0.2, 0, 0.35))
	# the head tuft rides the spring and hides under covering hats
	v._antenna_at(Vector3(0, 1.06, 0.0), null)
	CosmeticArt.part(v._antenna, CosmeticArt.cyl(0.0, 0.5, 6), fur, Vector3(0, 0.08, 0), Vector3(0.18, 0.2, 0.18))
	v._crown_parts.append(v._antenna)
	v._limbs(fur, fur, Vector3(0.3, 0.2, 0.42), Vector3(0.26, 0.24, 0.26))
	v._on_pair(v._hand_l, v._hand_r, CosmeticArt.cyl(0.0, 0.5, 5), dark, Vector3(0.2, 0, -0.55), Vector3(0.2, 0.4, 0.2), Vector3(-PI * 0.5, 0, 0))


## Robo-Pup: a tan metal pup with a dark face screen, big cyan eyes, a cream muzzle and black
## nose, a tongue that flaps, floppy ears that swing, a collar with a tag and an antenna tail
## (bulb and all) at the back.
static func _robopup(v: PlayerVisual) -> void:
	var shell: Material = CosmeticArt.std(Color(0.9, 0.7, 0.42), 0.38, 0.4)
	var cream: Material = CosmeticArt.std(Color(0.98, 0.94, 0.84), 0.5, 0.2)
	var black: Material = CosmeticArt.std(Color(0.04, 0.04, 0.06), 0.25, 0.3)
	v._body = v._paintable(v._tp(CosmeticArt.sphere(2), shell, Vector3(0, 0.62, 0), Vector3(0.78, 0.86, 0.78)))
	v._tp(CosmeticArt.sphere(2), CosmeticArt.std(Color(0.06, 0.07, 0.1), 0.15, 0.3), Vector3(0, 0.76, -0.2), Vector3(0.58, 0.34, 0.42))
	v._eyes(CosmeticArt.std(Color(0.5, 0.97, 1.0), 0.3, 0.0, 3.0), Vector3(0.12, 0.78, -0.385), Vector3(0.1, 0.12, 0.05))
	# the muzzle, nose and flapping tongue
	v._tp(CosmeticArt.sphere(1), cream, Vector3(0, 0.6, -0.34), Vector3(0.3, 0.2, 0.2))
	v._tp(CosmeticArt.sphere(0), black, Vector3(0, 0.65, -0.45), Vector3(0.1, 0.07, 0.07))
	_hang(v, Vector3(0, 0.55, -0.4), CosmeticArt.sphere(0), CosmeticArt.std(Color(1.0, 0.45, 0.55), 0.5), 0.04, Vector3(0.07, 0.1, 0.02), Vector3.ZERO, [-0.8, 0.3, 0.4, 0.0, -0.3])
	# floppy ears
	for side: float in [-1.0, 1.0]:
		var ear: MeshInstance3D = _hang(v, Vector3(0.3 * side, 0.98, -0.02), CosmeticArt.sphere(1), shell, 0.14, Vector3(0.14, 0.36, 0.1), Vector3(0, 0, 0.5 * side), [0.5, 0.8, 0.25, 0.0, 0.2])
		v._paintable(ear)
		CosmeticArt.part(ear, CosmeticArt.sphere(0), v._acc_base, Vector3(0, 0, -0.35), Vector3(0.6, 0.7, 0.3))
	# collar, tag and pack
	v._belt(CosmeticArt.torus(0.335, 0.375), Vector3(0, 0.4, 0))
	v._tp(CosmeticArt.cyl(0.5, 0.5, 12), CosmeticArt.std(Color(1.0, 0.82, 0.3), 0.3, 0.8, 0.4), Vector3(0, 0.36, -0.36), Vector3(0.07, 0.02, 0.07), Vector3(PI * 0.5, 0, 0))
	v._pack(CosmeticArt.box(), v._acc_dark, Vector3(0, 0.6, 0.36), Vector3(0.28, 0.24, 0.14))
	v._tp(CosmeticArt.sphere(0), v._acc_glow, Vector3(0, 0.6, 0.435), Vector3.ONE * 0.05)
	# the tail is the antenna, at the back
	v._antenna_at(Vector3(0, 0.42, 0.34), CosmeticArt.std(Color(0.35, 0.3, 0.28), 0.4, 0.6))
	v._limbs(cream, v._acc_hand)


## Pixel Hero: a cube of a character: a block head-and-body with a green tunic, a brown block
## fringe, square eyes, box hands and feet, a pixel sword on the back and a cape that flaps.
static func _pixel(v: PlayerVisual) -> void:
	var skin: Material = CosmeticArt.std(Color(0.98, 0.8, 0.62), 0.8)
	var tunic: Material = CosmeticArt.std(Color(0.3, 0.7, 0.3), 0.8)
	var hair: Material = CosmeticArt.std(Color(0.42, 0.26, 0.14), 0.85)
	var brown: Material = CosmeticArt.std(Color(0.38, 0.24, 0.14), 0.8)
	var gold: Material = CosmeticArt.std(Color(1.0, 0.82, 0.3), 0.3, 0.8, 0.5)
	var box: BoxMesh = CosmeticArt.box()
	v._body = v._paintable(v._tp(box, skin, Vector3(0, 0.62, 0), Vector3(0.74, 0.76, 0.68)))
	v._paintable(v._tp(box, tunic, Vector3(0, 0.39, 0), Vector3(0.76, 0.3, 0.7)))
	# hair: a slab and a fringe, all of it hidden by a covering hat
	for p: Array in [[Vector3(0, 1.015, 0.0), Vector3(0.78, 0.12, 0.72)], [Vector3(-0.2, 0.93, -0.35), Vector3(0.3, 0.12, 0.04)], [Vector3(0.22, 0.95, -0.35), Vector3(0.2, 0.08, 0.04)], [Vector3(0, 0.82, 0.35), Vector3(0.78, 0.3, 0.04)]]:
		var h: MeshInstance3D = v._tp(box, hair, p[0], p[1])
		v._crown_parts.append(h)
	# square eyes with a pixel of shine
	v._eye_base = Vector3(0.1, 0.14, 0.05)
	v._eye_l = v._tp(box, CosmeticArt.std(Color(0.06, 0.06, 0.12), 0.4), Vector3(-0.15, 0.78, -0.355), v._eye_base)
	v._eye_r = v._tp(box, CosmeticArt.std(Color(0.06, 0.06, 0.12), 0.4), Vector3(0.15, 0.78, -0.355), v._eye_base)
	v._eye_l.name = "EyeL"
	v._eye_r.name = "EyeR"
	v._on_pair(v._eye_l, v._eye_r, box, CosmeticArt.std(Color(1, 1, 1), 0.3, 0.0, 1.5), Vector3(0.2, 0.25, -0.55), Vector3(0.3, 0.3, 0.3))
	v._tp(box, CosmeticArt.std(Color(0.55, 0.2, 0.2), 0.6), Vector3(0, 0.62, -0.345), Vector3(0.14, 0.04, 0.03))
	for side: float in [-1.0, 1.0]:
		v._tp(box, CosmeticArt.std(Color(1.0, 0.55, 0.55), 0.7), Vector3(0.26 * side, 0.66, -0.345), Vector3(0.1, 0.07, 0.03))
	# belt with a square buckle
	v._belt(box, Vector3(0, 0.54, 0), Vector3(0.78, 0.06, 0.72), brown)
	v._tp(box, gold, Vector3(0, 0.54, -0.365), Vector3(0.1, 0.09, 0.02))
	# the sword (Pack) across the back
	var tilt := Vector3(0, 0, 0.6)
	var dir := Vector3(-sin(0.6), cos(0.6), 0)
	var c := Vector3(0.0, 0.66, 0.4)
	v._pack(box, CosmeticArt.std(Color(0.85, 0.88, 0.95), 0.3, 0.7), c, Vector3(0.08, 0.5, 0.03), tilt)
	v._tp(box, gold, c - dir * 0.27, Vector3(0.18, 0.04, 0.05), tilt)
	v._tp(box, brown, c - dir * 0.36, Vector3(0.05, 0.12, 0.05), tilt)
	# the cape (racer colour) flaps from the shoulders
	_hang(v, Vector3(0, 0.96, 0.35), box, v._acc_base, 0.3, Vector3(0.66, 0.6, 0.04), Vector3.ZERO, [-0.7, 0.5, 0.18, 0.0, -0.5])
	v._antenna_at(Vector3(0, 1.0, 0.02), null)
	v._limbs(brown, skin, Vector3(0.24, 0.17, 0.34), Vector3(0.19, 0.18, 0.2))
	for m: MeshInstance3D in [v._foot_l, v._foot_r, v._hand_l, v._hand_r]:
		m.mesh = box
