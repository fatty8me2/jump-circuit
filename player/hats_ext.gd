class_name HatsExt
extends RefCounted
## Hats added in the v2.0 update (world Silver hats for the new courses and the extra Gold /
## stat hats). CosmeticArt.hat() falls through to build() for any id it doesn't know, so new
## hats live here and never touch the original match block. Build parts into `h` with the
## CosmeticArt helpers (part / pivot / std / sphere / cyl / box / torus / brim / shader); `sway`,
## `spin` and `bob` metas animate exactly as they do there.

## Hats that leave the crown open (the antenna / crown spike stays visible), like
## CosmeticArt.OPEN_HATS.
const OPEN_HATS: Array[String] = ["bunny", "flower_crown", "pixel_crown", "laurel", "gilded_headphones"]


static func build(id: String, h: Node3D, v: PlayerVisual) -> void:
	match id:
		"windup":
			_windup(h)
		"toadstool":
			_toadstool(h)
		"ringmaster":
			_ringmaster(h)
		"laurel":
			_laurel(h)
		"dinoskull":
			_dinoskull(h)
		"wizard":
			_wizard(h)
		"pixel_crown":
			_pixel_crown(h)
		"knight_helm":
			_knight_helm(h)
		"toque":
			_toque(h)
		"bunny":
			_bunny(h)
		"flower_crown":
			_flower_crown(h)
		"monocle_hat":
			_monocle_hat(h)
		"cone":
			_cone(h)
		"gilded_viking":
			_gilded("viking", h, v)
		"gilded_tricorn":
			_gilded("tricorn", h, v)
		"gilded_cowboy":
			_gilded("cowboy", h, v)
		"gilded_beanie":
			_gilded("beanie", h, v)
		"gilded_headphones":
			_gilded("headphones", h, v)
		_:
			pass


# ---- world Silver hats -------------------------------------------------------------------------

## Toybox: a red tin cap with a brass wind-up key on top; the key's ring turns.
static func _windup(h: Node3D) -> void:
	var red := CosmeticArt.std(Color(0.9, 0.18, 0.16), 0.5)
	var brass := CosmeticArt.std(Color(0.85, 0.63, 0.25), 0.3, 0.85)
	CosmeticArt.part(h, CosmeticArt.sphere(1), red, Vector3(0, -0.09, 0), Vector3(0.56, 0.26, 0.56))
	CosmeticArt.part(h, CosmeticArt.torus(0.24, 0.28), brass, Vector3(0, -0.1, 0), Vector3(1, 0.5, 1))
	CosmeticArt.part(h, CosmeticArt.cyl(0.5, 0.5, 8), brass, Vector3(0, 0.15, 0), Vector3(0.04, 0.22, 0.04))
	var bow: Node3D = CosmeticArt.pivot(h, Vector3(0, 0.27, 0))
	bow.set_meta("spin", [2.0, 0.0])
	CosmeticArt.part(bow, CosmeticArt.torus(0.07, 0.13, 18), brass, Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0))
	CosmeticArt.part(h, CosmeticArt.box(), brass, Vector3(0.05, 0.06, 0), Vector3(0.06, 0.03, 0.05))
	CosmeticArt.part(h, CosmeticArt.box(), brass, Vector3(0.05, 0.1, 0), Vector3(0.05, 0.02, 0.05))


## Mushroom Hollow: a red toadstool cap with cream spots and a cream gill rim.
static func _toadstool(h: Node3D) -> void:
	var red := CosmeticArt.std(Color(0.88, 0.14, 0.14), 0.45)
	var cream := CosmeticArt.std(Color(0.98, 0.95, 0.88), 0.6)
	CosmeticArt.part(h, CosmeticArt.sphere(1), red, Vector3(0, -0.08, 0), Vector3(0.62, 0.3, 0.62))
	CosmeticArt.part(h, CosmeticArt.torus(0.27, 0.34), cream, Vector3(0, -0.1, 0), Vector3(1, 0.45, 1))
	var spots: Array[Vector3] = [Vector3(0.15, 0.042, 0.1), Vector3(-0.2, 0.02, -0.05), Vector3(0.02, 0.025, -0.22), Vector3(0.05, 0.06, -0.02)]
	for s: Vector3 in spots:
		CosmeticArt.part(h, CosmeticArt.sphere(0), cream, s, Vector3.ONE * 0.09)


## Carnival: a black top hat with a red band and a gold star pin that bobs.
static func _ringmaster(h: Node3D) -> void:
	var felt := CosmeticArt.std(Color(0.08, 0.07, 0.1), 0.45)
	var red := CosmeticArt.std(Color(0.85, 0.12, 0.15), 0.4)
	var gold := CosmeticArt.std(Color(1.0, 0.8, 0.3), 0.25, 0.85)
	CosmeticArt.part(h, CosmeticArt.brim("tophat"), felt, Vector3(0, -0.05, 0))
	CosmeticArt.part(h, CosmeticArt.cyl(0.5, 0.5, 20), felt, Vector3(0, 0.12, 0), Vector3(0.36, 0.34, 0.36))
	CosmeticArt.part(h, CosmeticArt.cyl(0.5, 0.5, 20), red, Vector3(0, 0.03, 0), Vector3(0.375, 0.07, 0.375))
	var star: Node3D = CosmeticArt.pivot(h, Vector3(0, 0.035, -0.2))
	star.set_meta("bob", [0.012, 2.4])
	CosmeticArt.part(star, CosmeticArt.sphere(0), gold, Vector3.ZERO, Vector3.ONE * 0.1)


## Olympus: a green laurel wreath (leaves alternate two greens) tied with a gold bow at the back.
static func _laurel(h: Node3D) -> void:
	var green := CosmeticArt.std(Color(0.3, 0.68, 0.28), 0.6)
	var green2 := CosmeticArt.std(Color(0.45, 0.8, 0.32), 0.6)
	var gold := CosmeticArt.std(Color(1.0, 0.8, 0.3), 0.25, 0.85)
	CosmeticArt.part(h, CosmeticArt.torus(0.24, 0.29), green, Vector3(0, -0.09, 0), Vector3(1, 0.7, 1))
	for k: int in 8:
		var th: float = TAU * float(k) / 8.0
		var mat: StandardMaterial3D = green if k % 2 == 0 else green2
		# the leaf's long axis follows the ring
		CosmeticArt.part(h, CosmeticArt.sphere(0), mat, Vector3(cos(th) * 0.27, -0.09, sin(th) * 0.27), Vector3(0.1, 0.035, 0.05), Vector3(0, -(th + PI * 0.5), 0))
	# a sprig of leaves standing up at the front, so the wreath reads from above
	CosmeticArt.part(h, CosmeticArt.sphere(0), green2, Vector3(0, 0.05, -0.02), Vector3(0.045, 0.13, 0.035))
	CosmeticArt.part(h, CosmeticArt.sphere(0), gold, Vector3(-0.045, -0.13, 0.28), Vector3(0.07, 0.055, 0.04))
	CosmeticArt.part(h, CosmeticArt.sphere(0), gold, Vector3(0.045, -0.13, 0.28), Vector3(0.07, 0.055, 0.04))


## Dino Valley: a bone-white dinosaur skull worn like a helmet, with dark eye sockets and horns.
static func _dinoskull(h: Node3D) -> void:
	var bone := CosmeticArt.std(Color(0.94, 0.9, 0.8), 0.7)
	var hole := CosmeticArt.std(Color(0.1, 0.07, 0.06), 0.9)
	CosmeticArt.part(h, CosmeticArt.sphere(1), bone, Vector3(0, -0.07, 0.03), Vector3(0.6, 0.42, 0.62))
	# the snout points forward (-Z): a cylinder whose axis is turned from Y to Z
	CosmeticArt.part(h, CosmeticArt.cyl(0.5, 0.5, 12), bone, Vector3(0, -0.1, -0.2), Vector3(0.26, 0.36, 0.26), Vector3(PI * 0.5, 0, 0))
	CosmeticArt.part(h, CosmeticArt.box(), bone, Vector3(0, -0.2, -0.2), Vector3(0.2, 0.05, 0.3))
	for side: float in [-1.0, 1.0]:
		CosmeticArt.part(h, CosmeticArt.sphere(0), hole, Vector3(0.17 * side, -0.05, -0.22), Vector3(0.13, 0.11, 0.1))
		CosmeticArt.part(h, CosmeticArt.cyl(0.0, 0.5, 8), bone, Vector3(0.2 * side, 0.08, 0.06), Vector3(0.09, 0.26, 0.09), Vector3(0, 0, -0.35 * side))


## Arcane Library: a tall indigo wizard hat leaning back, with a gold band, orbiting stars and a
## tip star that bobs.
static func _wizard(h: Node3D) -> void:
	var indigo := CosmeticArt.std(Color(0.22, 0.16, 0.62), 0.6)
	var brimc := CosmeticArt.std(Color(0.16, 0.12, 0.45), 0.7)
	var gold := CosmeticArt.std(Color(1.0, 0.85, 0.35), 0.3, 0.8, 1.4)
	CosmeticArt.part(h, CosmeticArt.brim("witch"), brimc, Vector3(0, -0.06, 0))
	var lean: Node3D = CosmeticArt.pivot(h, Vector3(0, -0.02, 0), Vector3(0.0, 0.0, 0.2))
	CosmeticArt.part(lean, CosmeticArt.cyl(0.0, 0.5, 16), indigo, Vector3(0, 0.22, 0), Vector3(0.36, 0.5, 0.36))
	CosmeticArt.part(lean, CosmeticArt.torus(0.17, 0.2), gold, Vector3(0, 0.03, 0), Vector3(1, 0.8, 1))
	for k: int in 3:
		var th: float = TAU * float(k) / 3.0 + 0.5
		CosmeticArt.part(lean, CosmeticArt.sphere(0), gold, Vector3(cos(th) * 0.1, 0.2, sin(th) * 0.1), Vector3.ONE * 0.04)
	var tip: Node3D = CosmeticArt.pivot(lean, Vector3(0, 0.48, 0))
	tip.set_meta("bob", [0.012, 2.5])
	CosmeticArt.part(tip, CosmeticArt.sphere(0), gold, Vector3.ZERO, Vector3.ONE * 0.08)


## Arcade: a ring of gold pixel blocks with three neon pixel tips that bob.
static func _pixel_crown(h: Node3D) -> void:
	var gold := CosmeticArt.std(Color(1.0, 0.82, 0.25), 0.3, 0.8)
	var neon: Array[StandardMaterial3D] = [
		CosmeticArt.std(Color(1.0, 0.2, 0.8), 0.4, 0.0, 1.2),
		CosmeticArt.std(Color(0.2, 0.95, 1.0), 0.4, 0.0, 1.2),
		CosmeticArt.std(Color(0.6, 1.0, 0.2), 0.4, 0.0, 1.2),
	]
	for k: int in 6:
		var th: float = TAU * float(k) / 6.0
		CosmeticArt.part(h, CosmeticArt.box(), gold, Vector3(cos(th) * 0.27, -0.03, sin(th) * 0.27), Vector3(0.1, 0.09, 0.1))
	var tips: Node3D = CosmeticArt.pivot(h, Vector3.ZERO)
	tips.set_meta("bob", [0.012, 3.0])
	for k: int in 3:
		var th2: float = TAU * float(k * 2) / 6.0
		CosmeticArt.part(tips, CosmeticArt.box(), neon[k], Vector3(cos(th2) * 0.27, 0.08, sin(th2) * 0.27), Vector3(0.1, 0.1, 0.1))


## Castle Siege: a steel helm with a dark visor slit, rivets and a red plume that sways.
static func _knight_helm(h: Node3D) -> void:
	var steel := CosmeticArt.std(Color(0.7, 0.72, 0.77), 0.3, 0.85)
	var dark := CosmeticArt.std(Color(0.38, 0.4, 0.46), 0.4, 0.7)
	var slit := CosmeticArt.std(Color(0.04, 0.04, 0.05), 0.9)
	var plume := CosmeticArt.std(Color(0.9, 0.12, 0.16), 0.6)
	CosmeticArt.part(h, CosmeticArt.sphere(1), steel, Vector3(0, -0.08, 0), Vector3(0.58, 0.46, 0.6))
	CosmeticArt.part(h, CosmeticArt.torus(0.26, 0.31), dark, Vector3(0, -0.1, 0), Vector3(1, 0.55, 1))
	CosmeticArt.part(h, CosmeticArt.box(), slit, Vector3(0, -0.07, -0.29), Vector3(0.26, 0.035, 0.03))
	CosmeticArt.part(h, CosmeticArt.box(), dark, Vector3(0, -0.14, -0.29), Vector3(0.04, 0.2, 0.04))
	for side: float in [-1.0, 1.0]:
		CosmeticArt.part(h, CosmeticArt.sphere(0), dark, Vector3(0.2 * side, -0.13, -0.2), Vector3.ONE * 0.05)
	var crest: Node3D = CosmeticArt.pivot(h, Vector3(0, 0.1, 0.04))
	crest.set_meta("sway", [0.6, 0.6, 0.25, 0.0, 0.0])
	# the plume starts upright and arcs back over the helm (the arc's +X becomes +Z)
	CosmeticArt.part_b(crest, CosmeticArt.arc(1.8, 0.22, 0.03, 8, 12), plume, Vector3.ZERO, Basis(Vector3.UP, -PI * 0.5).scaled(Vector3.ONE * 0.3))


# ---- extra hats ----------------------------------------------------------------------------------

## A puffy white chef's toque that bobs on the head.
static func _toque(h: Node3D) -> void:
	var white := CosmeticArt.std(Color(0.98, 0.98, 0.96), 0.8)
	var pleat := CosmeticArt.std(Color(0.9, 0.9, 0.88), 0.8)
	var puff: Node3D = CosmeticArt.pivot(h, Vector3.ZERO)
	puff.set_meta("bob", [0.01, 1.6])
	CosmeticArt.part(puff, CosmeticArt.cyl(0.5, 0.5, 16), pleat, Vector3(0, -0.1, 0), Vector3(0.58, 0.13, 0.58))
	CosmeticArt.part(puff, CosmeticArt.sphere(2), white, Vector3(0, 0.07, 0), Vector3(0.56, 0.34, 0.56))
	CosmeticArt.part(puff, CosmeticArt.sphere(1), white, Vector3(0.2, 0.12, 0.1), Vector3(0.32, 0.3, 0.32))
	CosmeticArt.part(puff, CosmeticArt.sphere(1), white, Vector3(-0.2, 0.12, 0.08), Vector3(0.32, 0.3, 0.32))
	CosmeticArt.part(puff, CosmeticArt.sphere(1), white, Vector3(0, 0.14, -0.2), Vector3(0.36, 0.3, 0.3))


## Pink headband with two floppy bunny ears that swing on the sway spring.
static func _bunny(h: Node3D) -> void:
	var pink := CosmeticArt.std(Color(1.0, 0.6, 0.76), 0.5)
	var fur := CosmeticArt.std(Color(0.98, 0.96, 0.98), 0.85)
	var inner := CosmeticArt.std(Color(1.0, 0.5, 0.65), 0.6)
	CosmeticArt.part(h, CosmeticArt.torus(0.22, 0.27), pink, Vector3(0, -0.1, 0), Vector3(1, 0.6, 1))
	for side: float in [-1.0, 1.0]:
		# tilted outward; the top leans away from the middle of the head
		var ear: Node3D = CosmeticArt.pivot(h, Vector3(0.12 * side, -0.04, 0), Vector3(0, 0, -0.18 * side))
		ear.set_meta("sway", [0.9, 0.7, 0.3, 0.0, 0.0])
		CosmeticArt.part(ear, CosmeticArt.sphere(1), fur, Vector3(0, 0.24, 0), Vector3(0.13, 0.5, 0.07))
		CosmeticArt.part(ear, CosmeticArt.sphere(0), inner, Vector3(0, 0.24, -0.02), Vector3(0.07, 0.4, 0.035))


## A ring of five pink-and-lilac flowers with gold centres on a green vine.
static func _flower_crown(h: Node3D) -> void:
	var vine := CosmeticArt.std(Color(0.35, 0.72, 0.35), 0.6)
	var petal := CosmeticArt.std(Color(1.0, 0.55, 0.75), 0.5)
	var petal2 := CosmeticArt.std(Color(0.7, 0.55, 1.0), 0.5)
	var centre := CosmeticArt.std(Color(1.0, 0.9, 0.3), 0.4, 0.0, 0.4)
	CosmeticArt.part(h, CosmeticArt.torus(0.24, 0.29), vine, Vector3(0, -0.1, 0), Vector3(1, 0.6, 1))
	for k: int in 5:
		var th: float = TAU * float(k) / 5.0 + 0.3
		var radial := Vector3(cos(th), 0.0, sin(th))
		var ring_at: Vector3 = Vector3(0, -0.1, 0) + radial * 0.27
		# a flattened petal disc turned to face outward (its thin axis is radial)
		var face: float = PI * 0.5 - th
		var mat: StandardMaterial3D = petal if k % 2 == 0 else petal2
		CosmeticArt.part(h, CosmeticArt.sphere(1), mat, ring_at + radial * 0.02, Vector3(0.13, 0.13, 0.05), Vector3(0, face, 0))
		CosmeticArt.part(h, CosmeticArt.sphere(0), centre, ring_at + radial * 0.035, Vector3.ONE * 0.05)
	# a bigger centrepiece flower on top at the front, so the crown rises above the head
	CosmeticArt.part(h, CosmeticArt.sphere(1), petal, Vector3(0, 0.05, -0.27), Vector3(0.16, 0.16, 0.05))
	CosmeticArt.part(h, CosmeticArt.sphere(0), centre, Vector3(0, 0.05, -0.3), Vector3.ONE * 0.06)


## A gold-banded top hat with a monocle that dangles from the band on a chain and swings.
static func _monocle_hat(h: Node3D) -> void:
	var felt := CosmeticArt.std(Color(0.06, 0.06, 0.08), 0.4)
	var gold := CosmeticArt.std(Color(1.0, 0.8, 0.3), 0.25, 0.85)
	var lens := CosmeticArt.std(Color(0.7, 0.9, 1.0), 0.1, 0.0, 0.8)
	CosmeticArt.part(h, CosmeticArt.brim("tophat"), felt, Vector3(0, -0.05, 0))
	CosmeticArt.part(h, CosmeticArt.cyl(0.5, 0.5, 20), felt, Vector3(0, 0.12, 0), Vector3(0.36, 0.34, 0.36))
	CosmeticArt.part(h, CosmeticArt.cyl(0.5, 0.5, 20), gold, Vector3(0, 0.0, 0), Vector3(0.375, 0.05, 0.375))
	var dangle: Node3D = CosmeticArt.pivot(h, Vector3(-0.13, -0.01, -0.13))
	dangle.set_meta("sway", [0.5, 0.5, 0.0, 0.0, 0.0])
	CosmeticArt.part(dangle, CosmeticArt.cyl(0.5, 0.5, 6), gold, Vector3(0, -0.07, 0), Vector3(0.012, 0.09, 0.012))
	CosmeticArt.part(dangle, CosmeticArt.torus(0.045, 0.07, 14), gold, Vector3(0, -0.17, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
	CosmeticArt.part(dangle, CosmeticArt.sphere(1), lens, Vector3(0, -0.17, 0), Vector3(0.12, 0.12, 0.02))


## A road-works traffic cone with two white bands, wobbling on the sway spring.
static func _cone(h: Node3D) -> void:
	var orange := CosmeticArt.std(Color(1.0, 0.45, 0.08), 0.5)
	var white := CosmeticArt.std(Color(0.97, 0.97, 0.95), 0.4, 0.0, 0.3)
	var black := CosmeticArt.std(Color(0.12, 0.12, 0.13), 0.7)
	var wob: Node3D = CosmeticArt.pivot(h, Vector3.ZERO)
	wob.set_meta("sway", [0.25, 0.25, 0.0, 0.0, 0.0])
	CosmeticArt.part(wob, CosmeticArt.cyl(0.5, 0.5, 14), black, Vector3(0, -0.08, 0), Vector3(0.56, 0.05, 0.56))
	CosmeticArt.part(wob, CosmeticArt.cyl(0.07, 0.5, 14), orange, Vector3(0, 0.12, 0), Vector3(0.5, 0.4, 0.5))
	CosmeticArt.part(wob, CosmeticArt.cyl(0.5, 0.5, 14), white, Vector3(0, 0.02, 0), Vector3(0.4, 0.05, 0.4))
	CosmeticArt.part(wob, CosmeticArt.cyl(0.5, 0.5, 14), white, Vector3(0, 0.2, 0), Vector3(0.21, 0.05, 0.21))
	CosmeticArt.part(wob, CosmeticArt.sphere(0), orange, Vector3(0, 0.33, 0), Vector3.ONE * 0.07)


# ---- gilded (Gold) versions of existing hats ---------------------------------------------------

## The Gold version of an existing hat: the same silhouette built by CosmeticArt.hat, with every
## piece re-finished in gold leaf. Its animation metas come along with the parts.
static func _gilded(base: String, h: Node3D, v: PlayerVisual) -> void:
	var src: Node3D = CosmeticArt.hat(base, v)
	for c: Node in src.get_children():
		src.remove_child(c)
		h.add_child(c)
	src.free()
	_regild(h, CosmeticArt.std(Color(1.0, 0.8, 0.3), 0.22, 0.9))


static func _regild(n: Node, gold: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = gold
	for c: Node in n.get_children():
		_regild(c, gold)
