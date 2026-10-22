class_name WyrdAI
extends RefCounted

## AI hook for one runtime. Not saved.
##
## @experimental
## The null provider is the default. A request keeps no pending state while that
## provider is active, or while the hook is disabled. [method deliver] closes a
## pending request and discards the text. Nothing in this release shows or caches it.

var _runtime: WyrdRuntime
var _provider: WyrdAIProvider
var _enabled: bool = true
var _next_id: int = 1
var _pending: Dictionary = {}


func bind(runtime: WyrdRuntime) -> void:
	_runtime = runtime


func set_enabled(on: bool) -> void:
	if on == _enabled:
		return
	_enabled = on
	if not _enabled:
		drop_pending(&"off")
	_trace_provider()


func is_enabled() -> bool:
	return _enabled


func provider() -> WyrdAIProvider:
	return _provider


func provider_id() -> StringName:
	if _provider == null:
		return &""
	return _provider.id()


## True when the hook is enabled and the provider is not [WyrdNullAIProvider].
func is_active() -> bool:
	return _enabled and _provider != null and not (_provider is WyrdNullAIProvider)


func kinds() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(WyrdAIRequest.KINDS)
	return copy


func request(kind: StringName, packet: Dictionary, constraints: Dictionary = {}, path: StringName = &"") -> int:
	if not _known(kind):
		push_warning("WyrdAI.request: unknown kind %s" % String(kind))
		_trace_request(0, kind, path, &"refused", &"kind")
		return 0
	if not _enabled:
		_trace_request(0, kind, path, &"refused", &"off")
		return 0
	if _provider == null or _provider is WyrdNullAIProvider:
		_trace_request(0, kind, path, &"refused", &"null")
		return 0
	var request_id := _next_id
	_next_id += 1
	var req := WyrdAIRequest.new()
	req.id = request_id
	req.kind = kind
	req.packet = packet.duplicate(true)
	req.constraints = constraints.duplicate(true)
	req.locale = StringName(TranslationServer.get_locale())
	req.path = path
	req.set_deliver(Callable(self, &"deliver"))
	_pending[request_id] = req
	_trace_request(request_id, kind, path, &"sent", &"-")
	_provider.request(req)
	return request_id


func deliver(request_id: int, result: WyrdAIResult) -> bool:
	var off_thread := OS.get_thread_caller_id() != OS.get_main_thread_id()
	var req := _pending.get(request_id) as WyrdAIRequest
	var kind := "-"
	var path := ""
	if req != null:
		kind = String(req.kind)
		path = String(req.path)
	var ok := result != null and result.ok
	if off_thread:
		push_error("WyrdAI.deliver: not on the main thread")
		_trace_result(request_id, kind, path, ok, "thread")
		return false
	if req == null:
		_trace_result(request_id, "-", "", ok, "unknown_request")
		return false
	_pending.erase(request_id)
	_trace_result(request_id, kind, path, ok, "-")
	return true


func cancel(request_id: int) -> bool:
	if not _pending.has(request_id):
		return false
	var req := _pending[request_id] as WyrdAIRequest
	_pending.erase(request_id)
	if _provider != null:
		_provider.cancel(request_id)
	_trace_cancel(req, &"host")
	return true


func pending_count() -> int:
	return _pending.size()


func set_provider(next: WyrdAIProvider) -> void:
	if next == null:
		push_error("WyrdAI.set_provider: provider is null")
		return
	drop_pending(&"provider")
	_provider = next
	_trace_provider()


## Drops every pending request. [code]new_game[/code] and [code]load[/code] also reset the id counter.
func drop_pending(reason: StringName) -> void:
	var ids: Array = _pending.keys()
	ids.sort()
	var current := _provider
	for raw in ids:
		var request_id := int(raw)
		var req := _pending[request_id] as WyrdAIRequest
		_pending.erase(request_id)
		if current != null:
			current.cancel(request_id)
		_trace_cancel(req, reason)
	if reason == &"new_game" or reason == &"load":
		_next_id = 1


func _known(kind: StringName) -> bool:
	for name in WyrdAIRequest.KINDS:
		if name == kind:
			return true
	return false


func _trace_provider() -> void:
	if _runtime == null:
		return
	var state := "on" if is_active() else "off"
	_runtime.trace_ai_provider(String(provider_id()), state)


func _trace_request(request_id: int, kind: StringName, path: StringName, state: StringName, reason: StringName) -> void:
	if _runtime == null:
		return
	_runtime.trace_ai_request(request_id, String(kind), String(path), String(state), String(reason))


func _trace_result(request_id: int, kind: String, path: String, ok: bool, rule: String) -> void:
	if _runtime == null:
		return
	_runtime.trace_ai_result(request_id, kind, path, ok, rule)


func _trace_cancel(req: WyrdAIRequest, reason: StringName) -> void:
	if _runtime == null or req == null:
		return
	_runtime.trace_ai_cancel(req.id, String(req.kind), String(req.path), String(reason))
