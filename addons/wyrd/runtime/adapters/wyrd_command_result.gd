class_name WyrdCommandResult
extends RefCounted

## Result of a host command: ok, or failed with a reason.
##

enum Status { OK, FAILED }

var status: Status = Status.FAILED
var reason: StringName = &""


static func ok() -> WyrdCommandResult:
	var result := WyrdCommandResult.new()
	result.status = Status.OK
	result.reason = &""
	return result


static func failed(failure_reason: StringName) -> WyrdCommandResult:
	var result := WyrdCommandResult.new()
	result.status = Status.FAILED
	result.reason = failure_reason
	return result


func is_ok() -> bool:
	return status == Status.OK
