class_name BalanceHookCargo
extends BalanceTrolley
## Crane-hook cargo you mantle onto (gold lip like every LedgeBlock) and ride across.


func _init() -> void:
	ledge_lip = true


func is_ledge() -> bool:
	return true
