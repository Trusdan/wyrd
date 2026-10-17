class_name WyrdFakeSpatial
extends WyrdSpatialAdapter

## Scripted spatial answers. An unknown distance is [constant INF].

var _places: Dictionary = {}
var _distances: Dictionary = {}
var _perceive: Dictionary = {}
var _reach: Dictionary = {}
var _nearby: Dictionary = {}
var nearby_calls: int = 0
var _witnesses: Dictionary = {}
var _perception: Dictionary = {}
var _precision: Dictionary = {}


func set_place(entity: StringName, place: StringName) -> void:
	_places[entity] = place


func set_distance(a: StringName, b: StringName, meters: float) -> void:
	_distances[_pair(a, b)] = meters
	_distances[_pair(b, a)] = meters


func set_can_perceive(observer: StringName, target: StringName, value: bool) -> void:
	_perceive[_pair(observer, target)] = value


func set_can_reach(agent: StringName, place: StringName, value: bool) -> void:
	_reach[_pair(agent, place)] = value


func set_nearby(
	center: StringName,
	radius_m: float,
	tag: StringName,
	ids: PackedStringArray
) -> void:
	_nearby[_nearby_key(center, radius_m, tag)] = ids


func set_witnesses(place: StringName, ids: PackedStringArray) -> void:
	_witnesses[place] = ids.duplicate()


## [param mode] is [code]precise[/code] or [code]coarse[/code]. An unmarked place stays precise.
func set_precision(place: StringName, mode: StringName) -> void:
	_precision[place] = mode


func precision(place: StringName) -> StringName:
	if not _precision.has(place):
		return &"precise"
	return _precision[place] as StringName


## One mode for [param observer] at [param place]. An empty place applies at every place.
func set_perception(observer: StringName, mode: StringName, place: StringName = &"") -> void:
	_perception["%s\t%s" % [String(observer), String(place)]] = mode


func perceive(observer: StringName, _actor: StringName, _target: StringName, place: StringName) -> StringName:
	var specific := "%s\t%s" % [String(observer), String(place)]
	if _perception.has(specific):
		return _perception[specific] as StringName
	var any := "%s\t" % String(observer)
	if _perception.has(any):
		return _perception[any] as StringName
	return &"saw"


func witnesses_of(_actor: StringName, _target: StringName, place: StringName) -> PackedStringArray:
	if not _witnesses.has(place):
		return PackedStringArray()
	return (_witnesses[place] as PackedStringArray).duplicate()


func nearby(center: StringName, radius_m: float, filter: WyrdEntityFilter) -> PackedStringArray:
	nearby_calls += 1
	var tag_name := &""
	if filter != null:
		tag_name = filter.tag
	var key := _nearby_key(center, radius_m, tag_name)
	if not _nearby.has(key):
		return PackedStringArray()
	return (_nearby[key] as PackedStringArray).duplicate()


func place_of(entity: StringName) -> StringName:
	if not _places.has(entity):
		return &""
	return _places[entity] as StringName


func distance(a: StringName, b: StringName) -> float:
	var key := _pair(a, b)
	if not _distances.has(key):
		return INF
	return _distances[key] as float


func can_perceive(observer: StringName, target: StringName) -> bool:
	var key := _pair(observer, target)
	if not _perceive.has(key):
		return false
	return _perceive[key] as bool


func can_reach(agent: StringName, place: StringName) -> bool:
	var key := _pair(agent, place)
	if not _reach.has(key):
		return false
	return _reach[key] as bool


static func _pair(a: StringName, b: StringName) -> String:
	return "%s\t%s" % [String(a), String(b)]


static func _nearby_key(center: StringName, radius_m: float, tag: StringName) -> String:
	return "%s\t%.3f\t%s" % [String(center), radius_m, String(tag)]
