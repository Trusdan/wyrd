class_name WyrdAI
extends RefCounted

## AI hook for one runtime. Not saved.
##
## @experimental
## The null provider is the default. A request keeps no pending state while that
## provider is active, or while the hook is disabled. [method deliver] closes a
## pending request, validates the text, and discards it. Nothing in this release
## shows or caches a result. [method packet_for_line] builds a packet without sending.

var _runtime: WyrdRuntime
var _provider: WyrdAIProvider
var _enabled: bool = true
var _next_id: int = 1
var _pending: Dictionary = {}
var _classifier: Callable = Callable()
var _classifier_set: bool = false


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
	var rule := "provider"
	if result != null and result.ok:
		rule = String(validate(result.text, req.kind, req.packet, req.constraints))
		if rule.is_empty():
			rule = "-"
	_trace_validate(request_id, kind, path, rule == "-", rule)
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


## Packet for an opted-in line. Does not send a request, and ignores the provider and the on/off state.
func packet_for_line(line_id: String, kind: StringName = &"bark_paraphrase", speaker: StringName = &"") -> Dictionary:
	return WyrdAIPacket.for_line(_runtime, line_id, kind, speaker)


## First failing rule, or an empty name when [param text] passes.
func validate(text: String, kind: StringName, packet: Dictionary, constraints: Dictionary = {}) -> StringName:
	var checker := WyrdAIValidator.new()
	checker.classifier = _classifier
	checker.classifier_registered = _classifier_set
	if _runtime != null and _runtime.config() != null:
		checker.banned_terms = _runtime.config().ai_banned_terms.duplicate()
	checker.entity_names = _entity_names()
	checker.spoilers = _spoilers(packet)
	return checker.check(text, kind, packet, constraints)


## One classifier per runtime. [code]Callable()[/code] clears it. Not saved.
## It survives [method WyrdRuntime.start_new_game] and [method WyrdRuntime.load_state].
func register_classifier(fn: Callable) -> void:
	if not fn.is_valid():
		_classifier = Callable()
		_classifier_set = false
		_trace_classifier("clear")
		return
	_classifier = fn
	_classifier_set = true
	_trace_classifier("set")


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


func _trace_validate(request_id: int, kind: String, path: String, ok: bool, rule: String) -> void:
	if _runtime == null:
		return
	_runtime.trace_ai_validate(request_id, kind, path, ok, rule)


func _trace_classifier(state: String) -> void:
	if _runtime == null:
		return
	_runtime.trace_ai_classifier(state)


func _entity_names() -> Dictionary:
	var names := {}
	var world := _world()
	if world == null:
		return names
	for id in world.candidates(WyrdEntityFilter.new()):
		var shown := world.display_name(StringName(str(id)))
		if shown.is_empty():
			continue
		if not names.has(shown):
			names[shown] = []
		(names[shown] as Array).append(String(id))
	return names


func _spoilers(packet: Dictionary) -> PackedStringArray:
	var found := {}
	if _runtime == null or _runtime.facts == null:
		return _sorted_forms(found)
	var listed: Dictionary = {}
	var raw_facts: Variant = packet.get("facts", {})
	if raw_facts is Dictionary:
		listed = raw_facts
	var secrecy := ""
	if _runtime.config() != null:
		secrecy = _runtime.config().secrecy_fact
	var world := _world()
	for key in _runtime.facts.world_keys():
		if listed.has(key) or key == secrecy:
			continue
		var world_value: Variant = _runtime.facts.get_in(StringName(key), &"world")
		var known_value: Variant = _runtime.facts.get_in(StringName(key), &"known/player")
		if known_value != null and _same_value(known_value, world_value):
			continue
		if not (world_value is String or world_value is StringName):
			continue
		var text := String(world_value)
		_add_form(found, text)
		_add_form(found, text.replace("_", " "))
		if world != null and world.exists(StringName(text)):
			_add_form(found, world.display_name(StringName(text)))
	_add_secret_roles(found)
	return _sorted_forms(found)


func _add_secret_roles(found: Dictionary) -> void:
	if _runtime == null or _runtime.content() == null or _runtime.roles == null:
		return
	var ids: Array = _runtime.content().roles.keys()
	ids.sort()
	for id in ids:
		var role := _runtime.content().roles[id] as WyrdRoleDef
		if role == null or role.visibility != "secret":
			continue
		var key := "role.%s.holder" % role.id
		if _runtime.roles.revealed(&"player", StringName(key)):
			continue
		_add_form(found, role.id)
		_add_form(found, role.id.replace("_", " "))


func _add_form(found: Dictionary, form: String) -> void:
	var text := form.strip_edges()
	if text.length() < 3 or found.has(text):
		return
	found[text] = true


func _sorted_forms(found: Dictionary) -> PackedStringArray:
	var names: Array = found.keys()
	names.sort()
	var out := PackedStringArray()
	for name in names:
		out.append(String(name))
	return out


func _same_value(left: Variant, right: Variant) -> bool:
	if left == right:
		return true
	if (left is String or left is StringName) and (right is String or right is StringName):
		return String(left) == String(right)
	return false


func _world() -> WyrdWorldAdapter:
	if _runtime == null:
		return null
	var found := _runtime.adapter(WyrdWorldAdapter)
	if found is WyrdWorldAdapter:
		return found as WyrdWorldAdapter
	return null
