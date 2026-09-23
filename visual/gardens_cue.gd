class_name GardensCue
extends Node3D
## Launch Gardens feedback trigger: restarts every one-shot GPUParticles3D child when
## `test` turns true (a machine event on the course clock: a press slamming, a ram punching,
## a firework beat) or - with no test - when the player comes within `radius` of this node
## (it re-arms once they leave). Visual only; skipped entirely in headless runs.

var test: Callable
var radius: float = 0.0
## Minimum seconds between two firings.
var cooldown: float = 0.5

var _was: bool = false
var _cool: float = 0.0
var _level: LevelBase


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_physics_process(false)
		return
	var n: Node = get_parent()
	while n != null and not (n is LevelBase):
		n = n.get_parent()
	_level = n as LevelBase


func fire() -> void:
	for c: Node in get_children():
		if c is GPUParticles3D:
			(c as GPUParticles3D).restart()


func _physics_process(dt: float) -> void:
	_cool = maxf(_cool - dt, 0.0)
	var now: bool = false
	if test.is_valid():
		now = bool(test.call())
	elif radius > 0.0 and _level != null and _level.player != null:
		now = _level.player.global_position.distance_to(global_position) < radius
	if now and not _was and _cool <= 0.0:
		fire()
		_cool = cooldown
	_was = now
