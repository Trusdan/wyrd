class_name WyrdFakeActions
extends WyrdActionAdapter

## Scripted commands. The schema and the next result are both configurable.

var schema: WyrdCommandSchema
var result: WyrdCommandResult
var executed: Array[StringName] = []


func _init() -> void:
	schema = WyrdCommandSchema.new()
	result = WyrdCommandResult.ok()


func set_result(next_result: WyrdCommandResult) -> void:
	result = next_result


func command_schema() -> WyrdCommandSchema:
	return schema


func execute(cmd: WyrdCommand) -> WyrdCommandResult:
	if cmd != null:
		executed.append(cmd.name)
	return result
