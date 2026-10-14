extends Node

const _Runtime := preload("res://addons/wyrd/runtime/wyrd_runtime.gd")

## Facade over one [WyrdRuntime].
##
## @experimental
## The editor plugin does not register this script as an autoload in S0.
## When it does, the autoload name is Wyrd, so this script has no class_name.

var _runtime: WyrdRuntime


func _init() -> void:
	_runtime = _Runtime.new()


func get_version() -> String:
	return _runtime.get_version()
