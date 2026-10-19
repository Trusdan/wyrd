class_name WyrdSkillAdapter
extends RefCounted

## Host hook for a choice's skill check.
##
## @experimental
## The default body is not implemented. [method check] returns a failed result so a caller
## never mistakes a stub for success.

func check(request: WyrdSkillCheck) -> WyrdCommandResult:
	var skill := &""
	if request != null:
		skill = request.skill
	push_error("not implemented: WyrdSkillAdapter.check(%s)" % skill)
	return WyrdCommandResult.failed(&"not_implemented")
