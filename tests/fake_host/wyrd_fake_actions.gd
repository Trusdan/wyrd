class_name WyrdFakeActions
extends WyrdActionAdapter

## Scripted commands. The schema and the next result are both configurable.

var schema: WyrdCommandSchema
var result: WyrdCommandResult
var executed: Array[StringName] = []
var results_by_name: Dictionary = {}


func _init() -> void:
	schema = WyrdCommandSchema.new()
	result = WyrdCommandResult.ok()


func set_result(next_result: WyrdCommandResult) -> void:
	result = next_result


func set_result_for(command_name: StringName, next_result: WyrdCommandResult) -> void:
	results_by_name[command_name] = next_result


func command_schema() -> WyrdCommandSchema:
	return schema


func execute(cmd: WyrdCommand) -> WyrdCommandResult:
	if cmd != null:
		executed.append(cmd.name)
		if results_by_name.has(cmd.name):
			return results_by_name[cmd.name] as WyrdCommandResult
	return result
