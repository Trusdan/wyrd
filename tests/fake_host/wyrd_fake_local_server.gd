class_name WyrdFakeLocalServer
extends Node

## Loopback HTTP/1.1 server for the reference provider's real HTTPRequest path.
## Tests push [member replies]; an empty queue answers with [method chat_reply].

var requests: Array[Dictionary] = []
var replies: Array[Dictionary] = []
var connections: int = 0
var auto_text: String = "Noted."
var port: int = 0

var _server := TCPServer.new()
var _clients: Array[Dictionary] = []


func start() -> int:
	if _server.is_listening():
		_server.stop()
	var err := _server.listen(0, "127.0.0.1")
	if err == OK:
		port = _server.get_local_port()
		if port > 0:
			return port
		_server.stop()
	for candidate in range(18080, 18180):
		err = _server.listen(candidate, "127.0.0.1")
		if err == OK:
			port = candidate
			return port
	port = 0
	return 0


func stop() -> void:
	for client in _clients:
		var peer: StreamPeerTCP = client.get("peer")
		if peer != null:
			peer.disconnect_from_host()
	_clients.clear()
	if _server.is_listening():
		_server.stop()


func live_connections() -> int:
	var count := 0
	for client in _clients:
		var peer: StreamPeerTCP = client.get("peer")
		if peer == null:
			continue
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			count += 1
	return count


static func chat_reply(text: String) -> String:
	var content := JSON.stringify({"text": text})
	return JSON.stringify({
		"choices": [{"message": {"content": content, "role": "assistant"}}],
	})


static func chat_content(content: String) -> String:
	return JSON.stringify({
		"choices": [{"message": {"content": content, "role": "assistant"}}],
	})


static func models_reply() -> String:
	return JSON.stringify({"data": [], "object": "list"})


func _process(_delta: float) -> void:
	_accept()
	var index := 0
	while index < _clients.size():
		if _service(_clients[index]):
			_clients.remove_at(index)
			continue
		index += 1


func _accept() -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer == null:
			return
		connections += 1
		_clients.append({
			"buf": PackedByteArray(),
			"peer": peer,
			"silent": false,
		})


func _service(client: Dictionary) -> bool:
	var peer: StreamPeerTCP = client["peer"]
	peer.poll()
	var peer_status := peer.get_status()
	if bool(client["silent"]):
		return peer_status != StreamPeerTCP.STATUS_CONNECTED
	if peer_status != StreamPeerTCP.STATUS_CONNECTED:
		if peer_status == StreamPeerTCP.STATUS_CONNECTING:
			return false
		return true
	var available := peer.get_available_bytes()
	if available > 0:
		var got: Array = peer.get_data(available)
		if int(got[0]) == OK:
			var buf: PackedByteArray = client["buf"]
			buf.append_array(got[1])
			client["buf"] = buf
	var buf: PackedByteArray = client["buf"]
	var split := _header_end(buf)
	if split < 0:
		return peer.get_status() != StreamPeerTCP.STATUS_CONNECTED
	var header := buf.slice(0, split).get_string_from_utf8()
	var length := _content_length(header)
	var body_from := split + 4
	if buf.size() < body_from + length:
		return peer.get_status() != StreamPeerTCP.STATUS_CONNECTED
	var body := buf.slice(body_from, body_from + length).get_string_from_utf8()
	requests.append(_describe(header, body))
	var reply := _next_reply()
	var mode := str(reply.get("mode", "reply"))
	if mode == "silent":
		client["silent"] = true
		return false
	if mode == "close":
		peer.disconnect_from_host()
		return true
	var status := int(reply.get("status", 200))
	var payload := str(reply.get("body", ""))
	var location := ""
	if mode == "redirect":
		status = 302
		location = str(reply.get("location", _other_port()))
		if payload.is_empty():
			payload = "{}"
	_send(peer, status, payload, location)
	peer.disconnect_from_host()
	return true


func _next_reply() -> Dictionary:
	if replies.is_empty():
		return {"body": chat_reply(auto_text), "mode": "reply", "status": 200}
	var next: Dictionary = replies[0]
	replies.remove_at(0)
	return next


func _other_port() -> String:
	var port := _server.get_local_port() + 1
	if port > 65535:
		port = _server.get_local_port() - 1
	return "http://127.0.0.1:%d/v1/chat/completions" % port


func _send(peer: StreamPeerTCP, status: int, payload: String, location: String) -> void:
	var reason := "OK"
	if status == 302:
		reason = "Found"
	elif status >= 400:
		reason = "Error"
	var bytes := payload.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n" % [status, reason, bytes.size()]
	if not location.is_empty():
		head += "Location: %s\r\n" % location
	head += "\r\n"
	peer.put_data(head.to_utf8_buffer())
	if not bytes.is_empty():
		peer.put_data(bytes)


func _describe(header: String, body: String) -> Dictionary:
	var lines := header.split("\r\n")
	var parts := lines[0].split(" ", false, 2)
	var method := parts[0] if parts.size() > 0 else ""
	var path := parts[1] if parts.size() > 1 else ""
	var headers := {}
	for i in range(1, lines.size()):
		var line := lines[i]
		var colon := line.find(":")
		if colon < 0:
			continue
		headers[line.substr(0, colon).strip_edges().to_lower()] = line.substr(colon + 1).strip_edges()
	return {"body": body, "headers": headers, "method": method, "path": path}


func _header_end(buf: PackedByteArray) -> int:
	if buf.size() < 4:
		return -1
	for i in buf.size() - 3:
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


func _content_length(header: String) -> int:
	for line in header.split("\r\n"):
		var lower := line.to_lower()
		if not lower.begins_with("content-length:"):
			continue
		var text := line.substr(line.find(":") + 1).strip_edges()
		if text.is_valid_int():
			return int(text)
		return 0
	return 0
