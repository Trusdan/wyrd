extends GutTest

const _HARBOR := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _Election := preload("res://example/playtest/harbor_election.gd")

const _VOICE := """id=dock_voice text=The crossing stays open. {holder(ferry_master)|variants} tags=voiced scene= context=storylet:dock_voice_crossing
id=dock_voice_master text=The ferry master keeps the crossing open. tags=voiced scene= context=variant:ferry_master storylet:dock_voice_crossing
id=dock_voice_mender text=The net mender keeps the crossing open. tags=voiced scene= context=variant:net_mender storylet:dock_voice_crossing
"""


func test_priority_outranks_specificity_and_a_tie_is_seeded() -> void:
	var compiled := _compile(_RANK)
	assert_false(compiled["diagnostics"].has_errors(), compiled["diagnostics"].format())
	var warnings := 0
	for item in compiled["diagnostics"].items:
		if String(item.code) == "W_STORYLET_TIE":
			warnings += 1
	assert_eq(warnings, 1)
	var runtime := _boot_pack(_RANK, 4)
	assert_eq(runtime.content().storylets["harbor.ranked"].specificity, 1)
	assert_eq(runtime.content().storylets["harbor.specific"].specificity, 2)
	var won := runtime.director.query("topic", "rumor.matrix", "ferry")
	assert_eq(str(won["id"]), "harbor.ranked")
	assert_eq(int(won["priority"]), 3)
	var left := _boot_pack(_RANK, 11).director.query("topic", "rumor.pair", "ferry")
	var right := _boot_pack(_RANK, 11).director.query("topic", "rumor.pair", "ferry")
	assert_eq(str(left["id"]), str(right["id"]))
	assert_true(str(left["id"]) == "harbor.alpha" or str(left["id"]) == "harbor.beta")
	var other := _boot_pack(_RANK, 29).director.query("topic", "rumor.pair", "ferry")
	var again := _boot_pack(_RANK, 29).director.query("topic", "rumor.pair", "ferry")
	assert_eq(str(other["id"]), str(again["id"]))


func test_bark_inventory_proximity_cooldown_matrix() -> void:
	var cells := [
		{"has": 0, "near": false, "expect": ""},
		{"has": 0, "near": true, "expect": "dock_bark_lantern"},
		{"has": 1, "near": false, "expect": ""},
		{"has": 1, "near": true, "expect": "dock_bark_lantern_carried"},
	]
	for cell in cells:
		var runtime := _harbor()
		_arm_bark(runtime.get_meta("host"), int(cell["has"]), bool(cell["near"]))
		assert_eq(str(runtime.director.query("bark", "", "ferry")["id"]), str(cell["expect"]), str(cell))
	var runtime := _harbor()
	_arm_bark(runtime.get_meta("host"), 0, true)
	assert_eq(str(runtime.director.query("bark", "", "ferry")["id"]), "dock_bark_lantern")
	_arm_bark(runtime.get_meta("host"), 1, true)
	assert_eq(str(runtime.director.query("bark", "", "ferry")["id"]), "dock_bark_lantern_carried")
	assert_eq(str(runtime.director.query("bark", "", "ferry")["id"]), "")
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 2)
	assert_false(saved.has("secrecy_tiers"))
	assert_false(saved.has("trace_director"))
	var loaded := _harbor()
	assert_true(loaded.load_state(saved).ok)
	_arm_bark(loaded.get_meta("host"), 1, true)
	assert_eq(str(loaded.director.query("bark", "", "ferry")["id"]), "")
	loaded.tick(10)
	assert_eq(str(loaded.director.query("bark", "", "ferry")["id"]), "dock_bark_lantern_carried")


func test_substate_save_load_matrix() -> void:
	var cells := [
		{"rope": false, "tongue": false, "stage": "repair", "rope_stage": "frayed", "tongue_stage": "loose"},
		{"rope": true, "tongue": false, "stage": "repair", "rope_stage": "spliced", "tongue_stage": "loose"},
		{"rope": false, "tongue": true, "stage": "repair", "rope_stage": "frayed", "tongue_stage": "seated"},
		{"rope": true, "tongue": true, "stage": "done", "rope_stage": "spliced", "tongue_stage": "seated"},
	]
	for cell in cells:
		var runtime := _bell(bool(cell["rope"]), bool(cell["tongue"]))
		assert_eq(runtime.quests.stage("bell_repair"), str(cell["stage"]), str(cell))
		if str(cell["stage"]) != "done":
			var leaves: Dictionary = runtime.quests.regions_of("bell_repair")
			assert_eq(str(leaves["rope"]["stage"]), str(cell["rope_stage"]))
			assert_eq(str(leaves["tongue"]["stage"]), str(cell["tongue_stage"]))
		else:
			assert_eq(str(runtime.quests.status("bell_repair")), "completed")
		var saved := runtime.save_state()
		assert_eq(int(saved["schema_version"]), 2)
		var loaded := _harbor()
		loaded.trace.enabled = true
		loaded.config().trace_director = true
		assert_true(loaded.load_state(saved).ok)
		assert_eq(loaded.trace.events.size(), 0)
		loaded.tick(0)
		assert_eq(loaded.quests.stage("bell_repair"), str(cell["stage"]))
		assert_eq(_rows(loaded, "director_candidate").size(), 0)
		assert_eq(_rows(loaded, "region").size(), 0)
	var counter := _harbor()
	counter.tick(0)
	_strike(counter, "harbor_bell", "rung")
	assert_eq(counter.sequences.progress("bell_signal"), 1)
	assert_false(counter.sequences.done("bell_signal"))
	var kept := counter.save_state()
	var resumed := _harbor()
	resumed.trace.enabled = true
	assert_true(resumed.load_state(kept).ok)
	assert_eq(resumed.trace.events.size(), 0)
	assert_eq(resumed.sequences.progress("bell_signal"), 1)
	assert_false(resumed.sequences.done("bell_signal"))


func test_voiced_line_golden() -> void:
	var voice: Dictionary = WyrdCli.execute(PackedStringArray([
		"voice-check",
		"--manifest",
		_HARBOR,
	]))
	assert_eq(int(voice["exit_code"]), 1, str(voice["output"]))
	var narrator := ""
	for line in str(voice["output"]).split("\n"):
		if line.begins_with("speaker=narrator "):
			narrator = line
	assert_true(narrator.contains("voiced=3"), narrator)
	assert_true(narrator.contains("variable="), narrator)
	var script: Dictionary = WyrdCli.execute(PackedStringArray([
		"script-export",
		"--speaker",
		"narrator",
		"--manifest",
		_HARBOR,
	]))
	assert_eq(int(script["exit_code"]), 0, str(script["output"]))
	var golden := PackedStringArray()
	for line in str(script["output"]).split("\n"):
		if line.contains("id=dock_voice"):
			golden.append(line)
	assert_eq("\n".join(golden) + "\n", _VOICE)


func test_secrecy_filter_at_each_tier() -> void:
	var locked := _harbor()
	var open_line := locked.director.query("topic", "rumor.ledger", "ferry")
	assert_push_error("unknown tier")
	assert_eq(str(open_line["id"]), "harbor_ledger.open")
	assert_eq(str(open_line["line_id"]), "lg01")
	var hidden := locked.director.why_not("harbor_ledger.sealed", "topic", "rumor.ledger", "ferry")
	assert_eq(str(hidden["reason"]), "secrecy")
	assert_eq(str(hidden["unlocked"]), "-")
	var named := _harbor()
	named.config().secrecy_tiers = PackedStringArray(["open", "sealed"])
	assert_eq(str(named.director.query("topic", "rumor.ledger", "ferry")["id"]), "harbor_ledger.open")
	var above := named.director.why_not("harbor_ledger.sealed", "topic", "rumor.ledger", "ferry")
	assert_eq(str(above["reason"]), "secrecy")
	assert_eq(str(above["tier"]), "sealed")
	assert_eq(str(above["unlocked"]), "-")
	named.facts.set(&"player.clearance", &"open")
	assert_eq(str(named.director.query("topic", "rumor.ledger", "ferry")["id"]), "harbor_ledger.open")
	var still := named.director.why_not("harbor_ledger.sealed", "topic", "rumor.ledger", "ferry")
	assert_eq(str(still["reason"]), "secrecy")
	assert_eq(str(still["unlocked"]), "open")
	named.facts.set(&"player.clearance", &"sealed")
	var shown := named.director.query("topic", "rumor.ledger", "ferry")
	assert_eq(str(shown["id"]), "harbor_ledger.sealed")
	assert_eq(str(shown["line_id"]), "lg03")
	var saved := named.save_state()
	assert_eq(int(saved["schema_version"]), 2)
	assert_eq(str(saved["facts"]["world"]["player.clearance"]), "sealed")
	assert_false(saved.has("secrecy_tiers"))
	var loaded := _harbor()
	loaded.config().secrecy_tiers = PackedStringArray(["open", "sealed"])
	loaded.trace.enabled = true
	loaded.config().trace_director = true
	assert_true(loaded.load_state(saved).ok)
	assert_eq(loaded.trace.events.size(), 0)
	assert_eq(str(loaded.director.query("topic", "rumor.ledger", "ferry")["id"]), "harbor_ledger.sealed")
	var high := _harbor()
	high.config().secrecy_tiers = PackedStringArray(["open", "sealed", "vault"])
	high.facts.set(&"player.clearance", &"vault")
	assert_eq(str(high.director.query("topic", "rumor.ledger", "ferry")["id"]), "harbor_ledger.open")
	var passed := high.director.why_not("harbor_ledger.sealed", "topic", "rumor.ledger", "ferry")
	assert_eq(str(passed["reason"]), "when")
	assert_eq(str(passed["unlocked"]), "vault")


func test_same_seed_storylet_picks() -> void:
	var picks: Array = []
	for _n in 2:
		var runtime := _harbor()
		_arm_bark(runtime.get_meta("host"), 1, true)
		var won := runtime.director.query("bark", "", "ferry")
		picks.append(str(won["id"]) + ":" + str(won["line_id"]))
		var topic := runtime.director.query("topic", "rumor.ferry_toll", "ferry")
		picks.append(str(topic["id"]) + ":" + str(topic["line_id"]))
	assert_eq(str(picks[0]), "dock_bark_lantern_carried:sg05")
	assert_eq(str(picks[0]), str(picks[2]))
	assert_eq(str(picks[1]), str(picks[3]))
	assert_eq(str(picks[1]), "harbor_gossip.generic:sg01")


func test_why_not_tiers_and_secrecy_fact() -> void:
	var omitted: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--manifest", _HARBOR, "harbor_ledger.sealed",
	]))
	assert_eq(int(omitted["exit_code"]), 0, str(omitted["output"]))
	assert_true(str(omitted["output"]).contains("reason=secrecy"), str(omitted["output"]))
	assert_true(str(omitted["output"]).contains("tier=sealed"), str(omitted["output"]))
	assert_true(str(omitted["output"]).contains("unlocked=-"), str(omitted["output"]))
	assert_push_error("unknown tier")
	var empty: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--tiers", "open,,sealed", "--manifest", _HARBOR, "harbor_ledger.sealed",
	]))
	assert_eq(int(empty["exit_code"]), 1)
	assert_eq(str(empty["output"]), "wyrd: --tiers has an empty name\n")
	var missing: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--tiers", "--manifest", _HARBOR, "harbor_ledger.sealed",
	]))
	assert_eq(int(missing["exit_code"]), 1)
	assert_eq(str(missing["output"]), "wyrd: --tiers needs a list\n")
	var bare: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--secrecy-fact", "--manifest", _HARBOR, "harbor_ledger.sealed",
	]))
	assert_eq(int(bare["exit_code"]), 1)
	assert_eq(str(bare["output"]), "wyrd: --secrecy-fact needs a fact\n")
	var runtime := _harbor()
	runtime.facts.set(&"player.clearance", &"sealed")
	var save_path := "user://wyrd_m6_matrix_clearance.json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(runtime.save_state()))
	file.close()
	var opened: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--tiers", "open, sealed", "--save", save_path, "--manifest", _HARBOR, "harbor_ledger.sealed",
	]))
	assert_eq(int(opened["exit_code"]), 0, str(opened["output"]))
	assert_true(str(opened["output"]).contains("reason=ok"), str(opened["output"]))
	assert_true(str(opened["output"]).contains("unlocked=sealed"), str(opened["output"]))
	var other: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--tiers", "open,sealed", "--secrecy-fact", "harbor.toll_fate", "--save", save_path,
		"--manifest", _HARBOR, "harbor_ledger.sealed",
	]))
	assert_eq(int(other["exit_code"]), 0, str(other["output"]))
	assert_true(str(other["output"]).contains("reason=secrecy"), str(other["output"]))
	assert_true(str(other["output"]).contains("unlocked=-"), str(other["output"]))
	runtime.facts.set(&"harbor.toll_fate", &"sealed")
	var fate_path := "user://wyrd_m6_matrix_fate.json"
	var fate := FileAccess.open(fate_path, FileAccess.WRITE)
	fate.store_string(JSON.stringify(runtime.save_state()))
	fate.close()
	var swapped: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--tiers", "open,open", "--secrecy-fact", "harbor.toll_fate", "--save", fate_path,
		"--manifest", _HARBOR, "harbor_ledger.sealed",
	]))
	assert_eq(int(swapped["exit_code"]), 0, str(swapped["output"]))
	assert_push_error("unknown tier")
	assert_true(str(swapped["output"]).contains("reason=secrecy"), str(swapped["output"]))
	var traced: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--trace-director", "--tiers", "open,sealed", "--save", save_path,
		"--manifest", _HARBOR, "harbor_ledger.sealed",
	]))
	assert_eq(int(traced["exit_code"]), 0, str(traced["output"]))
	assert_true(str(traced["output"]).begins_with("wyrd director_candidate "), str(traced["output"]))
	assert_eq(str(traced["output"]).count("\nwyrd why_not "), 1)


func test_storylets_and_cooldowns_dumps() -> void:
	var listed: Dictionary = WyrdCli.execute(PackedStringArray([
		"storylets", "--manifest", _HARBOR, "--scope", "topic", "--scope-id", "rumor.ledger",
		"--tiers", "open,sealed", "--filter", "ledger",
	]))
	assert_eq(int(listed["exit_code"]), 0, str(listed["output"]))
	assert_true(str(listed["output"]).contains("id=harbor_ledger.open "), str(listed["output"]))
	assert_true(str(listed["output"]).contains("id=harbor_ledger.sealed "), str(listed["output"]))
	assert_true(str(listed["output"]).contains("block=secrecy"), str(listed["output"]))
	assert_false(str(listed["output"]).contains("harbor_gossip"))
	var barked: Dictionary = WyrdCli.execute(PackedStringArray([
		"storylets", "--manifest", _HARBOR, "--scope", "bark", "--speaker", "tavern", "--tiers", "open,sealed",
	]))
	assert_eq(int(barked["exit_code"]), 0, str(barked["output"]))
	assert_eq(str(barked["output"]), "")
	var needs_scope: Dictionary = WyrdCli.execute(PackedStringArray([
		"storylets", "--trace-director", "--manifest", _HARBOR,
	]))
	assert_eq(int(needs_scope["exit_code"]), 1)
	assert_eq(str(needs_scope["output"]), "wyrd: --trace-director needs --scope\n")
	var pool: Dictionary = WyrdCli.execute(PackedStringArray([
		"storylets", "--trace-director", "--scope", "topic", "--scope-id", "rumor.ledger",
		"--tiers", "open,sealed", "--manifest", _HARBOR,
	]))
	assert_eq(int(pool["exit_code"]), 0, str(pool["output"]))
	assert_true(str(pool["output"]).contains("wyrd director_candidate "), str(pool["output"]))
	assert_true(str(pool["output"]).contains("storylet=harbor_ledger.sealed"), str(pool["output"]))
	var quiet := _boot_pack(_RANK, 3)
	assert_eq(quiet.storylets.seen_of("harbor.alpha"), 0)
	quiet.director.diagnose("harbor.alpha", "topic", "rumor.pair", "ferry")
	quiet.director.candidate_rows("topic", "rumor.pair", "ferry")
	assert_eq(quiet.storylets.seen_of("harbor.alpha"), 0)
	var runtime := _harbor()
	_arm_bark(runtime.get_meta("host"), 0, true)
	assert_eq(str(runtime.director.query("bark", "", "ferry")["id"]), "dock_bark_lantern")
	var save_path := "user://wyrd_m6_matrix_clock.json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(runtime.save_state()))
	file.close()
	var clocks: Dictionary = WyrdCli.execute(PackedStringArray([
		"cooldowns", "--manifest", _HARBOR, "--save", save_path, "--prefix", "dock_bark",
	]))
	assert_eq(int(clocks["exit_code"]), 0, str(clocks["output"]))
	assert_true(str(clocks["output"]).contains("storylet=dock_bark_lantern "), str(clocks["output"]))
	assert_true(str(clocks["output"]).contains("seen=1"), str(clocks["output"]))
	assert_true(str(clocks["output"]).contains("remaining=30"), str(clocks["output"]))
	assert_false(str(clocks["output"]).contains("speaker="))
	_arm_bark(runtime.get_meta("host"), 1, true)
	runtime.tick(30)
	assert_eq(str(runtime.director.query("bark", "", "ferry")["id"]), "dock_bark_lantern_carried")
	var carried_path := "user://wyrd_m6_matrix_speaker.json"
	var carried := FileAccess.open(carried_path, FileAccess.WRITE)
	carried.store_string(JSON.stringify(runtime.save_state()))
	carried.close()
	var speakers: Dictionary = WyrdCli.execute(PackedStringArray([
		"cooldowns", "--manifest", _HARBOR, "--save", carried_path,
	]))
	assert_eq(int(speakers["exit_code"]), 0, str(speakers["output"]))
	assert_true(str(speakers["output"]).contains("speaker=ferry "), str(speakers["output"]))
	assert_true(str(speakers["output"]).contains("storylet=dock_bark_lantern_carried "), str(speakers["output"]))
	assert_true(str(speakers["output"]).contains("remaining=10"), str(speakers["output"]))


func test_director_candidate_trace_filters_and_skips_load() -> void:
	var runtime := _boot_pack(_RANK, 8)
	runtime.trace.enabled = true
	runtime.director.query("topic", "rumor.pair", "ferry")
	assert_eq(_rows(runtime, "director_candidate").size(), 0)
	assert_eq(_rows(runtime, "director").size(), 1)
	runtime.config().trace_director = true
	runtime.trace.clear()
	runtime.director.query("topic", "rumor.pair", "ferry")
	var rows := _rows(runtime, "director_candidate")
	assert_eq(rows.size(), 2)
	assert_eq(str(rows[0]["storylet"]), "harbor.alpha")
	assert_eq(str(rows[0]["eligible"]), "true")
	assert_eq(str(rows[0]["clause"]), "-")
	assert_eq(str(rows[0]["path"]), "harbor.alpha")
	assert_eq(str(rows[1]["storylet"]), "harbor.beta")
	assert_eq(_rows(runtime, "director").size(), 1)
	runtime.trace.clear()
	runtime.trace.prefix = "harbor.alpha"
	runtime.director.query("topic", "rumor.pair", "ferry")
	assert_eq(_rows(runtime, "director_candidate").size(), 1)
	assert_eq(str(_rows(runtime, "director_candidate")[0]["storylet"]), "harbor.alpha")
	assert_eq(_rows(runtime, "director").size(), 0)
	var saved := runtime.save_state()
	var loaded := _boot_pack(_RANK, 8)
	loaded.trace.enabled = true
	loaded.config().trace_director = true
	assert_true(loaded.load_state(saved).ok)
	assert_eq(loaded.trace.events.size(), 0)
	loaded.director.query("topic", "rumor.pair", "ferry")
	assert_eq(_rows(loaded, "director_candidate").size(), 2)
	var quiet := _boot_pack(_RANK, 8)
	quiet.config().trace_director = true
	quiet.director.query("topic", "rumor.pair", "ferry")
	assert_eq(quiet.trace.events.size(), 0)


func _bell(rope: bool, tongue: bool) -> WyrdRuntime:
	var runtime := _harbor()
	runtime.tick(0)
	if rope:
		_strike(runtime, "harbor_rope", "spliced")
	if tongue:
		_strike(runtime, "harbor_tongue", "seated")
	return runtime


func _arm_bark(host: WyrdFakeHost, count: int, near: bool) -> void:
	if near:
		host.spatial.set_nearby(&"player", 4.0, &"lantern", PackedStringArray([&"post"]))
	else:
		host.spatial.set_nearby(&"player", 4.0, &"lantern", PackedStringArray())
	host.inventory.set_count(&"player", &"lantern", count)


func _strike(runtime: WyrdRuntime, object: String, state_name: String) -> void:
	runtime.events.emit(&"mechanism_state", {
		"actor": &"player",
		"object": StringName(object),
		"state": StringName(state_name),
	})


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == kind:
			rows.append(item)
	return rows


func _harbor() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := load(_HARBOR) as WyrdContentManifest
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.register_adapter(WyrdElectionAdapter, _Election.new())
	runtime.start_new_game(5)
	runtime.set_meta("host", host)
	return runtime


func _boot_pack(body: String, seed_value: int) -> WyrdRuntime:
	var compiled := _compile(body)
	assert_false(compiled["diagnostics"].has_errors(), compiled["diagnostics"].format())
	var runtime := WyrdRuntime.new()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([str(compiled["path"])])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(seed_value)
	return runtime


func _compile(body: String) -> Dictionary:
	var path := _write("user://wyrd_m6_matrix_%d.wyrd" % body.hash(), body)
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	return {"diagnostics": diagnostics, "pack": pack, "path": path}


func _write(path: String, body: String) -> String:
	var lines := PackedStringArray()
	for line in body.strip_edges().split("\n"):
		if line.begins_with("\t\t"):
			lines.append(line.substr(2))
		else:
			lines.append(line)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return path


const _RANK := """
language 1
storylet harbor.ranked
  scope: topic rumor.matrix
  speaker: ferry
  priority: 3
  when: true
  - The ranked line. #line:ranked1
storylet harbor.specific
  scope: topic rumor.matrix
  speaker: ferry
  when: true and true
  - The specific line. #line:specific1
storylet harbor.alpha
  scope: topic rumor.pair
  speaker: ferry
  priority: 1
  - The alpha line. #line:alpha1
storylet harbor.beta
  scope: topic rumor.pair
  speaker: ferry
  priority: 1
  - The beta line. #line:beta1
"""
