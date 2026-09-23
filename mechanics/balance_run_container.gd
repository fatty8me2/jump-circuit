class_name BalanceRunContainer
extends BalanceTrolley
## Crane-hung container whose long sides are wall-run faces (cyan run lines like every
## WallRunPanel) - you run along it while the crane swings it along the yard.


func _init() -> void:
	run_lines = true


func is_wall_run() -> bool:
	return true
