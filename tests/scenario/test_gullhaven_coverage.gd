extends GutTest

## Every 1.0 feature the coverage list names is in Gullhaven, or in the side pack for was:.


const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _GULLHAVEN := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _NEXT := "res://example/versions/gullhaven_next/harbor_next.wyrdmanifest.tres"

const _FEATURES: Array[Dictionary] = [
	{"id": "facts_stored", "file": "example/content/gullhaven/facts.wyrd", "pattern": "stored"},
	{"id": "facts_resolved", "file": "example/content/gullhaven/facts.wyrd", "pattern": "source:"},
	{"id": "facts_pattern", "file": "example/content/gullhaven/facts.wyrd", "pattern": "\\{id\\}"},
	{"id": "facts_recap", "file": "example/content/gullhaven/facts.wyrd", "pattern": "recap:"},
	{"id": "facts_invalidate", "file": "example/content/gullhaven/facts.wyrd", "pattern": "invalidate:"},
	{"id": "events_leaves_decays", "file": "example/content/gullhaven/facts.wyrd", "pattern": "leaves:.*decays"},
	{"id": "events_on", "file": "example/content/gullhaven/bell_repair.wyrd", "pattern": "on mechanism_state"},
	{"id": "sequence_region", "file": "example/content/gullhaven/bell_repair.wyrd", "pattern": "region "},
	{"id": "sequence_within", "file": "example/content/gullhaven/bell_repair.wyrd", "pattern": "within "},
	{"id": "slot_live", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "mode: live"},
	{"id": "slot_locked_at", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "locked_at\\("},
	{"id": "slot_cast", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "mode: cast\\("},
	{"id": "slot_barred", "file": "example/content/gullhaven/harbor_guild.wyrd", "pattern": "factor\\.barred"},
	{"id": "slot_unwilling", "file": "example/content/gullhaven/harbor_guild.wyrd", "pattern": "factor\\.unwilling"},
	{"id": "slot_hostile", "file": "example/content/gullhaven/harbor_guild.wyrd", "pattern": "factor\\.hostile"},
	{"id": "slot_empty", "file": "example/content/gullhaven/harbor_guild.wyrd", "pattern": "factor\\.empty"},
	{"id": "slot_successor", "file": "example/content/gullhaven/harbor_guild.wyrd", "pattern": "factor\\.successor"},
	{"id": "slot_default", "file": "example/content/gullhaven/harbor_guild.wyrd", "pattern": "factor\\.default"},
	{"id": "slot_contested", "file": "example/content/gullhaven/harbor_guild.wyrd", "pattern": "reeve\\.contested"},
	{"id": "slot_locked_gone", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "ferry\\.locked_gone"},
	{"id": "quest_on_empty", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "on_empty:"},
	{"id": "quest_requires", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "requires:"},
	{"id": "quest_start_when", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "start when"},
	{"id": "quest_waits_until", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "waits_until"},
	{"id": "quest_journal", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "journal:"},
	{"id": "outcome_route_closed", "file": "example/content/gullhaven/harbor_guild.wyrd", "pattern": "outcome petition = route_closed"},
	{"id": "outcome_done", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "outcome crossing = done"},
	{"id": "outcome_failed", "file": "example/content/gullhaven/harbor_guild.wyrd", "pattern": "outcome petition = failed"},
	{"id": "scene_on_abort", "file": "example/content/gullhaven/harbor_scenes.wyrd", "pattern": "on_abort:"},
	{"id": "scene_on_fail", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "on_fail"},
	{"id": "scene_show_disabled_when", "file": "example/content/gullhaven/harbor_scenes.wyrd", "pattern": "show_disabled_when"},
	{"id": "scene_goto", "file": "example/content/gullhaven/harbor_scenes.wyrd", "pattern": "-> scene"},
	{"id": "storylet_priority", "file": "example/content/gullhaven/harbor_storylets.wyrd", "pattern": "priority:"},
	{"id": "storylet_weight", "file": "example/content/gullhaven/harbor_storylets.wyrd", "pattern": "weight:"},
	{"id": "storylet_cooldown", "file": "example/content/gullhaven/harbor_storylets.wyrd", "pattern": "cooldown:"},
	{"id": "topic_unlock", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "unlock topic"},
	{"id": "topic_lock", "file": "example/content/gullhaven/dock_rumour.wyrd", "pattern": "lock topic"},
	{"id": "bark_speaker_cooldown", "file": "example/content/gullhaven/harbor_storylets.wyrd", "pattern": "speaker_cooldown:"},
	{"id": "succession_none", "file": "example/content/gullhaven/harbor_roles.wyrd", "pattern": "succession: none"},
	{"id": "succession_relation", "file": "example/content/gullhaven/harbor_roles.wyrd", "pattern": "succession: relation"},
	{"id": "succession_faction_assigns", "file": "example/content/gullhaven/harbor_roles.wyrd", "pattern": "succession: faction_assigns"},
	{"id": "succession_election", "file": "example/content/gullhaven/harbor_roles.wyrd", "pattern": "succession: election"},
	{"id": "succession_host_decides", "file": "example/content/gullhaven/harbor_roles.wyrd", "pattern": "succession: host_decides"},
	{"id": "vacancy_hold", "file": "example/content/gullhaven/harbor_roles.wyrd", "pattern": "vacancy: hold"},
	{"id": "vacancy_abolish", "file": "example/content/gullhaven/harbor_roles.wyrd", "pattern": "vacancy: abolish"},
	{"id": "role_scope", "file": "example/content/gullhaven/harbor_roles.wyrd", "pattern": "scope:"},
	{"id": "role_eligibility", "file": "example/content/gullhaven/harbor_roles.wyrd", "pattern": "eligibility:"},
	{"id": "role_default_holder", "file": "example/content/gullhaven/harbor_roles.wyrd", "pattern": "default_holder:"},
	{"id": "role_secret", "file": "example/content/gullhaven/harbor_roles.wyrd", "pattern": "visibility: secret"},
	{"id": "deed_record", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "record deed"},
	{"id": "deed_witnesses", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "witnesses:"},
	{"id": "deed_memorable", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "memorable:"},
	{"id": "deed_count", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "deed_count"},
	{"id": "adjust_baseline", "file": "example/content/gullhaven/harbor_scenes.wyrd", "pattern": "adjust baseline"},
	{"id": "effect_believe", "file": "example/content/gullhaven/harbor_tale.wyrd", "pattern": "~ believe"},
	{"id": "effect_declare", "file": "example/content/gullhaven/harbor_tale.wyrd", "pattern": "~ declare"},
	{"id": "deed_statement", "file": "example/content/gullhaven/harbor_tale.wyrd", "pattern": "statement:"},
	{"id": "storylet_secrecy", "file": "example/content/gullhaven/harbor_storylets.wyrd", "pattern": "secrecy:"},
	{"id": "document_claim", "file": "example/content/gullhaven/harbor_gazette.wyrd", "pattern": "claim "},
	{"id": "document_live", "file": "example/content/gullhaven/harbor_documents.wyrd", "pattern": "text: live"},
	{"id": "document_frozen", "file": "example/content/gullhaven/harbor_documents.wyrd", "pattern": "text: frozen"},
	{"id": "document_create", "file": "example/content/gullhaven/harbor_documents.wyrd", "pattern": "create document"},
	{"id": "document_publishes_by", "file": "example/content/gullhaven/harbor_gazette.wyrd", "pattern": "publishes_by"},
	{"id": "document_every", "file": "example/content/gullhaven/harbor_gazette.wyrd", "pattern": "every"},
	{"id": "document_delay", "file": "example/content/gullhaven/harbor_gazette.wyrd", "pattern": "delay"},
	{"id": "template_tier", "file": "example/content/gullhaven/harbor_templates.wyrd", "pattern": "tier:"},
	{"id": "template_on_deed", "file": "example/content/gullhaven/harbor_templates.wyrd", "pattern": "on_deed"},
	{"id": "template_expires", "file": "example/content/gullhaven/harbor_templates.wyrd", "pattern": "expires:"},
	{"id": "template_param", "file": "example/content/gullhaven/harbor_templates.wyrd", "pattern": "param "},
	{"id": "effect_start_quest", "file": "example/content/gullhaven/harbor_scenes.wyrd", "pattern": "start quest"},
	{"id": "effect_advance", "file": "example/content/gullhaven/harbor_scenes.wyrd", "pattern": "advance "},
	{"id": "effect_assign_role", "file": "example/content/gullhaven/harbor_scenes.wyrd", "pattern": "assign role"},
	{"id": "effect_vacate_role", "file": "example/content/gullhaven/dock_errand.wyrd", "pattern": "vacate role"},
	{"id": "check_on_fail", "file": "example/content/gullhaven/dock_crate.wyrd", "pattern": "check strength\\(.*\\) on_fail"},
	{"id": "do_command", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "~ do "},
	{"id": "ai_tag", "file": "example/content/gullhaven/dock_scenes.wyrd", "pattern": "#tag:ai"},
	{"id": "ai_context", "file": "example/content/gullhaven/harbor_storylets.wyrd", "pattern": "ai_context:"},
	{"id": "was_alias", "file": "example/versions/gullhaven_next/ferry_toll.wyrd", "pattern": "was:"},
]

const _ADAPTERS: Array[Dictionary] = [
	{"id": "world", "file": "example/content/gullhaven/facts.wyrd", "pattern": "source: world.is_alive"},
	{"id": "inventory", "file": "example/content/gullhaven/harbor_templates.wyrd", "pattern": "owner_of\\("},
	{"id": "spatial", "file": "example/content/gullhaven/harbor_storylets.wyrd", "pattern": "nearby\\("},
	{"id": "time", "file": "example/content/gullhaven/facts.wyrd", "pattern": "source: time.season"},
	{"id": "action", "file": "example/content/gullhaven/ferry_toll.wyrd", "pattern": "~ do post_notice"},
	{"id": "skill", "file": "example/content/gullhaven/dock_crate.wyrd", "pattern": "check strength"},
	{"id": "election", "file": "example/content/gullhaven/harbor_roles.wyrd", "pattern": "succession: election"},
]

## Words in WyrdKeywords.groups() that Gullhaven's non-comment text does not use.
const _LEDGER := {
	"allow_protected": "res://tests/golden/statements/st_template.wyrd",
	"await_host": "res://tests/golden/statements/st_await_host.wyrd",
	"beat": "res://tests/golden/statements/st_quest.wyrd",
	"disabled_when": "res://tests/scenario/pack/sample.wyrd",
	"float": "res://tests/golden/statements/st_effects.wyrd",
	"forget": "res://tests/golden/statements/st_knowledge.wyrd",
	"fragment": "res://tests/golden/statements/st_publish.wyrd",
	"learn": "res://tests/golden/statements/st_knowledge.wyrd",
	"max_active": "res://tests/golden/statements/st_template.wyrd",
	"meta": "res://tests/golden/statements/st_documents.wyrd",
	"on_missing_stage": "res://tests/migration/packs/stage_new.wyrd",
	"on_read": "res://tests/golden/statements/st_documents.wyrd",
	"ordered": "res://tests/golden/statements/st_err_sequence.wyrd",
	"redirect": "res://tests/golden/statements/st_quest.wyrd",
	"retract": "res://tests/golden/statements/st_effects.wyrd",
	"slant": "res://tests/migration/packs/notice_old.wyrd",
	"unbelieve": "res://tests/golden/statements/st_effects.wyrd",
}


func test_features_are_in_the_manifest_and_the_file() -> void:
	var gullhaven := FileAccess.get_file_as_string(_GULLHAVEN)
	var side := FileAccess.get_file_as_string(_NEXT)
	for feature in _FEATURES:
		var id := String(feature["id"])
		var path := String(feature["file"])
		var manifest := side if id == "was_alias" else gullhaven
		assert_true(manifest.contains("res://%s" % path), id)
		var where := _matching_line(path, String(feature["pattern"]))
		assert_false(where.is_empty(), id)
		if where.is_empty():
			continue
		assert_gt(int(where["line"]), 0, "%s %s" % [id, path])


func test_adapters_gullhaven_reaches() -> void:
	for adapter in _ADAPTERS:
		var id := String(adapter["id"])
		var where := _matching_line(String(adapter["file"]), String(adapter["pattern"]))
		assert_false(where.is_empty(), id)
	var provider := FileAccess.get_file_as_string("res://example/ai/wyrd_local_provider.gd")
	assert_true(provider.contains("extends WyrdAIProvider"))
	var tagged := _matching_line("example/content/gullhaven/dock_scenes.wyrd", "#tag:ai")
	assert_false(tagged.is_empty(), "ai_provider")


func test_keyword_ledger_covers_words_gullhaven_does_not_use() -> void:
	var text := _gullhaven_text()
	var groups: Dictionary = WyrdKeywords.groups()
	for group in groups.keys():
		for word in groups[group]:
			var token := String(word)
			if _has_word(text, token):
				continue
			assert_true(_LEDGER.has(token), "%s %s" % [String(group), token])
			var path := String(_LEDGER[token])
			assert_true(path.begins_with("res://tests/"), token)
			assert_true(FileAccess.file_exists(path), token)
			var body := _code_text(path)
			assert_true(_has_word(body, token), "%s in %s" % [token, path])


func test_check_strict_baseline_on_both_manifests() -> void:
	_assert_baseline(_GULLHAVEN)
	_assert_baseline(_NEXT)


func test_example_files_start_with_the_example_header() -> void:
	_walk_headers("res://example")


func test_hostile_factor_reaches_the_journal() -> void:
	var opened: Dictionary = _Harness.new().boot_gullhaven(true)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"net_mender", &"person", "net mender", PackedStringArray(), true)
	runtime.roles.assign(&"harbor_factor", &"net_mender")
	runtime.social.set_baseline(&"net_mender", &"player", &"affinity", -80.0)
	runtime.deeds.record(&"asked_guild", &"player", &"", &"gullhaven")
	runtime.tick(0)
	assert_eq(runtime.quests.stage("harbor_guild"), "petition")
	assert_eq(String(runtime.roles.slot_state(&"factor", "harbor_guild")), "hostile")
	var found := false
	for entry in runtime.quests.journal("harbor_guild"):
		if String(entry["id"]) == "j_guild_hostile":
			found = true
	assert_true(found, "j_guild_hostile")


func test_booting_gullhaven_without_host_decides_reports_the_error() -> void:
	var runtime := WyrdRuntime.new()
	runtime.register_adapter(WyrdElectionAdapter, preload("res://example/playtest/harbor_election.gd").new())
	var report := runtime.load_content(load(_GULLHAVEN) as WyrdContentManifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	assert_push_error("WyrdRoles: host_decides has no callback")
	assert_engine_error_count(0)


func _assert_baseline(path: String) -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["check", "--strict", "--manifest", path]))
	var output := String(result["output"])
	var warnings := 0
	var errors := 0
	var storylet := 0
	var template := 0
	for line in output.split("\n"):
		if line.contains("warning[W_CLAIM]"):
			warnings += 1
			assert_true(line.contains("harbor_tale.wyrd:42:41"), line)
		elif line.contains("warning[") or line.contains("error["):
			assert_true(false, "%s %s" % [path, line])
			errors += 1
		elif line.contains("info[I_STORYLET_SCORE]"):
			storylet += 1
		elif line.contains("info[I_TEMPLATE_SCORE]"):
			template += 1
		elif line.contains("info["):
			assert_true(false, "%s %s" % [path, line])
	assert_eq(warnings, 1, output)
	assert_eq(errors, 0, output)
	assert_eq(storylet, 8, path)
	assert_eq(template, 7, path)


func _matching_line(path: String, pattern: String) -> Dictionary:
	var expr := RegEx.new()
	if expr.compile(pattern) != OK:
		return {}
	var number := 0
	for line in FileAccess.get_file_as_string("res://%s" % path).split("\n"):
		number += 1
		var code := _strip_comment(line)
		if code.strip_edges().is_empty():
			continue
		if expr.search(code) != null:
			return {"line": number, "text": code}
	return {}


func _gullhaven_text() -> String:
	var parts := PackedStringArray()
	var dir := DirAccess.open("res://example/content/gullhaven")
	assert_not_null(dir)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".wyrd"):
			parts.append(_code_text("res://example/content/gullhaven/%s" % entry))
		entry = dir.get_next()
	dir.list_dir_end()
	return "\n".join(parts)


func _code_text(path: String) -> String:
	var parts := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var code := _strip_comment(line)
		if not code.strip_edges().is_empty():
			parts.append(code)
	return "\n".join(parts)


func _strip_comment(line: String) -> String:
	var mark := line.find("//")
	if mark >= 0:
		return line.substr(0, mark)
	return line


func _has_word(text: String, word: String) -> bool:
	var expr := RegEx.new()
	assert_eq(expr.compile("(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % word), OK)
	return expr.search(text) != null


func _walk_headers(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	assert_not_null(dir, dir_path)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk_headers(path)
		elif entry.ends_with(".wyrd") or entry.ends_with(".gd"):
			var first := FileAccess.get_file_as_string(path).split("\n")[0]
			assert_true(first.contains("[EXAMPLE CONTENT]"), path)
		entry = dir.get_next()
	dir.list_dir_end()
