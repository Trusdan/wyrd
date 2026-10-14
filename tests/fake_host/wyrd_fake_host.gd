class_name WyrdFakeHost
extends RefCounted

## The five scripted adapters, registered by their base-script path.
##
## This is the harness milestone tests will talk to. S0 has no runtime registrar yet,
## so the map lives here.

var world: WyrdFakeWorld
var inventory: WyrdFakeInventory
var spatial: WyrdFakeSpatial
var clock: WyrdFakeTime
var actions: WyrdFakeActions
var _by_base_path: Dictionary = {}


func _init() -> void:
	world = WyrdFakeWorld.new()
	inventory = WyrdFakeInventory.new()
	spatial = WyrdFakeSpatial.new()
	clock = WyrdFakeTime.new()
	actions = WyrdFakeActions.new()
	_remember(world)
	_remember(inventory)
	_remember(spatial)
	_remember(clock)
	_remember(actions)


func adapter_count() -> int:
	return _by_base_path.size()


func adapter_for(base: Script) -> RefCounted:
	if base == null or not _by_base_path.has(base.resource_path):
		push_error("Fake host has no adapter for %s." % base)
		return null
	return _by_base_path[base.resource_path] as RefCounted


func _remember(adapter: RefCounted) -> void:
	var script := adapter.get_script() as Script
	var base := script.get_base_script() as Script
	if base == null:
		push_error("Fake adapter %s has no base script." % script.resource_path)
		return
	_by_base_path[base.resource_path] = adapter
