class_name ArcadeDecor
extends RefCounted
## Pixel Panic's scenery, all of it voxels: sprites built from bitmaps (space invaders, ghosts, hearts,
## coins), text in a 3x5 pixel font ("INSERT COIN", "HI SCORE", "1UP"), tetromino stacks, pong courts,
## joysticks and buttons. Every piece is ONE MultiMesh of beveled cubes (a handful of draw calls),
## placed far from the route by the level. No collision, visual only.

const FONT: Dictionary = {
	"A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
	"C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
	"E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
	"G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
	"I": ["###", ".#.", ".#.", ".#.", "###"], "K": ["#.#", "#.#", "##.", "#.#", "#.#"],
	"L": ["#..", "#..", "#..", "#..", "###"], "M": ["#.#", "###", "###", "#.#", "#.#"],
	"N": ["##.", "#.#", "#.#", "#.#", "#.#"], "O": [".#.", "#.#", "#.#", "#.#", ".#."],
	"P": ["##.", "#.#", "##.", "#..", "#.."], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
	"S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
	"W": ["#.#", "#.#", "###", "###", "#.#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
	"0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["##.", "..#", ".#.", "#..", "###"], "9": ["###", "#.#", "###", "..#", "###"],
	"?": ["##.", "..#", ".#.", "...", ".#."], "!": [".#.", ".#.", ".#.", "...", ".#."], "-": ["...", "...", "###", "...", "..."],
}
const INVADER: Array[String] = [
	"..#.....#..", "...#...#...", "..#######..", ".##.###.##.", "###########", "#.#######.#", "#.#.....#.#", "...##.##...",
]
const SQUID: Array[String] = [
	"...##...", "..####..", ".######.", "##.##.##", "########", "..#..#..", ".#.##.#.", "#.#..#.#",
]
const GHOST: Array[String] = [
	"..#####..", ".#######.", "#########", "##.###.##", "#########", "#########", "#########", "##.#.#.##",
]
const HEART: Array[String] = [
	".##.##.", "#######", "#######", ".#####.", "..###..", "...#...",
]
const COIN: Array[String] = [
	"..####..", ".######.", "###..###", "###..###", "###..###", "###..###", ".######.", "..####..",
]

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r


## A rotation from a yaw and optional tilts.
static func turn(yaw: float, pitch: float = 0.0, roll: float = 0.0) -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, roll))


## A bitmap as voxels (row 0 on top, x centred, `depth` layers thick) in one MultiMesh, in `col`.
func sprite(pos: Vector3, rows: Array[String], vox: float, col: Color, basis: Basis = Basis.IDENTITY, depth: int = 2, glow: float = 0.6) -> Node3D:
	var cells: Array[Vector3] = []
	var h: int = rows.size()
	var w: int = rows[0].length()
	for r: int in h:
		for c: int in w:
			if rows[r][c] == "#":
				for z: int in depth:
					cells.append(Vector3((float(c) - float(w - 1) * 0.5) * vox, float(h - 1 - r) * vox, float(z) * vox))
	return _cubes(pos, cells, vox, col, basis, glow)


## Text in the 3x5 font (centred), lit.
func text(pos: Vector3, s: String, vox: float, col: Color, basis: Basis = Basis.IDENTITY, glow: float = 1.0) -> Node3D:
	var cells: Array[Vector3] = []
	var n: int = s.length()
	var total: float = float(n) * 4.0 - 1.0
	for i: int in n:
		var ch: String = s.substr(i, 1)
		if not FONT.has(ch):
			continue
		var g: Array = FONT[ch]
		for r: int in 5:
			for c: int in 3:
				if String(g[r])[c] == "#":
					cells.append(Vector3((float(i) * 4.0 + float(c) - total * 0.5 + 0.5) * vox, float(4 - r) * vox, 0.0))
	return _cubes(pos, cells, vox, col, basis, glow)


func _cubes(pos: Vector3, cells: Array[Vector3], vox: float, col: Color, basis: Basis, glow: float) -> Node3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * (vox - vox * 0.04)
	mm.mesh = bm
	mm.instance_count = cells.size()
	for i: int in cells.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, cells[i]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat: ShaderMaterial = ArcadeFx.block_mat(col, Vector3.ONE * vox, glow)
	mat.set_shader_parameter("bevel", vox * 0.12)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	holder.transform = Transform3D(basis, pos)
	holder.add_child(mi)
	root.add_child(holder)
	return holder


## A stack of coloured tetromino cells, `cols` wide, rising `rows` high with ragged gaps.
func stack(pos: Vector3, cols: int, rows: int, vox: float, basis: Basis = Basis.IDENTITY) -> Node3D:
	var holder := Node3D.new()
	holder.transform = Transform3D(basis, pos)
	root.add_child(holder)
	for k: int in 7:
		var cells: Array[Vector3] = []
		for r: int in rows:
			for c: int in cols:
				if (r * 7 + c * 3 + r * c) % 7 == k and rng.randf() < 0.9 and (r < 2 or rng.randf() < 0.7):
					cells.append(Vector3((float(c) - float(cols - 1) * 0.5) * vox, float(r) * vox, 0.0))
		if cells.is_empty():
			continue
		var n: Node3D = _cubes(Vector3.ZERO, cells, vox, ArcadeFx.pal(k), Basis.IDENTITY, 0.5)
		root.remove_child(n)
		holder.add_child(n)
	return holder


## A pong court seen from the side: two paddles and a ball, white.
func pong(pos: Vector3, vox: float, basis: Basis = Basis.IDENTITY) -> Node3D:
	var cells: Array[Vector3] = []
	for y: int in 5:
		cells.append(Vector3(-8.0 * vox, float(y + 2) * vox, 0))
		cells.append(Vector3(8.0 * vox, float(y) * vox, 0))
	cells.append(Vector3(2.0 * vox, 4.0 * vox, 0))
	for x: int in range(-8, 9, 2):
		cells.append(Vector3(float(x) * vox, 9.0 * vox, 0))
		cells.append(Vector3(float(x) * vox, -1.0 * vox, 0))
	return _cubes(pos, cells, vox, ArcadeFx.WHITE, basis, 0.9)


## A giant arcade joystick: a ball on a shaft on a square base (smooth, scenery).
func joystick(pos: Vector3, scale: float, col: Color = Color(1.0, 0.2, 0.26)) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.scale = Vector3.ONE * scale
	n.add_child(Look.box(Vector3(6, 1, 6), Look.flat(Color(0.1, 0.1, 0.18), 0.5), Vector3(0, 0.5, 0)))
	n.add_child(Look.cylinder(0.35, 5.0, Look.flat(Color(0.8, 0.82, 0.9), 0.3, 0.8), Vector3(0, 3.5, 0), -1.0, 12))
	n.add_child(Look.sphere(1.6, Look.flat(col, 0.35, 0.0, 0.8), Vector3(0, 7.0, 0)))
	root.add_child(n)
	return n


## A big round arcade button.
func button(pos: Vector3, scale: float, col: Color) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.scale = Vector3.ONE * scale
	n.add_child(Look.cylinder(2.6, 0.8, Look.flat(Color(0.1, 0.1, 0.18), 0.5), Vector3(0, 0.4, 0), -1.0, 20))
	n.add_child(Look.cylinder(2.1, 1.4, Look.flat(col, 0.3, 0.0, 1.0), Vector3(0, 1.2, 0), 1.9, 20))
	root.add_child(n)
	return n
