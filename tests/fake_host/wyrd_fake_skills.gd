class_name WyrdFakeSkills
extends WyrdSkillAdapter

## Scripted skill checks. Tests register this adapter themselves.

var result: WyrdCommandResult
var requests: Array[WyrdSkillCheck] = []
var results_by_skill: Dictionary = {}
var before_result: Callable = Callable()


func _init() -> void:
	result = WyrdCommandResult.ok()


func set_result(next_result: WyrdCommandResult) -> void:
	result = next_result


func set_result_for(skill: StringName, next_result: WyrdCommandResult) -> void:
	results_by_skill[skill] = next_result


func check(request: WyrdSkillCheck) -> WyrdCommandResult:
	if request != null:
		requests.append(request)
		if before_result.is_valid():
			before_result.call(request)
		if results_by_skill.has(request.skill):
			return results_by_skill[request.skill] as WyrdCommandResult
	return result
