extends GutTest

## Freeze marks, scene_started, and the facade relays.


const STABLE_MEMBERS := {
	"Wyrd": {
		"path": "res://addons/wyrd/runtime/wyrd.gd",
		"covered": true,
		"methods": ["get_version", "configure", "register_adapter", "register_function", "register_disposition_formula", "start_new_game", "load_content", "tick", "can_save", "save_state", "load_state", "invalidate_world", "invalidate_groups", "deeds_known_to"],
		"signals": ["line_ready", "choices_ready", "scene_started", "scene_ended", "bark_ready", "quest_state_changed", "stage_changed", "outcome_changed", "journal_entry_added", "topic_unlocked", "role_holder_changed", "role_vacant", "election_needed", "deed_recorded", "fact_changed", "content_unavailable", "document_read", "load_report_ready"],
		"properties": ["facts", "events", "deeds", "roles", "topics", "documents", "quests", "dialogue", "generator", "ai"],
	},
	"WyrdFactStore": {
		"path": "res://addons/wyrd/runtime/facts/wyrd_fact_store.gd",
		"covered": true,
		"methods": ["set_in", "invalidate"],
		"signals": ["fact_changed"],
		"properties": [],
	},
	"WyrdEvents": {
		"path": "res://addons/wyrd/runtime/wyrd_events.gd",
		"covered": true,
		"methods": ["emit", "begin_batch", "end_batch"],
		"signals": [],
		"properties": [],
	},
	"WyrdDeedLog": {
		"path": "res://addons/wyrd/runtime/deeds/wyrd_deed_log.gd",
		"covered": true,
		"methods": ["record"],
		"signals": ["deed_recorded"],
		"properties": [],
	},
	"WyrdRoles": {
		"path": "res://addons/wyrd/runtime/roles/wyrd_roles.gd",
		"covered": true,
		"methods": ["vacate", "assign"],
		"signals": ["role_holder_changed", "role_vacant", "election_needed"],
		"properties": [],
	},
	"WyrdTopics": {
		"path": "res://addons/wyrd/runtime/topics/wyrd_topics.gd",
		"covered": true,
		"methods": [],
		"signals": ["topic_unlocked"],
		"properties": [],
	},
	"WyrdDocuments": {
		"path": "res://addons/wyrd/runtime/documents/wyrd_documents.gd",
		"covered": true,
		"methods": ["open", "create_copy"],
		"signals": ["document_read"],
		"properties": [],
	},
	"WyrdQuestRunner": {
		"path": "res://addons/wyrd/runtime/quests/wyrd_quest_runner.gd",
		"covered": true,
		"methods": ["summary", "summary_source"],
		"signals": ["quest_state_changed", "stage_changed", "journal_entry_added", "content_unavailable"],
		"properties": [],
	},
	"WyrdSceneRunner": {
		"path": "res://addons/wyrd/runtime/scenes/wyrd_scene_runner.gd",
		"covered": true,
		"methods": ["open", "ask_topic", "choose", "advance", "abort", "open_scene"],
		"signals": ["line_ready", "choices_ready", "scene_started", "scene_ended"],
		"properties": [],
	},
	"WyrdGenerator": {
		"path": "res://addons/wyrd/runtime/generator/wyrd_generator.gd",
		"covered": true,
		"methods": ["offer", "propose", "accept"],
		"signals": [],
		"properties": [],
	},
	"WyrdAI": {
		"path": "res://addons/wyrd/runtime/ai/wyrd_ai.gd",
		"covered": true,
		"methods": ["set_enabled", "request", "cancel", "host_text", "deliver", "register_classifier"],
		"signals": [],
		"properties": [],
	},
	"WyrdWorldAdapter": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_world_adapter.gd",
		"covered": true,
		"methods": ["attr", "candidates", "display_name", "exists", "groups_of", "in_bounds", "is_alive", "is_protected", "kind", "members", "reports_changes", "tags"],
		"signals": [],
		"properties": [],
	},
	"WyrdInventoryAdapter": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_inventory_adapter.gd",
		"covered": true,
		"methods": ["count", "items", "owner_of"],
		"signals": [],
		"properties": [],
	},
	"WyrdSpatialAdapter": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_spatial_adapter.gd",
		"covered": true,
		"methods": ["can_perceive", "can_reach", "distance", "nearby", "perceive", "place_of", "precision", "witnesses_of"],
		"signals": [],
		"properties": [],
	},
	"WyrdTimeAdapter": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_time_adapter.gd",
		"covered": true,
		"methods": ["now_minutes", "season"],
		"signals": [],
		"properties": [],
	},
	"WyrdActionAdapter": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_action_adapter.gd",
		"covered": true,
		"methods": ["command_schema", "execute"],
		"signals": [],
		"properties": [],
	},
	"WyrdElectionAdapter": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_election_adapter.gd",
		"covered": true,
		"methods": ["start_election"],
		"signals": [],
		"properties": [],
	},
	"WyrdAIProvider": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_ai_provider.gd",
		"covered": true,
		"methods": ["cancel", "id", "locales", "prompt_version", "request"],
		"signals": [],
		"properties": [],
	},
	"WyrdSkillAdapter": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_skill_adapter.gd",
		"covered": true,
		"methods": ["check"],
		"signals": [],
		"properties": [],
	},
	"WyrdConfig": {
		"path": "res://addons/wyrd/runtime/wyrd_config.gd",
		"covered": true,
		"methods": ["axis_delta", "half_life_for", "kind_scale", "scales_for", "set_axis_delta", "set_kind_scale"],
		"signals": [],
		"properties": ["ai_banned_terms", "ai_cache_max", "ai_max_inflight", "ai_save_cache", "axis_deltas", "axis_names", "axis_verbs", "compact_after", "credibility_threshold", "disposition_default", "generator_retries", "half_life_minutes", "half_life_verbs", "hostile_threshold", "hour_bucket_minutes", "kind_scale_axes", "kind_scale_kinds", "kind_scale_values", "pressure_tiers", "publish_catchup_max", "publish_slice_rows", "rumor_coarse_minutes", "scheduler_frame_warn_usec", "scheduler_share_ai_prefetch", "scheduler_share_cache", "scheduler_share_generate", "scheduler_share_publish", "scheduler_share_rumor", "scheduler_share_waits", "scheduler_tick_minutes", "scheduler_work_per_tick", "secrecy_fact", "secrecy_tiers", "trace_director"],
	},
	"WyrdLoadReport": {
		"path": "res://addons/wyrd/runtime/wyrd_load_report.gd",
		"covered": true,
		"methods": ["add_row", "error_count", "sort_rows"],
		"signals": [],
		"properties": ["diagnostics", "manifest_hash", "ok", "rows"],
	},
	"WyrdLineView": {
		"path": "res://addons/wyrd/runtime/scenes/wyrd_line_view.gd",
		"covered": true,
		"methods": [],
		"signals": [],
		"properties": ["audio", "display_name", "id", "roles", "speaker", "tags", "text", "text_source"],
	},
	"WyrdContentManifest": {
		"path": "res://addons/wyrd/compiler/wyrd_content_manifest.gd",
		"covered": true,
		"methods": [],
		"signals": [],
		"properties": ["files", "language_version", "pack_id"],
	},
	"WyrdCommand": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_command.gd",
		"covered": true,
		"methods": [],
		"signals": [],
		"properties": ["args", "name"],
	},
	"WyrdCommandResult": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_command_result.gd",
		"covered": true,
		"methods": ["failed", "is_ok", "ok"],
		"signals": [],
		"properties": ["reason", "status"],
	},
	"WyrdCommandSchema": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_command_schema.gd",
		"covered": true,
		"methods": ["add_command", "add_skill", "has_command", "has_skill"],
		"signals": [],
		"properties": ["checks_skills", "command_names", "skill_names"],
	},
	"WyrdEntityFilter": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_entity_filter.gd",
		"covered": true,
		"methods": [],
		"signals": [],
		"properties": ["kind", "tag"],
	},
	"WyrdSkillCheck": {
		"path": "res://addons/wyrd/runtime/adapters/wyrd_skill_check.gd",
		"covered": true,
		"methods": [],
		"signals": [],
		"properties": ["args", "choice_id", "roll", "scene_id", "skill"],
	},
	"WyrdAIRequest": {
		"path": "res://addons/wyrd/runtime/ai/wyrd_ai_request.gd",
		"covered": false,
		"methods": ["set_deliver", "reply"],
		"signals": [],
		"properties": ["id", "kind", "packet", "constraints", "locale", "path", "key", "owner", "sent_minute"],
	},
	"WyrdAIResult": {
		"path": "res://addons/wyrd/runtime/ai/wyrd_ai_result.gd",
		"covered": false,
		"methods": [],
		"signals": [],
		"properties": ["ok", "text", "error"],
	},
	"WyrdChoiceView": {
		"path": "res://addons/wyrd/runtime/scenes/wyrd_choice_view.gd",
		"covered": false,
		"methods": [],
		"signals": [],
		"properties": ["index", "id", "text", "enabled", "reason", "tags", "check", "check_args"],
	},
	"WyrdDiagnostics": {
		"path": "res://addons/wyrd/compiler/wyrd_diagnostics.gd",
		"covered": false,
		"methods": ["add", "has_errors", "has_warnings", "sort_items", "format"],
		"signals": [],
		"properties": ["items"],
	},
	"WyrdDocumentView": {
		"path": "res://addons/wyrd/runtime/documents/wyrd_document_view.gd",
		"covered": false,
		"methods": [],
		"signals": [],
		"properties": ["id", "copy_id", "reader", "title", "frozen", "first_time", "tags", "meta", "pages"],
	},
	"WyrdProposal": {
		"path": "res://addons/wyrd/runtime/generator/wyrd_proposal.gd",
		"covered": false,
		"methods": [],
		"signals": [],
		"properties": ["id", "source", "key", "tier", "origin", "template", "instance", "casts", "params", "payload", "expected_counter", "used"],
	},
}


const _STAYS_EXPERIMENTAL := [
	"WyrdSocial",
	"WyrdRumor",
	"WyrdPublish",
	"WyrdStoryletDeck",
	"WyrdSequences",
	"WyrdDirector",
]

const _SCENE := """language 1
scene room
  narrator: Hello. #line:hi
  -> scene inner
scene inner
  narrator: Inner. #line:in
  -> end
"""


func test_scene_started_fires_once_before_the_first_line() -> void:
	var facade := _facade()
	var order: Array = []
	facade.scene_started.connect(func(scene_id: String) -> void:
		order.append(["scene_started", scene_id])
	)
	facade.line_ready.connect(func(line: WyrdLineView) -> void:
		order.append(["line_ready", line.text])
	)
	var report := _load(facade, _SCENE)
	assert_true(report.ok, report.diagnostics.format())
	facade.trace.enabled = true
	facade.dialogue.open_scene("room")
	assert_eq(order.size(), 2, str(order))
	assert_eq(order[0], ["scene_started", "room"])
	assert_eq(order[1][0], "line_ready")
	assert_eq(order[1][1], "Hello.")
	facade.dialogue.advance()
	assert_eq(order.size(), 3, str(order))
	assert_eq(order[2][0], "line_ready")
	assert_eq(order[2][1], "Inner.")
	var started := 0
	for row in facade.trace.events:
		assert_ne(str(row.get("kind", "")), "scene_started")
		if str(row.get("kind", "")) == "open_scene":
			started += 1
	assert_eq(started, 1)
	facade.free()


func test_scene_started_does_not_fire_for_a_refused_open() -> void:
	var fresh := _facade()
	var missed: Array = [0]
	fresh.scene_started.connect(func(_scene_id: String) -> void:
		missed[0] += 1
	)
	var report := _load(fresh, _SCENE)
	assert_true(report.ok, report.diagnostics.format())
	fresh.dialogue.open_scene("missing")
	assert_push_error('unknown scene "missing"')
	assert_eq(missed[0], 0)
	fresh.free()
	var facade := _facade()
	var fired: Array = [0]
	facade.scene_started.connect(func(_scene_id: String) -> void:
		fired[0] += 1
	)
	report = _load(facade, _SCENE)
	assert_true(report.ok, report.diagnostics.format())
	facade.dialogue.open_scene("room")
	assert_eq(fired[0], 1)
	facade.dialogue.open_scene("room")
	assert_push_error("a scene is already open")
	assert_eq(fired[0], 1)
	facade.free()


func test_facade_relays_match_after_load_new_game_and_load_state() -> void:
	var facade := _facade()
	_assert_relays(facade)
	var report := _load(facade, _SCENE)
	assert_true(report.ok, report.diagnostics.format())
	_assert_relays(facade)
	facade.start_new_game(3)
	_assert_relays(facade)
	var saved: Dictionary = facade.save_state()
	var loaded: WyrdLoadReport = facade.load_state(saved)
	assert_true(loaded.ok, loaded.diagnostics.format())
	_assert_relays(facade)
	facade.free()


func test_register_disposition_formula_matches_social_register_formula() -> void:
	var facade: Node = load("res://addons/wyrd/runtime/wyrd.gd").new()
	var direct := WyrdRuntime.new()
	var fn := Callable(self, "_formula_seven")
	facade.register_disposition_formula(fn)
	direct.social.register_formula(fn)
	assert_eq(facade.social.disposition(&"a", &"b"), 7)
	assert_eq(direct.social.disposition(&"a", &"b"), facade.social.disposition(&"a", &"b"))
	facade.free()


func test_experimental_flags_match_the_stable_list_and_the_doc() -> void:
	var snapshot := WyrdApiGolden.build()
	var classes: Dictionary = snapshot["classes"]
	var doc := FileAccess.get_file_as_string("res://docs/stability.md")
	var sections := _doc_sections(doc)
	for reported in STABLE_MEMBERS.keys():
		var spec: Dictionary = STABLE_MEMBERS[reported]
		assert_true(sections.has(reported), reported)
		var named := _as_set(sections[reported])
		var expected := {}
		for kind in ["methods", "signals", "properties"]:
			for member_name in spec[kind]:
				expected[str(member_name)] = true
		assert_eq(named.keys().size(), expected.size(), "%s doc %s" % [reported, named.keys()])
		for member_name in expected.keys():
			assert_true(named.has(member_name), "%s missing %s" % [reported, member_name])
		var flags := WyrdApiGolden.member_flags(str(spec["path"]))
		assert_false(bool(flags["class"]), reported)
		if not bool(spec["covered"]):
			_assert_source_flags(reported, spec, flags)
			continue
		assert_true(classes.has(reported), reported)
		var entry: Dictionary = classes[reported]
		assert_false(bool(entry["experimental"]), reported)
		for kind in ["methods", "signals", "properties"]:
			var stable := {}
			for member_name in spec[kind]:
				stable[str(member_name)] = true
			var rows: Array = entry[kind]
			var seen := {}
			for row in rows:
				var member_name := str(row.get("name", ""))
				seen[member_name] = true
				var want := not stable.has(member_name)
				assert_eq(bool(row.get("experimental", false)), want, "%s.%s" % [reported, member_name])
			for member_name in stable.keys():
				assert_true(seen.has(member_name), "%s missing %s" % [reported, member_name])
	for reported in _STAYS_EXPERIMENTAL:
		assert_true(classes.has(reported), reported)
		assert_true(bool(classes[reported]["experimental"]), reported)
	for reported in classes.keys():
		if STABLE_MEMBERS.has(reported):
			continue
		assert_true(bool(classes[reported]["experimental"]), reported)


func _formula_seven(_source: StringName, _target: StringName, _axes: Dictionary) -> int:
	return 7


func _assert_source_flags(reported: String, spec: Dictionary, flags: Dictionary) -> void:
	for kind in ["methods", "signals", "properties"]:
		var listed := {}
		for member_name in spec[kind]:
			listed[str(member_name)] = true
		var found: Dictionary = flags[kind]
		assert_eq(found.size(), listed.size(), "%s %s %s" % [reported, kind, found.keys()])
		for member_name in found.keys():
			assert_true(listed.has(str(member_name)), "%s extra %s" % [reported, member_name])
			assert_false(bool(found[member_name]), "%s.%s" % [reported, member_name])


func _assert_relays(facade: Node) -> void:
	var line := WyrdLineView.new()
	line.text = "relay"
	var choices: Array[WyrdChoiceView] = []
	var choice := WyrdChoiceView.new()
	choice.text = "stay"
	choices.append(choice)
	var report := WyrdLoadReport.new()
	report.ok = true
	_one(facade, facade.dialogue, "line_ready", [line])
	_one(facade, facade.dialogue, "choices_ready", [choices])
	_one(facade, facade.dialogue, "scene_started", ["room"])
	_one(facade, facade.dialogue, "scene_ended", ["room", &"done", &"end"])
	_one(facade, facade.dialogue.runtime, "bark_ready", [line])
	_one(facade, facade.quests, "quest_state_changed", ["gate", &"active"])
	_one(facade, facade.quests, "stage_changed", ["gate", "pay"])
	_one(facade, _effects(facade), "outcome_changed", ["gate", &"toll", &"done"])
	_one(facade, facade.quests, "journal_entry_added", ["gate", "e1", "Wrote it."])
	_one(facade, facade.topics, "topic_unlocked", [&"weather"])
	_one(facade, facade.roles, "role_holder_changed", [&"keeper", &"old", &"new"])
	_one(facade, facade.roles, "role_vacant", [&"keeper"])
	_one(facade, facade.roles, "election_needed", [&"keeper", &"old"])
	_one(facade, facade.deeds, "deed_recorded", [{"id": 1}])
	_one(facade, facade.facts, "fact_changed", [&"world.flag", false, true])
	_one(facade, facade.quests, "content_unavailable", ["gate", "pack"])
	_one(facade, facade.documents, "document_read", [&"note", "c1", &"player", true])
	_one(facade, facade.dialogue.runtime, "load_report_ready", [report])


func _one(facade: Node, source: Object, signal_name: String, args: Array) -> void:
	var log := RelayLog.new()
	var callable := _callable_for(log, args.size())
	var err := facade.connect(signal_name, callable)
	assert_eq(err, OK, signal_name)
	match args.size():
		1:
			source.emit_signal(signal_name, args[0])
		2:
			source.emit_signal(signal_name, args[0], args[1])
		3:
			source.emit_signal(signal_name, args[0], args[1], args[2])
		4:
			source.emit_signal(signal_name, args[0], args[1], args[2], args[3])
		_:
			assert_true(false, signal_name)
	facade.disconnect(signal_name, callable)
	assert_eq(log.rows.size(), 1, signal_name)
	assert_eq(log.rows[0], args, signal_name)


func _callable_for(log: RelayLog, count: int) -> Callable:
	match count:
		1:
			return Callable(log, "one")
		2:
			return Callable(log, "two")
		3:
			return Callable(log, "three")
		_:
			return Callable(log, "four")


func _doc_sections(text: String) -> Dictionary:
	var start := text.find("## Stable surface")
	var finish := text.find("## Experimental")
	var body := text.substr(start, finish - start).split("\n")
	var sections := {}
	var current := ""
	var names: Array = []
	for line in body:
		if line.begins_with("### "):
			if current != "":
				sections[current] = names
			current = line.substr(4).strip_edges()
			names = []
			continue
		if current == "":
			continue
		var rest := line
		while true:
			var open := rest.find("`")
			if open < 0:
				break
			var close := rest.find("`", open + 1)
			if close < 0:
				break
			var token := rest.substr(open + 1, close - open - 1)
			if token.is_valid_identifier():
				names.append(token)
			rest = rest.substr(close + 1)
	if current != "":
		sections[current] = names
	return sections


func _as_set(names: Array) -> Dictionary:
	var found := {}
	for member_name in names:
		found[str(member_name)] = true
	return found


func _effects(facade: Node) -> Object:
	return facade.dialogue.runtime.effects


func _facade() -> Node:
	var facade: Node = load("res://addons/wyrd/runtime/wyrd.gd").new()
	var host := WyrdFakeHost.new()
	host.register_into(facade.dialogue.runtime)
	return facade


func _load(facade: Node, body: String) -> WyrdLoadReport:
	var path := "user://wyrd_m12_surface.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"sample"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	return facade.load_content(manifest)


class RelayLog extends RefCounted:
	var rows: Array = []

	func one(a: Variant) -> void:
		rows.append([a])

	func two(a: Variant, b: Variant) -> void:
		rows.append([a, b])

	func three(a: Variant, b: Variant, c: Variant) -> void:
		rows.append([a, b, c])

	func four(a: Variant, b: Variant, c: Variant, d: Variant) -> void:
		rows.append([a, b, c, d])
