class_name WyrdFakeTime
extends WyrdTimeAdapter

## Scripted clock. The minute count starts at 0 until a test sets it.
## [member season_name] and [member hour] answer [code]time.season[/code] and [code]time.hour[/code].

var minutes: int = 0
var season_name: StringName = &""
var hour_value: int = 0


func set_minutes(value: int) -> void:
	minutes = value


func now_minutes() -> int:
	return minutes


func season() -> StringName:
	return season_name


func hour() -> int:
	return hour_value
