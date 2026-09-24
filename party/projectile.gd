class_name PartyProjectile
extends Node3D
## A thrown / fired Party Mode object with a deterministic flight: every screen spawns it from
## the same event (origin, velocity, gravity, start time) and so draws the same arc. Only the
## owner's copy (local = true) checks for hits - against the world, rivals' ghosts and practice
## dummies - and reports them through the callbacks; it then tells the others where it burst,
## so remote copies stop in the same place.

var layer: PartyLayer
var owner_id: int = 0
var local: bool = false
## Key in layer.projectiles (owner id + counter), so a "burst" message finds the remote copy.
var key: String = ""
var origin: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var gravity: float = 0.0
var life: float = 1.5
## Hit radius against targets.
var radius: float = 0.6
var hit_world: bool = true
var hit_targets: bool = true
## Optional custom flight: func(t: float) -> Vector3 (boomerangs).
var path: Callable
## Owner-side callbacks. on_target(target: Dictionary, pos) -> bool (true = stop here),
## on_world(pos, normal), on_expire(pos).
var on_target: Callable
var on_world: Callable
var on_expire: Callable
## Targets already hit (piercing projectiles hit each rival once).
var hit_ids: Array[int] = []
var t: float = 0.0
var done: bool = false


func pos_at(time: float) -> Vector3:
	if path.is_valid():
		return path.call(time)
	return origin + velocity * time + Vector3(0, -0.5 * gravity * time * time, 0)


func _ready() -> void:
	global_position = pos_at(0.0)
	if key != "" and layer != null:
		layer.projectiles[key] = self


func _physics_process(dt: float) -> void:
	if done:
		return
	var prev: Vector3 = pos_at(t)
	t += dt
	var p: Vector3 = pos_at(t)
	global_position = p
	var d: Vector3 = p - prev
	# face along the motion; a basis from the direction (not look_at(p + d)) stays valid far from
	# the origin, where p + d can round back to p when the step is tiny (a boomerang turning round)
	if d.length() > 0.001:
		var dir: Vector3 = d.normalized()
		global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	if local and layer != null:
		if hit_world:
			var q := PhysicsRayQueryParameters3D.create(prev, p, 1)
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				global_position = hit["position"]
				if on_world.is_valid():
					on_world.call(hit["position"] as Vector3, hit["normal"] as Vector3)
				stop()
				return
		if hit_targets:
			for tg: Dictionary in layer.targets_near_segment(prev, p, radius):
				if hit_ids.has(int(tg["id"])):
					continue
				hit_ids.append(int(tg["id"]))
				if on_target.is_valid() and bool(on_target.call(tg, p)):
					stop()
					return
	if t >= life:
		if local and on_expire.is_valid():
			on_expire.call(p)
		stop()


## Ends the flight (the owner's burst message calls this on remote copies too).
func stop(at: Variant = null) -> void:
	if done:
		return
	done = true
	if at != null:
		global_position = at
	if layer != null and layer.projectiles.get(key) == self:
		layer.projectiles.erase(key)
	# leave trails a moment to fade: stop emitting, hide meshes, free later
	for c: Node in find_children("*", "GPUParticles3D", true, false):
		(c as GPUParticles3D).emitting = false
	for c: Node in find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).visible = false
	set_physics_process(false)
	get_tree().create_timer(1.0, false).timeout.connect(queue_free)
