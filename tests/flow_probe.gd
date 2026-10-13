extends Node
## Test helper: records the last set_flow_highlight() it was given (the "flow_highlight" hook).
var last: float = 0.0


func set_flow_highlight(amount: float) -> void:
	last = amount
