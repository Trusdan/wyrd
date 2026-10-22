extends GutTest

## Drives [WyrdAIValidator] directly. Spoiler skips that depend on the world
## go through [method WyrdAI.validate], which builds that list.

func test_limits_accepts_a_plain_paraphrase() -> void:
	var checker := _checker()
	assert_eq(String(checker.check("The gate is shut tonight.", &"bark_paraphrase", {"text": "The gate is shut."})), "")


func test_limits_rejects_empty_and_over_cap() -> void:
	var checker := _checker()
	assert_eq(String(checker.check("", &"bark_paraphrase", {})), "limits")
	assert_eq(String(checker.check("   ", &"bark_paraphrase", {})), "limits")
	assert_eq(String(checker.check(_letters(241), &"bark_paraphrase", {})), "limits")
	assert_eq(String(checker.check(_letters(240), &"bark_paraphrase", {})), "")
	var doubled := {"text": "hello"}
	assert_eq(String(checker.check(_letters(11), &"bark_paraphrase", doubled)), "limits")
	assert_eq(String(checker.check(_letters(10), &"bark_paraphrase", doubled)), "")
	var capped := {"text": "hello"}
	assert_eq(String(checker.check(_letters(6), &"bark_paraphrase", capped, {"max_chars": 5})), "limits")
	assert_eq(String(checker.check(_letters(5), &"bark_paraphrase", capped, {"max_chars": 5})), "")
	assert_eq(String(checker.check(_letters(241), &"bark_paraphrase", {}, {"max_chars": 500})), "limits")
	assert_eq(String(checker.check(_letters(240), &"bark_paraphrase", {}, {"max_chars": 500})), "")


func test_limits_rejects_controls_and_marks() -> void:
	var checker := _checker()
	assert_eq(String(checker.check("one\ntwo", &"bark_paraphrase", {})), "limits")
	assert_eq(String(checker.check("one\rtwo", &"bark_paraphrase", {})), "limits")
	assert_eq(String(checker.check("a%sb" % String.chr(1), &"bark_paraphrase", {})), "limits")
	assert_eq(String(checker.check("a%sb" % String.chr(0x200B), &"bark_paraphrase", {})), "limits")
	for mark in ["{", "}", "#", "[", "]", "<", ">"]:
		assert_eq(String(checker.check("a%sb" % mark, &"bark_paraphrase", {})), "limits", mark)


func test_names_rule() -> void:
	var checker := _checker()
	checker.entity_names = {"Bram": ["ferry_master"], "lane": ["lane"]}
	var outside := {"entities": [], "text": "The book is in the shed."}
	assert_eq(String(checker.check("Bram waits here.", &"bark_paraphrase", outside)), "names")
	var inside := {"entities": [{"id": "ferry_master", "name": "Bram"}], "text": "The book is in the shed."}
	assert_eq(String(checker.check("Bram waits here.", &"bark_paraphrase", inside)), "")
	assert_eq(String(checker.check("bram waits here.", &"bark_paraphrase", outside)), "")
	assert_eq(String(checker.check("Bramble grows here.", &"bark_paraphrase", outside)), "")
	assert_eq(String(checker.check("the lane is quiet.", &"bark_paraphrase", outside)), "")


func test_banned_rule() -> void:
	var checker := _checker()
	checker.banned_terms = PackedStringArray(["", "Toll", "cut line"])
	assert_eq(String(checker.check("The toll is paid.", &"bark_paraphrase", {})), "banned")
	assert_eq(String(checker.check("The TOLL is paid.", &"bark_paraphrase", {})), "banned")
	assert_eq(String(checker.check("the cut line frays.", &"bark_paraphrase", {})), "banned")
	assert_eq(String(checker.check("The tollhouse is shut.", &"bark_paraphrase", {})), "")
	assert_eq(String(checker.check("a cutline holds.", &"bark_paraphrase", {})), "")


func test_spoiler_rule_matches_a_form() -> void:
	var checker := _checker()
	checker.spoilers = PackedStringArray(["hidden_bell"])
	assert_eq(String(checker.check("a hidden_bell sits.", &"bark_paraphrase", {})), "spoiler")
	assert_eq(String(checker.check("The gate is shut.", &"bark_paraphrase", {})), "")


func test_spoiler_list_skips_known_packet_and_secrecy() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	runtime.facts.set_in(&"harbor.toll_fate", "hidden_bell", &"world")
	assert_eq(String(runtime.ai.validate("a hidden_bell sits.", &"bark_paraphrase", {"facts": {}})), "spoiler")
	runtime.facts.set_in(&"harbor.toll_fate", "cut_line", &"world")
	assert_eq(String(runtime.ai.validate("the cut line frays.", &"bark_paraphrase", {"facts": {}})), "spoiler")
	runtime.facts.set_in(&"harbor.gazette", "ferry_master", &"world")
	var named := {"entities": [{"id": "ferry_master", "name": "Bram"}], "facts": {}}
	assert_eq(String(runtime.ai.validate("Bram waved once.", &"bark_paraphrase", named)), "spoiler")
	runtime.facts.set_in(&"harbor.toll_fate", "hidden_bell", &"world")
	runtime.facts.set_in(&"harbor.toll_fate", "hidden_bell", &"known/player")
	assert_eq(String(runtime.ai.validate("a hidden_bell sits.", &"bark_paraphrase", {"facts": {}})), "")
	runtime.facts.clear_in(&"harbor.toll_fate", &"known/player")
	var packed := {"facts": {"harbor.toll_fate": "other_fate"}}
	assert_eq(String(runtime.ai.validate("a hidden_bell sits.", &"bark_paraphrase", packed)), "")
	runtime.facts.set_in(&"player.clearance", "sealed_name", &"world")
	assert_eq(String(runtime.ai.validate("sealed_name holds.", &"bark_paraphrase", {"facts": {}})), "")
	assert_eq(String(runtime.ai.validate("the tide_clerk waits.", &"bark_paraphrase", {"facts": {}})), "spoiler")
	runtime.roles.tell(&"tide_clerk", &"player")
	assert_eq(String(runtime.ai.validate("the tide_clerk waits.", &"bark_paraphrase", {"facts": {}})), "")
	assert_false(host.world.display_name(&"ferry_master").is_empty())


func test_classifier_rule() -> void:
	var checker := _checker()
	var hook := _Hook.new()
	checker.classifier = Callable(hook, &"judge")
	checker.classifier_registered = true
	hook.result = true
	var packet := {"text": "The gate is shut."}
	assert_eq(String(checker.check("The gate is shut tonight.", &"bark_paraphrase", packet)), "")
	assert_eq(str(packet["text"]), "The gate is shut.")
	hook.result = false
	assert_eq(String(checker.check("The gate is shut tonight.", &"bark_paraphrase", packet)), "classifier")
	hook.result = 1
	assert_eq(String(checker.check("The gate is shut tonight.", &"bark_paraphrase", packet)), "classifier")
	hook.free()
	assert_eq(String(checker.check("The gate is shut tonight.", &"bark_paraphrase", packet)), "classifier")
	checker.classifier_registered = false
	assert_eq(String(checker.check("The gate is shut tonight.", &"bark_paraphrase", packet)), "")


func test_first_failing_rule_wins() -> void:
	var checker := _checker()
	checker.entity_names = {"Bram": ["ferry_master"]}
	checker.banned_terms = PackedStringArray(["shut"])
	checker.spoilers = PackedStringArray(["hidden_bell"])
	checker.classifier_registered = true
	checker.classifier = Callable(self, &"_reject")
	assert_eq(String(checker.check("{Bram is shut.", &"bark_paraphrase", {})), "limits")
	assert_eq(String(checker.check("Bram is shut.", &"bark_paraphrase", {})), "names")
	assert_eq(String(checker.check("the gate is shut.", &"bark_paraphrase", {})), "banned")
	assert_eq(String(checker.check("a hidden_bell sits.", &"bark_paraphrase", {})), "spoiler")
	assert_eq(String(checker.check("The gate is open.", &"bark_paraphrase", {})), "classifier")


func _reject(_text: String, _kind: StringName, _packet: Dictionary) -> bool:
	return false


func _checker() -> WyrdAIValidator:
	return WyrdAIValidator.new()


func _letters(count: int) -> String:
	var text := ""
	for _i in count:
		text += "a"
	return text


func _boot() -> Dictionary:
	var body := """// [EXAMPLE CONTENT]
language 1

facts
  player.clearance : symbol stored
  harbor.toll_fate : symbol stored
  harbor.gazette : symbol stored

role tide_clerk
  visibility: secret
"""
	var path := "user://wyrd_m10_validator.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10validator"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	return {"host": host, "runtime": runtime}


class _Hook extends Node:
	var result: Variant = true

	func judge(_text: String, _kind: StringName, packet: Dictionary) -> Variant:
		packet["text"] = "mutated"
		return result
