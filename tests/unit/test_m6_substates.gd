extends GutTest

const _HARBOR := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _Election := preload("res://example/playtest/harbor_election.gd")


func test_parallel_regions_advance_on_their_own() -> void:
	var runtime := _boot(_REPAIR)
	runtime.tick(0)
	assert_eq(runtime.quests.stage("bell_repair"), "repair")
	var leaves: Dictionary = runtime.quests.regions_of("bell_repair")
	assert_eq(str(leaves["rope"]["stage"]), "frayed")
	assert_eq(str(leaves["tongue"]["stage"]), "loose")
	_strike(runtime, "harbor_rope", "spliced")
	assert_eq(runtime.facts.get(&"harbor.splices"), 1)
	assert_eq(str(runtime.quests.regions_of("bell_repair")["rope"]["stage"]), "spliced")
	assert_eq(str(runtime.quests.regions_of("bell_repair")["tongue"]["stage"]), "loose")
	assert_eq(runtime.quests.stage("bell_repair"), "repair")
	runtime.facts.set(&"harbor.tongue_seated", true)
	runtime.tick(0)
	assert_eq(str(runtime.quests.regions_of("bell_repair")["tongue"]["stage"]), "seated")
	assert_eq(runtime.facts.get(&"harbor.tongue_done"), true)
	assert_eq(runtime.quests.stage("bell_repair"), "repair")
	runtime.facts.set(&"harbor.release", true)
	runtime.tick(0)
	assert_eq(runtime.quests.stage("bell_repair"), "done")
	assert_eq(str(runtime.quests.status("bell_repair")), "completed")
	assert_eq(runtime.quests.outcome("bell_repair", "repair"), "done")


func test_region_save_load_keeps_the_leaf_and_skips_entry() -> void:
	var runtime := _boot(_REPAIR)
	runtime.tick(0)
	_strike(runtime, "harbor_rope", "spliced")
	assert_eq(runtime.facts.get(&"harbor.splices"), 1)
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 3)
	var quest: Dictionary = saved["quests"]["bell_repair"]
	assert_eq(str(quest["regions"]["rope"]["stage"]), "spliced")
	assert_true(bool(quest["regions"]["rope"]["entered"]))
	var loaded := _boot(_REPAIR)
	var report := loaded.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	loaded.tick(0)
	assert_eq(loaded.facts.get(&"harbor.splices"), 1)
	assert_eq(str(loaded.quests.regions_of("bell_repair")["rope"]["stage"]), "spliced")
	assert_eq(str(loaded.quests.regions_of("bell_repair")["tongue"]["stage"]), "loose")
	assert_eq(loaded.quests.stage("bell_repair"), "repair")


func test_flat_quest_save_has_no_regions_key() -> void:
	var runtime := _boot(_FLAT)
	runtime.tick(0)
	assert_eq(runtime.quests.stage("flat"), "two")
	assert_eq(runtime.facts.get(&"harbor.hits"), 1)
	var saved := runtime.save_state()
	assert_false((saved["quests"]["flat"] as Dictionary).has("regions"))
	assert_false(saved.has("sequences"))
	var loaded := _boot(_FLAT)
	assert_true(loaded.load_state(saved).ok)
	loaded.tick(0)
	assert_eq(loaded.quests.stage("flat"), "two")
	assert_eq(loaded.facts.get(&"harbor.hits"), 1)


func test_depth_three_warns_and_still_runs() -> void:
	var compiled := _compile(_DEEP)
	assert_false(compiled["diagnostics"].has_errors(), compiled["diagnostics"].format())
	assert_eq(_count(compiled["diagnostics"], "W_SUBSTATE_DEPTH"), 1)
	assert_true(compiled["diagnostics"].format().contains("sub-state \"leaf\""))
	var runtime := _boot(_DEEP)
	runtime.tick(0)
	assert_eq(runtime.facts.get(&"harbor.deep_done"), true)
	assert_eq(runtime.quests.stage("deep"), "outer")
	var leaves: Dictionary = runtime.save_state()["quests"]["deep"]["regions"]
	assert_eq(str(leaves["mid"]["stage"]), "inner")
	var nested: Dictionary = leaves["mid"]["regions"]
	assert_eq(str(nested["deep"]["stage"]), "leaf")
	runtime.facts.set(&"harbor.release", true)
	runtime.tick(0)
	assert_eq(runtime.quests.stage("deep"), "done")
	assert_eq(str(runtime.quests.status("deep")), "completed")


func test_depth_two_and_sibling_targets() -> void:
	var shallow := _compile(_REPAIR)
	assert_false(shallow["diagnostics"].has_errors(), shallow["diagnostics"].format())
	assert_eq(_count(shallow["diagnostics"], "W_SUBSTATE_DEPTH"), 0)
	var shared := _compile(_SHARED)
	assert_false(shared["diagnostics"].has_errors(), shared["diagnostics"].format())
	assert_eq(_count(shared["diagnostics"], "E_STAGE_DUPLICATE"), 0)
	var outward := _compile(_OUTWARD)
	assert_true(outward["diagnostics"].has_errors())
	assert_true(outward["diagnostics"].format().contains("unknown stage \"repair\""))
	var inward := _compile(_INWARD)
	assert_true(inward["diagnostics"].has_errors())
	assert_true(inward["diagnostics"].format().contains("unknown stage \"frayed\""))


func test_region_scene_waits_for_the_open_slot() -> void:
	var runtime := _boot(_SCENES)
	runtime.tick(0)
	assert_eq(runtime.quests.offered_scene("gate"), "rope_note")
	assert_eq(runtime.facts.get(&"harbor.rope_done"), true)
	assert_eq(runtime.facts.get(&"harbor.tongue_done"), true)
	assert_eq(runtime.quests.offered_scene("gate"), "rope_note")
	runtime.quests.on_scene_ended("rope_note", &"ended", &"ended")
	assert_eq(runtime.quests.offered_scene("gate"), "tongue_note")


func test_ordered_sequence_does_not_skip() -> void:
	var runtime := _boot(_ORDERED)
	runtime.tick(0)
	_strike(runtime, "harbor_bell", "seated")
	assert_eq(runtime.sequences.progress("harbor.path"), 0)
	assert_false(runtime.sequences.done("harbor.path"))
	_strike(runtime, "harbor_bell", "spliced")
	assert_eq(runtime.sequences.progress("harbor.path"), 1)
	_strike(runtime, "harbor_bell", "spliced")
	assert_eq(runtime.sequences.progress("harbor.path"), 1)
	_strike(runtime, "harbor_bell", "seated")
	assert_eq(runtime.sequences.progress("harbor.path"), 2)
	assert_true(runtime.sequences.done("harbor.path"))
	_strike(runtime, "harbor_bell", "spliced")
	assert_eq(runtime.sequences.progress("harbor.path"), 2)


func test_any_counts_distinct_steps_once_and_one_step_up_to_m() -> void:
	var distinct := _boot(_DISTINCT)
	distinct.tick(0)
	_strike(distinct, "harbor_bell", "spliced")
	_strike(distinct, "harbor_bell", "spliced")
	assert_eq(distinct.sequences.progress("harbor.tools"), 1)
	_strike(distinct, "harbor_bell", "seated")
	assert_eq(distinct.sequences.progress("harbor.tools"), 2)
	assert_true(distinct.sequences.done("harbor.tools"))
	_strike(distinct, "harbor_bell", "rung")
	assert_eq(distinct.sequences.progress("harbor.tools"), 2)
	var repeat := _boot(_REPEAT)
	repeat.tick(0)
	for _n in 3:
		_strike(repeat, "harbor_bell", "rung")
	assert_eq(repeat.sequences.progress("harbor.bells"), 3)
	assert_true(repeat.sequences.done("harbor.bells"))
	_strike(repeat, "harbor_bell", "rung")
	assert_eq(repeat.sequences.progress("harbor.bells"), 3)


func test_window_includes_its_last_minute_and_spares_a_finished_sequence() -> void:
	var open := _boot(_REPEAT)
	open.tick(0)
	_strike(open, "harbor_bell", "rung")
	assert_eq(open.sequences.progress("harbor.bells"), 1)
	open.tick(60)
	assert_eq(open.sequences.progress("harbor.bells"), 1)
	_strike(open, "harbor_bell", "rung")
	assert_eq(open.sequences.progress("harbor.bells"), 2)
	open.tick(1)
	assert_eq(open.sequences.progress("harbor.bells"), 0)
	assert_false(open.sequences.done("harbor.bells"))
	assert_false(open.save_state().has("sequences"))
	var done := _boot(_REPEAT)
	done.tick(0)
	for _n in 3:
		_strike(done, "harbor_bell", "rung")
	done.tick(61)
	assert_true(done.sequences.done("harbor.bells"))
	assert_eq(done.sequences.progress("harbor.bells"), 3)


func test_reset_event_clears_before_a_step_and_a_condition_clears_on_tick() -> void:
	var runtime := _boot(_RESET_EVENT)
	runtime.tick(0)
	_strike(runtime, "harbor_bell", "rung")
	assert_eq(runtime.sequences.progress("harbor.bells"), 1)
	runtime.events.emit(&"season_changed", {})
	assert_eq(runtime.sequences.progress("harbor.bells"), 0)
	assert_false(runtime.sequences.done("harbor.bells"))
	var same := _boot(_RESET_SAME)
	same.tick(0)
	same.events.emit(&"season_changed", {})
	assert_eq(same.sequences.progress("harbor.once"), 0)
	assert_false(same.save_state().has("sequences"))
	var cond := _boot(_RESET_COND)
	cond.tick(0)
	_strike(cond, "harbor_bell", "rung")
	assert_eq(cond.sequences.progress("harbor.watch"), 1)
	cond.facts.set(&"harbor.rope_done", true)
	cond.tick(0)
	assert_eq(cond.sequences.progress("harbor.watch"), 0)
	assert_false(cond.sequences.done("harbor.watch"))


func test_done_wakes_a_quest_and_partial_progress_round_trips() -> void:
	var runtime := _boot(_WAKE)
	runtime.tick(0)
	assert_eq(runtime.quests.stage("gate"), "wait")
	_strike(runtime, "harbor_bell", "rung")
	assert_eq(runtime.quests.stage("gate"), "wait")
	_strike(runtime, "harbor_bell", "rung")
	assert_eq(runtime.quests.stage("gate"), "rung")
	assert_eq(str(runtime.quests.status("gate")), "completed")
	var partial := _boot(_REPEAT)
	partial.tick(0)
	_strike(partial, "harbor_bell", "rung")
	_strike(partial, "harbor_bell", "rung")
	var saved := partial.save_state()
	assert_eq(int(saved["schema_version"]), 3)
	var row: Dictionary = saved["sequences"]["harbor.bells"]
	assert_eq(int(row["count"]), 2)
	assert_false(bool(row["done"]))
	assert_eq(int(row["started"]), 0)
	assert_false(row.has("matched"))
	var loaded := _boot(_REPEAT)
	assert_true(loaded.load_state(saved).ok)
	assert_eq(loaded.sequences.progress("harbor.bells"), 2)
	assert_false(loaded.sequences.done("harbor.bells"))
	_strike(loaded, "harbor_bell", "rung")
	assert_true(loaded.sequences.done("harbor.bells"))
	loaded.sequences.progress("missing.seq")
	assert_push_error("unknown sequence")
	loaded.sequences.done("missing.seq")
	assert_push_error("unknown sequence")


func test_save_keeps_unknown_sequences_and_a_new_game_clears_them() -> void:
	var runtime := _boot(_REPEAT)
	runtime.tick(0)
	_strike(runtime, "harbor_bell", "rung")
	var saved := runtime.save_state()
	var bag: Dictionary = saved["sequences"]
	bag["mystery.seq"] = {"count": 2, "done": true}
	bag["bad"] = 4
	saved["sequences"] = bag
	var loaded := _boot(_REPEAT)
	assert_true(loaded.load_state(saved).ok)
	assert_eq(loaded.sequences.progress("harbor.bells"), 1)
	var again := loaded.save_state()
	assert_true((again["sequences"] as Dictionary).has("mystery.seq"))
	assert_false((again["sequences"] as Dictionary).has("bad"))
	var cleared := again.duplicate(true)
	cleared.erase("sequences")
	assert_true(loaded.load_state(cleared).ok)
	assert_eq(loaded.sequences.progress("harbor.bells"), 0)
	assert_eq(loaded.quests.stage("flat"), "")
	_strike(loaded, "harbor_bell", "rung")
	assert_eq(loaded.sequences.progress("harbor.bells"), 1)
	loaded.start_new_game(9)
	assert_eq(loaded.sequences.progress("harbor.bells"), 0)
	assert_false(loaded.save_state().has("sequences"))
	assert_false(loaded.save_state().has("mystery.seq"))


func test_sequence_syntax_and_export() -> void:
	var duplicate := _compile(_DUPLICATE)
	assert_true(duplicate["diagnostics"].has_errors())
	assert_true(duplicate["diagnostics"].format().contains("duplicate sequence"))
	var count := _compile(_BAD_COUNT)
	assert_true(count["diagnostics"].format().contains("any of 3 needs 3 steps"))
	var bare := _compile(_BARE_RESET)
	assert_true(bare["diagnostics"].format().contains("unknown event \"not_an_event\""))
	var spatial := _compile(_SPATIAL_STEP)
	assert_true(spatial["diagnostics"].format().contains("E_SPATIAL_CONTEXT"))
	var packed := _compile(_REPEAT)
	assert_false(packed["diagnostics"].has_errors(), packed["diagnostics"].format())
	var data := WyrdExport.to_data(packed["pack"])
	assert_true(data.has("sequences"))
	var rows: Array = data["sequences"]
	assert_eq(str(rows[0]["id"]), "harbor.bells")
	assert_eq(str(rows[0]["mode"]), "any")
	assert_eq(int(rows[0]["need"]), 3)
	assert_eq(int(rows[0]["of"]), 3)
	assert_eq(int(rows[0]["within"]), 60)
	var left := WyrdExport.to_json(data)
	var right := WyrdExport.to_json(WyrdExport.to_data(packed["pack"]))
	assert_eq(left, right)


func test_gullhaven_bell_repair_and_signal() -> void:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := load(_HARBOR) as WyrdContentManifest
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	for item in report.diagnostics.items:
		var code := String(item.code)
		assert_ne(code, "W_SUBSTATE_DEPTH")
		assert_ne(code, "W_FACT_NEVER_READ")
		assert_ne(code, "W_FACT_NEVER_SET")
		assert_ne(code, "W_FACT_UNUSED")
	runtime.register_adapter(WyrdElectionAdapter, _Election.new())
	runtime.start_new_game(5)
	runtime.tick(0)
	assert_eq(runtime.quests.stage("bell_repair"), "repair")
	assert_eq(str(runtime.quests.regions_of("bell_repair")["rope"]["stage"]), "frayed")
	assert_eq(str(runtime.quests.regions_of("bell_repair")["tongue"]["stage"]), "loose")
	_strike(runtime, "harbor_rope", "spliced")
	assert_eq(runtime.facts.get(&"harbor.rope_done"), true)
	assert_eq(runtime.quests.stage("bell_repair"), "repair")
	_strike(runtime, "harbor_tongue", "seated")
	assert_eq(runtime.facts.get(&"harbor.tongue_done"), true)
	assert_eq(runtime.quests.stage("bell_repair"), "done")
	assert_eq(str(runtime.quests.status("bell_repair")), "completed")
	assert_eq(runtime.quests.outcome("bell_repair", "repair"), "done")
	for _n in 3:
		_strike(runtime, "harbor_bell", "rung")
	assert_eq(runtime.sequences.progress("bell_signal"), 3)
	assert_true(runtime.sequences.done("bell_signal"))
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 3)
	assert_true(saved.has("sequences"))
	assert_eq(int(saved["sequences"]["bell_signal"]["count"]), 3)
	runtime.events.emit(&"season_changed", {})
	assert_eq(runtime.sequences.progress("bell_signal"), 0)
	assert_false(runtime.sequences.done("bell_signal"))
	assert_false(runtime.save_state().has("sequences"))
	runtime.set_meta("host", host)


func test_region_trace_logs_each_leaf_change() -> void:
	var runtime := _boot(_REPAIR)
	runtime.trace.enabled = true
	runtime.tick(0)
	var opened := _trace_rows(runtime, "region")
	assert_eq(opened.size(), 2)
	assert_eq(str(opened[0]["quest"]), "bell_repair")
	assert_eq(str(opened[0]["path"]), "rope")
	assert_eq(str(opened[0]["from"]), "")
	assert_eq(str(opened[0]["to"]), "frayed")
	assert_eq(str(opened[1]["path"]), "tongue")
	assert_eq(str(opened[1]["from"]), "")
	assert_eq(str(opened[1]["to"]), "loose")
	var held := opened.size()
	runtime.tick(0)
	assert_eq(_trace_rows(runtime, "region").size(), held)
	_strike(runtime, "harbor_rope", "spliced")
	var moved := _trace_rows(runtime, "region")
	assert_eq(moved.size(), held + 1)
	var last: Dictionary = moved[moved.size() - 1]
	assert_eq(str(last["path"]), "rope")
	assert_eq(str(last["from"]), "frayed")
	assert_eq(str(last["to"]), "spliced")
	var saved := runtime.save_state()
	var loaded := _boot(_REPAIR)
	loaded.trace.enabled = true
	assert_true(loaded.load_state(saved).ok)
	loaded.tick(0)
	assert_eq(str(loaded.quests.regions_of("bell_repair")["rope"]["stage"]), "spliced")
	assert_eq(_trace_rows(loaded, "region").size(), 0)
	runtime.trace.clear()
	runtime.trace.prefix = "tongue"
	runtime.facts.set(&"harbor.tongue_seated", true)
	runtime.tick(0)
	var tongue := _trace_rows(runtime, "region")
	assert_eq(tongue.size(), 1)
	assert_eq(str(tongue[0]["path"]), "tongue")
	assert_eq(str(tongue[0]["from"]), "loose")
	assert_eq(str(tongue[0]["to"]), "seated")
	runtime.trace.prefix = ""
	runtime.trace.clear()
	runtime.facts.set(&"harbor.release", true)
	runtime.tick(0)
	assert_eq(runtime.quests.stage("bell_repair"), "done")
	assert_eq(_trace_rows(runtime, "region").size(), 0)


func test_region_trace_path_is_nested_and_tracing_can_stay_off() -> void:
	var quiet := _boot(_DEEP)
	quiet.tick(0)
	assert_eq(quiet.trace.events.size(), 0)
	var runtime := _boot(_DEEP)
	runtime.trace.enabled = true
	runtime.tick(0)
	var lines := _trace_rows(runtime, "region")
	assert_eq(lines.size(), 2)
	assert_eq(str(lines[0]["path"]), "mid")
	assert_eq(str(lines[0]["to"]), "inner")
	assert_eq(str(lines[1]["path"]), "mid/deep")
	assert_eq(str(lines[1]["from"]), "")
	assert_eq(str(lines[1]["to"]), "leaf")
	var nested := _boot(_DEEP)
	nested.trace.prefix = "mid/deep"
	nested.trace.enabled = true
	nested.tick(0)
	var only := _trace_rows(nested, "region")
	assert_eq(only.size(), 1)
	assert_eq(str(only[0]["path"]), "mid/deep")
	var broad := _boot(_DEEP)
	broad.trace.prefix = "mid"
	broad.trace.enabled = true
	broad.tick(0)
	assert_eq(_trace_rows(broad, "region").size(), 2)
	var missed := _boot(_DEEP)
	missed.trace.prefix = "leaf"
	missed.trace.enabled = true
	missed.tick(0)
	assert_eq(_trace_rows(missed, "region").size(), 0)


func test_sequence_trace_logs_step_finish_reset_and_expiry() -> void:
	var runtime := _boot(_REPEAT)
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(_trace_rows(runtime, "sequence").size(), 0)
	_strike(runtime, "harbor_bell", "rung")
	var step := _trace_rows(runtime, "sequence")
	assert_eq(step.size(), 1)
	assert_eq(str(step[0]["id"]), "harbor.bells")
	assert_eq(str(step[0]["key"]), "harbor.bells")
	assert_eq(int(step[0]["count"]), 1)
	assert_eq(str(step[0]["done"]), "false")
	assert_eq(str(step[0]["reason"]), "step")
	_strike(runtime, "harbor_bell", "rung")
	_strike(runtime, "harbor_bell", "rung")
	var finished := _trace_rows(runtime, "sequence")
	assert_eq(finished.size(), 3)
	assert_eq(str(finished[1]["reason"]), "step")
	assert_eq(str(finished[2]["reason"]), "done")
	assert_eq(int(finished[2]["count"]), 3)
	assert_eq(str(finished[2]["done"]), "true")
	var kept := finished.size()
	runtime.tick(61)
	assert_eq(_trace_rows(runtime, "sequence").size(), kept)
	var window := _boot(_REPEAT)
	window.trace.enabled = true
	_strike(window, "harbor_bell", "rung")
	window.tick(61)
	var expired := _trace_rows(window, "sequence")
	assert_eq(expired.size(), 2)
	assert_eq(str(expired[1]["reason"]), "expire")
	assert_eq(int(expired[1]["count"]), 0)
	assert_eq(str(expired[1]["done"]), "false")
	var reset := _boot(_RESET_EVENT)
	reset.trace.enabled = true
	_strike(reset, "harbor_bell", "rung")
	reset.events.emit(&"season_changed", {})
	var cleared := _trace_rows(reset, "sequence")
	assert_eq(str(cleared[cleared.size() - 1]["reason"]), "reset")
	assert_eq(int(cleared[cleared.size() - 1]["count"]), 0)
	assert_eq(str(cleared[cleared.size() - 1]["done"]), "false")
	var cond := _boot(_RESET_COND)
	cond.trace.enabled = true
	_strike(cond, "harbor_bell", "rung")
	cond.facts.set(&"harbor.rope_done", true)
	cond.tick(0)
	var watched := _trace_rows(cond, "sequence")
	assert_eq(str(watched[watched.size() - 1]["reason"]), "reset")
	var filtered := _boot(_REPEAT)
	filtered.trace.prefix = "other"
	filtered.trace.enabled = true
	_strike(filtered, "harbor_bell", "rung")
	assert_eq(_trace_rows(filtered, "sequence").size(), 0)
	filtered.trace.prefix = "harbor"
	filtered.trace.clear()
	_strike(filtered, "harbor_bell", "rung")
	assert_eq(_trace_rows(filtered, "sequence").size(), 1)
	var quiet := _boot(_REPEAT)
	_strike(quiet, "harbor_bell", "rung")
	assert_eq(quiet.trace.events.size(), 0)


func _trace_rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == kind:
			rows.append(item)
	return rows


func _strike(runtime: WyrdRuntime, object: String, state_name: String) -> void:
	runtime.events.emit(&"mechanism_state", {
		"actor": &"player",
		"object": StringName(object),
		"state": StringName(state_name),
	})


func _boot(body: String) -> WyrdRuntime:
	var compiled := _compile(body)
	assert_false(compiled["diagnostics"].has_errors(), compiled["diagnostics"].format())
	var runtime := WyrdRuntime.new()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([str(compiled["path"])])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(5)
	return runtime


func _compile(body: String) -> Dictionary:
	var path := _write("user://wyrd_m6_substates_%d.wyrd" % body.hash(), body)
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


func _count(diagnostics: WyrdDiagnostics, code: String) -> int:
	var found := 0
	for item in diagnostics.items:
		if String(item.code) == code:
			found += 1
	return found


const _HEAD := """
language 1
events
  season_changed()
  mechanism_state(object: symbol, state: symbol, actor: symbol)
"""


const _REPAIR := _HEAD + """
facts
  harbor.splices : int stored
  harbor.tongue_seated : bool stored
  harbor.tongue_done : bool stored
  harbor.release : bool stored
quest bell_repair "The Bell Repair"
  start when true
  stage repair
    region rope
      stage frayed
        on mechanism_state where event.object == harbor_rope and event.state == spliced:
          ~ inc harbor.splices by 1
          -> spliced
      stage spliced
    region tongue
      stage loose
        waits_until harbor.tongue_seated
        -> seated
      stage seated
        ~ set harbor.tongue_done = true
    -> done when harbor.tongue_done and harbor.release
  stage done
    ~ outcome repair = done
"""


const _FLAT := """
language 1
facts
  harbor.hits : int stored
quest flat "Flat"
  start when true
  stage one
    ~ inc harbor.hits by 1
    -> two
  stage two
"""


const _DEEP := """
language 1
facts
  harbor.deep_done : bool stored
  harbor.release : bool stored
quest deep "Deep"
  start when true
  stage outer
    region mid
      stage inner
        region deep
          stage leaf
            ~ set harbor.deep_done = true
    -> done when harbor.deep_done and harbor.release
  stage done
    ~ outcome repair = done
"""


const _SHARED := _HEAD + """
quest bell_repair "The Bell Repair"
  start when true
  stage repair
    region rope
      stage wait
    region tongue
      stage wait
"""


const _OUTWARD := """
language 1
quest bell_repair "The Bell Repair"
  start when true
  stage repair
    region rope
      stage frayed
        -> repair
      stage spliced
"""


const _INWARD := """
language 1
quest bell_repair "The Bell Repair"
  start when true
  stage repair
    region rope
      stage frayed
    -> frayed
  stage done
"""


const _SCENES := """
language 1
facts
  harbor.rope_done : bool stored
  harbor.tongue_done : bool stored
scene rope_note
  narrator: The rope is spliced. #line:rope_note
scene tongue_note
  narrator: The tongue is seated. #line:tongue_note
quest gate "The Gate"
  start when true
  stage repair
    region rope
      stage frayed
        scene rope_note
        ~ set harbor.rope_done = true
    region tongue
      stage loose
        ~ set harbor.tongue_done = true
        scene tongue_note
"""


const _ORDERED := _HEAD + """
sequence harbor.path ordered within 1d
  on mechanism_state where event.state == spliced
  on mechanism_state where event.state == seated
"""


const _DISTINCT := _HEAD + """
sequence harbor.tools any(2 of 3) within 1d
  on mechanism_state where event.state == spliced
  on mechanism_state where event.state == seated
  on mechanism_state where event.state == rung
"""


const _REPEAT := _HEAD + """
sequence harbor.bells any(3 of 3) within 60m
  on mechanism_state where event.state == rung
"""


const _RESET_EVENT := _HEAD + """
sequence harbor.bells any(2 of 2) within 1d reset on season_changed
  on mechanism_state where event.state == rung
"""


const _RESET_SAME := _HEAD + """
sequence harbor.once ordered within 60m reset on season_changed
  on season_changed where true
"""


const _RESET_COND := _HEAD + """
facts
  harbor.rope_done : bool stored
sequence harbor.watch any(2 of 2) within 1d reset on harbor.rope_done
  on mechanism_state where event.state == rung
"""


const _WAKE := _HEAD + """
quest gate "The Gate"
  start when true
  stage wait
    waits_until done(harbor.bells)
    -> rung
  stage rung
    ~ outcome repair = done
sequence harbor.bells any(2 of 2) within 60m
  on mechanism_state where event.state == rung
"""


const _DUPLICATE := _HEAD + """
sequence harbor.bells ordered within 1m
  on season_changed where true
sequence harbor.bells ordered within 1m
  on season_changed where true
"""


const _BAD_COUNT := _HEAD + """
sequence harbor.bad any(1 of 3) within 1m
  on season_changed where true
  on season_changed where true
"""


const _BARE_RESET := _HEAD + """
sequence harbor.bad ordered within 1m reset on not_an_event
  on season_changed where true
"""


const _SPATIAL_STEP := _HEAD + """
sequence harbor.bad ordered within 1m
  on season_changed where nearby(player, 4m, tag: lantern) > 0
"""
