class_name WyrdFakeTime
extends WyrdTimeAdapter

## Scripted clock. The minute count starts at 0 until a test sets it.

var minutes: int = 0


func set_minutes(value: int) -> void:
	minutes = value


func now_minutes() -> int:
	return minutes
