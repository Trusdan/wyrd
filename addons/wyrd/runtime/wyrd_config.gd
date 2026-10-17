class_name WyrdConfig
extends Resource

## Host knobs for one runtime. Plain exported data. No callables.
##
## @experimental
## Field names beyond the design list: [member hour_bucket_minutes],
## [member half_life_verbs], [member half_life_minutes], [member disposition_default],
## [member hostile_threshold], [member axis_verbs], [member axis_names],
## [member axis_deltas], [member kind_scale_kinds], [member kind_scale_axes],
## [member kind_scale_values], [member scheduler_work_per_tick],
## [member scheduler_tick_minutes], [member scheduler_share_waits],
## [member scheduler_share_rumor], [member scheduler_share_publish],
## [member scheduler_share_cache], [member scheduler_frame_warn_usec],
## [member credibility_threshold], [member compact_after],
## [member secrecy_tiers], [member secrecy_fact], and [member trace_director].
## S2a uses the hour bucket for [code]chance[/code] and the work cap for each tick.

@export var hour_bucket_minutes: int = 60
@export var half_life_verbs: PackedStringArray = PackedStringArray()
@export var half_life_minutes: PackedFloat64Array = PackedFloat64Array()
@export var disposition_default: int = 50
@export var hostile_threshold: int = 20
@export var axis_verbs: PackedStringArray = PackedStringArray()
@export var axis_names: PackedStringArray = PackedStringArray()
@export var axis_deltas: PackedFloat64Array = PackedFloat64Array()
## Parallel to [member kind_scale_axes] and [member kind_scale_values]. Not saved.
@export var kind_scale_kinds: PackedStringArray = PackedStringArray()
@export var kind_scale_axes: PackedStringArray = PackedStringArray()
@export var kind_scale_values: PackedFloat64Array = PackedFloat64Array()
@export var scheduler_work_per_tick: int = 64
## Game minutes in one scheduler tick. Slices of [code]Wyrd.tick[/code] add up
## until this many minutes have accumulated. Not saved.
@export var scheduler_tick_minutes: int = 1
## Weights for waits, rumor, publish, and cache refresh. They split
## [member scheduler_work_per_tick]. Not saved.
@export var scheduler_share_waits: int = 40
@export var scheduler_share_rumor: int = 12
@export var scheduler_share_publish: int = 8
@export var scheduler_share_cache: int = 4
## Debug builds log [code]wyrd scheduler queue=frame[/code] when one game tick's
## units take longer than this many microseconds. The default is 2000 (2 ms).
## [code]0[/code] disables it. The line does not change the work. Not saved.
@export var scheduler_frame_warn_usec: int = 2000
## Inclusive minimum score for a statement deed. Not saved.
@export var credibility_threshold: float = 0.5
## 0 leaves the log until the host calls [method WyrdDeedLog.compact]. Not saved.
@export var compact_after: int = 0
## Ordered secrecy names, lowest first. Not saved. An empty list locks every named tier.
@export var secrecy_tiers: PackedStringArray = PackedStringArray()
## World fact whose symbol is the unlocked secrecy name. Not saved.
@export var secrecy_fact: String = "player.clearance"
## When true, a director query logs one line per scope-and-speaker match. Not saved.
## Tracing must also be on. Load does not log those lines.
@export var trace_director: bool = false


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


## Replaces the factor for one kind and axis. [code]1.0[/code] leaves that kind's deeds unscaled.
func set_kind_scale(kind: StringName, axis_name: StringName, scale: float) -> void:
	var count := mini(kind_scale_kinds.size(), mini(kind_scale_axes.size(), kind_scale_values.size()))
	for i in count:
		if StringName(kind_scale_kinds[i]) == kind and StringName(kind_scale_axes[i]) == axis_name:
			kind_scale_values[i] = scale
			return
	kind_scale_kinds.append(String(kind))
	kind_scale_axes.append(String(axis_name))
	kind_scale_values.append(scale)


## [code]1.0[/code] when this kind and axis have no factor.
func kind_scale(kind: StringName, axis_name: StringName) -> float:
	var count := mini(kind_scale_kinds.size(), mini(kind_scale_axes.size(), kind_scale_values.size()))
	for i in count:
		if StringName(kind_scale_kinds[i]) == kind and StringName(kind_scale_axes[i]) == axis_name:
			return kind_scale_values[i]
	return 1.0


## Rows of [code]kind[/code] and [code]scale[/code] for one axis.
func scales_for(axis_name: StringName) -> Array:
	var rows: Array = []
	var count := mini(kind_scale_kinds.size(), mini(kind_scale_axes.size(), kind_scale_values.size()))
	for i in count:
		if StringName(kind_scale_axes[i]) != axis_name:
			continue
		rows.append({"kind": StringName(kind_scale_kinds[i]), "scale": float(kind_scale_values[i])})
	return rows


func axis_delta(verb: StringName, axis_name: StringName) -> float:
	var total := 0.0
	var count := mini(axis_verbs.size(), mini(axis_names.size(), axis_deltas.size()))
	for i in count:
		if StringName(axis_verbs[i]) == verb and StringName(axis_names[i]) == axis_name:
			total += axis_deltas[i]
	return total
