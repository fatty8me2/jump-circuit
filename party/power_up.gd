class_name PowerUp
extends Node3D
## Base of every Party Mode item. One script per item under party/powerups/.
##
## An instance hangs off a racer's PlayerVisual (so it faces where the model faces):
##  * local = true: on our own Player - reads the Attack / Use / Cycle presses the PartyLayer
##    forwards, moves the player through speed/jump/gravity multipliers (mods()), detects hits
##    against rivals' ghosts and practice dummies and tells the layer, which sends them.
##  * local = false: a cosmetic mirror on a rival's ghost, built from a "pw" message; the
##    rival's actions arrive as "fx" messages and are replayed through remote().
## Instant items (duration 0) do their thing in begin() and finish().
## Items with no ghost-side model can replay their effects through a static
## `remote_fx(layer, from_id, action, data)` instead.

var layer: PartyLayer
var item_id: String = ""
## Peer id of the racer wearing it.
var owner_id: int = 0
var local: bool = true
## The Player (local) or RemoteRacer (mirror).
var body: Node3D
## Seconds; 0 = instant item.
var duration: float = 0.0
var time_left: float = 0.0
var ended: bool = false
## True for the three transformations: they take over the Attack button.
var takes_attack: bool = false
## Attack held longer than this is a charge, shorter is a tap.
var hold_threshold: float = 0.22


func setup(p_layer: PartyLayer, p_body: Node3D, p_local: bool, p_owner: int, p_id: String) -> void:
	layer = p_layer
	body = p_body
	local = p_local
	owner_id = p_owner
	item_id = p_id


func _ready() -> void:
	time_left = duration
	build_look()
	if local:
		begin()


func _physics_process(dt: float) -> void:
	if ended:
		return
	if duration > 0.0:
		time_left -= dt
		if time_left <= 0.0:
			finish()
			return
	if local:
		tick(dt)
	else:
		remote_tick(dt)


# ---- overridables ------------------------------------------------------------------------

## Costume / aura / particles, built on both sides (local and ghost mirror).
func build_look() -> void:
	pass


## Local start. Instant items act here and then call finish().
func begin() -> void:
	pass


## (speed, jump, gravity) multipliers while active.
func mods() -> Vector3:
	return Vector3.ONE


func air_jumps() -> int:
	return 0


func tick(_dt: float) -> void:
	pass


func remote_tick(_dt: float) -> void:
	pass


func on_attack_press() -> void:
	pass


## Called every physics tick while Attack is held (`held` seconds so far).
func on_attack_hold(_held: float) -> void:
	pass


func on_attack_release(_held: float) -> void:
	pass


## Use pressed while this is active: return true to consume it (else the slot item is used).
func on_use() -> bool:
	return false


func on_cycle() -> void:
	pass


## Replays one of the owner's actions on the ghost mirror.
func remote(_action: String, _data: Dictionary) -> void:
	pass


## A hit is about to land on the wearer: return true to absorb it (Balloon Shield).
func absorb_hit(_from_id: int) -> bool:
	return false


## Extra HUD line (current tool, the Energy Wave chant...).
func hud_status() -> String:
	return ""


## Charge meter 0..1 for the HUD, or -1 for none.
func charge_frac() -> float:
	return -1.0


## Cleanup when the power ends (restore anything not covered by mods()).
func on_end() -> void:
	pass


# ---- helpers ------------------------------------------------------------------------------

func finish() -> void:
	if ended:
		return
	ended = true
	on_end()
	if local and layer != null:
		layer.power_finished(self)
	# shrink the costume away, then free
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


## World position of the wearer's feet / chest.
func feet() -> Vector3:
	if body is Player:
		return (body as Player).global_position
	return body.global_position


func chest() -> Vector3:
	return feet() + Vector3(0, 0.75, 0)


func player() -> Player:
	return body as Player


## Sends an action for the ghost mirrors / other screens.
func fx(action: String, data: Dictionary = {}) -> void:
	if local and layer != null:
		layer.send_fx(item_id, action, data)


func world() -> Node:
	return layer if layer != null else get_parent()


static func v3(a: Variant) -> Vector3:
	if typeof(a) == TYPE_ARRAY and (a as Array).size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	if typeof(a) == TYPE_VECTOR3:
		return a
	return Vector3.ZERO


static func arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
