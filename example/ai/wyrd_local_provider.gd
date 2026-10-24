# [EXAMPLE CONTENT] Reference local AI provider. An invented fishing village, not a host game.
extends WyrdAIProvider

## Reference provider for an OpenAI-compatible server on this machine.
## Loopback only. No API key, no auth header, no redirects.
## The host adds [WyrdLocalTransport] to the tree and calls [method attach].

const _Prompts := preload("res://example/ai/wyrd_local_prompts.gd")

var base_url: String = "http://127.0.0.1:8080"
var model: String = "smollm2-360m-instruct-q4_k_m"
var timeout_s: float = 10.0
var locales_list: PackedStringArray = PackedStringArray(["en"])

var _transport: Node
var _runtime_ref: WeakRef
var _open: Dictionary = {}
var _probe_done: Callable = Callable()


func id() -> StringName:
	return StringName("local:" + model)


func prompt_version() -> int:
	return _Prompts.PROMPT_VERSION


func locales() -> PackedStringArray:
	return locales_list.duplicate()


func bind_trace(runtime: WyrdRuntime) -> void:
	if runtime == null:
		_runtime_ref = null
		return
	_runtime_ref = weakref(runtime)


func attach(transport: Node) -> void:
	_transport = transport
	if transport == null:
		return
	if transport.has_signal("finished") and not transport.is_connected("finished", Callable(self, &"_on_http")):
		transport.connect("finished", Callable(self, &"_on_http"))
	if transport.has_signal("probe_finished") and not transport.is_connected("probe_finished", Callable(self, &"_on_probe")):
		transport.connect("probe_finished", Callable(self, &"_on_probe"))


## Stores the normalised base when the URL is allowed. A refusal keeps the previous base.
func set_base_url(url: String) -> bool:
	var checked := check_url(url)
	if not bool(checked.get("ok", false)):
		_log_refused("-", str(checked.get("reason", "bad_url")), "-", "-")
		return false
	base_url = str(checked.get("base", ""))
	return true


func request(req: WyrdAIRequest) -> void:
	var checked := check_url(base_url)
	if not bool(checked.get("ok", false)):
		_refuse(req, str(checked.get("reason", "bad_url")))
		return
	var model_reason := check_model(model)
	if not model_reason.is_empty():
		_refuse(req, model_reason)
		return
	if not _transport_ready():
		_refuse(req, "no_transport")
		return
	if _Prompts.user_message(req.kind, req.packet, req.constraints).is_empty():
		var refused := WyrdAIResult.new()
		refused.ok = false
		refused.error = "kind"
		req.reply(refused)
		return
	var endpoint := str(checked.get("base", "")) + "/v1/chat/completions"
	var payload := JSON.stringify(_Prompts.body(req, model), "", true)
	_open[req.id] = req
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var err: Error = _transport.call("send", req.id, endpoint, headers, payload, timeout_s)
	if err != OK:
		_open.erase(req.id)
		_fail(req, "connect")


func cancel(request_id: int) -> void:
	_open.erase(request_id)
	if _transport != null and is_instance_valid(_transport) and _transport.has_method("cancel"):
		_transport.call("cancel", request_id)


## Not a Wyrd request. [param on_done] is [code](ok: bool, reason: String)[/code].
func probe(on_done: Callable) -> void:
	_probe_done = Callable()
	var checked := check_url(base_url)
	if not bool(checked.get("ok", false)):
		var reason := str(checked.get("reason", "bad_url"))
		_log_refused("-", reason, "-", "-")
		on_done.call(false, reason)
		return
	var model_reason := check_model(model)
	if not model_reason.is_empty():
		_log_refused("-", model_reason, "-", "-")
		on_done.call(false, model_reason)
		return
	if not _transport_ready():
		_log_refused("-", "no_transport", "-", "-")
		on_done.call(false, "no_transport")
		return
	_probe_done = on_done
	var endpoint := str(checked.get("base", "")) + "/v1/models"
	var err: Error = _transport.call("probe", endpoint, timeout_s)
	if err != OK:
		_probe_done = Callable()
		_log_probe(false, "connect")
		on_done.call(false, "connect")


static func check_url(url: String) -> Dictionary:
	var scheme_at := url.to_lower().find("://")
	if scheme_at < 0:
		return _url_fail("bad_url", "")
	var scheme := url.to_lower().substr(0, scheme_at)
	if scheme != "http":
		return _url_fail("bad_url", "")
	var rest := url.substr(scheme_at + 3)
	var auth_end := rest.length()
	for i in rest.length():
		var mark := rest.unicode_at(i)
		if mark == 47 or mark == 63 or mark == 35:
			auth_end = i
			break
	var authority := rest.substr(0, auth_end)
	var tail := rest.substr(auth_end)
	if authority.is_empty():
		return _url_fail("bad_url", "")
	if authority.find("@") >= 0:
		return _url_fail("not_loopback", "")
	var host := ""
	var port := -1
	if authority.begins_with("["):
		var bracket := authority.find("]")
		var shown := authority
		if bracket > 1:
			shown = authority.substr(1, bracket - 1)
		return _url_fail("not_loopback", shown.to_lower())
	var colon := authority.rfind(":")
	if colon >= 0:
		host = authority.substr(0, colon)
		var port_text := authority.substr(colon + 1)
		if port_text.is_empty() or not _digits(port_text):
			return _url_fail("bad_url", host.to_lower())
		port = int(port_text)
		if port < 1 or port > 65535:
			return _url_fail("bad_url", host.to_lower())
	else:
		host = authority
	host = host.to_lower()
	if host.is_empty():
		return _url_fail("bad_url", "")
	if host != "127.0.0.1" and host != "localhost":
		return _url_fail("not_loopback", host)
	if tail.find("?") >= 0 or tail.find("#") >= 0:
		return _url_fail("bad_url", host)
	if tail != "" and tail != "/" and tail != "/v1" and tail != "/v1/":
		return _url_fail("bad_url", host)
	var base := "http://%s" % host
	if port >= 0:
		base += ":%d" % port
	return {"base": base, "host": host, "ok": true, "reason": ""}


## [code]cloud_model[/code] when the name could be forwarded to a hosted service.
static func check_model(name: String) -> String:
	if name.to_lower().contains("cloud"):
		return "cloud_model"
	return ""


func _on_http(id: int, result: int, status: int, body: PackedByteArray) -> void:
	if not _open.has(id):
		return
	var req := _open[id] as WyrdAIRequest
	_open.erase(id)
	if req == null:
		return
	var outcome := _classify(result, status, body, false)
	if bool(outcome.get("ok", false)):
		var reply := WyrdAIResult.new()
		reply.ok = true
		reply.text = str(outcome.get("text", ""))
		req.reply(reply)
		return
	_fail(req, str(outcome.get("error", "connect")))


func _on_probe(result: int, status: int, body: PackedByteArray) -> void:
	var done := _probe_done
	_probe_done = Callable()
	if not done.is_valid():
		return
	var outcome := _classify(result, status, body, true)
	var ok := bool(outcome.get("ok", false))
	var reason := "-" if ok else str(outcome.get("error", "connect"))
	_log_probe(ok, reason)
	done.call(ok, reason)


func _classify(result: int, status: int, body: PackedByteArray, for_probe: bool) -> Dictionary:
	if result == HTTPRequest.RESULT_TIMEOUT:
		return {"error": "timeout", "ok": false}
	if result == HTTPRequest.RESULT_CANT_CONNECT or result == HTTPRequest.RESULT_CANT_RESOLVE or result == HTTPRequest.RESULT_CONNECTION_ERROR or result == HTTPRequest.RESULT_NO_RESPONSE:
		return {"error": "connect", "ok": false}
	if result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED or (status >= 300 and status < 400):
		return {"error": "redirect", "ok": false}
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return {"error": "too_large", "ok": false}
	if result == HTTPRequest.RESULT_SUCCESS and status == 200:
		var text := body.get_string_from_utf8()
		if for_probe:
			var parsed := JSON.new()
			if parsed.parse(text) != OK:
				return {"error": "parse", "ok": false}
			return {"error": "-", "ok": true}
		var reply: Dictionary = _Prompts.parse_reply(text)
		if bool(reply.get("ok", false)):
			return {"ok": true, "text": str(reply.get("text", ""))}
		return {"error": str(reply.get("error", "parse")), "ok": false}
	if status >= 100 and status != 200:
		return {"error": "http_%d" % status, "ok": false}
	return {"error": "connect", "ok": false}


func _refuse(req: WyrdAIRequest, reason: String) -> void:
	_log_refused(str(req.id), reason, _or_dash(req.key), _or_dash(String(req.path)))
	var result := WyrdAIResult.new()
	result.ok = false
	result.error = reason
	req.reply(result)


func _fail(req: WyrdAIRequest, reason: String) -> void:
	_log_error(str(req.id), reason, _or_dash(req.key), _or_dash(String(req.path)))
	var result := WyrdAIResult.new()
	result.ok = false
	result.error = reason
	req.reply(result)


func _transport_ready() -> bool:
	return _transport != null and is_instance_valid(_transport) and _transport.is_inside_tree() and _transport.has_method("send")


func _log_refused(id_text: String, reason: String, key: String, path: String) -> void:
	_log("wyrd ai_local op=refused id=%s reason=%s key=%s path=%s" % [id_text, reason, key, path], {
		"id": id_text,
		"key": key,
		"op": "refused",
		"path": path,
		"reason": reason,
	})


func _log_error(id_text: String, reason: String, key: String, path: String) -> void:
	_log("wyrd ai_local op=error id=%s reason=%s key=%s path=%s" % [id_text, reason, key, path], {
		"id": id_text,
		"key": key,
		"op": "error",
		"path": path,
		"reason": reason,
	})


func _log_probe(ok: bool, reason: String) -> void:
	var flag := "true" if ok else "false"
	_log("wyrd ai_local op=probe ok=%s reason=%s" % [flag, reason], {
		"ok": flag,
		"op": "probe",
		"reason": reason,
	})


func _log(line: String, fields: Dictionary) -> void:
	if _runtime_ref == null:
		return
	var runtime := _runtime_ref.get_ref() as WyrdRuntime
	if runtime == null or runtime.trace == null or not runtime.trace.enabled:
		return
	runtime.trace_add("ai_local", fields)
	print(line)


static func _url_fail(reason: String, host: String) -> Dictionary:
	return {"base": "", "host": host, "ok": false, "reason": reason}


static func _digits(text: String) -> bool:
	if text.is_empty():
		return false
	for i in text.length():
		var code := text.unicode_at(i)
		if code < 48 or code > 57:
			return false
	return true


static func _or_dash(text: String) -> String:
	if text.is_empty():
		return "-"
	return text
