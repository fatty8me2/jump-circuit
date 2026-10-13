class_name HyperloopDecor
extends RefCounted
## Hyperloop's scenery kit: the white-and-cyan megastructure the course threads through. Everything is
## visual (no collision) and built from shared meshes and materials. The pieces:
##   axis_tower  the central spire of the whole complex, ringed in light
##   giant_ring  a vast torus of white ceramic with a cyan light strip
##   tube        a long glass transit tube with glowing ribs (a HyperloopTrain streaks through some)
##   pylon       a support column with collar rings, plunging into the cloud sea
##   keel        a tapering steel girder hung under a deck
##   gantry      an overhead portal that frames a lane (cyan strip across the top)
##   rib_arch    a thin open arch (a run of them makes a "tunnel" you see through)
## Repeated parts go through a MultiMesh so a whole tube is a handful of draw calls.

const WHITE := Color(0.95, 0.97, 1.0)
const STEEL := Color(0.60, 0.68, 0.78)
const CYAN := Color(0.20, 0.88, 1.0)
const CORAL := Color(1.0, 0.60, 0.48)

var root: Node3D
var rng: RandomNumberGenerator


func _init(parent: Node3D, r: RandomNumberGenerator) -> void:
	root = parent
	rng = r


static func white_mat() -> StandardMaterial3D:
	return Look.flat(WHITE, 0.38, 0.05)


static func steel_mat() -> StandardMaterial3D:
	return Look.flat(STEEL, 0.32, 0.65)


static func glow_mat(col: Color = CYAN, energy: float = 2.4) -> StandardMaterial3D:
	return Look.flat(col, 0.3, 0.0, energy)


static func glass_mat(alpha: float = 0.16) -> StandardMaterial3D:
	var key: String = "hl_glass:%.2f" % alpha
	if Look._cache.has(key):
		return Look._cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.92, 1.0, alpha)
	m.emission_enabled = true
	m.emission = CYAN
	m.emission_energy_multiplier = 0.25
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.15
	Look._cache[key] = m
	return m


func _no_shadow(mi: MeshInstance3D) -> MeshInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Draws `xforms` copies of `mesh` as one MultiMeshInstance3D (world transforms).
func multi(mesh: Mesh, mat: Material, xforms: Array[Transform3D], shadow: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


## A basis whose local Y axis points along `axis` (for cylinders laid along a direction).
static func basis_y(axis: Vector3) -> Basis:
	var y: Vector3 = axis.normalized() if axis.length() > 0.0001 else Vector3.UP
	var ref: Vector3 = Vector3.RIGHT if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z)


## A basis whose local -Z axis points along `dir` (up stays up where it can).
static func basis_fwd(dir: Vector3) -> Basis:
	var f: Vector3 = dir.normalized() if dir.length() > 0.0001 else Vector3(0, 0, -1)
	var ref: Vector3 = Vector3.RIGHT if absf(f.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x: Vector3 = f.cross(ref).normalized()
	var y: Vector3 = x.cross(f).normalized()
	return Basis(x, y, -f)


# ---- the big pieces -----------------------------------------------------------------------------

## The central spire: a tall white shaft, bands of cyan light, a ring-and-needle crown.
func axis_tower(base: Vector3, height: float, radius: float) -> void:
	var white := white_mat()
	var glow := glow_mat()
	var shaft := Look.cylinder(radius, height, white, base + Vector3(0, height * 0.5, 0), radius * 0.62, 28)
	root.add_child(_no_shadow(shaft))
	# bands of light every ~34 m, thicker rings every third
	var xf: Array[Transform3D] = []
	var xf_big: Array[Transform3D] = []
	var n: int = int(height / 34.0)
	for i: int in n:
		var t: float = (float(i) + 0.5) / float(n)
		var r: float = lerpf(radius, radius * 0.62, t) + 0.35
		var y: float = base.y + height * t
		var tr := Transform3D(Basis.IDENTITY.scaled(Vector3(r, 1.0, r)), Vector3(base.x, y, base.z))
		if i % 3 == 0:
			xf_big.append(tr)
		else:
			xf.append(tr)
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 1.0
	band_mesh.bottom_radius = 1.0
	band_mesh.height = 1.0
	band_mesh.radial_segments = 28
	band_mesh.rings = 1
	multi(band_mesh, glow, xf)
	var big_mesh := CylinderMesh.new()
	big_mesh.top_radius = 1.0
	big_mesh.bottom_radius = 1.0
	big_mesh.height = 4.0
	big_mesh.radial_segments = 28
	big_mesh.rings = 1
	multi(big_mesh, white_mat(), xf_big)
	# a halo ring and a needle at the crown
	var top: Vector3 = base + Vector3(0, height, 0)
	giant_ring(top - Vector3(0, 18, 0), radius * 2.6, 1.6, Vector3.ZERO)
	root.add_child(_no_shadow(Look.cylinder(0.9, 70.0, glow, top + Vector3(0, 28, 0), 0.05, 8)))
	root.add_child(_no_shadow(Look.sphere(2.2, glow, top + Vector3(0, 64, 0))))


## A vast torus (ring road / halo): white ceramic with a cyan light strip round its outer face.
## `tilt` is euler degrees applied to the ring (flat in XZ at zero).
func giant_ring(center: Vector3, radius: float, tube: float, tilt: Vector3, lit: bool = true) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = radius - tube
	tm.outer_radius = radius + tube
	tm.rings = 72
	tm.ring_segments = 10
	var ring := Look.mesh_node(tm, white_mat(), center)
	ring.rotation_degrees = tilt
	root.add_child(_no_shadow(ring))
	if lit:
		var sm := TorusMesh.new()
		sm.inner_radius = radius + tube * 0.9
		sm.outer_radius = radius + tube * 1.1
		sm.rings = 72
		sm.ring_segments = 4
		var strip := Look.mesh_node(sm, glow_mat(CYAN, 2.0), center)
		strip.rotation_degrees = tilt
		root.add_child(_no_shadow(strip))


## A glass transit tube from a to b: translucent shell, a glowing spine along its floor, and ribs.
func tube(a: Vector3, b: Vector3, radius: float, rib_every: float = 14.0) -> void:
	var d: Vector3 = b - a
	var length: float = d.length()
	if length < 1.0:
		return
	var bas: Basis = basis_y(d)
	var mid: Vector3 = (a + b) * 0.5
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 20
	cm.rings = 1
	var shell := MeshInstance3D.new()
	shell.mesh = cm
	shell.material_override = glass_mat()
	shell.transform = Transform3D(bas, mid)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shell)
	# the rail spine on the floor of the tube
	var spine := CylinderMesh.new()
	spine.top_radius = radius * 0.05
	spine.bottom_radius = radius * 0.05
	spine.height = length
	spine.radial_segments = 6
	spine.rings = 1
	var floor_pt: Vector3 = mid + (Vector3.DOWN * radius * 0.78)
	var sp := Look.mesh_node(spine, glow_mat(CYAN, 2.2), floor_pt)
	sp.transform = Transform3D(bas, floor_pt)
	root.add_child(_no_shadow(sp))
	# white ribs
	var ribs: Array[Transform3D] = []
	var n: int = maxi(int(length / rib_every), 1)
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.98
	tm.outer_radius = radius * 1.06
	tm.rings = 24
	tm.ring_segments = 4
	for i: int in n + 1:
		var p: Vector3 = a + d * (float(i) / float(n))
		ribs.append(Transform3D(bas, p))
	multi(tm, white_mat(), ribs)


## A support column from `top` down to `bottom_y`, with collar rings.
func pylon(top: Vector3, bottom_y: float, radius: float) -> void:
	var h: float = top.y - bottom_y
	if h < 1.0:
		return
	var col := Look.cylinder(radius, h, white_mat(), Vector3(top.x, bottom_y + h * 0.5, top.z), radius * 1.5, 14)
	root.add_child(_no_shadow(col))
	var collars: Array[Transform3D] = []
	var n: int = int(h / 12.0)
	for i: int in n:
		var y: float = top.y - 3.0 - float(i) * 12.0
		var t: float = (top.y - y) / h
		var r: float = lerpf(radius, radius * 1.5, t) + 0.12
		collars.append(Transform3D(Basis.IDENTITY.scaled(Vector3(r, 1.0, r)), Vector3(top.x, y, top.z)))
	if not collars.is_empty():
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.height = 0.5
		cm.radial_segments = 14
		cm.rings = 1
		multi(cm, glow_mat(CYAN, 1.6), collars)


## A steel girder under a deck (centre of the deck top `top`, deck `size`, turned by `yaw` degrees).
func keel(top: Vector3, size: Vector3, yaw_deg: float, depth: float = 3.0) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(top.x, top.y - size.y, top.z)
	holder.rotation_degrees.y = yaw_deg
	root.add_child(holder)
	var cm := CylinderMesh.new()
	cm.height = depth
	cm.radial_segments = 4
	cm.rings = 1
	cm.top_radius = 0.7071 * 0.94
	cm.bottom_radius = 0.7071 * 0.3
	var mi := Look.mesh_node(cm, steel_mat())
	mi.rotation.y = PI / 4.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inner := Node3D.new()
	inner.scale = Vector3(size.x, 1.0, size.z)
	inner.position = Vector3(0, -depth * 0.5, 0)
	inner.add_child(mi)
	holder.add_child(inner)


## An overhead portal over a lane: two posts and a beam with a cyan strip underneath.
func gantry(base: Vector3, yaw_deg: float, span: float, height: float, col: Color = CYAN) -> void:
	var n := Node3D.new()
	n.position = base
	n.rotation_degrees.y = yaw_deg
	root.add_child(n)
	var white := white_mat()
	for sx: float in [-1.0, 1.0]:
		n.add_child(_no_shadow(Look.box(Vector3(0.7, height, 0.7), white, Vector3(sx * span * 0.5, height * 0.5, 0))))
	n.add_child(_no_shadow(Look.box(Vector3(span + 0.7, 0.7, 0.9), white, Vector3(0, height + 0.35, 0))))
	n.add_child(_no_shadow(Look.box(Vector3(span - 0.7, 0.16, 0.5), glow_mat(col, 2.6), Vector3(0, height - 0.04, 0))))


## A thin open arch (half a ring over a deck, or a full ring) used in runs to suggest a tunnel.
func rib_arch(center: Vector3, yaw_deg: float, radius: float, full: bool = false) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.18
	tm.outer_radius = radius + 0.18
	tm.rings = 28
	tm.ring_segments = 4
	var mi := Look.mesh_node(tm, white_mat(), center)
	mi.rotation_degrees = Vector3(90, yaw_deg, 0)
	root.add_child(_no_shadow(mi))
