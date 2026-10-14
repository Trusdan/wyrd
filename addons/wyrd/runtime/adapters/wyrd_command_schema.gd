class_name WyrdCommandSchema
extends RefCounted

## Names of the commands a host accepts.
##
## @experimental
## Argument types land with the real schema. S0 only records command names.

var command_names: Array[StringName] = []


func add_command(command_name: StringName) -> void:
	if not command_names.has(command_name):
		command_names.append(command_name)


func has_command(command_name: StringName) -> bool:
	return command_names.has(command_name)
