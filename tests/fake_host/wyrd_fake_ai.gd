class_name WyrdFakeAI
extends RefCounted

## Scripted AI providers for tests. Each one extends [WyrdAIProvider] directly.


class EchoNow extends WyrdAIProvider:
	var host: WyrdRuntime
	var seen_pending: int = -1
	var cancelled: Array[int] = []
	var texts: PackedStringArray = PackedStringArray()

	func id() -> StringName:
		return &"echo-now"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(req: WyrdAIRequest) -> void:
		if host != null and host.ai != null:
			seen_pending = host.ai.pending_count()
		var result := WyrdAIResult.new()
		result.ok = true
		result.text = str(req.packet.get("text", ""))
		texts.append(result.text)
		req.reply(result)

	func cancel(request_id: int) -> void:
		cancelled.append(request_id)


class EchoLater extends WyrdAIProvider:
	var waiting: Array[WyrdAIRequest] = []
	var cancelled: Array[int] = []

	func id() -> StringName:
		return &"echo-later"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(req: WyrdAIRequest) -> void:
		waiting.append(req)

	func answer(index: int = 0, ok: bool = true, text: String = "later") -> bool:
		var result := WyrdAIResult.new()
		result.ok = ok
		result.text = text
		return waiting[index].reply(result)

	func cancel(request_id: int) -> void:
		cancelled.append(request_id)


class NeverAnswers extends WyrdAIProvider:
	var calls: int = 0
	var cancelled: Array[int] = []

	func id() -> StringName:
		return &"never"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray()

	func request(_req: WyrdAIRequest) -> void:
		calls += 1

	func cancel(request_id: int) -> void:
		cancelled.append(request_id)
