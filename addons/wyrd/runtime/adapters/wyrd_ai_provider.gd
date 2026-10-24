class_name WyrdAIProvider
extends RefCounted

## Host hook for an AI answer.
##
## [method request] returns at once. The answer comes later, on the main thread,
## through [method WyrdAIRequest.reply] or [method WyrdAI.deliver].
## A provider never waits. The core has no network code.
## Unimplemented methods [code]push_error[/code] and return a typed fallback.

func id() -> StringName:
	push_error("not implemented: WyrdAIProvider.id()")
	return &""


func prompt_version() -> int:
	push_error("not implemented: WyrdAIProvider.prompt_version()")
	return 0


func locales() -> PackedStringArray:
	push_error("not implemented: WyrdAIProvider.locales()")
	return PackedStringArray()


func request(_req: WyrdAIRequest) -> void:
	push_error("not implemented: WyrdAIProvider.request()")


func cancel(_request_id: int) -> void:
	push_error("not implemented: WyrdAIProvider.cancel()")
