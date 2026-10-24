# [EXAMPLE CONTENT] Reference local AI transport. An invented fishing village, not a host game.
extends Node

## One HTTPRequest per open call. The provider cannot own scene-tree nodes.
## Redirects are not followed. Nothing here adds an auth header.

signal finished(id: int, result: int, status: int, body: PackedByteArray)
signal probe_finished(result: int, status: int, body: PackedByteArray)

var _nodes: Dictionary = {}
var _probe: HTTPRequest


func send(id: int, url: String, headers: PackedStringArray, payload: String, timeout_s: float) -> Error:
	var http := _make(timeout_s)
	http.name = "LocalAIRequest%d" % id
	add_child(http)
	_nodes[id] = http
	http.request_completed.connect(_on_request.bind(id))
	var err := http.request(url, headers, HTTPClient.METHOD_POST, payload)
	if err != OK:
		_drop(id)
	return err


func probe(url: String, timeout_s: float) -> Error:
	_drop_probe()
	var http := _make(timeout_s)
	http.name = "LocalAIProbe"
	add_child(http)
	_probe = http
	http.request_completed.connect(_on_probe)
	var err := http.request(url, PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET, "")
	if err != OK:
		_drop_probe()
	return err


func cancel(id: int) -> void:
	_drop(id)


func _make(timeout_s: float) -> HTTPRequest:
	var http := HTTPRequest.new()
	http.timeout = timeout_s
	http.max_redirects = 0
	http.body_size_limit = 65536
	http.use_threads = false
	http.accept_gzip = false
	return http


func _drop(id: int) -> void:
	if not _nodes.has(id):
		return
	var http := _nodes[id] as HTTPRequest
	_nodes.erase(id)
	_free_http(http)


func _drop_probe() -> void:
	var http := _probe
	_probe = null
	_free_http(http)


func _free_http(http: HTTPRequest) -> void:
	if http == null or not is_instance_valid(http):
		return
	http.cancel_request()
	if is_instance_valid(http):
		http.queue_free()


func _on_request(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray, id: int) -> void:
	if not _nodes.has(id):
		return
	var http := _nodes[id] as HTTPRequest
	_nodes.erase(id)
	if http != null and is_instance_valid(http):
		http.queue_free()
	finished.emit(id, result, status, body)


func _on_probe(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _probe == null:
		return
	var http := _probe
	_probe = null
	if http != null and is_instance_valid(http):
		http.queue_free()
	probe_finished.emit(result, status, body)
