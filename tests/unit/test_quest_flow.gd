extends GutTest


func test_start_each_status() -> void:
	var runtime := _boot(_STATUSES)
	assert_eq(runtime.quests.status("blocked"), &"unavailable")
	runtime.tick(0)
	assert_eq(runtime.quests.status("hold"), &"dormant")
	assert_eq(runtime.quests.status("auto"), &"active")
	assert_eq(runtime.quests.status("finish"), &"completed")
	assert_eq(runtime.quests.status("failq"), &"failed")
	assert_eq(runtime.quests.status("ready"), &"dormant")
	var ready = runtime.quests._states["ready"]
	runtime.quests._set_status("ready", ready, runtime.quests.AVAILABLE)
	assert_eq(runtime.quests.status("ready"), &"available")
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.quests.start("ready")
	assert_eq(runtime.quests.status("ready"), &"active")
	assert_eq(runtime.quests.stage("ready"), "one")
	assert_eq(_row(runtime, "quest_start", "ready")["reason"], "started")
	assert_eq(_row(runtime, "quest_start", "ready")["ok"], "true")
	runtime.quests.start("auto")
	runtime.quests.start("finish")
	runtime.quests.start("failq")
	runtime.quests.start("hold")
	assert_eq(runtime.quests.status("hold"), &"active")
	assert_eq(runtime.quests.stage("hold"), "one")
	runtime.quests.abandon("hold")
	assert_eq(runtime.quests.status("hold"), &"abandoned")
	runtime.trace.clear()
	runtime.quests.start("hold")
	assert_eq(runtime.quests.status("hold"), &"abandoned")
	assert_eq(_row(runtime, "quest_start", "hold")["reason"], "abandoned")
	assert_eq(_row(runtime, "quest_start", "hold")["ok"], "false")
	runtime.quests.start("blocked")
	assert_eq(runtime.quests.status("blocked"), &"unavailable")
	assert_eq(_row(runtime, "quest_start", "blocked")["reason"], "unavailable")
	assert_eq(_row(runtime, "quest_start", "blocked")["ok"], "false")
	assert_eq(_status_rows(runtime, "blocked").size(), 0)
	assert_push_warning("\"auto\" is active")
	assert_push_warning("\"finish\" is completed")
	assert_push_warning("\"failq\" is failed")
	assert_push_warning("\"hold\" is abandoned")
	assert_push_warning_count(4)


func test_advance_leaves_a_waiting_stage() -> void:
	var opened := _boot_host(_WAITING)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.quests.start("waitq")
	assert_eq(runtime.quests.status("waitq"), &"active")
	assert_eq(runtime.quests.stage("waitq"), "one")
	assert_true(runtime.quests.waiting_reason("waitq").begins_with("waits_until:"))
	runtime.trace.enabled = true
	runtime.quests.advance("waitq", "two")
	assert_eq(runtime.quests.stage("waitq"), "two")
	assert_eq(runtime.quests.waiting_reason("waitq"), "waits_until: false")
	assert_eq(_row(runtime, "quest_advance", "waitq")["reason"], "moved")
	assert_eq(_row(runtime, "quest_advance", "waitq")["ok"], "true")
	assert_eq(_row(runtime, "quest_advance", "waitq")["from"], "one")
	assert_eq(_row(runtime, "quest_advance", "waitq")["to"], "two")
	assert_eq(_row(runtime, "transition", "waitq")["from"], "one")
	runtime.quests.start("held")
	assert_eq(runtime.quests.waiting_reason("held"), "on_empty")
	assert_eq(runtime.quests.stage("held"), "held")
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	runtime.roles.assign(&"watcher", &"ada")
	runtime.quests.advance("held", "next")
	assert_eq(runtime.quests.stage("held"), "next")
	assert_eq(runtime.quests.waiting_reason("held"), "waits_until: false")
	runtime.quests.start("offered")
	assert_eq(runtime.quests.waiting_reason("offered"), "scene:dock.note")
	assert_false(runtime.dialogue.is_open())
	runtime.quests.advance("offered", "two")
	assert_eq(runtime.quests.stage("offered"), "two")
	assert_eq(runtime.quests.offered_scene("offered"), "")


func test_on_empty_wait_uses_only_the_stage_slots() -> void:
	var opened := _boot_host(_STAGE_SLOTS)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	runtime.roles.assign(&"role_filled", &"ada")
	runtime.quests.start("unused")
	assert_eq(runtime.quests.variant_of("unused"), "alpha.default")
	assert_eq(runtime.quests.status("unused"), &"completed")
	assert_eq(runtime.quests.waiting_reason("unused"), "")
	runtime.quests.start("bare")
	assert_eq(runtime.quests.stage("bare"), "s10")
	assert_eq(runtime.quests.waiting_reason("bare"), "on_empty")
	assert_eq(runtime.quests.offered_scene("bare"), "")
	runtime.quests.start("condq")
	assert_eq(runtime.quests.waiting_reason("condq"), "on_empty")
	runtime.quests.start("stepq")
	assert_eq(runtime.quests.waiting_reason("stepq"), "on_empty")
	assert_eq(runtime.quests.journal("stepq").size(), 0)
	runtime.quests.start("covered")
	assert_eq(runtime.quests.variant_of("covered"), "alpha.empty")
	assert_eq(runtime.quests.status("covered"), &"completed")
	assert_eq(runtime.quests.waiting_reason("covered"), "")
	runtime.quests.start("quiet")
	assert_eq(runtime.quests.status("quiet"), &"completed")
	assert_eq(runtime.quests.waiting_reason("quiet"), "")
	runtime.quests.start("regionq")
	assert_eq(runtime.quests.stage("regionq"), "s10")
	assert_eq(runtime.quests.waiting_reason("regionq"), "on_empty")
	assert_eq(runtime.quests.offered_scene("regionq"), "")


func test_advance_refuses_a_host_step_or_open_scene() -> void:
	var runtime := _boot(_GATES)
	runtime.quests.start("hostq")
	assert_eq(runtime.quests.waiting_reason("hostq"), "host:board")
	runtime.trace.enabled = true
	runtime.quests.advance("hostq", "two")
	assert_eq(runtime.quests.stage("hostq"), "one")
	assert_eq(_row(runtime, "quest_advance", "hostq")["reason"], "host_step")
	assert_eq(_row(runtime, "quest_advance", "hostq")["ok"], "false")
	runtime.quests.complete_host_step("hostq", {"ok": true})
	assert_eq(runtime.quests.stage("hostq"), "one")
	runtime.quests.advance("hostq", "two")
	assert_eq(runtime.quests.stage("hostq"), "two")
	runtime.quests.start("sceneq")
	runtime.dialogue.open_scene("dock.note")
	assert_true(runtime.dialogue.is_open())
	assert_eq(runtime.dialogue.open_quest_id(), "sceneq")
	runtime.trace.clear()
	runtime.quests.advance("sceneq", "two")
	assert_eq(runtime.quests.stage("sceneq"), "one")
	assert_eq(_row(runtime, "quest_advance", "sceneq")["reason"], "scene_open")
	runtime.dialogue.abort(&"left")
	assert_false(runtime.dialogue.is_open())
	runtime.quests.advance("sceneq", "two")
	assert_eq(runtime.quests.stage("sceneq"), "two")
	runtime.quests.start("both")
	runtime.dialogue.open_scene("dock.note")
	runtime.trace.clear()
	runtime.quests.advance("both", "two")
	assert_eq(runtime.quests.stage("both"), "one")
	assert_eq(_row(runtime, "quest_advance", "both")["reason"], "host_step")
	runtime.dialogue.abort(&"left")
	assert_push_warning("\"hostq\" is waiting on the host")
	assert_push_warning("\"sceneq\" has an open scene")
	assert_push_warning("\"both\" is waiting on the host")


func test_same_stage_advance_is_a_no_op() -> void:
	var runtime := _boot(_PLAIN)
	runtime.quests.start("gate")
	runtime.trace.enabled = true
	runtime.quests.advance("gate", "one")
	assert_eq(runtime.quests.stage("gate"), "one")
	assert_eq(runtime.quests.status("gate"), &"active")
	var row := _row(runtime, "quest_advance", "gate")
	assert_eq(row["ok"], "false")
	assert_eq(row["reason"], "same_stage")
	assert_eq(row["from"], "one")
	assert_eq(row["to"], "one")
	assert_eq(_rows(runtime, "transition").size(), 0)
	assert_push_warning_count(0)


func test_a_stage_can_start_another_quest_and_advance_itself() -> void:
	var runtime := _boot(_CHAIN)
	runtime.trace.enabled = true
	runtime.quests.start("outer")
	assert_eq(runtime.facts.get(&"harbor.before"), true)
	assert_null(runtime.facts.get(&"harbor.after"))
	assert_eq(runtime.facts.get(&"harbor.inner"), true)
	assert_eq(runtime.facts.get(&"harbor.two"), true)
	assert_eq(runtime.quests.stage("outer"), "two")
	assert_eq(runtime.quests.status("inner"), &"active")
	assert_eq(runtime.quests.stage("inner"), "begun")
	assert_eq(_row(runtime, "quest_advance", "outer")["reason"], "moved")
	assert_push_warning("\"outer\" is active")


func test_hop_limit_stops_a_self_advance() -> void:
	var runtime := _boot(_LOOP)
	var seen: Array[String] = []
	runtime.quests.stage_changed.connect(func(quest_id: String, stage_id: String) -> void:
		seen.append("%s:%s" % [quest_id, stage_id])
	)
	runtime.quests.start("loop")
	assert_eq(seen.size(), 25)
	assert_eq(seen[0], "loop:a")
	assert_eq(seen[24], "loop:a")
	assert_eq(runtime.quests.stage("loop"), "a")
	assert_eq(runtime.quests.status("loop"), &"active")
	assert_push_error("stage hop limit on \"loop\"")
	assert_push_error_count(1)


func test_advance_drops_region_rows_and_leaves_sequences() -> void:
	var runtime := _boot(_REGION)
	runtime.events.emit(&"mechanism_state", {
		"actor": &"player",
		"object": &"harbor_bell",
		"state": &"spliced",
	})
	assert_eq(runtime.sequences.progress("harbor.path"), 1)
	runtime.quests.start("gate")
	assert_eq(runtime.quests.stage("gate"), "two")
	assert_eq(runtime.facts.get(&"harbor.seen"), true)
	assert_null(runtime.facts.get(&"harbor.later"))
	assert_eq(runtime.quests.regions_of("gate"), {})
	assert_eq(runtime.sequences.progress("harbor.path"), 1)
	assert_false(runtime.sequences.done("harbor.path"))


func test_trace_lines_filter_by_quest() -> void:
	var runtime := _boot(_PLAIN)
	runtime.trace.prefix = "other"
	runtime.trace.enabled = true
	runtime.quests.start("gate")
	assert_eq(runtime.trace.events.size(), 1)
	runtime.trace.prefix = "gate"
	runtime.trace.clear()
	runtime.quests.start("gate")
	assert_push_warning("\"gate\" is active")
	assert_eq(_rows(runtime, "quest_start").size(), 1)
	assert_eq(_rows(runtime, "quest_status").size(), 0)
	var quiet := _boot(_PLAIN)
	quiet.quests.start("missing")
	quiet.quests.advance("missing", "one")
	quiet.quests.start("gate")
	quiet.trace.enabled = true
	quiet.quests.advance("gate", "missing")
	assert_eq(quiet.trace.events.size(), 0)
	assert_push_error("unknown quest \"missing\"")
	assert_push_error("unknown stage \"missing\"")
	assert_push_error_count(3)


func test_save_and_load_keep_the_quest_row() -> void:
	var first := _boot(_PLAIN)
	first.quests.start("gate")
	var started := first.save_state()
	assert_eq(int(started["schema_version"]), 4)
	var loaded := _boot(_PLAIN)
	loaded.trace.enabled = true
	assert_true(loaded.load_state(started).ok)
	assert_eq(JSON.stringify(loaded.quests.export_state()), JSON.stringify(first.quests.export_state()))
	assert_eq(_rows(loaded, "quest_status").size(), 0)
	assert_eq(_rows(loaded, "quest_start").size(), 0)
	loaded.quests.advance("gate", "two")
	var moved := loaded.save_state()
	var again := _boot(_PLAIN)
	again.trace.enabled = true
	assert_true(again.load_state(moved).ok)
	assert_eq(again.quests.stage("gate"), "two")
	assert_eq(JSON.stringify(again.quests.export_state()), JSON.stringify(loaded.quests.export_state()))
	assert_eq(_rows(again, "quest_advance").size(), 0)
	assert_eq(_rows(again, "quest_status").size(), 0)


func test_not_active_advance_warns() -> void:
	var runtime := _boot(_PLAIN)
	runtime.trace.enabled = true
	runtime.quests.advance("gate", "two")
	assert_eq(runtime.quests.status("gate"), &"dormant")
	assert_eq(runtime.quests.stage("gate"), "")
	var row := _row(runtime, "quest_advance", "gate")
	assert_eq(row["ok"], "false")
	assert_eq(row["reason"], "not_active")
	assert_eq(row["to"], "two")
	assert_push_warning("\"gate\" is dormant")


func _row(runtime: WyrdRuntime, kind: String, quest_id: String) -> Dictionary:
	for item in _rows(runtime, kind):
		if str(item.get("quest", "")) == quest_id:
			return item
	return {}


func _status_rows(runtime: WyrdRuntime, quest_id: String) -> Array:
	var found: Array = []
	for item in _rows(runtime, "quest_status"):
		if str(item.get("quest", "")) == quest_id:
			found.append(item)
	return found


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var found: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and str((item as Dictionary).get("kind", "")) == kind:
			found.append(item)
	return found


func _boot(body: String) -> WyrdRuntime:
	return _open(body)["runtime"]


func _boot_host(body: String) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var opened := _load(runtime, body)
	opened["host"] = host
	return opened


func _open(body: String) -> Dictionary:
	return _load(WyrdRuntime.new(), body)


func _load(runtime: WyrdRuntime, body: String) -> Dictionary:
	var path := _write("user://wyrd_quest_flow_%d.wyrd" % body.hash(), body)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(5)
	return {"path": path, "runtime": runtime}


func _write(path: String, body: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body.strip_edges() + "\n")
	file.close()
	return path


const _STATUSES := """
language 1
quest hold "Hold"
  start when false
  stage one
    waits_until false
quest auto "Auto"
  start when true
  stage one
    waits_until false
quest finish "Finish"
  start when true
  stage only
    ~ outcome gate = done
quest failq "Fail"
  start when true
  stage only
    ~ outcome gate = failed
quest ready "Ready"
  start when false
  stage one
    waits_until false
quest drop "Drop"
  start when false
  stage one
    waits_until false
quest blocked "Blocked"
  requires: [pack.missing]
  start when false
  stage one
    waits_until false
"""


const _STAGE_SLOTS := """
language 1
quest unused "Unused"
  start when false
  slot alpha = role_filled mode: live
  slot beta = role_spare mode: live
  on_empty: wait
  stage s10
    variant alpha.default:
      ~ outcome gate = done
quest bare "Bare"
  start when false
  slot alpha = role_bare mode: live
  slot beta = role_spare mode: live
  on_empty: wait
  stage s10
    scene room with alpha
    waits_until false
quest condq "Cond"
  start when false
  slot alpha = role_cond mode: live
  on_empty: wait
  stage s10
    waits_until filled(alpha)
quest stepq "Step"
  start when false
  slot alpha = role_step mode: live
  on_empty: wait
  stage s10
    journal: {holder(alpha).name} waits. #line:j_step
    ~ outcome gate = done
quest covered "Covered"
  start when false
  slot alpha = role_cover mode: live
  slot beta = role_spare mode: live
  on_empty: wait
  stage s10
    variant alpha.empty:
      ~ outcome gate = done
quest quiet "Quiet"
  start when false
  slot spare = role_spare mode: live
  on_empty: wait
  stage only
    ~ outcome gate = done
quest regionq "Region"
  start when false
  slot alpha = role_region mode: live
  on_empty: wait
  stage s10
    region wing
      stage inner
        scene room with alpha
    waits_until false
scene room
  alpha: The chair is empty. #line:room
  -> end
"""


const _WAITING := """
language 1
quest waitq "Wait"
  start when false
  stage one
    waits_until false
  stage two
    waits_until false
quest held "Held"
  start when false
  slot lookout = watcher mode: live
  on_empty: wait
  stage held
    journal: {holder(lookout).name} waits. #line:j_held
  stage next
    waits_until false
quest offered "Offered"
  start when false
  stage one
    scene dock.note
  stage two
    waits_until false
scene dock.note
  narrator: A note. #line:n1
  -> end
"""


const _GATES := """
language 1
quest hostq "Host"
  start when false
  stage one
    await_host board returns { ok }
    waits_until false
  stage two
    waits_until false
quest sceneq "Scene"
  start when false
  stage one
    scene dock.note
    waits_until false
  stage two
    waits_until false
quest both "Both"
  start when false
  stage one
    scene dock.note
    await_host board returns { ok }
    waits_until false
  stage two
    waits_until false
scene dock.note
  narrator: A note. #line:n1
  -> end
"""


const _PLAIN := """
language 1
quest gate "Gate"
  start when false
  stage one
    waits_until false
  stage two
    waits_until false
"""


const _CHAIN := """
language 1
facts
  harbor.before : bool stored
  harbor.after : bool stored
  harbor.inner : bool stored
  harbor.two : bool stored
quest outer "Outer"
  start when false
  stage one
    ~ set harbor.before = true
    ~ start quest outer
    ~ start quest inner
    ~ advance outer to two
    ~ set harbor.after = true
    waits_until false
  stage two
    ~ set harbor.two = true
    waits_until false
quest inner "Inner"
  start when false
  stage begun
    ~ set harbor.inner = true
    waits_until false
"""


const _LOOP := """
language 1
quest loop "Loop"
  start when false
  stage a
    ~ advance loop to b
  stage b
    ~ advance loop to a
"""


const _REGION := """
language 1
events
  mechanism_state(object: symbol, state: symbol, actor: symbol)
facts
  harbor.seen : bool stored
  harbor.later : bool stored
sequence harbor.path ordered within 1d
  on mechanism_state where event.state == spliced
  on mechanism_state where event.state == seated
quest gate "Gate"
  start when false
  stage one
    region rope
      stage frayed
        ~ set harbor.seen = true
        ~ advance gate to two
        ~ set harbor.later = true
    waits_until false
  stage two
    waits_until false
"""
