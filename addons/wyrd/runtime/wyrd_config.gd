class_name WyrdConfig
extends Resource

## Host knobs for one runtime. Plain exported data. No callables.
##
## @experimental
## Field names beyond the design list: [member hour_bucket_minutes],
## [member half_life_verbs], [member half_life_minutes], [member disposition_default],
## and [member scheduler_work_per_tick]. S2b reads the half-lives and the
## disposition default. S2a uses the hour bucket for [code]chance[/code] and the
## work cap for each tick.

@export var hour_bucket_minutes: int = 60
@export var half_life_verbs: PackedStringArray = PackedStringArray()
@export var half_life_minutes: PackedFloat64Array = PackedFloat64Array()
@export var disposition_default: int = 50
@export var scheduler_work_per_tick: int = 64


func half_life_for(verb: StringName) -> float:
	var count := mini(half_life_verbs.size(), half_life_minutes.size())
	for i in count:
		if StringName(half_life_verbs[i]) == verb:
			return half_life_minutes[i]
	return 0.0
