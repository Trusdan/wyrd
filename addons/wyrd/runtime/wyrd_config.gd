class_name WyrdConfig
extends Resource

## Host knobs for one runtime. Plain exported data. No callables.
##
## @experimental
## Field names beyond the design list: [member hour_bucket_minutes],
## [member half_life_verbs], [member half_life_minutes], [member disposition_default],
## [member hostile_threshold], [member axis_verbs], [member axis_names],
## [member axis_deltas], [member scheduler_work_per_tick], and
## [member credibility_threshold].
## S2a uses the hour bucket for [code]chance[/code] and the work cap for each tick.

@export var hour_bucket_minutes: int = 60
@export var half_life_verbs: PackedStringArray = PackedStringArray()
@export var half_life_minutes: PackedFloat64Array = PackedFloat64Array()
@export var disposition_default: int = 50
@export var hostile_threshold: int = 20
@export var axis_verbs: PackedStringArray = PackedStringArray()
@export var axis_names: PackedStringArray = PackedStringArray()
@export var axis_deltas: PackedFloat64Array = PackedFloat64Array()
@export var scheduler_work_per_tick: int = 64
## Inclusive minimum score for a statement deed. Not saved.
@export var credibility_threshold: float = 0.5


func half_life_for(verb: StringName) -> float:
	var count := mini(half_life_verbs.size(), half_life_minutes.size())
	for i in count:
		if StringName(half_life_verbs[i]) == verb:
			return half_life_minutes[i]
	return 0.0


func set_axis_delta(verb: StringName, axis_name: StringName, delta: float) -> void:
	var count := mini(axis_verbs.size(), mini(axis_names.size(), axis_deltas.size()))
	for i in count:
		if StringName(axis_verbs[i]) == verb and StringName(axis_names[i]) == axis_name:
			axis_deltas[i] = delta
			return
	axis_verbs.append(String(verb))
	axis_names.append(String(axis_name))
	axis_deltas.append(delta)


func axis_delta(verb: StringName, axis_name: StringName) -> float:
	var total := 0.0
	var count := mini(axis_verbs.size(), mini(axis_names.size(), axis_deltas.size()))
	for i in count:
		if StringName(axis_verbs[i]) == verb and StringName(axis_names[i]) == axis_name:
			total += axis_deltas[i]
	return total
