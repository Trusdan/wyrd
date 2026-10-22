class_name WyrdFakeAIText
extends WyrdAIProvider

## Scripted provider that answers one fixed string.
## [member hold] keeps the request pending so a test can deliver it.

var text: String = ""
var ok: bool = true
var hold: bool = false
var waiting: Array[WyrdAIRequest] = []


func id() -> StringName:
	return &"fixed-text"


func prompt_version() -> int:
	return 1


func locales() -> PackedStringArray:
	return PackedStringArray(["en"])


func request(req: WyrdAIRequest) -> void:
	waiting.append(req)
	if hold:
		return
	_reply(req)


func cancel(_request_id: int) -> void:
	pass


func _reply(req: WyrdAIRequest) -> bool:
	var result := WyrdAIResult.new()
	result.ok = ok
	result.text = text
	return req.reply(result)
