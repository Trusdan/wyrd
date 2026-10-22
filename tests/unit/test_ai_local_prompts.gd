extends GutTest

const _Prompts := preload("res://example/ai/wyrd_local_prompts.gd")
const _Provider := preload("res://example/ai/wyrd_local_provider.gd")

const _SYSTEM := "You rewrite short text for a video game. Use only what the user message gives you. Do not add names, places, people, facts or events. Keep every name exactly as written. Write plain text on one line, with no line breaks and none of these characters: { } # [ ] < >. Answer with JSON only, in the form {\"text\": \"...\"}."

const _RAW := ["ent_bram", "ent_nia", "ent_dock", "gate_state", "heard_bell", "dock_guard", "night.watch", "shut_gate", "unknown_person", "unknown_place"]


func test_check_url_accepts_loopback_and_refuses_the_rest() -> void:
	var accepted := [
		["http://127.0.0.1:8080", "http://127.0.0.1:8080"],
		["http://localhost:8081", "http://localhost:8081"],
		["HTTP://LOCALHOST", "http://localhost"],
		["http://127.0.0.1:8080/", "http://127.0.0.1:8080"],
		["http://127.0.0.1:8080/v1", "http://127.0.0.1:8080"],
		["http://127.0.0.1:8080/v1/", "http://127.0.0.1:8080"],
		["http://localhost", "http://localhost"],
		["http://127.0.0.1:1", "http://127.0.0.1:1"],
		["http://127.0.0.1:65535", "http://127.0.0.1:65535"],
	]
	for row in accepted:
		var checked: Dictionary = _Provider.check_url(String(row[0]))
		assert_true(bool(checked["ok"]), String(row[0]))
		assert_eq(str(checked["base"]), String(row[1]))
		assert_eq(str(checked["reason"]), "")
	var refused := [
		["https://127.0.0.1:8080", "bad_url"],
		["ftp://localhost", "bad_url"],
		["", "bad_url"],
		["http://example.com", "not_loopback"],
		["http://127.0.0.2", "not_loopback"],
		["http://0.0.0.0:8080", "not_loopback"],
		["http://[::1]:8080", "not_loopback"],
		["http://127.0.0.1@example.com", "not_loopback"],
		["http://user:pw@localhost:8080", "not_loopback"],
		["http://127.0.0.1.example.com", "not_loopback"],
		["http://localhost.example", "not_loopback"],
		["http://127.0.0.1:0", "bad_url"],
		["http://127.0.0.1:99999", "bad_url"],
		["http://127.0.0.1:80a", "bad_url"],
		["http://127.0.0.1:8080/api", "bad_url"],
		["http://127.0.0.1:8080/?x=1", "bad_url"],
		["http://127.0.0.1:8080#x", "bad_url"],
	]
	for row in refused:
		var checked: Dictionary = _Provider.check_url(String(row[0]))
		assert_false(bool(checked["ok"]), String(row[0]))
		assert_eq(str(checked["reason"]), String(row[1]), String(row[0]))
		assert_eq(str(checked["base"]), "")


func test_check_model_refuses_a_cloud_name() -> void:
	assert_eq(_Provider.check_model("gemma3:cloud"), "cloud_model")
	assert_eq(_Provider.check_model("gpt-oss:120b-cloud"), "cloud_model")
	assert_eq(_Provider.check_model("CLOUDY"), "cloud_model")
	assert_eq(_Provider.check_model("smollm2:360m-instruct-q4_K_M"), "")


func test_set_base_url_keeps_the_previous_base_when_refused() -> void:
	var runtime := WyrdRuntime.new()
	runtime.trace.enabled = true
	var provider = _Provider.new()
	provider.bind_trace(runtime)
	assert_true(provider.set_base_url("HTTP://LOCALHOST:8081/v1"))
	assert_eq(provider.base_url, "http://localhost:8081")
	assert_eq(_rows(runtime, "ai_local").size(), 0)
	assert_false(provider.set_base_url("http://example.com"))
	assert_eq(provider.base_url, "http://localhost:8081")
	var refused: Dictionary = _rows(runtime, "ai_local")[0]
	assert_eq(str(refused["op"]), "refused")
	assert_eq(str(refused["reason"]), "not_loopback")
	assert_eq(str(refused["id"]), "-")
	assert_eq(str(refused["key"]), "-")
	assert_eq(str(refused["path"]), "-")


func test_identity_and_two_models_do_not_share_a_cache_key() -> void:
	var provider = _Provider.new()
	assert_eq(String(provider.id()), "local:smollm2-360m-instruct-q4_k_m")
	assert_eq(provider.prompt_version(), 1)
	assert_eq(provider.locales(), PackedStringArray(["en"]))
	var runtime := WyrdRuntime.new()
	var packet := _bark_packet()
	provider.model = "smollm2-360m-instruct-q4_k_m"
	runtime.register_adapter(WyrdAIProvider, provider)
	var first := runtime.ai.cache_key(&"bark_paraphrase", packet)
	var other = _Provider.new()
	other.model = "other-model"
	runtime.register_adapter(WyrdAIProvider, other)
	var second := runtime.ai.cache_key(&"bark_paraphrase", packet)
	assert_ne(first, second)
	assert_eq(String(other.id()), "local:other-model")


func test_each_kind_has_the_fixed_prompt() -> void:
	assert_eq(_Prompts.system_text(), _SYSTEM)
	assert_eq(_Prompts.PROMPT_VERSION, 1)
	var bark: Dictionary = _bark_packet()
	var gossip: Dictionary = _gossip_packet()
	var journal: Dictionary = _journal_packet()
	var epilogue: Dictionary = _epilogue_packet()
	var spoken: Dictionary = _tts_packet()
	assert_eq(_Prompts.char_cap(&"bark_paraphrase", bark, {}), 34)
	assert_eq(_Prompts.char_cap(&"journal_summary", journal, {}), 116)
	assert_eq(_Prompts.char_cap(&"epilogue_stitch", epilogue, {}), 34)
	assert_eq(_Prompts.user_message(&"bark_paraphrase", bark, {}), _BARK)
	assert_eq(_Prompts.user_message(&"gossip", gossip, {}), _GOSSIP)
	assert_eq(_Prompts.user_message(&"journal_summary", journal, {}), _JOURNAL)
	assert_eq(_Prompts.user_message(&"epilogue_stitch", epilogue, {}), _EPILOGUE)
	assert_eq(_Prompts.user_message(&"tts_prep", spoken, {}), _TTS)
	assert_eq(_Prompts.user_message(&"poem", bark, {}), "")
	var messages: PackedStringArray = PackedStringArray([
		_SYSTEM,
		_BARK,
		_GOSSIP,
		_JOURNAL,
		_EPILOGUE,
		_TTS,
	])
	for message in messages:
		for raw in _RAW:
			assert_false(message.contains(raw), raw)


func test_char_cap_matches_the_validator() -> void:
	var runtime := WyrdRuntime.new()
	var packets := [
		[&"bark_paraphrase", _bark_packet()],
		[&"gossip", _gossip_packet()],
		[&"journal_summary", _journal_packet()],
		[&"epilogue_stitch", _epilogue_packet()],
		[&"tts_prep", _tts_packet()],
	]
	for row in packets:
		var kind: StringName = row[0]
		var packet: Dictionary = row[1]
		var cap := _Prompts.char_cap(kind, packet, {})
		assert_eq(runtime.ai.validate("a".repeat(cap), kind, packet, {}), StringName(""))
		assert_eq(runtime.ai.validate("a".repeat(cap + 1), kind, packet, {}), &"limits")
		var limited := {"max_chars": 10}
		var small := _Prompts.char_cap(kind, packet, limited)
		assert_eq(small, 10)
		assert_eq(runtime.ai.validate("a".repeat(small), kind, packet, limited), StringName(""))
		assert_eq(runtime.ai.validate("a".repeat(small + 1), kind, packet, limited), &"limits")


func test_seed_and_body_are_stable() -> void:
	assert_eq(_Prompts.seed_for("0123456789abcdef"), int("89abcdef".hex_to_int()) & 0x7FFFFFFF)
	assert_eq(_Prompts.seed_for("0123456789abcdef"), _Prompts.seed_for("0123456789abcdef"))
	assert_eq(_Prompts.seed_for("00000000ffffffff"), 0x7FFFFFFF)
	assert_eq(_Prompts.seed_for("0000000080000000"), 0)
	assert_eq(_Prompts.seed_for("abcd"), 0)
	assert_eq(_Prompts.seed_for(""), 0)
	assert_eq(_Prompts.seed_for("0123456789abcdeg"), 0)
	var req := WyrdAIRequest.new()
	req.kind = &"tts_prep"
	req.packet = _tts_packet()
	req.constraints = {}
	req.key = "0123456789abcdef"
	var built: Dictionary = _Prompts.body(req, "smollm2-360m-instruct-q4_k_m")
	assert_false(bool(built["stream"]))
	assert_true(is_equal_approx(float(built["temperature"]), 0.7))
	assert_eq(int(built["seed"]), _Prompts.seed_for(req.key))
	var cap := _Prompts.char_cap(req.kind, req.packet, req.constraints)
	assert_eq(int(built["max_tokens"]), int(ceili(float(cap) / 3.0)) + 16)
	var schema: Dictionary = built["response_format"]["json_schema"]["schema"]
	assert_eq(int(schema["properties"]["text"]["maxLength"]), cap)
	assert_eq(str(built["response_format"]["type"]), "json_schema")
	assert_true(bool(built["response_format"]["json_schema"]["strict"]))
	assert_eq(str(built["messages"][0]["content"]), _SYSTEM)
	assert_eq(str(built["messages"][1]["content"]), _TTS)


func test_parse_reply_keeps_the_text_and_names_the_failure() -> void:
	var valid: Dictionary = _Prompts.parse_reply(WyrdFakeLocalServer.chat_reply("  The gate.  "))
	assert_true(bool(valid["ok"]))
	assert_eq(str(valid["text"]), "  The gate.  ")
	assert_eq(str(valid["error"]), "")
	for bad in ["nope", "{}", "{\"choices\":[]}", "{\"choices\":[{\"message\":{\"content\":1}}]}"]:
		var parsed: Dictionary = _Prompts.parse_reply(bad)
		assert_false(bool(parsed["ok"]), bad)
		assert_eq(str(parsed["error"]), "parse", bad)
	var schema: Dictionary = _Prompts.parse_reply(WyrdFakeLocalServer.chat_content("{\"nope\":1}"))
	assert_false(bool(schema["ok"]))
	assert_eq(str(schema["error"]), "schema")
	var number: Dictionary = _Prompts.parse_reply(WyrdFakeLocalServer.chat_content("{\"text\":2}"))
	assert_eq(str(number["error"]), "schema")


func _bark_packet() -> Dictionary:
	return {
		"entities": [
			{"id": "ent_bram", "name": "Bram"},
			{"id": "ent_dock", "name": "Dock"},
			{"id": "ent_nia", "name": "Nia"},
		],
		"facts": {
			"gate_state": "ent_bram",
			"heard_bell": true,
		},
		"kind": "bark_paraphrase",
		"line_ids": ["gate"],
		"speaker": {"id": "ent_bram", "name": "Bram", "roles": ["dock_guard", "night.watch"]},
		"text": "The gate is shut.",
		"v": 1,
	}


func _gossip_packet() -> Dictionary:
	var packet := _bark_packet()
	packet["kind"] = "gossip"
	packet["deeds"] = [
		{"actor": "ent_bram", "how": "heard", "place": "ent_dock", "target": "ent_nia", "verb": "shut_gate"},
		{"actor": "unknown_person", "how": "saw", "place": "unknown_place", "target": "", "verb": "spoke"},
	]
	return packet


func _journal_packet() -> Dictionary:
	return {
		"entities": [
			{"id": "ent_bram", "name": "Bram"},
			{"id": "ent_nia", "name": "Nia"},
		],
		"entries": ["Bram shut the gate.", "Nia heard the bell.", "The lane is quiet."],
		"kind": "journal_summary",
		"line_ids": ["j1", "j2", "j3"],
		"quest": "toll",
		"text": "Bram shut the gate.\nNia heard the bell.\nThe lane is quiet.",
		"v": 1,
	}


func _epilogue_packet() -> Dictionary:
	return {
		"entities": [],
		"entries": ["The harbor slept.", "The bell was quiet.", "Dawn came."],
		"facts": {},
		"kind": "epilogue_stitch",
		"line_ids": [],
		"text": "The harbor slept.",
		"v": 1,
	}


func _tts_packet() -> Dictionary:
	return {
		"entities": [],
		"facts": {},
		"kind": "tts_prep",
		"line_ids": [],
		"text": "The harbor slept.",
		"v": 1,
	}


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			rows.append(event)
	return rows


const _BARK := "Task: say this line again in different words, with the same meaning and tone.\nSpeaker: Bram, dock guard, night watch\nWhat the listener knows:\n- gate state: Bram\n- heard bell: yes\nLine: The gate is shut.\nKeep it to at most 34 characters."

const _GOSSIP := "Task: say this line again as one piece of local gossip. You may mention one of the deeds below. Mention nothing else.\nSpeaker: Bram, dock guard, night watch\nDeeds the listener knows, newest first:\n- Bram shut gate Nia at Dock (heard)\n- someone spoke (saw)\nWhat the listener knows:\n- gate state: Bram\n- heard bell: yes\nLine: The gate is shut.\nKeep it to at most 34 characters."

const _JOURNAL := "Task: write one short story-so-far paragraph from these journal entries. Keep their order. Add nothing.\nEntries:\n1. Bram shut the gate.\n2. Nia heard the bell.\n3. The lane is quiet.\nKeep it to at most 116 characters."

const _EPILOGUE := "Task: join these passages into one short passage. Keep their order and meaning. Add nothing.\nPassages:\n1. The harbor slept.\n2. The bell was quiet.\n3. Dawn came.\nKeep it to at most 34 characters."

const _TTS := "Task: rewrite this text so it reads aloud clearly. Spell out numbers and symbols and expand abbreviations. Change nothing else.\nText: The harbor slept.\nKeep it to at most 34 characters."
