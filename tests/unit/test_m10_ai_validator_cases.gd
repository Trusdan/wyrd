extends GutTest

const _Exit := preload("res://tests/scenario/m10_gullhaven.gd")


func test_each_rule_accepts_and_rejects_on_a_gullhaven_packet() -> void:
	var opened := _Exit.new().boot("echo")
	var runtime: WyrdRuntime = opened["runtime"]
	var packet := runtime.ai.packet_for_line("a_leave", &"bark_paraphrase", &"")
	var authored := str(packet["text"])
	assert_eq(authored, "The boat leaves the dock.")
	_pair(runtime, packet, &"limits", authored, "")
	_pair(runtime, packet, &"names", authored, "Bram waits.")
	runtime.config().ai_banned_terms = PackedStringArray(["skiff"])
	_pair(runtime, packet, &"banned", authored, "The skiff sank.")
	runtime.config().ai_banned_terms = PackedStringArray()
	_pair(runtime, packet, &"spoiler", authored, "a hidden_bell sits.")
	runtime.ai.register_classifier(Callable(self, &"_allow"))
	assert_eq(runtime.ai.validate(authored, &"bark_paraphrase", packet), &"")
	runtime.ai.register_classifier(Callable(self, &"_reject"))
	assert_eq(runtime.ai.validate(authored, &"bark_paraphrase", packet), &"classifier")
	runtime.ai.register_classifier(Callable())


func _pair(runtime: WyrdRuntime, packet: Dictionary, rule: StringName, accepted: String, rejected: String) -> void:
	assert_eq(runtime.ai.validate(accepted, &"bark_paraphrase", packet), &"", String(rule))
	assert_eq(runtime.ai.validate(rejected, &"bark_paraphrase", packet), rule, String(rule))


func _allow(_text: String, _kind: StringName, _packet: Dictionary) -> bool:
	return true


func _reject(_text: String, _kind: StringName, _packet: Dictionary) -> bool:
	return false
