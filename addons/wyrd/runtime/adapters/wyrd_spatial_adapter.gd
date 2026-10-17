class_name WyrdSpatialAdapter
extends RefCounted

## Host answers to proximity, place, and access. Wyrd never touches the scene tree.
##
## @experimental
## Signatures follow the design sketch. A missing comparison returns [constant INF] once a host
## implements [method distance]. These default bodies are not implemented.
## [method precision] answers [code]precise[/code] or [code]coarse[/code] for a place.
## The default is [code]precise[/code] and does not [code]push_error[/code].
## Precise rumor hops read it. A coarse place does not spread in this slice.

func nearby(center: StringName, radius_m: float, filter: WyrdEntityFilter) -> PackedStringArray:
	var tag_name := &""
	if filter != null:
		tag_name = filter.tag
	push_error(
		"not implemented: WyrdSpatialAdapter.nearby(%s, %s, %s)" % [center, radius_m, tag_name]
	)
	return PackedStringArray()


func place_of(entity: StringName) -> StringName:
	push_error("not implemented: WyrdSpatialAdapter.place_of(%s)" % entity)
	return &""


func distance(a: StringName, b: StringName) -> float:
	push_error("not implemented: WyrdSpatialAdapter.distance(%s, %s)" % [a, b])
	return INF


func can_perceive(observer: StringName, target: StringName) -> bool:
	push_error("not implemented: WyrdSpatialAdapter.can_perceive(%s, %s)" % [observer, target])
	return false


func can_reach(agent: StringName, place: StringName) -> bool:
	push_error("not implemented: WyrdSpatialAdapter.can_reach(%s, %s)" % [agent, place])
	return false


## Entities that perceived a deed at [param place]. Empty when the host has no list.
func witnesses_of(_actor: StringName, _target: StringName, _place: StringName) -> PackedStringArray:
	return PackedStringArray()


## [code]precise[/code] or [code]coarse[/code]. The default is [code]precise[/code].
## It does not [code]push_error[/code]. An unknown place stays precise.
func precision(_place: StringName) -> StringName:
	return &"precise"


## How [param observer] perceived a deed. [code]saw[/code], [code]heard[/code],
## [code]inferred[/code], or empty when they did not perceive it. The default is
## [code]saw[/code] and does not [code]push_error[/code].
func perceive(
	_observer: StringName,
	_actor: StringName,
	_target: StringName,
	_place: StringName
) -> StringName:
	return &"saw"
