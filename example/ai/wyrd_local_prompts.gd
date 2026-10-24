# [EXAMPLE CONTENT] Reference local AI prompts. An invented fishing village, not a host game.
extends RefCounted

## Fixed prompts for the reference local provider. Prompt version 1.
## Pure functions: no node and no network. The strings below are the prompts.

const PROMPT_VERSION := 1

const SYSTEM := "You rewrite short text for a video game. Use only what the user message gives you. Do not add names, places, people, facts or events. Keep every name exactly as written. Write plain text on one line, with no line breaks and none of these characters: { } # [ ] < >. Answer with JSON only, in the form {\"text\": \"...\"}."


static func system_text() -> String:
	return SYSTEM


## 240, then an int max_chars of at least 1, then twice a non-empty fallback.
static func char_cap(kind: StringName, packet: Dictionary, constraints: Dictionary) -> int:
	var cap := 240
	var max_chars: Variant = constraints.get("max_chars", null)
	if typeof(max_chars) == TYPE_INT and int(max_chars) >= 1:
		cap = mini(cap, int(max_chars))
	var fallback := WyrdAIPacket.fallback_text(kind, packet)
	if not fallback.is_empty():
		cap = mini(cap, fallback.length() * 2)
	return cap


## Last 8 hex digits of a 16-digit key, masked to 31 bits. Any other key is 0.
static func seed_for(key: String) -> int:
	if key.length() != 16:
		return 0
	for i in key.length():
		var code := key.unicode_at(i)
		var digit := code >= 48 and code <= 57
		var lower := code >= 97 and code <= 102
		var upper := code >= 65 and code <= 70
		if not digit and not lower and not upper:
			return 0
	return int(key.substr(8, 8).hex_to_int()) & 0x7FFFFFFF


## Empty when [param kind] is not one of the five. [method WyrdLocalProvider.request] then refuses it.
static func user_message(kind: StringName, packet: Dictionary, constraints: Dictionary) -> String:
	var cap := char_cap(kind, packet, constraints)
	var lines: Array[String] = []
	match kind:
		&"bark_paraphrase":
			_bark(lines, packet, cap, "Task: say this line again in different words, with the same meaning and tone.", false)
		&"gossip":
			_bark(lines, packet, cap, "Task: say this line again as one piece of local gossip. You may mention one of the deeds below. Mention nothing else.", true)
		&"journal_summary":
			lines.append("Task: write one short story-so-far paragraph from these journal entries. Keep their order. Add nothing.")
			lines.append("Entries:")
			_numbered(lines, _string_entries(packet.get("entries", null)))
			lines.append("Keep it to at most %d characters." % cap)
		&"epilogue_stitch":
			lines.append("Task: join these passages into one short passage. Keep their order and meaning. Add nothing.")
			lines.append("Passages:")
			var passages := _string_entries(packet.get("entries", null))
			if passages.is_empty():
				lines.append("1. %s" % str(packet.get("text", "")))
			else:
				_numbered(lines, passages)
			lines.append("Keep it to at most %d characters." % cap)
		&"tts_prep":
			lines.append("Task: rewrite this text so it reads aloud clearly. Spell out numbers and symbols and expand abbreviations. Change nothing else.")
			lines.append("Text: %s" % str(packet.get("text", "")))
			lines.append("Keep it to at most %d characters." % cap)
		_:
			return ""
	return _join(lines)


static func body(req: WyrdAIRequest, model: String) -> Dictionary:
	var cap := char_cap(req.kind, req.packet, req.constraints)
	return {
		"max_tokens": int(ceili(float(cap) / 3.0)) + 16,
		"messages": [
			{"content": SYSTEM, "role": "system"},
			{"content": user_message(req.kind, req.packet, req.constraints), "role": "user"},
		],
		"model": model,
		"response_format": {
			"json_schema": {
				"name": "wyrd_text",
				"schema": {
					"additionalProperties": false,
					"properties": {
						"text": {
							"maxLength": cap,
							"minLength": 1,
							"type": "string",
						},
					},
					"required": ["text"],
					"type": "object",
				},
				"strict": true,
			},
			"type": "json_schema",
		},
		"seed": seed_for(req.key),
		"stream": false,
		"temperature": 0.7,
	}


## [code]ok[/code] only when [code]choices[0].message.content[/code] is JSON with a string [code]text[/code].
## The text is returned unchanged.
static func parse_reply(text: String) -> Dictionary:
	var outer := JSON.new()
	if outer.parse(text) != OK or typeof(outer.data) != TYPE_DICTIONARY:
		return {"error": "parse", "ok": false, "text": ""}
	var choices: Variant = (outer.data as Dictionary).get("choices", null)
	if typeof(choices) != TYPE_ARRAY or (choices as Array).is_empty():
		return {"error": "parse", "ok": false, "text": ""}
	var choice: Variant = (choices as Array)[0]
	if typeof(choice) != TYPE_DICTIONARY:
		return {"error": "parse", "ok": false, "text": ""}
	var message: Variant = (choice as Dictionary).get("message", null)
	if typeof(message) != TYPE_DICTIONARY:
		return {"error": "parse", "ok": false, "text": ""}
	var content: Variant = (message as Dictionary).get("content", null)
	if typeof(content) != TYPE_STRING:
		return {"error": "parse", "ok": false, "text": ""}
	var inner := JSON.new()
	if inner.parse(String(content)) != OK:
		return {"error": "parse", "ok": false, "text": ""}
	if typeof(inner.data) != TYPE_DICTIONARY:
		return {"error": "schema", "ok": false, "text": ""}
	var reply: Variant = (inner.data as Dictionary).get("text", null)
	if typeof(reply) != TYPE_STRING:
		return {"error": "schema", "ok": false, "text": ""}
	return {"error": "", "ok": true, "text": String(reply)}


static func _bark(lines: Array[String], packet: Dictionary, cap: int, task: String, with_deeds: bool) -> void:
	lines.append(task)
	var speaker: Variant = packet.get("speaker", null)
	if speaker is Dictionary:
		var name := str((speaker as Dictionary).get("name", ""))
		if not name.is_empty():
			var bits := name
			var roles: Variant = (speaker as Dictionary).get("roles", [])
			if roles is Array:
				for role in roles:
					var words := _words(str(role))
					if not words.is_empty():
						bits += ", " + words
			lines.append("Speaker: " + bits)
	var entities := _entities(packet)
	if with_deeds:
		var deeds: Variant = packet.get("deeds", [])
		if deeds is Array and not (deeds as Array).is_empty():
			lines.append("Deeds the listener knows, newest first:")
			for deed in deeds:
				if deed is Dictionary:
					lines.append(_deed_line(deed, entities))
	var facts: Variant = packet.get("facts", {})
	if facts is Dictionary and not (facts as Dictionary).is_empty():
		lines.append("What the listener knows:")
		for key in (facts as Dictionary).keys():
			lines.append("- %s: %s" % [_words(str(key)), _fact_value((facts as Dictionary)[key], entities)])
	lines.append("Line: %s" % str(packet.get("text", "")))
	lines.append("Keep it to at most %d characters." % cap)


static func _deed_line(deed: Dictionary, entities: Array) -> String:
	var actor := _lookup(entities, str(deed.get("actor", "")))
	if actor.is_empty():
		actor = "someone"
	var line := "- %s %s" % [actor, _words(str(deed.get("verb", "")))]
	var target := _lookup(entities, str(deed.get("target", "")))
	if not target.is_empty():
		line += " " + target
	var place := _lookup(entities, str(deed.get("place", "")))
	if not place.is_empty():
		line += " at " + place
	line += " (%s)" % str(deed.get("how", ""))
	return line


static func _fact_value(value: Variant, entities: Array) -> String:
	if typeof(value) == TYPE_BOOL:
		return "yes" if value else "no"
	if value is String or value is StringName:
		var text := str(value)
		var name := _lookup(entities, text)
		if not name.is_empty():
			return name
		return text
	return str(value)


static func _lookup(entities: Array, id: String) -> String:
	if id.is_empty():
		return ""
	for row in entities:
		if row is Dictionary and str((row as Dictionary).get("id", "")) == id:
			return str((row as Dictionary).get("name", ""))
	return ""


static func _entities(packet: Dictionary) -> Array:
	var raw: Variant = packet.get("entities", [])
	if raw is Array:
		return raw
	return []


static func _string_entries(raw: Variant) -> Array[String]:
	var found: Array[String] = []
	if not (raw is Array) or (raw as Array).is_empty():
		return found
	for item in raw:
		if typeof(item) != TYPE_STRING:
			var none: Array[String] = []
			return none
		found.append(String(item))
	return found


static func _join(lines: Array) -> String:
	var packed := PackedStringArray()
	for line in lines:
		packed.append(str(line))
	return "\n".join(packed)


static func _numbered(lines: Array[String], entries: Array[String]) -> void:
	var n := 1
	for item in entries:
		lines.append("%d. %s" % [n, item])
		n += 1


static func _words(text: String) -> String:
	return text.replace("_", " ").replace(".", " ")
